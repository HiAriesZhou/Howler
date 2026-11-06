import Foundation

public enum ConnectionTesterError: Error, Equatable, LocalizedError {
    case noText
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .noText: return "The service answered without any text. Check the model name."
        case .timedOut: return "The connection check timed out. Verify the service and network, then retry once."
        }
    }
}

public enum ConnectionTester {
    public static let probePrompt = "Reply with the single word: OK"
    /// A setup probe is bounded independently of normal conversation timeouts.
    public static let timeout: TimeInterval = 30
    public static let probeMessages = [ChatMessage(role: .user, content: probePrompt)]

    /// Carries the system prompt too, so a service that rejects one fails the check
    /// rather than the first question.
    public static func probeOptions(appName: String, systemPrompt: String? = nil) -> RequestOptions {
        RequestOptions(appName: appName, timeout: timeout, systemPrompt: systemPrompt)
    }

    /// Sends a tiny real streaming request. Succeeds as soon as the service streams the
    /// first piece of visible text, then cancels. A stream that ends without text fails.
    public static func test(
        client: ChatClient,
        service: ModelService,
        apiKey: String,
        appName: String = "Howler",
        systemPrompt: String? = nil,
        replyLanguage: String? = nil,
        deadline: Duration = .seconds(30)
    ) async throws {
        let stream = client.stream(
            service: service,
            apiKey: apiKey,
            messages: replyLanguage.map {
                [ChatMessage(role: .user, content: probePrompt, taskInstructions: ReplyLanguage.instruction($0))]
            } ?? probeMessages,
            options: probeOptions(appName: appName, systemPrompt: systemPrompt)
        )
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await _ in stream { return }
                throw ConnectionTesterError.noText
            }
            group.addTask {
                try await Task.sleep(for: deadline)
                throw ConnectionTesterError.timedOut
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }
}
