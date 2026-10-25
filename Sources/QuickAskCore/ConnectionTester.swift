import Foundation

public enum ConnectionTester {
    public static let probePrompt = "Reply with the single word: OK"

    /// Sends a tiny real streaming request. Succeeds as soon as the provider accepts
    /// the request and streams the first piece of text (or ends cleanly), then cancels.
    public static func test(
        client: ChatClient,
        provider: Provider,
        apiKey: String,
        model: String,
        appName: String = "QuickAsk"
    ) async throws {
        let stream = client.stream(
            provider: provider,
            apiKey: apiKey,
            model: model,
            messages: [ChatMessage(role: .user, content: probePrompt)],
            options: RequestOptions(appName: appName, timeout: 30)
        )
        for try await _ in stream {
            break // first delta is enough; leaving the loop cancels the request
        }
    }
}
