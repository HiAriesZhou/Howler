import AppKit
import HowlerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private var statusItem: NSStatusItem?
    private var panelController: PanelController?
    private var settingsController: SettingsWindowController?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settingsController = SettingsWindowController(settings: settings)
        self.settingsController = settingsController
        panelController = PanelController(settings: settings) { [weak self] in
            self?.openSettings()
        }

        hotKey = HotKey(keyCode: HotKey.defaultKeyCode, modifiers: HotKey.defaultModifiers) { [weak self] in
            MainActor.assumeIsolated { self?.togglePanel() }
        }
        setUpStatusItem(hotKeyRegistered: hotKey != nil)

        if !settings.isConfigured {
            openSettings()
        }
    }

    private func setUpStatusItem(hotKeyRegistered: Bool) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: AppInfo.name)
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        let open = NSMenuItem(title: "Open \(AppInfo.name)", action: #selector(togglePanel), keyEquivalent: " ")
        open.keyEquivalentModifierMask = [.option]
        open.target = self
        menu.addItem(open)
        if !hotKeyRegistered {
            let warning = NSMenuItem(title: "\(HotKey.defaultDisplay) is used by another app", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
        }
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() {
        panelController?.toggle()
    }

    @objc private func openSettings() {
        panelController?.hide()
        settingsController?.show()
    }
}
