import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import HowlerCore

/// Serves canned responses so `ChatClient` can be exercised end to end without network.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        var status: Int
        var body: Data
    }

    static var stub = Stub(status: 200, body: Data())
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.stub.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Deliver in small chunks to exercise incremental parsing. swift-corelibs-foundation
        // keeps only the last chunk a custom URLProtocol loads, so send it whole there.
        #if canImport(Darwin)
        let chunkSize = 7
        #else
        let chunkSize = max(Self.stub.body.count, 1)
        #endif
        var offset = 0
        while offset < Self.stub.body.count {
            let end = min(offset + chunkSize, Self.stub.body.count)
            client?.urlProtocol(self, didLoad: Self.stub.body.subdata(in: offset..<end))
            offset = end
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ChatClientTests: XCTestCase {
    private func makeClient() -> ChatClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return ChatClient(session: URLSession(configuration: configuration))
    }

    private func collect(_ provider: Provider) async throws -> String {
        var text = ""
        for try await delta in makeClient().stream(
            provider: provider, apiKey: "k", model: "",
            messages: [ChatMessage(role: .user, content: "hi")]
        ) {
            text += delta
        }
        return text
    }

    func testStreamsOpenAICompatibleText() async throws {
        StubURLProtocol.stub = .init(status: 200, body: Data("""
        data: {"choices":[{"delta":{"content":"你好"}}]}

        data: {"choices":[{"delta":{"content":", world"}}]}

        data: [DONE]


        """.utf8))
        let text = try await collect(.deepSeek)
        XCTAssertEqual(text, "你好, world")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.host, "api.deepseek.com")
    }

    func testStreamsAnthropicText() async throws {
        StubURLProtocol.stub = .init(status: 200, body: Data("""
        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"OK"}}

        event: message_stop
        data: {"type":"message_stop"}


        """.utf8))
        let text = try await collect(.anthropic)
        XCTAssertEqual(text, "OK")
    }

    func testHTTPErrorSurfacesProviderMessage() async {
        StubURLProtocol.stub = .init(
            status: 401,
            body: Data(#"{"error":{"message":"Incorrect API key provided."}}"#.utf8)
        )
        do {
            _ = try await collect(.openAI)
            XCTFail("expected an error")
        } catch let error as ChatClientError {
            XCTAssertEqual(error, .http(status: 401, message: "HTTP 401: Incorrect API key provided."))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testInStreamErrorThrows() async {
        StubURLProtocol.stub = .init(status: 200, body: Data("""
        data: {"candidates":[{"content":{"parts":[{"text":"partial"}]}}]}

        data: {"error":{"code":500,"message":"Internal error"}}


        """.utf8))
        do {
            _ = try await collect(.gemini)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ChatClientError, .stream("Internal error"))
        }
    }

    func testStreamThatEndsWithoutAStopSignalIsIncomplete() async {
        // The connection closes cleanly mid-reply: no finish_reason, no [DONE].
        StubURLProtocol.stub = .init(status: 200, body: Data("""
        data: {"choices":[{"delta":{"content":"The first half"}}]}


        """.utf8))
        var received = ""
        do {
            for try await delta in makeClient().stream(
                provider: .openAI, apiKey: "k", model: "",
                messages: [ChatMessage(role: .user, content: "hi")]
            ) {
                received += delta
            }
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ChatClientError, .incomplete)
        }
        XCTAssertEqual(received, "The first half")
    }

    func testGeminiStopReasonCompletesTheStream() async throws {
        StubURLProtocol.stub = .init(status: 200, body: Data("""
        data: {"candidates":[{"content":{"parts":[{"text":"Hi"}]},"finishReason":"STOP"}]}


        """.utf8))
        let text = try await collect(.gemini)
        XCTAssertEqual(text, "Hi")
    }

    func testOpenAITruncationThrowsAfterText() async {
        StubURLProtocol.stub = .init(status: 200, body: Data("""
        data: {"choices":[{"delta":{"content":"Long answ"}}]}

        data: {"choices":[{"delta":{},"finish_reason":"length"}]}

        data: [DONE]


        """.utf8))
        do {
            _ = try await collect(.openRouter)
            XCTFail("expected an error")
        } catch let ChatClientError.stream(message) {
            XCTAssertTrue(message.contains("cut off"), message)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testSendsAttachmentAsContext() async throws {
        StubURLProtocol.stub = .init(status: 200, body: Data("data: [DONE]\n\n".utf8))
        let attachment = try XCTUnwrap(ContextAttachment(source: .pasted, text: "let x = 1"))
        for try await _ in makeClient().stream(
            provider: .openAI, apiKey: "k", model: "",
            messages: [ChatMessage(role: .user, content: "Explain", attachment: attachment)]
        ) {}
        let body = try XCTUnwrap(StubURLProtocol.lastRequest.flatMap(Self.body))
        XCTAssertTrue(body.contains("let x = 1"), body)
        XCTAssertTrue(body.contains("Explain"), body)
    }

    /// URLProtocol sees the body as a stream, not `httpBody`.
    private static func body(of request: URLRequest) -> String? {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return String(decoding: data, as: UTF8.self)
    }

    func testConnectionTesterSucceedsOnFirstDelta() async throws {
        StubURLProtocol.stub = .init(status: 200, body: Data("data: {\"choices\":[{\"delta\":{\"content\":\"OK\"}}]}\n\n".utf8))
        try await ConnectionTester.test(client: makeClient(), provider: .xAI, apiKey: "k", model: "")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.host, "api.x.ai")
        XCTAssertEqual(StubURLProtocol.lastRequest?.timeoutInterval, ConnectionTester.timeout)
    }

    func testConnectionTesterFailsWhenStreamHasNoText() async {
        // Role header, a reasoning-only chunk, then [DONE]: HTTP 200 but no answer.
        StubURLProtocol.stub = .init(status: 200, body: Data("""
        data: {"choices":[{"delta":{"role":"assistant","content":""}}]}

        data: {"choices":[{"delta":{"reasoning_content":"Thinking"}}]}

        data: [DONE]


        """.utf8))
        do {
            try await ConnectionTester.test(client: makeClient(), provider: .deepSeek, apiKey: "k", model: "")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ConnectionTesterError, .noText)
        }
    }

    func testConnectionTesterFailsOnEmptyAnthropicStream() async {
        StubURLProtocol.stub = .init(status: 200, body: Data("""
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1","role":"assistant","content":[]}}

        event: message_stop
        data: {"type":"message_stop"}


        """.utf8))
        do {
            try await ConnectionTester.test(client: makeClient(), provider: .anthropic, apiKey: "k", model: "")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ConnectionTesterError, .noText)
        }
    }

    func testChatRequestsAllowLongIdleGaps() throws {
        let request = try RequestBuilder.streamingRequest(
            provider: .xAI, apiKey: "k", model: "",
            messages: [ChatMessage(role: .user, content: "hi")]
        )
        XCTAssertEqual(request.timeoutInterval, 600)
    }
}
