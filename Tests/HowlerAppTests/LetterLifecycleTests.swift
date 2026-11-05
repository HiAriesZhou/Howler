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
        stream?.finish()
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
