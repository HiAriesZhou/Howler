import AppKit
import XCTest
import HowlerCore
@testable import Howler

@MainActor
final class TranscriptScrollingTests: XCTestCase {
    private var controller: PanelController!
    private var streams: [AsyncThrowingStream<String, Error>.Continuation] = []

    override func setUp() async throws {
        _ = NSApplication.shared
        let defaults = DemoDefaults(suiteName: "HowlerTests.TranscriptScrolling")!
        let settings = AppSettings(defaults: defaults, keys: MemoryKeys().access)
        settings.useDemoService(.anthropic)
        controller = PanelController(settings: settings, openSettings: {})
        controller.show()
        controller.viewModel.updateReduceMotion(true)
        controller.viewModel.streamFactory = { [unowned self] _, _ in
            AsyncThrowingStream { self.streams.append($0) }
        }
    }

    override func tearDown() async throws {
        streams.forEach { $0.finish() }
        streams.removeAll()
        controller.viewModel.reset()
        controller.conceal()
        controller = nil
    }

    func testLongAnswerGrowsWithoutScrollingAndSendingReturnsToTop() async throws {
        let model = controller.viewModel
        send("First")
        streams[0].yield(paragraphs(40))
        streams[0].finish()
        try await waitUntil { model.queue.active == nil && self.documentHeight > 1000 }
        let scroll = try scrollView()
        XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
        try saveSnapshot("long-answer")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 400))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertEqual(scroll.contentView.bounds.minY, 400, accuracy: 1)
        send("Second")
        try await waitUntil { scroll.contentView.bounds.minY < 1 }
        XCTAssertEqual(model.turns.map(\.question.content), ["Second", "First"])
        await settle()
        try saveSnapshot("newest-turn")
    }

    func testGrowingReplyAboveAnOlderTurnKeepsItsPosition() async throws {
        try await prepareTwoTurns()
        let scroll = try scrollView()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 500))
        scroll.reflectScrolledClipView(scroll.contentView)
        await settle()
        let oldHeight = documentHeight
        let oldOffset = scroll.contentView.bounds.minY
        streams[1].yield(paragraphs(8))
        try await waitUntil { self.documentHeight > oldHeight + 100 }
        await settle()
        XCTAssertEqual(documentHeight - scroll.contentView.bounds.minY,
                       oldHeight - oldOffset, accuracy: 2)
        try saveSnapshot("reading-older-turn")
    }

    func testQueuedTurnStartsWithoutMovingTheOlderTurnBeingRead() async throws {
        try await prepareTwoTurns()
        let model = controller.viewModel
        send("Third")
        let scroll = try scrollView()
        await settle()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 500))
        scroll.reflectScrolledClipView(scroll.contentView)
        await settle()
        let oldHeight = documentHeight
        let oldOffset = scroll.contentView.bounds.minY
        streams[1].finish()
        try await waitUntil { model.queue.active?.question == "Third" }
        await settle()
        XCTAssertEqual(documentHeight - scroll.contentView.bounds.minY,
                       oldHeight - oldOffset, accuracy: 2)
    }

    func testQueuedTurnStartsAtTopForAReaderAtTop() async throws {
        try await prepareTwoTurns()
        let model = controller.viewModel
        send("Third")
        streams[1].finish()
        try await waitUntil { model.queue.active?.question == "Third" }
        await settle()
        XCTAssertEqual(try scrollView().contentView.bounds.minY, 0, accuracy: 1)
    }

    func testRetryShrinkingReplyAboveAnOlderTurnKeepsItsPosition() async throws {
        try await prepareTwoTurns()
        let model = controller.viewModel
        streams[1].yield(paragraphs(8))
        streams[1].finish(throwing: ChatClientError.incomplete)
        try await waitUntil { model.queue.isPaused }
        await settle()
        let scroll = try scrollView()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 650))
        scroll.reflectScrolledClipView(scroll.contentView)
        await settle()
        let oldHeight = documentHeight
        let oldOffset = scroll.contentView.bounds.minY
        model.retry()
        try await waitUntil { self.streams.count == 3 && self.documentHeight < oldHeight - 100 }
        await settle()
        XCTAssertEqual(documentHeight - scroll.contentView.bounds.minY,
                       oldHeight - oldOffset, accuracy: 2)
    }

    private func prepareTwoTurns() async throws {
        send("First")
        streams[0].yield(paragraphs(40))
        streams[0].finish()
        try await waitUntil { self.controller.viewModel.queue.active == nil && self.documentHeight > 1000 }
        send("Second")
        streams[1].yield(paragraphs(2))
        try await waitUntil { self.controller.viewModel.turns.first?.answer.content.isEmpty == false }
        await settle()
    }

    private func send(_ question: String) {
        controller.viewModel.input = question
        controller.viewModel.send()
    }

    private func paragraphs(_ count: Int) -> String {
        Array(repeating: "A synthetic paragraph about a chart and its labels.\n\n", count: count).joined()
    }

    private var documentHeight: CGFloat {
        (try? scrollView().documentView?.frame.height) ?? 0
    }

    private func scrollView() throws -> NSScrollView {
        func find(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.documentView?.frame.height ?? 0 > 500 { return scroll }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
        }
        return try XCTUnwrap(controller.panel.contentView.flatMap { find(in: $0) })
    }

    private func settle() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        controller.panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func saveSnapshot(_ name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["HOWLER_TEST_SNAPSHOTS"] else { return }
        let content = try XCTUnwrap(controller.panel.contentView)
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Expected transcript layout transition", file: file, line: line)
                throw NSError(domain: "TranscriptScrollingTests", code: 1)
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
