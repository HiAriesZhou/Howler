import AppKit
import XCTest
@testable import Howler

@MainActor
final class StatusMenuTests: XCTestCase {
    func testMenuStaysTextOnlyAfterAppKitPreparesItsActions() throws {
        _ = NSApplication.shared
        let target = MenuTarget()
        let parts = AppDelegate.makeStatusMenu(showsUpdate: true, target: target)
        let menu = parts.menu
        // AppKit supplies some action images only while preparing a native menu.
        let timer = Timer(timeInterval: 0.15, repeats: false) { _ in menu.cancelTracking() }
        RunLoop.main.add(timer, forMode: .eventTracking)
        menu.popUp(positioning: nil, at: NSPoint(x: 200, y: 200), in: nil)
        let rows = menu.items.filter { !$0.isSeparatorItem && !$0.isHidden }
        XCTAssertEqual(rows.map(\.title), ["Open \(AppInfo.name)", "Settings", "Check for Updates", "Send Feedback", "Quit \(AppInfo.name)"])
        XCTAssertFalse(menu.showsStateColumn)
        XCTAssertTrue(rows.allSatisfy { $0.image == nil }, "Native action preparation must not reinsert icons")
        XCTAssertTrue(rows.allSatisfy { $0.indentationLevel == 0 })
        XCTAssertTrue(rows.allSatisfy { $0.keyEquivalent.isEmpty })
        for index in [0, 3, 4, 5] { menu.performActionForItem(at: index) }
        XCTAssertEqual(target.actions, ["open", "settings", "update", "feedback"])
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(status) }
        AppDelegate.updateUpdateItem(try XCTUnwrap(parts.update), statusItem: status,
                                     available: "0.1.140-development.123", canCheck: true)
        XCTAssertEqual(parts.update?.title, "Update to \(AppInfo.name) 0.1.140-development.123")
        XCTAssertNil(AppDelegate.makeStatusMenu(showsUpdate: false, target: target).update)
    }
}

@MainActor
private final class MenuTarget: NSObject {
    var actions: [String] = []
    @objc func togglePanel() { actions.append("open") }
    @objc func openSettings() { actions.append("settings") }
    @objc func checkForUpdates() { actions.append("update") }
    @objc func sendFeedback() { actions.append("feedback") }
}
