import AppKit
import SwiftUI
import XCTest
@testable import Howler

final class UpdatePresentationTests: XCTestCase {
    @MainActor
    private func render<V: View>(_ view: V, name: String, scale: CGFloat = 2) throws -> Data {
        _ = NSApplication.shared
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        if let folder = ProcessInfo.processInfo.environment["HOWLER_TEST_SNAPSHOTS"] {
            let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
        }
        return try XCTUnwrap(image.dataProvider?.data) as Data
    }

    @MainActor
    func testUpdateMarkStaysStaticAndAdaptsToBothAppearancesAndScales() async throws {
        for dark in [false, true] {
            for scale: CGFloat in [1, 2] {
                func mark(_ available: Bool) -> some View {
                    Image(nsImage: MenuBarMark.image(updateAvailable: available))
                        .renderingMode(.template)
                        .foregroundStyle(dark ? Color.white : Color.black)
                        .frame(width: 28, height: 24)
                        .background(dark ? Color.black : Color.white)
                }
                let name = "update-mark-\(dark ? "dark" : "light")-\(Int(scale))x"
                let normal = try render(mark(false), name: name + "-normal", scale: scale)
                let waiting = try render(mark(true), name: name + "-waiting", scale: scale)
                let again = try render(mark(true), name: name + "-again", scale: scale)
                XCTAssertFalse(normal.isEmpty)
                XCTAssertNotEqual(normal, waiting, "The reminder must be visible at either display scale")
                XCTAssertEqual(waiting, again, "The reminder is a static mark, including with Reduce Motion")
            }
        }
        XCTAssertTrue(MenuBarMark.image(updateAvailable: true).isTemplate)
        XCTAssertEqual(MenuBarMark.image().size, MenuBarMark.image(updateAvailable: true).size)
    }

    @MainActor
    func testMenuReminderShowsVersionAndClearsWithoutChangingItsAction() async throws {
        _ = NSApplication.shared
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(status) }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let target = UpdateActionTarget()
        let item = NSMenuItem(title: "", action: #selector(UpdateActionTarget.check), keyEquivalent: "")
        item.target = target
        menu.addItem(item)
        status.menu = menu

        AppDelegate.updateUpdateItem(item, statusItem: status, available: "0.1.13", canCheck: true)
        XCTAssertEqual(item.title, "Update to \(AppInfo.name) 0.1.13…")
        XCTAssertTrue(item.isEnabled)
        let button = try XCTUnwrap(status.button)
        XCTAssertTrue(try XCTUnwrap(button.toolTip).contains("0.1.13"))
        XCTAssertTrue(try XCTUnwrap(button.accessibilityLabel()).contains(AppInfo.version))
        XCTAssertTrue(try XCTUnwrap(button.accessibilityLabel()).contains("0.1.13"))
        XCTAssertTrue(try XCTUnwrap(button.image?.accessibilityDescription).contains("update available"))
        menu.performActionForItem(at: 0)
        XCTAssertEqual(target.count, 1)

        // Sparkle's attention/session callbacks supply nil after the user sees the
        // update window, dismisses it, or a session fails.
        XCTAssertTrue(try XCTUnwrap(button.toolTip).contains("0.1.13"))
        AppDelegate.updateUpdateItem(item, statusItem: status, available: nil, canCheck: true)
        XCTAssertEqual(item.title, "Check for Updates…")
        XCTAssertEqual(button.toolTip, "\(AppInfo.name) \(AppInfo.version)")
        XCTAssertEqual(button.accessibilityLabel(), button.toolTip)
        XCTAssertEqual(button.image?.accessibilityDescription, AppInfo.name)
        menu.performActionForItem(at: 0)
        XCTAssertEqual(target.count, 2)
    }

    @MainActor
    func testUnavailableCheckKeepsExistingReminderButDisablesAction() async throws {
        _ = NSApplication.shared
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(status) }
        let item = NSMenuItem()
        AppDelegate.updateUpdateItem(item, statusItem: status, available: "0.1.13", canCheck: false)
        XCTAssertFalse(item.isEnabled)
        XCTAssertTrue(try XCTUnwrap(status.button?.toolTip).contains("0.1.13"))
        XCTAssertTrue(try XCTUnwrap(status.button?.image?.accessibilityDescription).contains("update available"))
        AppDelegate.updateUpdateItem(item, statusItem: status, available: nil, canCheck: false)
        XCTAssertFalse(item.isEnabled)
        XCTAssertEqual(status.button?.image?.accessibilityDescription, AppInfo.name)
    }

    @MainActor
    func testVersionFootnoteRendersCurrentAndAvailableStates() async throws {
        _ = NSApplication.shared
        for dark in [false, true] {
            var current: Data?
            for available in [nil, "0.1.13", "0.1.130-development.123"] as [String?] {
                var presses = 0
                let footnote = VersionFootnote(available: available, canCheck: true, installUpdate: { presses += 1 })
                    .padding(20)
                    .frame(width: 460)
                    .background(dark ? Color.black : Color.white)
                    .environment(\.colorScheme, dark ? .dark : .light)
                // Native link buttons need AppKit; ImageRenderer substitutes a placeholder.
                let host = NSHostingView(rootView: footnote)
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.setFrameSize(NSSize(width: 460, height: host.fittingSize.height))
                let window = NSWindow(contentRect: host.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                defer { window.close() }
                window.orderFront(nil)
                try await Task.sleep(nanoseconds: 50_000_000)
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let pixels = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let name = "update-footer-\(dark ? "dark" : "light")-\(available ?? "current")"
                if let folder = ProcessInfo.processInfo.environment["HOWLER_TEST_SNAPSHOTS"] {
                    try pixels.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
                }
                XCTAssertFalse(pixels.isEmpty)
                let buttons = nativeButtons(in: host)
                if available != nil {
                    let button = try XCTUnwrap(buttons.first)
                    // SwiftUI draws the label separately from NSButton.title. The native
                    // snapshot covers the label; exercise the actual platform action here.
                    XCTAssertTrue(button.isEnabled)
                    button.performClick(nil)
                    XCTAssertEqual(presses, 1)
                } else {
                    XCTAssertTrue(buttons.isEmpty)
                }
                if let current {
                    XCTAssertNotEqual(pixels, current, "A waiting update must have a visible link")
                } else {
                    current = pixels
                }
            }
        }
    }

    @MainActor
    private func nativeButtons(in view: NSView) -> [NSButton] {
        let own = (view as? NSButton).map { [$0] } ?? []
        return own + view.subviews.flatMap { nativeButtons(in: $0) }
    }
}

@MainActor
private final class UpdateActionTarget: NSObject {
    private(set) var count = 0
    @objc func check() { count += 1 }
}
