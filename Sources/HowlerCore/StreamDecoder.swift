import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One thing an SSE event means for the chat transcript. A single event can carry
/// several (e.g. the last text chunk together with the stop reason).
public enum StreamDelta: Equatable, Sendable {
    /// Text to append to the assistant reply.
    case text(String)
    /// The provider signalled that the reply finished normally.
    case done
    /// The provider reported an error, or the reply stopped early (truncation, safety filter).
    case error(String)
}

/// Turns provider-specific SSE events into `StreamDelta`s. Bookkeeping events (role headers,
/// pings, usage, thinking) decode to an empty list.
public enum StreamDecoder {
    public static let truncatedMessage = "The reply was cut off: it reached the output token limit."
    public static let contextExceededMessage = "The reply was cut off: the conversation reached the model's context limit."

    public static func decode(_ event: SSEEvent, format: WireFormat) -> [StreamDelta] {
        switch format {
        case .openAICompatible: return decodeOpenAI(event)
        case .anthropic: return decodeAnthropic(event)
        case .gemini: return decodeGemini(event)
        }
    }

    /// Text first, so nothing already generated is lost when the same chunk ends the reply.
    private static func deltas(text: String, ending: StreamDelta?) -> [StreamDelta] {
        var result: [StreamDelta] = []
        if !text.isEmpty { result.append(.text(text)) }
        if let ending { result.append(ending) }
        return result
    }

    // MARK: OpenAI-compatible (OpenAI, xAI, DeepSeek, OpenRouter)

    private struct OpenAIChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
            let finish_reason: String?
        }
        let choices: [Choice]?
        let error: APIErrorBody?
    }

    static func decodeOpenAI(_ event: SSEEvent) -> [StreamDelta] {
        let data = event.data.trimmingCharacters(in: .whitespacesAndNewlines)
        if data == "[DONE]" { return [.done] }
        guard let chunk = try? JSONDecoder().decode(OpenAIChunk.self, from: Data(data.utf8)) else {
            return []
        }
        if let error = chunk.error { return [.error(error.text)] }
        let text = (chunk.choices ?? []).compactMap { $0.delta?.content }.joined()
        return deltas(text: text, ending: openAIEnding(chunk.choices?.first?.finish_reason))
    }

    private static func openAIEnding(_ reason: String?) -> StreamDelta? {
        switch reason {
        case nil, "": return nil // some gateways send "" on intermediate chunks
        case "length": return .error(truncatedMessage)
        case "insufficient_system_resource": // DeepSeek: interrupted by server load
            return .error("The provider ran out of capacity and stopped the reply early.")
        case "content_filter": return .error("Response blocked by the provider's content filter.")
        case "error": return .error("The provider reported an error while answering.")
        default: return .done // "stop", "tool_calls", …
        }
    }

    // MARK: Anthropic Messages

    private struct AnthropicEvent: Decodable {
        struct Delta: Decodable {
            let type: String?
            let text: String?
            let stop_reason: String?
        }
        let type: String
        let delta: Delta?
        let error: APIErrorBody?
    }

    static func decodeAnthropic(_ event: SSEEvent) -> [StreamDelta] {
        guard let payload = try? JSONDecoder().decode(AnthropicEvent.self, from: Data(event.data.utf8)) else {
            return []
        }
        switch payload.type {
        case "content_block_delta":
            // Only visible text; thinking/signature/tool-input deltas are not shown.
            guard payload.delta?.type == "text_delta" else { return [] }
            return deltas(text: payload.delta?.text ?? "", ending: nil)
        case "message_delta":
            switch payload.delta?.stop_reason {
            case "refusal":
                return [.error("The model declined to answer this request.")]
            case "max_tokens":
                // Thinking shares the budget, so this can happen on long answers.
                return [.error(truncatedMessage)]
            case "model_context_window_exceeded":
                return [.error(contextExceededMessage)]
            case "end_turn", "stop_sequence":
                // Finished; don't depend on the trailing message_stop arriving.
                return [.done]
            default:
                return [] // message_stop follows
            }
        case "message_stop":
            return [.done]
        case "error":
            return [.error(payload.error?.text ?? "Unknown streaming error.")]
        default:
            return []
        }
    }

    // MARK: Gemini streamGenerateContent (alt=sse)

    private struct GeminiChunk: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                    let thought: Bool?
                }
                let parts: [Part]?
            }
            let content: Content?
            let finishReason: String?
        }
        struct PromptFeedback: Decodable { let blockReason: String? }
        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?
        let error: APIErrorBody?
    }

    static func decodeGemini(_ event: SSEEvent) -> [StreamDelta] {
        guard let chunk = try? JSONDecoder().decode(GeminiChunk.self, from: Data(event.data.utf8)) else {
            return []
        }
        if let error = chunk.error { return [.error(error.text)] }
        if let reason = chunk.promptFeedback?.blockReason {
            return [.error("Prompt blocked by Gemini (\(reason)).")]
        }
        let candidate = chunk.candidates?.first
        let parts = candidate?.content?.parts ?? []
        let text = parts.filter { $0.thought != true }.compactMap(\.text).joined()
        return deltas(text: text, ending: geminiEnding(candidate?.finishReason))
    }

    /// Gemini has no terminal event: the chunk carrying `finishReason` is the last one.
    private static func geminiEnding(_ reason: String?) -> StreamDelta? {
        switch reason {
        case nil, "FINISH_REASON_UNSPECIFIED": return nil
        case "STOP": return .done
        case "MAX_TOKENS": return .error(truncatedMessage)
        case "SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION", "IMAGE_SAFETY":
            return .error("Response blocked by Gemini (\(reason!)).")
        case let other?: return .error("Gemini stopped the reply early (\(other)).")
        }
    }
}

/// `{"message": "...", "type"/"code"/"status": ...}` — the shape shared by every provider's error object.
struct APIErrorBody: Decodable {
    let message: String?
    let type: String?
    let status: String?

    var text: String {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return type ?? status ?? "Unknown error."
    }
}

public enum APIErrorParser {
    private struct Envelope: Decodable {
        let error: APIErrorBody?
        let message: String?
    }

    /// Human-readable message for a non-2xx response body from any supported provider.
    public static func message(statusCode: Int, body: Data) -> String {
        let detail = extract(body)
        let prefix = "HTTP \(statusCode)"
        if let detail { return "\(prefix): \(detail)" }
        return "\(prefix): \(HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized)"
    }

    static func extract(_ body: Data) -> String? {
        let decoder = JSONDecoder()
        // OpenAI / xAI / DeepSeek / OpenRouter / Anthropic / Gemini: {"error": {"message": ...}}
        if let envelope = try? decoder.decode(Envelope.self, from: body) {
            if let error = envelope.error { return error.text }
            if let message = envelope.message, !message.isEmpty { return message }
        }
        // Gemini sometimes wraps the error in an array.
        if let list = try? decoder.decode([Envelope].self, from: body),
           let error = list.first?.error {
            return error.text
        }
        // Some gateways return {"error": "plain string"}.
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let text = object["error"] as? String, !text.isEmpty {
            return text
        }
        let text = String(decoding: body.prefix(300), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text.hasPrefix("<") ? nil : text
    }
}
