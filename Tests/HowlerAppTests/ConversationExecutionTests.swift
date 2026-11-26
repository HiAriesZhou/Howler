import XCTest
import AppKit
import HowlerCore
@testable import Howler

@MainActor
final class ConversationExecutionTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var streams: [AsyncThrowingStream<String, Error>.Continuation] = []
    private var requests: [[ChatMessage]] = []

    override func setUp() async throws {
        suite = "HowlerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        streams = []
        requests = []
    }

    override func tearDown() async throws {
        streams.forEach { $0.finish() }
        defaults.removePersistentDomain(forName: suite)
    }

    private func model() -> ChatViewModel {
        let settings = AppSettings(defaults: defaults, keys: MemoryKeys().access)
        let model = ChatViewModel(settings: settings)
        model.streamFactory = { [unowned self] messages, _ in
            self.requests.append(messages)
            return AsyncThrowingStream { self.streams.append($0) }
        }
        model.panelDidOpen(reduceMotion: true, candlelit: false)
        return model
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Expected asynchronous state transition", file: file, line: line)
    }

    private var picture: ImageData {
        ImageData(data: Data([1, 2, 3]), mediaType: "image/png", width: 1, height: 1)
    }

    func testFollowupsQueueDuringThinkingAndSeeCompletedIntroduction() async {
        let model = model()
        model.introduceScreenshot(picture)
        model.input = "First question"
        model.send()
        model.input = "Second question"
        model.send()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(model.queue.waiting.count, 2)
        streams[0].yield("Introduction")
        streams[0].finish()
        await waitUntil { self.requests.count == 2 }
        XCTAssertEqual(requests[1].filter { $0.role == .assistant }.map(\.content), ["Introduction"])
        XCTAssertEqual(model.queue.active?.question, "First question")
        streams[1].yield("First answer")
        streams[1].finish()
        await waitUntil { self.requests.count == 3 }
        XCTAssertEqual(model.queue.active?.question, "Second question")
        streams[2].yield("Second answer")
        streams[2].finish()
        await waitUntil { model.queue.active == nil }
        XCTAssertEqual(model.messages.filter { $0.role == .assistant }.map(\.content),
                       ["Introduction", "First answer", "Second answer"])
        model.reset()
    }

    func testTurnsListNewestStartedTurnFirstAndLeaveWaitingQuestionsOut() async {
        let model = model()
        model.input = "First"
        model.send()
        streams[0].yield("First answer")
        streams[0].finish()
        await waitUntil { model.queue.active == nil }
        model.input = "Second"
        model.send()
        model.input = "Third"
        model.send()
        XCTAssertEqual(model.queue.waiting.count, 1)
        XCTAssertEqual(model.turns.map(\.question.content), ["Second", "First"])
        XCTAssertEqual(model.turns.map(\.answer.content), ["", "First answer"])
        XCTAssertEqual(model.turns.map(\.id), model.queue.tasks.prefix(2).reversed().map(\.id))
        XCTAssertEqual(model.messages.map(\.content), ["First", "First answer", "Second", ""],
                       "The request history stays in chronological order")
        model.reset()
    }

    func testPresentationMustFinishAndHidingCannotStallTheQueue() async {
        let model = model()
        model.panelDidOpen(reduceMotion: false, candlelit: false)
        model.input = "One"
        model.send()
        model.input = "Two"
        model.send()
        streams[0].yield(String(repeating: "Long answer ", count: 100))
        streams[0].finish()
        await waitUntil { model.queue.active?.state == .revealing }
        XCTAssertEqual(requests.count, 1)
        model.setVisible(false)
        XCTAssertEqual(requests.count, 2)
        streams[1].yield("Two")
        streams[1].finish()
        await waitUntil { model.queue.active == nil }
        XCTAssertEqual(model.queue.tasks.map(\.state), [.completed, .completed])
        model.reset()
    }

    func testFailurePausesRetryReplacesAndBurnRejectsLateResults() async {
        let model = model()
        model.input = "Question"
        model.send()
        model.input = "Waiting"
        model.send()
        streams[0].yield("Partial")
        streams[0].finish(throwing: ChatClientError.incomplete)
        await waitUntil { model.queue.isPaused }
        XCTAssertEqual(requests.count, 1)
        model.retry()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].count, 1, "Retry must not send its old partial reply as context")
        streams[1].yield("Replacement")
        streams[1].finish()
        await waitUntil { self.requests.count == 3 }
        XCTAssertEqual(model.queue.tasks[0].answer, "Replacement")
        model.burn()
        streams[2].yield("Stale")
        streams[2].finish()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertTrue(model.queue.tasks.isEmpty)
        XCTAssertTrue(model.images.isEmpty)
    }

    func testTransportSizeErrorsRetainHistoryAndPauseWaitingQuestions() async throws {
        func frame(_ text: String) -> String {
            "data: {\"choices\":[{\"delta\":{\"content\":\"\(text)\"}}]}\n\n"
        }
        let partial = "Partial"
        let half = String(repeating: "a", count: 512 * 1024)
        let chunk = String(repeating: "a", count: 256 * 1024)
        let replyPrefix = String(repeating: frame(chunk), count: 31)
            + frame(String(repeating: "a", count: chunk.utf8.count - partial.utf8.count))
        let cases = [
            (String(repeating: "a", count: 1024 * 1024 + 1) + "\n\n", partial,
             "The server sent a line larger than 1 MiB."),
            ("data: \(half)\ndata: \(half)\n\n", partial,
             "The server sent an event larger than 1 MiB."),
            (replyPrefix + frame("b"), partial + String(repeating: "a", count: 8 * 1024 * 1024 - partial.utf8.count),
             "The reply is larger than 8 MiB.")
        ]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QueueBoundaryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = ChatClient(session: session)
        for (suffix, expected, reason) in cases {
            let model = model()
            model.input = "Earlier question"
            model.send()
            streams.last?.yield("Earlier answer")
            streams.last?.finish()
            await waitUntil { model.queue.active == nil }
            QueueBoundaryURLProtocol.body = Data((frame(partial) + suffix + "data: [DONE]\n\n").utf8)
            var requestCount = 0
            model.streamFactory = { messages, options in
                requestCount += 1
                return client.stream(service: Provider.openAI.service(), apiKey: "fixture-key",
                                     messages: messages, options: options)
            }
            model.input = "Bounded question"
            model.send()
            model.input = "Waiting question"
            model.send()
            let deadline = ContinuousClock.now + .seconds(30)
            while !model.queue.isPaused, model.queue.tasks[1].state != .completed,
                  ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(model.queue.isPaused)
            XCTAssertEqual(model.queue.pauseReason, reason)
            XCTAssertEqual(model.queue.tasks[0].answer, "Earlier answer")
            XCTAssertEqual(model.queue.tasks[0].state, .completed)
            XCTAssertTrue(model.queue.tasks[1].answer == expected)
            XCTAssertEqual(model.queue.tasks[1].state, .paused)
            XCTAssertEqual(model.queue.tasks[2].state, .queued)
            XCTAssertEqual(requestCount, 1)
            model.reset()
        }
    }

    func testNewScreenshotPreservesDraftAssociationAndLanguageSnapshot() async {
        let model = model()
        model.settings.setReplyLanguage("zh-Hans")
        model.introduceScreenshot(picture)
        let original = model.latestImageID
        model.input = "About the first image"
        model.settings.setReplyLanguage("ja")
        model.introduceScreenshot(picture)
        XCTAssertEqual(model.draftImageID, original)
        model.send()
        XCTAssertEqual(model.queue.tasks.map(\.language), ["zh-Hans", "ja", "ja"])
        XCTAssertEqual(model.queue.tasks.last?.imageID, original)
        let history = model.requestHistory(for: model.queue.tasks.last!)
        XCTAssertEqual(history.filter { $0.image != nil }.count, 1)
        XCTAssertEqual(history.last?.image, picture)
        model.reset()
    }

    func testExplicitImageSelectionSurvivesStartingANewDraft() async {
        let model = model()
        model.introduceScreenshot(picture)
        let first = model.latestImageID
        model.introduceScreenshot(picture)
        model.selectDraftImage(first)
        model.input = "About the older image"
        XCTAssertEqual(model.draftImageID, first)
        model.send()
        XCTAssertEqual(model.queue.tasks.last?.imageID, first)
        model.selectDraftImage(nil)
        model.input = "A plain question"
        XCTAssertNil(model.draftImageID)
        model.send()
        XCTAssertNil(model.queue.tasks.last?.imageID)
        model.reset()
    }

    func testNoImageSelectionRemovesAPastedPictureFromTheRequest() async {
        let model = model()
        model.pasteImage(picture)
        model.input = "Plain question"
        model.selectDraftImage(nil)
        model.send()
        XCTAssertNil(model.queue.tasks[0].imageID)
        XCTAssertNil(requests[0].last?.image)
        XCTAssertNil(model.queue.tasks[0].attachment?.image)
        model.reset()
    }

    func testNewCapturePreservesAnUnsentPastedImageEvenWithEmptyText() async {
        let model = model()
        model.pasteImage(picture)
        let pastedID = model.draftImageID
        let other = ImageData(data: Data([4, 5, 6]), mediaType: "image/png", width: 2, height: 1)
        model.introduceScreenshot(other)
        XCTAssertEqual(model.draftImageID, pastedID)
        XCTAssertEqual(model.previewAttachment?.image, picture)
        model.send()
        let followup = model.queue.tasks.last!
        XCTAssertEqual(followup.imageID, pastedID)
        XCTAssertEqual(model.requestHistory(for: followup).last?.image, picture)
        model.reset()
    }

    func testDeferredLongPasteCannotRestoreContentAfterBurn() async {
        let model = model()
        model.input = "Old draft"
        model.input += String(repeating: " paste", count: 100)
        model.burn()
        model.input = "New letter"
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.input, "New letter")
        XCTAssertNil(model.attachment)
        model.reset()
    }

    func testCancelledOrStaleScreenshotDoesNotSendAndPlainDraftSurvives() async {
        let model = model()
        var captured: ((Result<ImageData, Error>?) -> Void)?
        model.captureScreenRegion = { captured = $0 }
        model.input = "A plain draft"
        model.captureScreen()
        captured?(nil)
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(model.input, "A plain draft")
        model.captureScreen()
        model.reset()
        captured?(.success(picture))
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(model.images.isEmpty)
        model.input = "Still plain"
        model.introduceScreenshot(picture)
        XCTAssertNil(model.draftImageID)
        XCTAssertEqual(model.input, "Still plain")
        model.reset()
    }
}

private final class QueueBoundaryURLProtocol: URLProtocol {
    static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
