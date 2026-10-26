import Foundation

public enum ConnectionTesterError: Error, Equatable, LocalizedError {
    case noText

    public var errorDescription: String? {
        switch self {
        case .noText: return "The provider answered without any text. Check the model name."
        }
    }
}

public enum ConnectionTester {
    public static let probePrompt = "Reply with the single word: OK"
    /// Idle timeout for the probe; reasoning models can think for a while before the first token.
    public static let timeout: TimeInterval = 120

    /// Sends a tiny real streaming request. Succeeds as soon as the provider streams the
    /// first piece of visible text, then cancels. A stream that ends without text fails.
    public static func test(
        client: ChatClient,
        provider: Provider,
        apiKey: String,
        model: String,
        appName: String = "Napkin"
    ) async throws {
        let stream = client.stream(
            provider: provider,
            apiKey: apiKey,
            model: model,
            messages: [ChatMessage(role: .user, content: probePrompt)],
            options: RequestOptions(appName: appName, timeout: timeout)
        )
        for try await _ in stream {
            return // first text delta is enough; leaving the loop cancels the request
        }
        throw ConnectionTesterError.noText
    }
}
