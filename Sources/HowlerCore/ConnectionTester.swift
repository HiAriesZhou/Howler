import Foundation

public enum ConnectionTesterError: Error, Equatable, LocalizedError {
    case noText

    public var errorDescription: String? {
        switch self {
        case .noText: return "The service answered without any text. Check the model name."
        }
    }
}

public enum ConnectionTester {
    public static let probePrompt = "Reply with the single word: OK"
    /// Idle timeout for the probe; reasoning models can think for a while before the first token.
    public static let timeout: TimeInterval = 120
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
        systemPrompt: String? = nil
    ) async throws {
        let stream = client.stream(
            service: service,
            apiKey: apiKey,
            messages: probeMessages,
            options: probeOptions(appName: appName, systemPrompt: systemPrompt)
        )
        for try await _ in stream {
            return // first text delta is enough; leaving the loop cancels the request
        }
        throw ConnectionTesterError.noText
    }
}
