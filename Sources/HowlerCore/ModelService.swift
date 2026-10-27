import Foundation

/// The one model service Howler writes with: how to reach it and what to ask for.
/// The API key is not part of it; it lives in the Keychain.
public struct ModelService: Codable, Equatable, Sendable {
    public var format: WireFormat
    /// Base of the API, e.g. `https://api.deepseek.com`; the format adds the endpoint path.
    public var baseURL: URL
    public var model: String
    /// Extra top-level request-body fields, e.g. `{"thinking": {"type": "disabled"}}`.
    public var body: [String: JSONValue]
    /// Extra HTTP headers. Never the API key.
    public var headers: [String: String]

    public init(
        format: WireFormat,
        baseURL: URL,
        model: String,
        body: [String: JSONValue] = [:],
        headers: [String: String] = [:]
    ) {
        self.format = format
        self.baseURL = baseURL
        self.model = model
        self.body = body
        self.headers = headers
    }

    public var host: String {
        baseURL.host ?? baseURL.absoluteString
    }

    /// The well-known provider at this address, if any.
    public var knownProvider: Provider? {
        Provider(host: host)
    }

    /// The mark pressed into the wax seal: a known provider's own, else the first letter of
    /// the service's name in its host (`api.moonshot.cn` → "M").
    public var glyph: ProviderGlyph {
        if let knownProvider { return knownProvider.glyph }
        let labels = host.split(separator: ".").filter { !["api", "www"].contains($0.lowercased()) }
        let initial = labels.first?.first(where: \.isLetter).map { String($0).uppercased() }
        return .letters(initial ?? "?")
    }

    /// "deepseek-flash · api.deepseek.com · Chat Completions"
    public var summary: String {
        "\(model) · \(host) · \(format.displayName)"
    }

    /// The URL requests go to, as shown to people; Gemini's names the model.
    public var endpointDescription: String {
        let base = baseURL.absoluteString
        switch format {
        case .openAICompatible: return base + "/chat/completions"
        case .anthropic: return base + "/messages"
        case .gemini: return base + "/models/\(model):streamGenerateContent?alt=sse"
        }
    }

    /// Body fields Howler writes itself; `body` may not replace them.
    public static func reservedBodyKeys(for format: WireFormat) -> Set<String> {
        switch format {
        case .openAICompatible, .anthropic: return ["model", "stream", "messages"]
        case .gemini: return ["contents"]
        }
    }

    /// Header names that would carry the API key; it only ever comes from the Keychain.
    public static let reservedHeaders: Set<String> = ["authorization", "x-api-key", "x-goog-api-key"]
}
