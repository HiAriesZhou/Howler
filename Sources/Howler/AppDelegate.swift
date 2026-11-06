import AppKit
import Combine
import HowlerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: AppSettings = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["HOWLER_DEMO"] != nil {
            let defaults = DemoDefaults(suiteName: "HowlerDemo")!
            let keys = ServiceStore.KeyAccess(exists: { _ in false }, get: { _ in nil },
                                             set: { _, _ in }, delete: { _ in })
            return AppSettings(defaults: defaults, keys: keys)
        }
        #endif
        return AppSettings()
    }()
    private let updater = Updater()
    private var statusItem: NSStatusItem?
    private var hotKeyWarningItem: NSMenuItem?
    private var updateItem: NSMenuItem?
    private var panelController: PanelController?
    private var settingsController: SettingsWindowController?
    private var hotKey: HotKey?
    private var settingsHotKey: HotKey?
    private var screenshotHotKey: HotKey?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        let settingsController = SettingsWindowController(settings: settings, updater: updater)
        self.settingsController = settingsController
        panelController = PanelController(settings: settings) { [weak self] in
            self?.openSettings()
        }
        setUpStatusItem()

        // Re-register whenever the shortcut changes; stand aside while Settings records one.
        settings.$hotKey.removeDuplicates()
            .combineLatest(settings.$screenshotHotKey.removeDuplicates(),
                           settings.$captureAndExplainEnabled.removeDuplicates(),
                           settings.$isRecordingHotKey.removeDuplicates())
            .sink { [weak self] combo, capture, enabled, recording in
                MainActor.assumeIsolated {
                    self?.registerHotKey(combo, capture: capture, captureEnabled: enabled, suspended: recording)
                }
            }
            .store(in: &cancellables)

        #if DEBUG
        if let demo = ProcessInfo.processInfo.environment["HOWLER_DEMO"] {
            if ProcessInfo.processInfo.environment["HOWLER_DEMO_DARK"] != nil {
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
            if demo == "menu", let menu = statusItem?.menu {
                MenuDemo.present(menu)
                return
            }
            if demo == "settings" {
                settings.useDemoService(.anthropic)
                if ProcessInfo.processInfo.environment["HOWLER_DEMO_CAPTURE"] == "off" {
                    settings.setCaptureAndExplainEnabled(false)
                }
                if let raw = ProcessInfo.processInfo.environment["HOWLER_DEMO_PROVIDER"], let provider = Provider(rawValue: raw) {
                    settings.useDemoService(provider)
                }
                let tab = ProcessInfo.processInfo.environment["HOWLER_DEMO_TAB"]
                settingsController.show(tab: tab.flatMap(SettingsTab.init(rawValue:)))
                if tab == "cycle" { settingsController.cycleTabs() }
                if let path = ProcessInfo.processInfo.environment["HOWLER_DEMO_SNAPSHOT"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        settingsController.snapshot(to: path)
                        NSApp.terminate(nil)
                    }
                }
            } else {
                panelController?.runDemo()
            }
            return
        }
        #endif
        if !settings.isConfigured {
            openSettings()
        }
    }

    private func registerHotKey(_ combo: HotKeyCombo, capture: HotKeyCombo, captureEnabled: Bool, suspended: Bool) {
        hotKey = nil // unregister first: re-registering our own combo would fail
        settingsHotKey = nil
        screenshotHotKey = nil
        guard !suspended else { return }
        hotKey = HotKey(keyCode: combo.keyCode, modifiers: combo.modifiers.rawValue) { [weak self] in
            MainActor.assumeIsolated { self?.panelController?.toggle() }
        }
        // ⌥, opens Settings from any app; if another app holds it, the menu still does.
        let settingsCombo = HotKeyCombo.settings
        settingsHotKey = HotKey(keyCode: settingsCombo.keyCode, modifiers: settingsCombo.modifiers.rawValue) { [weak self] in
            MainActor.assumeIsolated { self?.openSettings() }
        }
        if captureEnabled, !capture.matches(combo) {
            screenshotHotKey = HotKey(keyCode: capture.keyCode, modifiers: capture.modifiers.rawValue) { [weak self] in
                MainActor.assumeIsolated { self?.panelController?.viewModel.captureScreen() }
            }
        }
        settings.screenshotHotKeyRegistered = screenshotHotKey != nil
        settings.hotKeyRegistered = hotKey != nil
        updateMenu(for: combo)
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarMark.image()

        let parts = Self.makeStatusMenu(showsUpdate: updater.isEnabled, target: self)
        let menu = parts.menu
        updateItem = parts.update
        item.menu = menu
        statusItem = item
        hotKeyWarningItem = parts.warning
        if let updateItem {
            // Subscribe after the controls exist: @Published emits its current value immediately.
            updater.$available.combineLatest(updater.$canCheck)
                .sink { [weak item, weak updateItem] available, canCheck in
                    MainActor.assumeIsolated {
                        guard let item, let updateItem else { return }
                        Self.updateUpdateItem(updateItem, statusItem: item, available: available, canCheck: canCheck)
                    }
                }
                .store(in: &cancellables)
        }
    }

    static func makeStatusMenu(showsUpdate: Bool, target: AnyObject) -> (menu: NSMenu, warning: NSMenuItem, update: NSMenuItem?) {
        let menu = NSMenu()
        var updateItem: NSMenuItem?
        menu.autoenablesItems = false // the update item follows Sparkle's canCheckForUpdates
        menu.showsStateColumn = false
        // AppKit adds images for recognized actions such as openSettings even after
        // image is cleared. A neutral menu action keeps this menu entirely text-only.
        func item(_ title: String, action: Selector) -> NSMenuItem {
            ClosureMenuItem(title: title) { [weak target] in
                guard let target else { return }
                NSApp.sendAction(action, to: target, from: nil)
            }
        }
        // No key equivalents: the global shortcut opens the letter, and a menu shortcut is one
        // more thing to press by accident.
        let open = item("Open \(AppInfo.name)", action: #selector(togglePanel))
        menu.addItem(open)
        let warning = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        warning.isEnabled = false
        warning.isHidden = true
        menu.addItem(warning)
        menu.addItem(.separator())
        let settingsItem = item("Settings", action: #selector(openSettings))
        menu.addItem(settingsItem)
        if showsUpdate {
            let update = item("Check for Updates", action: #selector(checkForUpdates))
            menu.addItem(update)
            updateItem = update
        }
        let feedback = item("Send Feedback", action: #selector(sendFeedback))
        menu.addItem(feedback)
        menu.addItem(.separator())
        let quit = ClosureMenuItem(title: "Quit \(AppInfo.name)") { NSApp.terminate(nil) }
        menu.addItem(quit)
        return (menu, warning, updateItem)
    }

    /// "Check for Updates", or the gentle reminder when a scheduled check found one.
    static func updateUpdateItem(_ updateItem: NSMenuItem, statusItem: NSStatusItem, available: String?, canCheck: Bool) {
        updateItem.title = available.map { "Update to \(AppInfo.name) \($0)" } ?? "Check for Updates"
        updateItem.isEnabled = canCheck
        updateItem.image = nil
        let description = available.map { "\(AppInfo.name) \(AppInfo.version), version \($0) is available" }
            ?? "\(AppInfo.name) \(AppInfo.version)"
        statusItem.button?.image = MenuBarMark.image(updateAvailable: available != nil)
        statusItem.button?.toolTip = description
        statusItem.button?.setAccessibilityLabel(description)
    }

    /// Explains in the menu when the shortcut isn't active.
    private func updateMenu(for combo: HotKeyCombo) {
        guard let hotKeyWarningItem else { return }
        hotKeyWarningItem.title = "\(combo.display) is used by another app"
        hotKeyWarningItem.isHidden = settings.hotKeyRegistered
    }

    /// Accessory apps show no menu bar, but key equivalents still route through the main
    /// menu: without an Edit menu, ⌘C / ⌘V / ⌘A do nothing in the letter's text field.
    private func installEditMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func togglePanel() {
        panelController?.show()
    }

    @objc private func sendFeedback() {
        panelController?.hide(burning: false)
        Feedback.open()
    }

    @objc private func checkForUpdates() {
        panelController?.hide(burning: false)
        if updater.available != nil {
            updater.installAvailableUpdate()
        } else {
            updater.checkForUpdates()
        }
    }

    @objc private func openSettings() {
        panelController?.hide(burning: false)
        settingsController?.show()
    }
}
