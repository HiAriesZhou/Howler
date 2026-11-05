import XCTest
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
