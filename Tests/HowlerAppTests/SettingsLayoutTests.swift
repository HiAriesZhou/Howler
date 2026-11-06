import AppKit
import XCTest
@testable import Howler

@MainActor
final class SettingsLayoutTests: XCTestCase {
    func testThreeTabsKeepWindowSizeAndStopShortcutRecording() async throws {
        _ = NSApplication.shared
        let defaults = DemoDefaults(suiteName: "HowlerTests.SettingsLayout")!
        let settings = AppSettings(defaults: defaults, keys: MemoryKeys().access)
        settings.useDemoService(.anthropic)
        let controller = SettingsWindowController(settings: settings, updater: Updater())
        controller.show(tab: .general)
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "\(AppInfo.name) Settings" && $0.isVisible })
        defer { window.close() }
        try await Task.sleep(nanoseconds: 800_000_000)
        let size = window.frame.size
        XCTAssertEqual(window.contentView?.frame.width, SettingsWindowController.width)
        XCTAssertGreaterThan(size.height, 300)
        let segmented = try XCTUnwrap(window.toolbar?.items.compactMap { $0.view as? NSSegmentedControl }.first)
        XCTAssertEqual(segmented.segmentCount, 3)
        XCTAssertEqual((0..<3).compactMap { segmented.label(forSegment: $0) }, ["General", "Prompt", "Shortcut"])

        for tab in SettingsTab.allCases {
            controller.show(tab: tab)
            try await Task.sleep(nanoseconds: 400_000_000)
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(window.frame.size, size, "Switching to \(tab) must keep the shared window size")
            if let folder = ProcessInfo.processInfo.environment["HOWLER_TEST_SNAPSHOTS"] {
                controller.snapshot(to: "\(folder)/settings-\(tab.rawValue).png")
            }
        }
        settings.isRecordingHotKey = true
        settings.recordingAction = .capture
        controller.show(tab: .prompt)
        XCTAssertFalse(settings.isRecordingHotKey)
        settings.setScreenshotHotKey(nil)
        settings.screenshotHotKeyRegistered = false
        controller.show(tab: .shortcut)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(window.frame.size, size)
        if let folder = ProcessInfo.processInfo.environment["HOWLER_TEST_SNAPSHOTS"] {
            controller.snapshot(to: "\(folder)/settings-shortcut-off.png")
        }
    }
}
