import Foundation
import HowlerCore

/// One in-memory conversation. Cleared whenever the panel closes; never written anywhere.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isStreaming = false
    @Published private(set) var errorText: String?
    /// Incremented each time the panel opens so the view can focus the input field.
    @Published private(set) var focusRequest = 0

    let settings: AppSettings
    private var streamTask: Task<Void, Never>?
    /// Bumped on reset so a cancelled stream can't write into the next conversation.
    private var generation = 0

    init(settings: AppSettings) {
        self.settings = settings
    }

    func requestFocus() {
        focusRequest += 1
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        guard let provider = settings.activeProvider,
              let apiKey = settings.apiKey(for: provider), !apiKey.isEmpty
        else {
            errorText = "No API key found. Open Settings to configure a provider."
            return
        }

        input = ""
        errorText = nil
        messages.append(ChatMessage(role: .user, content: text))
        let history = messages
        let reply = ChatMessage(role: .assistant, content: "")
        messages.append(reply)
        isStreaming = true

        let model = settings.model(for: provider)
        let stream = settings.client.stream(
            provider: provider,
            apiKey: apiKey,
            model: model,
            messages: history,
            options: RequestOptions(appName: AppInfo.name)
        )
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
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func reset() {
        generation += 1
        stop()
        messages.removeAll()
        input = ""
        errorText = nil
    }

    private func append(_ delta: String, to id: UUID) {
        guard let index = messages.lastIndex(where: { $0.id == id }) else { return }
        messages[index].content += delta
    }
}
