import XCTest
import HowlerCore
@testable import Howler

@MainActor
final class StateBoundaryTests: XCTestCase {
    func testRestoringMultilineQuestionPreservesItsAttachmentAndImage() async throws {
        let defaults = DemoDefaults(suiteName: "HowlerTests.RestoreDraft")!
        let settings = AppSettings(defaults: defaults, keys: MemoryKeys().access)
        let model = ChatViewModel(settings: settings)
        var continuations: [AsyncThrowingStream<String, Error>.Continuation] = []
        model.streamFactory = { _, _ in AsyncThrowingStream { continuations.append($0) } }
        defer { model.reset(); continuations.forEach { $0.finish() } }
        let picture = ImageData(data: Data([1]), mediaType: "image/png", width: 1, height: 1)
        model.introduceScreenshot(picture)
        let originalImage = model.latestImageID
        model.introduceScreenshot(picture)
        let newestImage = model.latestImageID
        model.selectDraftImage(originalImage)
        let context = try XCTUnwrap(ContextAttachment(source: .pasted, text: "Original attachment"))
        model.attach(context)
        let question = "First line\nSecond line\nThird line"
        for character in question { model.input.append(character) }
        model.send()
        XCTAssertEqual(model.draftImageID, newestImage)
        let queued = try XCTUnwrap(model.queue.waiting.last)
        model.withdraw(queued.id)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertEqual(model.input, question)
        XCTAssertEqual(model.attachment, context)
        XCTAssertEqual(model.draftImageID, originalImage)
        model.send()
        XCTAssertEqual(model.queue.waiting.last?.question, question)
        XCTAssertEqual(model.queue.waiting.last?.attachment, context)
        XCTAssertEqual(model.queue.waiting.last?.imageID, originalImage)
    }

    func testKeyChangePausesQueueAfterReadFailureClearsCache() async throws {
        let defaults = DemoDefaults(suiteName: "HowlerTests.KeyRevision")!
        let keys = MemoryKeys()
        var access = keys.access
        var denied = false
        access.get = { account in
            if denied { throw ConfigurationFailure.missingKey }
            return keys.values[account]
        }
        let store = ServiceStore(defaults: defaults, keys: access)
        try store.save(.init(format: .openAICompatible, baseURL: URL(string: "https://fixture.example/v1")!, model: "fixture"))
        try store.setAPIKey("synthetic-old")
        let settings = AppSettings(defaults: defaults, keys: access)
        XCTAssertEqual(settings.apiKey(), "synthetic-old")
        let model = ChatViewModel(settings: settings)
        var continuation: AsyncThrowingStream<String, Error>.Continuation?
        model.streamFactory = { _, _ in AsyncThrowingStream { continuation = $0 } }
        defer { model.reset(); continuation?.finish() }
        model.input = "First"
        model.send()
        model.input = "Waiting"
        model.send()
        denied = true
        await settings.check()
        XCTAssertNotNil(settings.keyAccessError)
        let version = settings.connectionVersion
        denied = false
        try store.setAPIKey("synthetic-new")
        settings.reload()
        XCTAssertNotEqual(settings.connectionVersion, version)
        XCTAssertTrue(model.queue.isPaused)
        XCTAssertEqual(model.queue.waiting.count, 1)
        XCTAssertEqual(settings.apiKey(), "synthetic-new")
    }
}
