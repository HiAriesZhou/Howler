import Foundation
import Combine
import HowlerCore

/// A single in-memory letter. Visibility and input do not control its lifetime.
@MainActor
final class ChatViewModel: ObservableObject {
    struct LetterImage: Identifiable {
        let id: UUID
        let number: Int
        let attachment: ContextAttachment
    }

    @Published var input = "" {
        didSet {
            inputRevision &+= 1
            absorbLongPaste(previous: oldValue)
        }
    }
    @Published private(set) var queue = ConversationQueue()
    @Published private(set) var images: [LetterImage] = []
    @Published private(set) var draftImageID: UUID?
    @Published private(set) var errorText: String?
    @Published private(set) var openCount = 0
    @Published private(set) var focusTick = 0
    @Published private(set) var attachment: ContextAttachment?
    @Published private(set) var attachmentStamp = 0
    @Published private(set) var writingID: UUID?
    @Published private(set) var copiedID: UUID?
    @Published private(set) var candlelit = false

    let settings: AppSettings
    let quill = QuillPacer()
    private var streamTask: Task<Void, Never>?
    private var connectionObserver: AnyCancellable?
    private var isAbsorbingPaste = false
    private var inputRevision: UInt64 = 0
    private(set) var conversationID = UUID()
    private var visible = true
    private var reduceMotion = false
    private var isPumping = false

    var keepingOpen: (() -> Void) -> Void = { $0() }
    var captureScreenRegion: (@escaping (Result<ImageData, Error>?) -> Void) -> Void = { $0(nil) }
    /// Injected transports operate on synthetic content in tests, never real credentials.
    var streamFactory: (([ChatMessage], RequestOptions) -> AsyncThrowingStream<String, Error>)?
    #if DEBUG
    var demoStream: (() -> AsyncThrowingStream<String, Error>)?
    #endif

    init(settings: AppSettings) {
        self.settings = settings
        quill.onCaughtUp = { [weak self] in self?.finishPresentation() }
        connectionObserver = settings.$connectionVersion.dropFirst().sink { [weak self] _ in
            guard let self, self.queue.active != nil || !self.queue.waiting.isEmpty else { return }
            self.pause("The model setup changed. Retry or continue with the new setup.")
        }
    }

    var messages: [ChatMessage] {
        queue.tasks.filter { $0.state != .queued }.flatMap { task in
            [ChatMessage(id: task.id, role: .user, content: displayQuestion(task), attachment: task.attachment),
             ChatMessage(id: task.replyID, role: .assistant, content: task.answer)]
        }
    }
    var isStreaming: Bool { queue.active?.state == .generating }
    var latestImageID: UUID? { images.last?.id }
    var previewAttachment: ContextAttachment? { attachment ?? image(draftImageID)?.attachment }
    var lastAnswer: ChatMessage? { messages.last { $0.role == .assistant && !$0.content.isEmpty } }

    func image(_ id: UUID?) -> LetterImage? { images.first { $0.id == id } }
    func selectDraftImage(_ id: UUID?) {
        guard id == nil || image(id) != nil else { return }
        if attachment?.image != nil { attachment = nil }
        draftImageID = id
    }

    func panelDidOpen(reduceMotion: Bool, candlelit: Bool) {
        openCount += 1
        self.candlelit = candlelit
        self.reduceMotion = reduceMotion
        setVisible(true)
    }

    func updateReduceMotion(_ value: Bool) {
        reduceMotion = value
        quill.instant = value || !visible
        if value, queue.active?.state == .revealing { quill.snapToEnd() }
    }

    func setVisible(_ value: Bool) {
        visible = value
        quill.instant = reduceMotion || !value
        if !value, queue.active?.state == .revealing { quill.snapToEnd() }
    }

    /// The controller retains only a rendered snapshot while the business state is cleared.
    func burn() { reset() }

    func reset() {
        conversationID = UUID()
        streamTask?.cancel()
        streamTask = nil
        queue.clear()
        quill.reset()
        writingID = nil
        images.removeAll()
        input = ""
        draftImageID = nil
        errorText = nil
        attachment = nil
        copiedID = nil
        isAbsorbingPaste = false
        InkAttributed.clear()
    }

    func pasteFromClipboard() {
        var pasted: ContextAttachment?
        keepingOpen { pasted = Clipboard.attachment() }
        if let pasted { attach(pasted) }
        else { errorText = "There's no text or picture on the clipboard." }
    }

    func pasteImage(_ image: ImageData) { attach(ContextAttachment(source: .pasted, image: image)) }

    func captureScreen() {
        let session = conversationID
        captureScreenRegion { [weak self] result in
            guard let self, self.conversationID == session else { return }
            switch result {
            case .success(let picture): self.introduceScreenshot(picture)
            case .failure(let error): self.errorText = error.localizedDescription
            case nil: return
            }
            self.focusTick += 1
        }
    }

    func introduceScreenshot(_ picture: ImageData) {
        let context = ContextAttachment(source: .screenshot, image: picture)
        let id = registerImage(context)
        if input.isEmpty && attachment == nil { draftImageID = id }
        attachmentStamp += 1
        queue.enqueue(ConversationTask(kind: .screenshotIntroduction, question: "Image introduction",
                                        attachment: context, imageID: id,
                                        language: settings.resolvedReplyLanguage, systemPrompt: settings.systemPrompt))
        pump()
    }

    private func registerImage(_ context: ContextAttachment) -> UUID {
        let id = UUID()
        images.append(LetterImage(id: id, number: images.count + 1, attachment: context))
        return id
    }

    func copyText(_ text: String) { Clipboard.copy(text) }
    func removeAttachment() { attachment = nil; draftImageID = nil }

    func attach(_ newAttachment: ContextAttachment) {
        attachment = newAttachment
        if newAttachment.image != nil { draftImageID = registerImage(newAttachment) }
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
        let session = conversationID
        let revision = inputRevision
        let targetImage = draftImageID
        DispatchQueue.main.async { [weak self] in
            guard let self, self.conversationID == session else { return }
            guard self.inputRevision == revision else {
                self.isAbsorbingPaste = false
                return
            }
            self.input = previous
            self.isAbsorbingPaste = false
            self.draftImageID = targetImage
            self.attach(pasted)
        }
    }

    // MARK: Submitted tasks

    static let attachmentOnlyQuestion = "Explain this."

    func send() {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, previewAttachment != nil { text = Self.attachmentOnlyQuestion }
        guard !text.isEmpty else { return }
        let target = draftImageID
        queue.enqueue(ConversationTask(question: text, attachment: attachment, imageID: target,
                                        language: settings.resolvedReplyLanguage, systemPrompt: settings.systemPrompt))
        input = ""
        attachment = nil
        draftImageID = latestImageID
        errorText = nil
        pump()
    }

    func withdraw(_ id: UUID) {
        guard input.isEmpty, attachment == nil, let task = queue.withdraw(id) else { return }
        input = task.question
        attachment = task.attachment
        draftImageID = task.imageID
        focusTick += 1
    }

    func stop() { pause("Stopped. Retry this reply, or skip it and continue.") }

    private func pause(_ reason: String) {
        streamTask?.cancel()
        streamTask = nil
        queue.pause(reason: reason)
        writingID = nil
        quill.reset()
    }

    func retry() {
        settings.reload()
        queue.retry()
        errorText = nil
        pump()
    }

    func skipAndContinue() {
        settings.reload()
        queue.skip()
        errorText = nil
        pump()
    }

    private func pump() {
        guard !isPumping else { return }
        isPumping = true
        defer { isPumping = false }
        settings.reload()
        guard let token = queue.startNext(), let task = queue.active else { return }
        let options = RequestOptions(appName: AppInfo.name, systemPrompt: task.systemPrompt)
        guard let stream = makeStream(history: requestHistory(for: task), options: options) else {
            pause(settings.service == nil ? "No model set up. Open Settings to set one up."
                  : "No API key found. Open Settings to finish the setup.")
            return
        }
        writingID = task.replyID
        quill.instant = reduceMotion || !visible
        quill.begin()
        streamTask = Task { [weak self] in
            do {
                for try await delta in stream {
                    guard let self, self.queue.runID == token, !Task.isCancelled else { return }
                    self.queue.append(delta, for: token)
                    self.quill.update(target: self.queue.active?.answer.count ?? 0)
                }
                guard let self, self.queue.runID == token, !Task.isCancelled else { return }
                self.streamTask = nil
                self.queue.generated(for: token)
                if self.queue.isPaused {
                    self.writingID = nil
                    self.quill.reset()
                } else {
                    self.quill.endStream()
                }
            } catch {
                guard let self, self.queue.runID == token, !Task.isCancelled else { return }
                self.pause(error.localizedDescription)
            }
        }
    }

    private func finishPresentation() {
        guard let token = queue.runID, queue.active?.state == .revealing else { return }
        queue.presented(for: token)
        writingID = nil
        pump()
    }

    /// A request carries its target image once. Earlier image turns keep their labels and
    /// answers as text; an old-image follow-up explicitly reattaches its own image.
    func requestHistory(for current: ConversationTask) -> [ChatMessage] {
        var history: [ChatMessage] = []
        for task in queue.tasks {
            if task.id == current.id { break }
            guard task.state == .completed || task.state == .skipped else { continue }
            let text = task.attachment?.text.map { ContextAttachment(source: .pasted, text: $0) } ?? nil
            history.append(ChatMessage(role: .user, content: displayQuestion(task), attachment: text))
            if !task.answer.isEmpty {
                let suffix = task.state == .skipped ? "\n[Incomplete reply]" : ""
                history.append(ChatMessage(role: .assistant, content: task.answer + suffix))
            }
        }
        var question = displayQuestion(current)
        if let context = current.attachment, context.text != nil { question = context.prompt(for: question) }
        var instructions = ReplyLanguage.instruction(current.language)
        if current.kind == .screenshotIntroduction { instructions += "\n" + ReplyLanguage.screenshotIntroduction }
        let picture = image(current.imageID)?.attachment
        history.append(ChatMessage(id: current.id, role: .user, content: question,
                                   attachment: picture, taskInstructions: instructions))
        return history
    }

    func displayQuestion(_ task: ConversationTask) -> String {
        guard let image = image(task.imageID) else { return task.question }
        return "Screenshot \(image.number) · \(task.question)"
    }

    private func makeStream(history: [ChatMessage], options: RequestOptions) -> AsyncThrowingStream<String, Error>? {
        if let streamFactory { return streamFactory(history, options) }
        #if DEBUG
        if let demoStream { return demoStream() }
        #endif
        guard let service = settings.service, let key = settings.apiKey(), !key.isEmpty else { return nil }
        return settings.client.stream(service: service, apiKey: key, messages: history, options: options)
    }

    func copy(_ message: ChatMessage) {
        copyText(message.content)
        copiedID = message.id
        let session = conversationID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.conversationID == session else { return }
            if self.copiedID == message.id { self.copiedID = nil }
        }
    }
}
