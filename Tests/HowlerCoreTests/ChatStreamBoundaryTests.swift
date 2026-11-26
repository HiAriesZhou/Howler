#if canImport(Darwin)
import Foundation
import XCTest
@testable import HowlerCore

final class BoundaryURLProtocol: URLProtocol {
    static var body = Data()
    static var onStop: (() -> Void)?
    private let lock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        let finish = DispatchWorkItem { [weak self] in
            guard let self else { return }
            lock.lock()
            defer { lock.unlock() }
            if !stopped { client?.urlProtocolDidFinishLoading(self) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: finish)
    }

    override func stopLoading() {
        lock.lock()
        let firstStop = !stopped
        stopped = true
        lock.unlock()
        if firstStop { Self.onStop?() }
    }
}

final class ChatStreamBoundaryTests: XCTestCase {
    private let replyLimit = 8 * 1024 * 1024
    private var session: URLSession!

    override func setUp() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundaryURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        BoundaryURLProtocol.onStop = nil
        BoundaryURLProtocol.body = Data()
    }

    private func frame(_ text: String, provider: Provider) -> String {
        switch provider {
        case .anthropic:
            return "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"\(text)\"}}\n\n"
        case .gemini:
            return "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"\(text)\"}]}}]}\n\n"
        default:
            return "data: {\"choices\":[{\"delta\":{\"content\":\"\(text)\"}}]}\n\n"
        }
    }

    private func done(_ provider: Provider) -> String {
        switch provider {
        case .anthropic: return "data: {\"type\":\"message_stop\"}\n\n"
        case .gemini: return "data: {\"candidates\":[{\"finishReason\":\"STOP\"}]}\n\n"
        default: return "data: [DONE]\n\n"
        }
    }

    private func transcript(_ text: String, provider: Provider) -> String {
        let bytes = Array(text.utf8)
        let chunkSize = 256 * 1024
        return stride(from: 0, to: bytes.count, by: chunkSize).map { offset in
            frame(String(decoding: bytes[offset..<min(offset + chunkSize, bytes.count)], as: UTF8.self), provider: provider)
        }.joined()
    }

    private func stream(_ provider: Provider = .openAI) -> AsyncThrowingStream<String, Error> {
        ChatClient(session: session).stream(service: provider.service(), apiKey: "fixture-key",
                                           messages: [ChatMessage(role: .user, content: "Synthetic boundary probe")])
    }

    private func check(_ body: String, provider: Provider = .openAI,
                       expected: String, errorMessage: String? = nil,
                       file: StaticString = #filePath, line: UInt = #line) async {
        BoundaryURLProtocol.body = Data(body.utf8)
        let cancelled = expectation(description: "underlying request cancelled")
        BoundaryURLProtocol.onStop = { cancelled.fulfill() }
        var received = ""
        do {
            for try await delta in stream(provider) { received += delta }
            XCTAssertNil(errorMessage, "Expected a size error", file: file, line: line)
        } catch {
            XCTAssertEqual(error.localizedDescription, errorMessage, file: file, line: line)
        }
        XCTAssertEqual(received.utf8.count, expected.utf8.count, file: file, line: line)
        XCTAssertTrue(received == expected, "Previously yielded text must be retained", file: file, line: line)
        await fulfillment(of: [cancelled], timeout: 2)
    }

    func testVisibleReplyAtLimitCompletesForEveryWireFormat() async {
        for provider in [Provider.openAI, .anthropic, .gemini] {
            let text = String(repeating: "a", count: replyLimit - 4) + "👋"
            let prefix = String(repeating: "a", count: replyLimit - 4)
            await check(transcript(prefix, provider: provider) + frame("👋", provider: provider) + done(provider),
                        provider: provider, expected: text)
        }
    }

    func testReplyOneByteOverLimitKeepsTheCompletePriorDeltas() async {
        let prefix = String(repeating: "a", count: replyLimit)
        await check(transcript(prefix, provider: .openAI) + frame("b", provider: .openAI) + done(.openAI),
                    expected: prefix, errorMessage: "The reply is larger than 8 MiB.")
    }

    func testMultibyteDeltaCrossingReplyLimitIsNotPartiallyYielded() async {
        for provider in [Provider.openAI, .anthropic, .gemini] {
            let prefix = String(repeating: "a", count: replyLimit - 3)
            await check(transcript(prefix, provider: provider) + frame("👋", provider: provider) + done(provider),
                        provider: provider, expected: prefix, errorMessage: "The reply is larger than 8 MiB.")
        }
    }

    func testOversizedUnterminatedLineCancelsAndRetainsPriorText() async {
        await check(frame("Prior text", provider: .openAI) + String(repeating: "a", count: 1024 * 1024 + 1),
                    expected: "Prior text", errorMessage: "The server sent a line larger than 1 MiB.")
    }

    func testAccumulatedDataEventCancelsAndRetainsPriorText() async {
        let half = String(repeating: "a", count: 512 * 1024)
        await check(frame("Prior text", provider: .openAI) + "data: \(half)\ndata: \(half)\n\n" + done(.openAI),
                    expected: "Prior text", errorMessage: "The server sent an event larger than 1 MiB.")
    }

    func testAccumulatedDataWithoutAFinalNewlineCancelsBeforeEOF() async {
        let half = String(repeating: "a", count: 512 * 1024)
        await check(frame("Prior text", provider: .openAI) + "data: \(half)\ndata: \(half)",
                    expected: "Prior text", errorMessage: "The server sent an event larger than 1 MiB.")
    }

    func testDoneCancelsAnOtherwiseOpenRequest() async {
        await check(frame("Normal reply", provider: .openAI) + done(.openAI), expected: "Normal reply")
    }

    func testConsumerCancellationCancelsAnOtherwiseOpenRequest() async {
        BoundaryURLProtocol.body = Data(frame("Partial", provider: .openAI).utf8)
        let received = expectation(description: "first visible delta")
        let cancelled = expectation(description: "underlying request cancelled")
        BoundaryURLProtocol.onStop = { cancelled.fulfill() }
        let reply = stream()
        let consumer = Task {
            do {
                for try await delta in reply {
                    XCTAssertEqual(delta, "Partial")
                    received.fulfill()
                }
            } catch {}
        }
        await fulfillment(of: [received], timeout: 2)
        consumer.cancel()
        await consumer.value
        await fulfillment(of: [cancelled], timeout: 2)
    }

    func testIgnoredProviderTextDoesNotConsumeVisibleReplyBudget() async {
        let ignored = "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"\(String(repeating: "a", count: 512 * 1024))\"}}]}\n\n"
        let prefix = String(repeating: "a", count: replyLimit)
        await check(ignored + transcript(prefix, provider: .openAI) + done(.openAI), expected: prefix)
    }
}
#endif
