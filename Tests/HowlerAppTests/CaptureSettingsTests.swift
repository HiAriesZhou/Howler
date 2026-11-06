import AppKit
import HowlerCore
import XCTest
@testable import Howler

@MainActor
final class CaptureSettingsTests: XCTestCase {
    func testOldCaptureSwitchMigratesOnceAndNewShortcutStaysEnabled() throws {
        for enabled in [true, false] {
            let suite = "HowlerTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let custom = HotKeyCombo(keyCode: 40, modifiers: [.control, .option], keyLabel: "K")
            try defaults.set(JSONEncoder().encode(custom), forKey: ShortcutAction.capture.defaultsKey)
            defaults.set(enabled, forKey: "captureAndExplainEnabled")
            let settings = AppSettings(defaults: defaults, keys: MemoryKeys().access)
            XCTAssertEqual(settings.screenshotHotKey, enabled ? custom : nil)
            XCTAssertNil(defaults.object(forKey: "captureAndExplainEnabled"))
            let migrated = AppSettings(defaults: defaults, keys: MemoryKeys().access)
            XCTAssertEqual(migrated.screenshotHotKey, enabled ? custom : nil)
            XCTAssertTrue(migrated.setShortcut(custom, for: .capture))
            XCTAssertEqual(AppSettings(defaults: defaults, keys: MemoryKeys().access).screenshotHotKey, custom)
        }
    }

    func testEmptyCaptureShortcutKeepsManualCaptureAndPendingResultsAvailable() throws {
        let defaults = DemoDefaults(suiteName: "HowlerTests.EmptyCaptureShortcut")!
        let settings = AppSettings(defaults: defaults, keys: MemoryKeys().access)
        let model = ChatViewModel(settings: settings)
        var captures = 0
        var completion: ((Result<ImageData, Error>?) -> Void)?
        var requests = 0
        model.captureScreenRegion = {
            captures += 1
            completion = $0
        }
        model.streamFactory = { _, _ in
            requests += 1
            return AsyncThrowingStream { $0.finish() }
        }
        defer { model.reset() }
        settings.setScreenshotHotKey(nil)
        model.captureScreen() // Attach is independent of its global shortcut.
        XCTAssertEqual(captures, 1)
        let picture = ImageData(data: Data([1, 2, 3]), mediaType: "image/png", width: 1, height: 1)
        completion?(.success(picture))
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(model.queue.tasks.count, 1)
        XCTAssertFalse(model.queue.isPaused)

        settings.resetScreenshotHotKey()
        model.captureScreen()
        settings.setScreenshotHotKey(nil) // Changing a shortcut does not cancel a selected capture.
        completion?(.success(picture))
        XCTAssertEqual(captures, 2)
        XCTAssertEqual(model.queue.tasks.count, 2)
        XCTAssertFalse(model.queue.isPaused)
    }

    func testBurnStillRejectsPendingManualCaptureWithAnEmptyShortcut() throws {
        let settings = AppSettings(defaults: DemoDefaults(suiteName: "HowlerTests.EmptyCaptureBurn")!,
                                   keys: MemoryKeys().access)
        settings.setScreenshotHotKey(nil)
        let model = ChatViewModel(settings: settings)
        var completion: ((Result<ImageData, Error>?) -> Void)?
        model.captureScreenRegion = { completion = $0 }
        model.captureScreen()
        model.reset()
        let picture = ImageData(data: Data([1]), mediaType: "image/png", width: 1, height: 1)
        completion?(.success(picture))
        XCTAssertTrue(model.queue.tasks.isEmpty)
        XCTAssertTrue(model.images.isEmpty)
    }
}
