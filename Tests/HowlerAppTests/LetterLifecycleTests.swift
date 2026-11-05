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
        _ = NSApplication.shared
        let defaults = DemoDefaults(suiteName: "HowlerTests.LongLetter")!
        let settings = AppSettings(defaults: defaults, keys: MemoryKeys().access)
        settings.useDemoService(.anthropic)
        let controller = PanelController(settings: settings, openSettings: {})
        let model = controller.viewModel
        model.streamFactory = { _, _ in
            AsyncThrowingStream { stream in
                stream.yield(Array(repeating: "A synthetic paragraph about a chart.\n\n", count: 40).joined())
                stream.finish()
            }
        }
        controller.show()
        model.panelDidOpen(reduceMotion: true, candlelit: false)
        model.input = "Explain the chart"
        model.send()
        let laidOut = expectation(description: "long letter finishes layout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { laidOut.fulfill() }
        await fulfillment(of: [laidOut], timeout: 2)
        let height = controller.panel.frame.height
        XCTAssertGreaterThan(height, 400, "Must exercise a configured, expanded transcript")
        controller.conceal()
        controller.show()
        let restored = expectation(description: "restored letter layout settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { restored.fulfill() }
        await fulfillment(of: [restored], timeout: 2)
        XCTAssertEqual(controller.panel.frame.height, height, accuracy: 1)
        model.reset()
        controller.conceal()
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
