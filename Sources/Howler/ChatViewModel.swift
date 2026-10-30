import Foundation
import HowlerCore

/// One in-memory conversation. Cleared whenever the panel closes; never written anywhere.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var input = "" {
        didSet { absorbLongPaste(previous: oldValue) }
    }
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isStreaming = false
    @Published private(set) var errorText: String?
    /// Incremented each time the panel opens: focuses the input and re-presses the stamp.
    @Published private(set) var openCount = 0
    /// Incremented when the letter comes back from a screen capture: focuses the input.
    @Published private(set) var focusTick = 0
    /// Context waiting to travel with the next question.
    @Published private(set) var attachment: ContextAttachment?
    /// Bumped whenever a new attachment is sealed, so its sigil burns in.
    @Published private(set) var attachmentStamp = 0
    /// The reply the quill is still writing; nil once the ink has caught up.
    @Published private(set) var writingID: UUID?
    @Published private(set) var copiedID: UUID?
    /// When the letter caught fire on its way out; nil while it is whole.
    @Published private(set) var burnStartedAt: Date?
    /// The desktop is in Dark Mode: the letter is lit by candle rather than daylight.
    @Published private(set) var candlelit = false

    let settings: AppSettings
    let quill = QuillPacer()
    private var streamTask: Task<Void, Never>?
    /// Bumped on reset so a cancelled stream can't write into the next conversation.
    private var generation = 0
    private var isAbsorbingPaste = false

    /// Set by the panel: runs work that may raise a system alert without the letter
    /// treating the lost focus as "clicked elsewhere".
    var keepingOpen: (() -> Void) -> Void = { $0() }
    /// Set by the panel: steps aside while the user drags out a screen region, then
    /// reports the picture (nil if they cancelled).
    var captureScreenRegion: (@escaping (Result<ImageData, Error>?) -> Void) -> Void = { $0(nil) }

    #if DEBUG
    /// Demo mode replaces the network with a scripted stream.
    var demoStream: (() -> AsyncThrowingStream<String, Error>)?
    #endif

    init(settings: AppSettings) {
        self.settings = settings
        quill.onCaughtUp = { [weak self] in self?.writingID = nil }
    }

    // MARK: Panel lifecycle

    func panelDidOpen(reduceMotion: Bool, candlelit: Bool) {
        openCount += 1
        self.candlelit = candlelit
        quill.instant = reduceMotion
    }

    /// Sets the letter alight. The panel hides it and calls `reset()` once it has burned.
    func burn() {
        stop()
        burnStartedAt = Date()
    }

    func reset() {
        burnStartedAt = nil
        stop()
        quill.reset()
        writingID = nil
        messages.removeAll()
        InkAttributed.clear()
        input = ""
        errorText = nil
        attachment = nil
        copiedID = nil
    }

    // MARK: Attachments

    /// "Paste from Clipboard": seals in whatever is there, text of any length or a picture.
    /// The clipboard is only ever read on such an explicit request.
    func pasteFromClipboard() {
        var pasted: ContextAttachment?
        keepingOpen { pasted = Clipboard.attachment() }
        if let pasted {
            attach(pasted)
        } else {
            errorText = "There's no text or picture on the clipboard."
        }
    }

    /// ⌘V with a picture on the clipboard, which the text field can't take.
    func pasteImage(_ image: ImageData) {
        attach(ContextAttachment(source: .pasted, image: image))
    }

    func captureScreen() {
        captureScreenRegion { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let image): self.attach(ContextAttachment(source: .screenshot, image: image))
            case .failure(let error): self.errorText = error.localizedDescription
            case nil: break // cancelled with Esc
            }
            self.focusTick += 1
        }
    }

    /// Copies text the letter wrote (an answer, a code block).
    func copyText(_ text: String) {
        Clipboard.copy(text)
    }

    func removeAttachment() {
        attachment = nil
    }

    /// Seals context into the next question; its seal is pressed in.
    func attach(_ newAttachment: ContextAttachment) {
        attachment = newAttachment
        attachmentStamp += 1
    }

    /// A long or multi-line paste would bury the question; keep it as an attachment instead
    /// and leave the input as it was. The inserted run is found by diffing, so the clipboard
    /// is never read here.
    private func absorbLongPaste(previous: String) {
        // More than one character at once: a paste (or dictation), not typing.
        guard !isAbsorbingPaste, input.count - previous.count > 1 else { return }
        let prefix = input.commonPrefix(with: previous)
        let remainingOld = previous.dropFirst(prefix.count)
        let remainingNew = input.dropFirst(prefix.count)
        let suffixLength = zip(remainingOld.reversed(), remainingNew.reversed()).prefix { $0 == $1 }.count
        let inserted = String(remainingNew.dropLast(suffixLength))
        guard PastedText.belongsInAttachment(inserted),
              let pasted = ContextAttachment(source: .pasted, text: inserted)
        else { return }

        isAbsorbingPaste = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.input = previous
            self.isAbsorbingPaste = false
            self.attach(pasted)
        }
    }

    // MARK: Sending

    /// Sent when the user presses ↩ with context sealed in but nothing written.
    static let attachmentOnlyQuestion = "Explain this."

    func send() {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, attachment != nil { text = Self.attachmentOnlyQuestion }
        guard !text.isEmpty, !isStreaming else { return }
        guard let service = settings.service else {
            errorText = "No model set up. Open Settings to set one up."
            return
        }
        guard let stream = makeStream(service: service, history: messages + [userTurn(text)]) else {
            errorText = "No API key found. Open Settings to finish the setup."
            return
        }

        if writingID != nil { quill.snapToEnd() } // finish the previous reply's ink at once
        messages.append(userTurn(text))
        attachment = nil
        input = ""
        errorText = nil
        let reply = ChatMessage(role: .assistant, content: "")
        messages.append(reply)
        isStreaming = true
        writingID = reply.id
        quill.begin()

        let currentGeneration = generation
        streamTask = Task { [weak self] in
            do {
                for try await delta in stream {
                    guard let self, self.generation == currentGeneration else { return }
                    self.append(delta, to: reply.id)
                }
            } catch {
                guard let self, self.generation == currentGeneration, !Task.isCancelled else { return }
                self.errorText = error.localizedDescription
            }
            guard let self, self.generation == currentGeneration else { return }
            self.isStreaming = false
            self.streamTask = nil
            self.quill.endStream()
        }
    }

    func stop() {
        generation += 1 // the stopped task must not touch the state of a later send
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        quill.snapToEnd()
    }

    func copy(_ message: ChatMessage) {
        copyText(message.content)
        copiedID = message.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.copiedID == message.id { self?.copiedID = nil }
        }
    }

    var lastAnswer: ChatMessage? {
        messages.last { $0.role == .assistant && !$0.content.isEmpty }
    }

    private func userTurn(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, content: text, attachment: attachment)
    }

    private func makeStream(service: ModelService, history: [ChatMessage]) -> AsyncThrowingStream<String, Error>? {
        #if DEBUG
        if let demoStream { return demoStream() }
        #endif
        guard let apiKey = settings.apiKey(), !apiKey.isEmpty else { return nil }
        return settings.client.stream(
            service: service,
            apiKey: apiKey,
            messages: history,
            options: RequestOptions(appName: AppInfo.name, systemPrompt: settings.systemPrompt)
        )
    }

    private func append(_ delta: String, to id: UUID) {
        guard let index = messages.lastIndex(where: { $0.id == id }) else { return }
        messages[index].content += delta
        quill.update(target: messages[index].content.count)
    }
}
