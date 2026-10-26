import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What one SSE event means for the chat transcript.
public enum StreamDelta: Equatable, Sendable {
    /// Text to append to the assistant reply.
    case text(String)
    /// The provider signalled the end of the reply.
    case done
    /// The provider reported an error inside the stream.
    case error(String)
    /// Bookkeeping event with nothing to show (role headers, pings, usage, thinking).
    case ignore
}

/// Turns provider-specific SSE events into `StreamDelta`s.
public enum StreamDecoder {
    public static func decode(_ event: SSEEvent, format: WireFormat) -> StreamDelta {
        switch format {
        case .openAICompatible: return decodeOpenAI(event)
        case .anthropic: return decodeAnthropic(event)
        case .gemini: return decodeGemini(event)
        }
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

    static func decodeOpenAI(_ event: SSEEvent) -> StreamDelta {
        let data = event.data.trimmingCharacters(in: .whitespacesAndNewlines)
        if data == "[DONE]" { return .done }
        guard let chunk = try? JSONDecoder().decode(OpenAIChunk.self, from: Data(data.utf8)) else {
            return .ignore
        }
        if let error = chunk.error { return .error(error.text) }
        let text = (chunk.choices ?? []).compactMap { $0.delta?.content }.joined()
        if !text.isEmpty { return .text(text) }
        if chunk.choices?.first?.finish_reason == "content_filter" {
            return .error("Response blocked by the provider's content filter.")
        }
        return .ignore
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

    static func decodeAnthropic(_ event: SSEEvent) -> StreamDelta {
        guard let payload = try? JSONDecoder().decode(AnthropicEvent.self, from: Data(event.data.utf8)) else {
            return .ignore
        }
        switch payload.type {
        case "content_block_delta":
            // Only visible text; thinking/signature/tool-input deltas are not shown.
            if payload.delta?.type == "text_delta", let text = payload.delta?.text, !text.isEmpty {
                return .text(text)
            }
            return .ignore
        case "message_delta":
            switch payload.delta?.stop_reason {
            case "refusal":
                return .error("The model declined to answer this request.")
            case "max_tokens":
                // Thinking shares the budget, so this can happen on long answers.
                return .error("The reply was cut off: it reached the output token limit.")
            case "model_context_window_exceeded":
                return .error("The reply was cut off: the conversation reached the model's context limit.")
            default:
                return .ignore
            }
        case "message_stop":
            return .done
        case "error":
            return .error(payload.error?.text ?? "Unknown streaming error.")
        default:
            return .ignore
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

    static func decodeGemini(_ event: SSEEvent) -> StreamDelta {
        guard let chunk = try? JSONDecoder().decode(GeminiChunk.self, from: Data(event.data.utf8)) else {
            return .ignore
        }
        if let error = chunk.error { return .error(error.text) }
        if let reason = chunk.promptFeedback?.blockReason {
            return .error("Prompt blocked by Gemini (\(reason)).")
        }
        let parts = chunk.candidates?.first?.content?.parts ?? []
        let text = parts.filter { $0.thought != true }.compactMap(\.text).joined()
        if !text.isEmpty { return .text(text) }
        switch chunk.candidates?.first?.finishReason {
        case "SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION":
            return .error("Response blocked by Gemini (\(chunk.candidates!.first!.finishReason!)).")
        default:
            // Gemini has no terminal event; the stream simply ends.
            return .ignore
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
