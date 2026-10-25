import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import QuickAskCore

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

    func testConnectionTesterSucceedsOnFirstDelta() async throws {
        StubURLProtocol.stub = .init(status: 200, body: Data("data: {\"choices\":[{\"delta\":{\"content\":\"OK\"}}]}\n\n".utf8))
        try await ConnectionTester.test(client: makeClient(), provider: .xAI, apiKey: "k", model: "")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.host, "api.x.ai")
    }
}
