import AppKit
import Combine
import HowlerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private var statusItem: NSStatusItem?
    private var openItem: NSMenuItem?
    private var hotKeyWarningItem: NSMenuItem?
    private var panelController: PanelController?
    private var settingsController: SettingsWindowController?
    private var hotKey: HotKey?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        let settingsController = SettingsWindowController(settings: settings)
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
            if demo == "settings" {
                if let raw = ProcessInfo.processInfo.environment["HOWLER_DEMO_PROVIDER"], let provider = Provider(rawValue: raw) {
                    settings.useDemoService(provider)
                }
                openSettings()
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

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarMark.image()

        let menu = NSMenu()
        let open = NSMenuItem(title: "Open \(AppInfo.name)", action: #selector(togglePanel), keyEquivalent: "")
        open.target = self
        if #available(macOS 26, *) {
            // macOS 26 gives Settings… and Quit icons; without one this row's title sits apart.
            // Howler's own seal, at the size of the symbols beside it.
            open.image = MenuBarMark.image(side: Self.menuIconSide)
        }
        menu.addItem(open)
        let warning = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        warning.isEnabled = false
        warning.isHidden = true
        menu.addItem(warning)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        openItem = open
        hotKeyWarningItem = warning
    }

    /// Shows the shortcut next to "Open Howler", or explains why it isn't active.
    private func updateMenu(for combo: HotKeyCombo) {
        guard let openItem, let hotKeyWarningItem else { return }
        let equivalent = Self.keyEquivalent(for: combo)
        openItem.keyEquivalent = equivalent ?? ""
        openItem.keyEquivalentModifierMask = equivalent == nil ? [] : Self.modifierFlags(for: combo)
        openItem.title = equivalent == nil ? "Open \(AppInfo.name)  (\(combo.display))" : "Open \(AppInfo.name)"
        hotKeyWarningItem.title = "\(combo.display) is used by another app"
        hotKeyWarningItem.isHidden = settings.hotKeyRegistered
    }

    private static func keyEquivalent(for combo: HotKeyCombo) -> String? {
        if combo.keyCode == HotKeyCombo.spaceKeyCode { return " " }
        if let number = Int(combo.keyLabel.dropFirst()), combo.keyLabel.hasPrefix("F"), (1...20).contains(number),
           let scalar = UnicodeScalar(NSF1FunctionKey + number - 1) {
            return String(Character(scalar))
        }
        // Symbol labels (↩, ←, …) are not the characters those keys type; show them in the title.
        guard combo.keyLabel.count == 1, combo.keyLabel.allSatisfy({ $0.isASCII }) else { return nil }
        return combo.keyLabel.lowercased()
    }

    private static func modifierFlags(for combo: HotKeyCombo) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if combo.modifiers.contains(.command) { flags.insert(.command) }
        if combo.modifiers.contains(.option) { flags.insert(.option) }
        if combo.modifiers.contains(.control) { flags.insert(.control) }
        if combo.modifiers.contains(.shift) { flags.insert(.shift) }
        return flags
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

    @objc private func openSettings() {
        panelController?.hide(burning: false)
        settingsController?.show()
    }
}
