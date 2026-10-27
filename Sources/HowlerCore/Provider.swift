import Foundation

/// How a model service's streaming endpoint is shaped on the wire. The raw values are the
/// names used by `Howler config set format=…`.
public enum WireFormat: String, CaseIterable, Codable, Sendable {
    /// `POST {base}/chat/completions` with `stream: true` (OpenAI and compatible APIs).
    case openAICompatible = "chat-completions"
    /// `POST {base}/messages` with `stream: true`.
    case anthropic = "anthropic-messages"
    /// `POST {base}/models/{model}:streamGenerateContent?alt=sse`.
    case gemini = "gemini-generate-content"

    public var displayName: String {
        switch self {
        case .openAICompatible: return "Chat Completions"
        case .anthropic: return "Anthropic Messages"
        case .gemini: return "Gemini generateContent"
        }
    }
}

/// A provider's icon. We never bundle trademarked logos: either an SF Symbol or a
/// monochrome letter mark drawn by the UI.
public enum ProviderGlyph: Equatable, Sendable {
    case symbol(String)
    case letters(String)
}

/// Well-known model services. They are presets (`Howler config set preset=deepseek`) and
/// give a configured service its seal mark; the service itself is any `ModelService`.
public enum Provider: String, CaseIterable, Identifiable, Codable, Sendable {
    case openAI = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case xAI = "xai"
    case deepSeek = "deepseek"
    case openRouter = "openrouter"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .xAI: return "xAI"
        case .deepSeek: return "DeepSeek"
        case .openRouter: return "OpenRouter"
        }
    }

    public var glyph: ProviderGlyph {
        switch self {
        case .openAI: return .letters("O")
        case .anthropic: return .letters("A")
        case .gemini: return .symbol("sparkle")
        case .xAI: return .letters("x")
        case .deepSeek: return .letters("D")
        case .openRouter: return .symbol("arrow.triangle.branch")
        }
    }

    public var wireFormat: WireFormat {
        switch self {
        case .anthropic: return .anthropic
        case .gemini: return .gemini
        case .openAI, .xAI, .deepSeek, .openRouter: return .openAICompatible
        }
    }

    /// Model used when the user leaves the model field empty.
    public var defaultModel: String {
        switch self {
        case .openAI: return "gpt-5.4-mini"
        case .anthropic: return "claude-opus-5-5"
        case .gemini: return "gemini-3.6-flash"
        case .xAI: return "grok-4.6"
        case .deepSeek: return "deepseek-flash"
        case .openRouter: return "openrouter/auto"
        }
    }

    public var baseURL: URL {
        switch self {
        case .openAI: return URL(string: "https://api.openai.com/v1")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1")!
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta")!
        case .xAI: return URL(string: "https://api.x.ai/v1")!
        case .deepSeek: return URL(string: "https://api.deepseek.com")!
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1")!
        }
    }

    /// Model to use for a user-entered value; blank falls back to the default.
    public func resolvedModel(_ userValue: String?) -> String {
        let trimmed = userValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultModel : trimmed
    }

    /// This provider as a model service; a blank model means the default one.
    public func service(model: String? = nil) -> ModelService {
        ModelService(format: wireFormat, baseURL: baseURL, model: resolvedModel(model))
    }

    /// The well-known provider behind `host`, if any.
    public init?(host: String) {
        guard let match = Provider.allCases.first(where: { $0.baseURL.host == host.lowercased() }) else { return nil }
        self = match
    }
}
