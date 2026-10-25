import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private var window: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
            window.title = "\(AppInfo.name) Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // Accessory apps must activate explicitly for a regular window to take focus.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
