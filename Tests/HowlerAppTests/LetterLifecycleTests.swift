import XCTest
import HowlerCore
@testable import Howler

@MainActor
final class LetterLifecycleTests: XCTestCase {

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
