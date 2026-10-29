import AppKit
import Combine
import HowlerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let updater = Updater()
    private var statusItem: NSStatusItem?
    private var hotKeyWarningItem: NSMenuItem?
    private var updateItem: NSMenuItem?
    private var panelController: PanelController?
    private var settingsController: SettingsWindowController?
    private var hotKey: HotKey?
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
            .combineLatest(settings.$isRecordingHotKey.removeDuplicates())
            .sink { [weak self] combo, recording in
                MainActor.assumeIsolated { self?.registerHotKey(combo, suspended: recording) }
            }
            .store(in: &cancellables)

        #if DEBUG
        if let demo = ProcessInfo.processInfo.environment["HOWLER_DEMO"] {
            if ProcessInfo.processInfo.environment["HOWLER_DEMO_DARK"] != nil {
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
            if demo == "settings" {
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

    private func registerHotKey(_ combo: HotKeyCombo, suspended: Bool) {
        hotKey = nil // unregister first: re-registering our own combo would fail
        guard !suspended else { return }
        hotKey = HotKey(keyCode: combo.keyCode, modifiers: combo.modifiers.rawValue) { [weak self] in
            MainActor.assumeIsolated { self?.togglePanel() }
        }
        settings.hotKeyRegistered = hotKey != nil
        updateMenu(for: combo)
    }

    /// The size macOS 26 draws menu item symbols at.
    private static let menuIconSide: CGFloat = 16

    private static func menuSymbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarMark.image()

        let menu = NSMenu()
        menu.autoenablesItems = false // the update item follows Sparkle's canCheckForUpdates
        // No key equivalents: the global shortcut opens the letter, and a menu shortcut is one
        // more thing to press by accident.
        let open = NSMenuItem(title: "Open \(AppInfo.name)", action: #selector(togglePanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let warning = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        warning.isEnabled = false
        warning.isHidden = true
        menu.addItem(warning)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        if updater.isEnabled {
            let update = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
            updateItem = update
            updater.$available.combineLatest(updater.$canCheck)
                .sink { [weak self] available, canCheck in
                    MainActor.assumeIsolated { self?.updateUpdateItem(available: available, canCheck: canCheck) }
                }
                .store(in: &cancellables)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quit)
        if #available(macOS 26, *) {
            // macOS 26 draws icons beside menu items; give every row one, in one style,
            // instead of the system's defaults for Settings… and Quit.
            open.image = MenuBarMark.image(side: Self.menuIconSide)
            settingsItem.image = Self.menuSymbol("gearshape")
            updateItem?.image = Self.menuSymbol("arrow.triangle.2.circlepath")
            quit.image = Self.menuSymbol("power")
        }
        item.menu = menu
        statusItem = item
        hotKeyWarningItem = warning
    }

    /// "Check for Updates…", or the gentle reminder when a scheduled check found one.
    private func updateUpdateItem(available: String?, canCheck: Bool) {
        guard let updateItem else { return }
        updateItem.title = available.map { "Update to \(AppInfo.name) \($0)…" } ?? "Check for Updates…"
        updateItem.isEnabled = canCheck
        if #available(macOS 26, *) {
            updateItem.image = Self.menuSymbol(available == nil ? "arrow.triangle.2.circlepath" : "arrow.down.circle")
        } else {
            updateItem.image = available == nil ? nil : Self.menuSymbol("arrow.down.circle")
        }
        statusItem?.button?.toolTip = available.map { "\(AppInfo.name) \($0) is available" }
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
        panelController?.toggle()
    }

    @objc private func checkForUpdates() {
        panelController?.hide(burning: false)
        updater.checkForUpdates()
    }

    @objc private func openSettings() {
        panelController?.hide(burning: false)
        settingsController?.show()
    }
}
