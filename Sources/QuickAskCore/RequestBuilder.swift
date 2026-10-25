import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct RequestOptions: Equatable, Sendable {
    /// Output cap. Required by Anthropic; optional for Gemini; not sent to
    /// OpenAI-compatible APIs (their models pick their own limits).
    public var maxTokens: Int?
    /// Shown to OpenRouter as the calling app (`X-Title`).
    public var appName: String
    public var timeout: TimeInterval

    public init(maxTokens: Int? = nil, appName: String = "QuickAsk", timeout: TimeInterval = 120) {
        self.maxTokens = maxTokens
        self.appName = appName
        self.timeout = timeout
    }
}

public enum RequestBuilderError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case noMessages
    case invalidModel(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "API key is missing."
        case .noMessages: return "Nothing to send."
        case .invalidModel(let model): return "Invalid model name: \(model)"
        }
    }
}

/// Builds streaming HTTP requests for each provider. Pure: no I/O.
public enum RequestBuilder {
    public static let anthropicVersion = "2026-10-21"
    public static let anthropicDefaultMaxTokens = 64_000
    /// Anthropic models that accept server-side refusal fallbacks (`fallbacks: "default"`).
    public static let anthropicFallbackModels: Set<String> = [
        "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
    ]
    public static let anthropicFallbackBeta = "server-side-fallback-2026-07-01"
    public static let projectURL = "https://github.com/HiAriesZhou/QuickAsk"

    public static func streamingRequest(
        provider: Provider,
        apiKey: String,
        model: String,
        messages: [ChatMessage],
        options: RequestOptions = RequestOptions()
    ) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw RequestBuilderError.missingAPIKey }
        let turns = normalize(messages)
        guard !turns.isEmpty else { throw RequestBuilderError.noMessages }
        let model = provider.resolvedModel(model)

        var request: URLRequest
        let body: [String: Any]
        switch provider.wireFormat {
        case .openAICompatible:
            request = URLRequest(url: provider.baseURL.appendingPathComponent("chat/completions"))
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            if provider == .openRouter {
                request.setValue(projectURL, forHTTPHeaderField: "HTTP-Referer")
                request.setValue(options.appName, forHTTPHeaderField: "X-Title")
            }
            body = [
                "model": model,
                "stream": true,
                "messages": turns.map { ["role": $0.role.rawValue, "content": $0.content] },
            ]

        case .anthropic:
            request = URLRequest(url: provider.baseURL.appendingPathComponent("messages"))
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
            var anthropicBody: [String: Any] = [
                "model": model,
                "stream": true,
                "max_tokens": options.maxTokens ?? anthropicDefaultMaxTokens,
                "messages": turns.map { ["role": $0.role.rawValue, "content": $0.content] },
            ]
            if anthropicFallbackModels.contains(model) {
                request.setValue(anthropicFallbackBeta, forHTTPHeaderField: "anthropic-beta")
                anthropicBody["fallbacks"] = "default"
            }
            body = anthropicBody

        case .gemini:
            let geminiModel = model.hasPrefix("models/") ? String(model.dropFirst(7)) : model
            guard !geminiModel.contains("/"),
                  let modelPath = geminiModel.addingPercentEncoding(withAllowedCharacters: geminiModelAllowed)
            else { throw RequestBuilderError.invalidModel(model) }
            var components = URLComponents(
                url: provider.baseURL, resolvingAgainstBaseURL: false
            )!
            components.percentEncodedPath += "/models/\(modelPath):streamGenerateContent"
            components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
            request = URLRequest(url: components.url!)
            // Header rather than `?key=` so the key never appears in a URL.
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            var geminiBody: [String: Any] = [
                "contents": turns.map {
                    ["role": $0.role == .user ? "user" : "model", "parts": [["text": $0.content]]]
                },
            ]
            if let maxTokens = options.maxTokens {
                geminiBody["generationConfig"] = ["maxOutputTokens": maxTokens]
            }
            body = geminiBody
        }

        request.httpMethod = "POST"
        request.timeoutInterval = options.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// Drops empty turns (e.g. a reply that failed before any text arrived) and merges
    /// consecutive turns of the same role so every provider sees strictly alternating roles.
    public static func normalize(_ messages: [ChatMessage]) -> [ChatMessage] {
        var result: [ChatMessage] = []
        for message in messages {
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let last = result.last, last.role == message.role {
                result[result.count - 1].content = last.content + "\n\n" + message.content
            } else {
                result.append(message)
            }
        }
        // A conversation must start with the user.
        while let first = result.first, first.role != .user { result.removeFirst() }
        return result
    }

    private static let geminiModelAllowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._"
    )
}
