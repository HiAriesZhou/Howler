import XCTest
@testable import NapkinCore

final class StreamDecoderTests: XCTestCase {
    private func decode(_ data: String, event: String? = nil, _ format: WireFormat) -> StreamDelta {
        StreamDecoder.decode(SSEEvent(event: event, data: data), format: format)
    }

    /// Runs a raw SSE transcript through parser + decoder like `ChatClient` does.
    private func run(_ transcript: String, _ format: WireFormat) -> (text: String, done: Bool, error: String?) {
        var parser = SSEParser()
        var events = parser.feed(transcript)
        if let tail = parser.finish() { events.append(tail) }
        var text = ""
        for event in events {
            switch StreamDecoder.decode(event, format: format) {
            case .text(let delta): text += delta
            case .done: return (text, true, nil)
            case .error(let message): return (text, false, message)
            case .ignore: break
            }
        }
        return (text, false, nil)
    }

    // MARK: OpenAI-compatible

    func testOpenAIDeltas() {
        XCTAssertEqual(decode(#"{"choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}"#, .openAICompatible), .ignore)
        XCTAssertEqual(decode(#"{"choices":[{"index":0,"delta":{"content":"Hel"}}]}"#, .openAICompatible), .text("Hel"))
        XCTAssertEqual(decode(#"{"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#, .openAICompatible), .ignore)
        XCTAssertEqual(decode("[DONE]", .openAICompatible), .done)
        XCTAssertEqual(decode(#"{"choices":[],"usage":{"total_tokens":3}}"#, .openAICompatible), .ignore)
        XCTAssertEqual(decode("not json", .openAICompatible), .ignore)
    }

    func testDeepSeekReasoningContentIsNotShown() {
        let chunk = #"{"choices":[{"index":0,"delta":{"content":null,"reasoning_content":"thinking..."}}]}"#
        XCTAssertEqual(decode(chunk, .openAICompatible), .ignore)
    }

    func testOpenRouterMidStreamError() {
        let chunk = #"{"id":"x","error":{"code":502,"message":"Provider returned error"},"choices":[{"delta":{"content":""},"finish_reason":"error"}]}"#
        XCTAssertEqual(decode(chunk, .openAICompatible), .error("Provider returned error"))
    }

    func testOpenAITranscript() {
        let transcript = """
        : OPENROUTER PROCESSING

        data: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

        data: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"2 + 2"},"finish_reason":null}]}

        data: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":" = **4**"},"finish_reason":null}]}

        data: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

        data: [DONE]


        """
        let result = run(transcript, .openAICompatible)
        XCTAssertEqual(result.text, "2 + 2 = **4**")
        XCTAssertTrue(result.done)
        XCTAssertNil(result.error)
    }

    // MARK: Anthropic

    func testAnthropicTranscript() {
        let transcript = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-opus-5-5"}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"abc"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: content_block_start
        data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

        event: ping
        data: {"type": "ping"}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":", 世界"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":1}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":12}}

        event: message_stop
        data: {"type":"message_stop"}


        """
        let result = run(transcript, .anthropic)
        XCTAssertEqual(result.text, "Hello, 世界")
        XCTAssertTrue(result.done)
        XCTAssertNil(result.error)
    }

    func testAnthropicErrorEvent() {
        let data = #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        XCTAssertEqual(decode(data, event: "error", .anthropic), .error("Overloaded"))
    }

    func testAnthropicRefusal() {
        let data = #"{"type":"message_delta","delta":{"stop_reason":"refusal","stop_details":{"type":"refusal","category":null}},"usage":{"output_tokens":0}}"#
        guard case .error = decode(data, .anthropic) else { return XCTFail("refusal should surface as an error") }
    }

    func testAnthropicTruncationIsReported() {
        for reason in ["max_tokens", "model_context_window_exceeded"] {
            let data = #"{"type":"message_delta","delta":{"stop_reason":"\#(reason)"},"usage":{"output_tokens":64000}}"#
            guard case .error(let message) = decode(data, .anthropic) else {
                return XCTFail("\(reason) should surface as an error")
            }
            XCTAssertTrue(message.contains("cut off"), message)
        }
    }

    func testAnthropicFallbackBlockIsTransparent() {
        let data = #"{"type":"content_block_start","index":0,"content_block":{"type":"fallback","from":{"model":"claude-opus-5-5"},"to":{"model":"claude-opus-4-8"}}}"#
        XCTAssertEqual(decode(data, .anthropic), .ignore)
    }

    // MARK: Gemini

    func testGeminiChunks() {
        let text = #"{"candidates":[{"content":{"parts":[{"text":"Hi "},{"text":"there"}],"role":"model"},"index":0}],"modelVersion":"gemini-x"}"#
        XCTAssertEqual(decode(text, .gemini), .text("Hi there"))

        let thought = #"{"candidates":[{"content":{"parts":[{"text":"pondering","thought":true}],"role":"model"}}]}"#
        XCTAssertEqual(decode(thought, .gemini), .ignore)

        let final = #"{"candidates":[{"content":{"parts":[{"text":""}],"role":"model"},"finishReason":"STOP"}],"usageMetadata":{"totalTokenCount":9}}"#
        XCTAssertEqual(decode(final, .gemini), .ignore)
    }

    func testGeminiErrorsAndBlocks() {
        let error = #"{"error":{"code":400,"message":"API key not valid.","status":"INVALID_ARGUMENT"}}"#
        XCTAssertEqual(decode(error, .gemini), .error("API key not valid."))

        let blocked = #"{"promptFeedback":{"blockReason":"SAFETY"}}"#
        XCTAssertEqual(decode(blocked, .gemini), .error("Prompt blocked by Gemini (SAFETY)."))

        let safety = #"{"candidates":[{"finishReason":"SAFETY"}]}"#
        guard case .error = decode(safety, .gemini) else { return XCTFail("safety stop should be an error") }
    }

    func testGeminiTranscriptEndsWithoutDoneEvent() {
        let transcript = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Line 1\\n\"}],\"role\":\"model\"}}]}\r\n\r\n"
            + "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Line 2\"}],\"role\":\"model\"},\"finishReason\":\"STOP\"}]}\r\n\r\n"
        let result = run(transcript, .gemini)
        XCTAssertEqual(result.text, "Line 1\nLine 2")
        XCTAssertFalse(result.done)
        XCTAssertNil(result.error)
    }

    // MARK: HTTP error bodies

    func testAPIErrorMessages() {
        let openAI = #"{"error":{"message":"Incorrect API key provided.","type":"invalid_request_error","code":"invalid_api_key"}}"#
        XCTAssertEqual(APIErrorParser.message(statusCode: 401, body: Data(openAI.utf8)), "HTTP 401: Incorrect API key provided.")

        let anthropic = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        XCTAssertEqual(APIErrorParser.message(statusCode: 401, body: Data(anthropic.utf8)), "HTTP 401: invalid x-api-key")

        let gemini = #"[{"error":{"code":404,"message":"models/nope is not found","status":"NOT_FOUND"}}]"#
        XCTAssertEqual(APIErrorParser.message(statusCode: 404, body: Data(gemini.utf8)), "HTTP 404: models/nope is not found")

        let plain = #"{"error":"Model not found"}"#
        XCTAssertEqual(APIErrorParser.message(statusCode: 400, body: Data(plain.utf8)), "HTTP 400: Model not found")

        let html = "<html><body>Bad gateway</body></html>"
        XCTAssertTrue(APIErrorParser.message(statusCode: 502, body: Data(html.utf8)).hasPrefix("HTTP 502: "))
        XCTAssertFalse(APIErrorParser.message(statusCode: 502, body: Data(html.utf8)).contains("<html>"))
    }
}
