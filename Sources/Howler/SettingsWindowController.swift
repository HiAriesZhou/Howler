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
        settings.refreshKeyPresence()
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(settings: settings))
            // The page changes height as a provider is chosen; let the window follow it.
            controller.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: controller)
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
