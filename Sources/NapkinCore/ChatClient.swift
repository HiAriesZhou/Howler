import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ChatClientError: Error, Equatable, LocalizedError {
    case http(status: Int, message: String)
    case stream(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .http(_, let message): return message
        case .stream(let message): return message
        case .invalidResponse: return "Unexpected response from server."
        }
    }
}

/// Streams a chat completion from any supported provider.
///
/// Uses an ephemeral `URLSession` so nothing (requests, responses, cookies) is
/// cached to disk, and never logs request or response content.
public final class ChatClient: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForResource = 600
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Yields text deltas as they arrive. Cancelling the consuming task cancels the request.
    public func stream(
        provider: Provider,
        apiKey: String,
        model: String,
        messages: [ChatMessage],
        options: RequestOptions = RequestOptions()
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try RequestBuilder.streamingRequest(
                        provider: provider, apiKey: apiKey, model: model,
                        messages: messages, options: options
                    )
                    try await self.run(request, format: provider.wireFormat) { text in
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ request: URLRequest,
        format: WireFormat,
        onText: @escaping (String) -> Void
    ) async throws {
        let (bytes, response) = try await responseBytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatClientError.invalidResponse }

        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count >= 64 * 1024 { break }
            }
            throw ChatClientError.http(
                status: http.statusCode,
                message: APIErrorParser.message(statusCode: http.statusCode, body: body)
            )
        }

        var parser = SSEParser()
        // Returns true when the provider signalled the end of the reply.
        func handle(_ event: SSEEvent) throws -> Bool {
            switch StreamDecoder.decode(event, format: format) {
            case .text(let text): onText(text)
            case .done: return true
            case .error(let message): throw ChatClientError.stream(message)
            case .ignore: break
            }
            return false
        }

        for try await byte in bytes {
            if let event = parser.feed(byte), try handle(event) { return }
        }
        try Task.checkCancellation()
        if let event = parser.finish() { _ = try handle(event) }
    }

    #if canImport(Darwin)
    private func responseBytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try await session.bytes(for: request)
    }
    #else
    /// swift-corelibs-foundation has no `URLSession.bytes(for:)`. The app ships on macOS only;
    /// this buffered path exists so the core library and its tests build and run on Linux.
    private func responseBytes(for request: URLRequest) async throws -> (AsyncStream<UInt8>, URLResponse) {
        let (data, response) = try await session.data(for: request)
        let bytes = AsyncStream<UInt8> { continuation in
            for byte in data { continuation.yield(byte) }
            continuation.finish()
        }
        return (bytes, response)
    }
    #endif
}
