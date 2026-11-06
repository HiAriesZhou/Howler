import AppKit
import HowlerCore
import XCTest
@testable import Howler

@MainActor
final class CaptureSettingsTests: XCTestCase {
    func testCaptureSwitchPersistsAndKeepsRecordedShortcut() throws {
        let suite = "HowlerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, keys: MemoryKeys().access)
        XCTAssertTrue(settings.captureAndExplainEnabled)
        XCTAssertEqual(settings.screenshotHotKey, .screenshot)
        let custom = HotKeyCombo(keyCode: 40, modifiers: [.control, .option], keyLabel: "K")
        settings.setScreenshotHotKey(custom)
        settings.recordingScreenshot = true
        settings.isRecordingHotKey = true
        settings.setCaptureAndExplainEnabled(false)
        XCTAssertFalse(settings.isRecordingHotKey)
        let reopened = AppSettings(defaults: defaults, keys: MemoryKeys().access)
        XCTAssertFalse(reopened.captureAndExplainEnabled)
        XCTAssertEqual(reopened.screenshotHotKey, custom)
        reopened.setCaptureAndExplainEnabled(true)
        XCTAssertEqual(reopened.screenshotHotKey, custom)
        XCTAssertEqual(reopened.hotKey, .standard)
        XCTAssertTrue(AppSettings(defaults: defaults, keys: MemoryKeys().access).captureAndExplainEnabled)
    }

    func testDisabledCaptureDoesNotReadScreenOrSubmitPendingSelection() throws {
        let defaults = DemoDefaults(suiteName: "HowlerTests.CaptureSwitch")!
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
        settings.setCaptureAndExplainEnabled(false)
        model.captureScreen()
        XCTAssertEqual(captures, 0)
        settings.setCaptureAndExplainEnabled(true)
        model.captureScreen()
        XCTAssertEqual(captures, 1)
        settings.setCaptureAndExplainEnabled(false)
        let picture = ImageData(data: Data([1, 2, 3]), mediaType: "image/png", width: 1, height: 1)
        completion?(.success(picture))
        XCTAssertEqual(requests, 0)
        XCTAssertTrue(model.queue.tasks.isEmpty)
        XCTAssertTrue(model.images.isEmpty)
        settings.setCaptureAndExplainEnabled(true)
        model.captureScreen()
        completion?(.success(picture))
        XCTAssertEqual(captures, 2)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(model.queue.tasks.count, 1)
        settings.setCaptureAndExplainEnabled(false)
        XCTAssertEqual(model.queue.tasks.count, 1)
        XCTAssertFalse(model.queue.isPaused)
    }
}
