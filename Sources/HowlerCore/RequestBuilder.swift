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
    /// Idle timeout: the longest silence allowed between bytes. Reasoning models can stay
    /// silent for minutes before the first token; `ChatClient`'s 600s resource timeout still
    /// caps the whole request.
    public var timeout: TimeInterval

    public init(maxTokens: Int? = nil, appName: String = "Howler", timeout: TimeInterval = 600) {
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

/// Builds streaming HTTP requests for a model service. Pure: no I/O.
public enum RequestBuilder {
    public static let anthropicVersion = "2026-10-21"
    public static let anthropicDefaultMaxTokens = 64_000
    /// Anthropic models that accept server-side refusal fallbacks (`fallbacks: "default"`).
    public static let anthropicFallbackModels: Set<String> = [
        "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
    ]
    public static let anthropicFallbackBeta = "server-side-fallback-2026-07-01"
    public static let projectURL = "https://github.com/HiAriesZhou/Howler"

    public static func streamingRequest(
        service: ModelService,
        apiKey: String,
        messages: [ChatMessage],
        options: RequestOptions = RequestOptions()
    ) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw RequestBuilderError.missingAPIKey }
        let turns = normalize(messages)
        guard !turns.isEmpty else { throw RequestBuilderError.noMessages }
        // Whether a model reads images is up to the service; its own error says when it can't.
        let known = service.knownProvider
        let model = service.model

        var request: URLRequest
        var body: [String: Any]
        switch service.format {
        case .openAICompatible:
            request = URLRequest(url: service.baseURL.appendingPathComponent("chat/completions"))
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            if known == .openRouter {
                request.setValue(projectURL, forHTTPHeaderField: "HTTP-Referer")
                request.setValue(options.appName, forHTTPHeaderField: "X-Title")
            }
            body = [
                "model": model,
                "stream": true,
                "messages": turns.map { ["role": $0.role.rawValue, "content": openAIContent($0)] },
            ]

        case .anthropic:
            request = URLRequest(url: service.baseURL.appendingPathComponent("messages"))
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
            var anthropicBody: [String: Any] = [
                "model": model,
                "stream": true,
                "max_tokens": options.maxTokens ?? anthropicDefaultMaxTokens,
                "messages": turns.map { ["role": $0.role.rawValue, "content": anthropicContent($0)] },
            ]
            if known == .anthropic, anthropicFallbackModels.contains(model) {
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
                url: service.baseURL, resolvingAgainstBaseURL: false
            )!
            components.percentEncodedPath += "/models/\(modelPath):streamGenerateContent"
            components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
            request = URLRequest(url: components.url!)
            // Header rather than `?key=` so the key never appears in a URL.
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            var geminiBody: [String: Any] = [
                "contents": turns.map {
                    ["role": $0.role == .user ? "user" : "model", "parts": geminiParts($0)]
                },
            ]
            if let maxTokens = options.maxTokens {
                geminiBody["generationConfig"] = ["maxOutputTokens": maxTokens]
            }
            body = geminiBody
        }

        // The service's own fields (e.g. turning thinking off) override Howler's defaults.
        for (name, value) in service.body where !ModelService.reservedBodyKeys(for: service.format).contains(name) {
            body[name] = value.foundationValue
        }
        for (name, value) in service.headers where !ModelService.reservedHeaders.contains(name.lowercased()) {
            request.setValue(value, forHTTPHeaderField: name)
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
    /// Attached text is folded into `content`, so the result holds exactly what is sent;
    /// an attached image stays as the turn's attachment.
    public static func normalize(_ messages: [ChatMessage]) -> [ChatMessage] {
        var result: [ChatMessage] = []
        for message in messages {
            let wire = message.wireContent
            guard !wire.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let picture = message.attachment.flatMap { $0.image == nil ? nil : $0 }
            if let last = result.last, last.role == message.role {
                result[result.count - 1].content = last.content + "\n\n" + wire
                if last.attachment == nil { result[result.count - 1].attachment = picture }
            } else {
                result.append(ChatMessage(id: message.id, role: message.role, content: wire, attachment: picture))
            }
        }
        // A conversation must start with the user.
        while let first = result.first, first.role != .user { result.removeFirst() }
        return result
    }

    // MARK: Multimodal content

    /// A plain string, or text + image parts when the turn carries a picture.
    private static func openAIContent(_ turn: ChatMessage) -> Any {
        guard let image = turn.image else { return turn.content }
        return [
            ["type": "text", "text": turn.content],
            ["type": "image_url", "image_url": ["url": "data:\(image.mediaType);base64,\(image.data.base64EncodedString())"]],
        ]
    }

    /// Anthropic recommends the image before the text that refers to it.
    private static func anthropicContent(_ turn: ChatMessage) -> Any {
        guard let image = turn.image else { return turn.content }
        return [
            ["type": "image", "source": ["type": "base64", "media_type": image.mediaType, "data": image.data.base64EncodedString()]],
            ["type": "text", "text": turn.content],
        ]
    }

    private static func geminiParts(_ turn: ChatMessage) -> [[String: Any]] {
        guard let image = turn.image else { return [["text": turn.content]] }
        return [
            ["inline_data": ["mime_type": image.mediaType, "data": image.data.base64EncodedString()]],
            ["text": turn.content],
        ]
    }

    private static let geminiModelAllowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._"
    )
}
