import AppKit
import XCTest
import HowlerCore
@testable import Howler

@MainActor
final class LetterLifecycleTests: XCTestCase {
    func testConcealingAndLosingFocusPreserveTheLetterButBurnClearsImmediately() async throws {
        _ = NSApplication.shared
        let name = "HowlerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults, keys: MemoryKeys().access)
        let controller = PanelController(settings: settings, openSettings: {})
        let model = controller.viewModel
        var stream: AsyncThrowingStream<String, Error>.Continuation?
        model.streamFactory = { _, _ in AsyncThrowingStream { stream = $0 } }
        controller.show()
        model.input = "Synthetic question"
        model.send()
        model.input = "Unsent draft"
        let session = model.conversationID
        controller.panel.resignKey()
        XCTAssertEqual(model.conversationID, session)
        XCTAssertEqual(model.input, "Unsent draft")
        controller.hide(burning: false)
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(model.queue.tasks.count, 1)
        controller.show()
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(model.input, "Unsent draft")
        controller.hide()
        XCTAssertNotEqual(model.conversationID, session)
        XCTAssertTrue(model.input.isEmpty)
        XCTAssertTrue(model.queue.tasks.isEmpty)
        controller.show() // reopen during the previous burn animation
        model.input = "New letter"
        let completed = expectation(description: "old animation completion no longer changes the letter")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { completed.fulfill() }
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(model.input, "New letter")
        let content = try XCTUnwrap(controller.panel.contentView)
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let center = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
        XCTAssertGreaterThan(center.alphaComponent, 0.9, "The restored live letter must not inherit the old burn mask")
        stream?.finish()
        model.reset()
        controller.conceal()
    }

    func testConcealingACompletedLongLetterPreservesItsHeight() async throws {
        try await checkCompletedLetterHeight(responseDelay: 0)
    }

    func testConcealingACompletedDelayedLetterPreservesItsHeight() async throws {
        try await checkCompletedLetterHeight(responseDelay: 0.65)
    }

    private func checkCompletedLetterHeight(responseDelay: TimeInterval) async throws {
        _ = NSApplication.shared
        let defaults = DemoDefaults(suiteName: "HowlerTests.LongLetter")!
        let settings = AppSettings(defaults: defaults, keys: MemoryKeys().access)
        settings.useDemoService(.anthropic)
        let controller = PanelController(settings: settings, openSettings: {})
        let model = controller.viewModel
        defer {
            model.reset()
            controller.conceal()
        }
        let answer = Array(repeating: "A synthetic paragraph about a chart.\n\n", count: 40).joined()
        model.streamFactory = { _, _ in
            AsyncThrowingStream { stream in
                DispatchQueue.main.asyncAfter(deadline: .now() + responseDelay) {
                    stream.yield(answer)
                    stream.finish()
                }
            }
        }
        controller.show()
        model.input = "Explain the chart"
        model.send()
        try await waitUntil("The entire reply must be presented before measuring its height") {
            model.queue.tasks.last?.state == .completed
        }
        XCTAssertEqual(model.queue.tasks.last?.answer, answer)
        XCTAssertNil(model.writingID)
        let screen = try XCTUnwrap(controller.panel.screen)
        let margins = PanelController.margins
        let availablePaperHeight = controller.panel.frame.maxY - margins.top - screen.visibleFrame.minY - 16
        let expectedHeight = max(PanelController.minPaperHeight, min(PanelController.a4Height, availablePaperHeight))
            + margins.top + margins.bottom
        try await waitUntil("The completed long transcript must fill the available paper height") {
            controller.panel.contentView?.layoutSubtreeIfNeeded()
            return abs(controller.panel.frame.height - expectedHeight) <= 1
        }
        let height = controller.panel.frame.height
        XCTAssertGreaterThan(height, PanelController.minPaperHeight + margins.top + margins.bottom)
        try await saveSnapshot(controller.panel, name: "letter-before-\(responseDelay)")
        controller.conceal()
        controller.show()
        XCTAssertEqual(controller.panel.frame.height, height, accuracy: 1)
        await Task.yield()
        controller.panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.panel.frame.height, height, accuracy: 1)
        XCTAssertEqual(model.queue.tasks.last?.state, .completed)
        try await saveSnapshot(controller.panel, name: "letter-restored-\(responseDelay)")
        controller.hide()
        controller.show()
        XCTAssertEqual(controller.panel.frame.height, PanelController.minPaperHeight + margins.top + margins.bottom, accuracy: 1)
        XCTAssertTrue(model.queue.tasks.isEmpty)
    }

    private func saveSnapshot(_ panel: NSPanel, name: String) async throws {
        guard let folder = ProcessInfo.processInfo.environment["HOWLER_TEST_SNAPSHOTS"] else { return }
        try await Task.sleep(nanoseconds: 800_000_000)
        let content = try XCTUnwrap(panel.contentView)
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let center = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
        XCTAssertGreaterThan(center.alphaComponent, 0.9, "The snapshot must contain the visible letter")
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
    }

    private func waitUntil(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else {
                XCTFail(description, file: file, line: line)
                throw NSError(domain: "LetterLifecycleTests", code: 1)
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testCaptureShortcutAndLanguagePersistWithoutReplacingTheOrdinaryShortcut() async throws {
        let name = "HowlerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults, keys: MemoryKeys().access)
        XCTAssertEqual(settings.screenshotHotKey, .screenshot)
        let normal = settings.hotKey
        settings.setScreenshotHotKey(normal)
        XCTAssertEqual(settings.screenshotHotKey, .screenshot)
        let capture = HotKeyCombo(keyCode: 40, modifiers: [.control, .option], keyLabel: "K")
        settings.setScreenshotHotKey(capture)
        settings.setReplyLanguage("ja")
        let reopened = AppSettings(defaults: defaults, keys: MemoryKeys().access)
        XCTAssertEqual(reopened.hotKey, normal)
        XCTAssertEqual(reopened.screenshotHotKey, capture)
        XCTAssertEqual(reopened.replyLanguage, "ja")
        settings.resetScreenshotHotKey()
        XCTAssertEqual(settings.screenshotHotKey, .screenshot)
    }
}
