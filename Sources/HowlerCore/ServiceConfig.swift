import Foundation

public enum ServiceConfigError: Error, Equatable, LocalizedError {
    case malformed(String)
    case unknownField(String)
    case apiKeyOnCommandLine
    case invalidValue(field: String, reason: String)
    case missing([String])

    public var errorDescription: String? {
        switch self {
        case .malformed(let argument):
            return "Expected field=value, got \"\(argument)\"."
        case .unknownField(let field):
            let fields = ServiceConfig.Field.allCases.map(\.rawValue).joined(separator: ", ")
            return "Unknown field \"\(field)\". Fields: \(fields), api-key."
        case .apiKeyOnCommandLine:
            return "Don't put the API key on the command line. Use: config set api-key --stdin | --env NAME | --file PATH"
        case .invalidValue(let field, let reason):
            return "\(field): \(reason)"
        case .missing(let fields):
            return "Missing \(fields.joined(separator: ", ")). Set them in the same command, or start with preset=…"
        }
    }
}

/// Edits a `ModelService` from `field=value` arguments (`Howler config set …`). Pure: the
/// caller stores the result.
public enum ServiceConfig {
    public enum Field: String, CaseIterable, Sendable {
        case preset
        case format
        case baseURL = "base-url"
        case model
        case body
        case headers
    }

    /// Applies the assignments in order on top of `current` and returns the new service.
    /// `preset=` starts over from a known provider, so later fields refine it.
    public static func apply(_ assignments: [String], to current: ModelService?) throws -> ModelService {
        var format = current?.format
        var baseURL = current?.baseURL
        var model = current?.model
        var body = current?.body ?? [:]
        var headers = current?.headers ?? [:]

        for assignment in assignments {
            guard let equals = assignment.firstIndex(of: "=") else {
                if assignment == "api-key" { throw ServiceConfigError.apiKeyOnCommandLine }
                throw ServiceConfigError.malformed(assignment)
            }
            let name = assignment[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(assignment[assignment.index(after: equals)...])
            if name == "api-key" || name == "apikey" || name == "key" { throw ServiceConfigError.apiKeyOnCommandLine }
            guard let field = Field(rawValue: name) else { throw ServiceConfigError.unknownField(name) }

            switch field {
            case .preset:
                let preset = try parsePreset(value)
                format = preset.wireFormat
                baseURL = preset.baseURL
                model = preset.defaultModel
                body = [:]
                headers = [:]
            case .format:
                format = try parseFormat(value)
            case .baseURL:
                baseURL = try parseBaseURL(value)
            case .model:
                model = try parseModel(value)
            case .body:
                body = try parseObject(value, field: .body)
            case .headers:
                headers = try parseHeaders(value)
            }
        }

        var missing: [String] = []
        if format == nil { missing.append(Field.format.rawValue) }
        if baseURL == nil { missing.append(Field.baseURL.rawValue) }
        if model == nil { missing.append(Field.model.rawValue) }
        guard let format, let baseURL, let model, missing.isEmpty else { throw ServiceConfigError.missing(missing) }

        let clashes = Set(body.keys).intersection(ModelService.reservedBodyKeys(for: format)).sorted()
        if !clashes.isEmpty {
            throw ServiceConfigError.invalidValue(
                field: Field.body.rawValue,
                reason: "\(clashes.joined(separator: ", ")) is written by Howler and can't be set in body."
            )
        }
        return ModelService(format: format, baseURL: baseURL, model: model, body: body, headers: headers)
    }

    // MARK: Values

    static func parsePreset(_ value: String) throws -> Provider {
        let name = value.trimmingCharacters(in: .whitespaces).lowercased()
        guard let provider = Provider(rawValue: name) else {
            let names = Provider.allCases.map(\.rawValue).joined(separator: ", ")
            throw ServiceConfigError.invalidValue(field: Field.preset.rawValue, reason: "use one of \(names).")
        }
        return provider
    }

    static func parseFormat(_ value: String) throws -> WireFormat {
        let name = value.trimmingCharacters(in: .whitespaces).lowercased()
        guard let format = WireFormat(rawValue: name) else {
            let names = WireFormat.allCases.map(\.rawValue).joined(separator: ", ")
            throw ServiceConfigError.invalidValue(field: Field.format.rawValue, reason: "use one of \(names).")
        }
        return format
    }

    /// HTTPS, or plain HTTP to this Mac (local servers such as Ollama or LM Studio).
    static func parseBaseURL(_ value: String) throws -> URL {
        var text = value.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("/") { text.removeLast() }
        let field = Field.baseURL.rawValue
        guard let components = URLComponents(string: text), let host = components.host, !host.isEmpty,
              let scheme = components.scheme?.lowercased(), let url = components.url
        else { throw ServiceConfigError.invalidValue(field: field, reason: "not a URL: \(value)") }
        guard components.query == nil, components.fragment == nil, components.user == nil else {
            throw ServiceConfigError.invalidValue(field: field, reason: "leave out query strings, fragments and credentials.")
        }
        let isLocal = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
        guard scheme == "https" || (scheme == "http" && isLocal) else {
            throw ServiceConfigError.invalidValue(field: field, reason: "use https:// (http:// only for localhost).")
        }
        return url
    }

    static func parseModel(_ value: String) throws -> String {
        let model = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !model.contains(where: \.isWhitespace) else {
            throw ServiceConfigError.invalidValue(field: Field.model.rawValue, reason: "a model name without spaces, e.g. deepseek-flash.")
        }
        return model
    }

    static func parseObject(_ value: String, field: Field) throws -> [String: JSONValue] {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [:] }
        do {
            return try JSONValue.object(from: text)
        } catch {
            throw ServiceConfigError.invalidValue(field: field.rawValue, reason: "a JSON object, e.g. {\"key\": \"value\"}.")
        }
    }

    static func parseHeaders(_ value: String) throws -> [String: String] {
        let field = Field.headers.rawValue
        var headers: [String: String] = [:]
        for (name, value) in try parseObject(value, field: .headers) {
            guard case .string(let text) = value else {
                throw ServiceConfigError.invalidValue(field: field, reason: "header values must be strings.")
            }
            guard !ModelService.reservedHeaders.contains(name.lowercased()) else {
                throw ServiceConfigError.invalidValue(field: field, reason: "\(name) carries the API key; set it with config set api-key.")
            }
            headers[name] = text
        }
        return headers
    }
}
