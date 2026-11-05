import XCTest
@testable import HowlerCore

final class ConversationQueueTests: XCTestCase {
    func testIntroductionsAndQuestionsWaitForGenerationAndPresentation() throws {
        var queue = ConversationQueue()
        let intro = ConversationTask(kind: .screenshotIntroduction, question: "Image introduction")
        queue.enqueue(intro)
        let run = try XCTUnwrap(queue.startNext())
        queue.enqueue(ConversationTask(question: "First question"))
        queue.enqueue(ConversationTask(question: "Second question"))
        XCTAssertNil(queue.startNext())
        queue.append("Introduction", for: run)
        queue.generated(for: run)
        XCTAssertNil(queue.startNext(), "Network completion must not bypass the quill")
        queue.presented(for: run)
        let next = try XCTUnwrap(queue.startNext())
        XCTAssertEqual(queue.active?.question, "First question")
        queue.append("First answer", for: next)
        queue.generated(for: next)
        queue.presented(for: next)
        XCTAssertNotNil(queue.startNext())
        XCTAssertEqual(queue.active?.question, "Second question")
    }

    func testRetryInvalidatesTheOldAttemptAndReplacesPartialText() throws {
        var queue = ConversationQueue()
        queue.enqueue(ConversationTask(question: "Question"))
        let old = try XCTUnwrap(queue.startNext())
        queue.append("Partial", for: old)
        queue.pause(reason: "Disconnected")
        queue.enqueue(ConversationTask(question: "Waiting"))
        XCTAssertNil(queue.startNext())
        queue.retry()
        let new = try XCTUnwrap(queue.startNext())
        XCTAssertNotEqual(old, new)
        queue.append("Late result", for: old)
        queue.generated(for: old)
        XCTAssertEqual(queue.active?.answer, "")
        XCTAssertEqual(queue.active?.state, .generating)
        queue.append("Replacement", for: new)
        queue.generated(for: new)
        queue.presented(for: new)
        XCTAssertEqual(queue.tasks[0].answer, "Replacement")
        XCTAssertNotNil(queue.startNext())
    }

    func testEmptyResponsePausesAndSkipRetainsPartialAnswers() throws {
        var queue = ConversationQueue()
        queue.enqueue(ConversationTask(question: "Empty"))
        let run = try XCTUnwrap(queue.startNext())
        queue.generated(for: run)
        XCTAssertTrue(queue.isPaused)
        queue.skip()
        queue.enqueue(ConversationTask(question: "Partial"))
        let second = try XCTUnwrap(queue.startNext())
        queue.append("Useful fragment", for: second)
        queue.pause(reason: "Stopped")
        queue.skip()
        XCTAssertEqual(queue.tasks[1].answer, "Useful fragment")
        XCTAssertEqual(queue.tasks[1].state, .skipped)
        XCTAssertNotNil(queue.tasks[1].issue)
    }

    func testImageAndLanguageSnapshotsSurviveLaterScreenshotsAndWithdrawal() throws {
        var queue = ConversationQueue()
        let first = UUID(), second = UUID()
        let question = ConversationTask(question: "First image?", imageID: first, language: "zh-Hans")
        queue.enqueue(question)
        queue.enqueue(ConversationTask(kind: .screenshotIntroduction, question: "Image introduction",
                                       imageID: second, language: "en"))
        let withdrawn = try XCTUnwrap(queue.withdraw(question.id))
        XCTAssertEqual(withdrawn.imageID, first)
        XCTAssertEqual(withdrawn.language, "zh-Hans")
        XCTAssertNil(queue.withdraw(queue.tasks[0].id))
        queue.enqueue(ConversationTask(question: withdrawn.question, imageID: withdrawn.imageID,
                                       language: withdrawn.language))
        XCTAssertEqual(queue.tasks.map(\.imageID), [second, first])
    }

    func testClearRejectsLateEventsFromPriorConversation() throws {
        var queue = ConversationQueue()
        queue.enqueue(ConversationTask(question: "Old"))
        let old = try XCTUnwrap(queue.startNext())
        queue.clear()
        queue.enqueue(ConversationTask(question: "New"))
        let new = try XCTUnwrap(queue.startNext())
        queue.append("Stale", for: old)
        queue.generated(for: old)
        queue.presented(for: old)
        XCTAssertEqual(queue.active?.question, "New")
        XCTAssertEqual(queue.active?.answer, "")
        XCTAssertEqual(queue.runID, new)
    }
}
