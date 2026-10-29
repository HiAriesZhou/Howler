import Foundation

/// A global shortcut as stored in settings. Modifier bits use Carbon's values
/// (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`) so the app can hand them straight to
/// `RegisterEventHotKey`, while this type stays free of Carbon for Linux tests.
public struct HotKeyCombo: Equatable, Codable, Sendable {
    public struct Modifiers: OptionSet, Codable, Sendable, Hashable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 0x0100)
        public static let shift = Modifiers(rawValue: 0x0200)
        public static let option = Modifiers(rawValue: 0x0800)
        public static let control = Modifiers(rawValue: 0x1000)
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers
    /// Captured when the shortcut is recorded, so the display matches the user's layout.
    public var keyLabel: String

    public init(keyCode: UInt32, modifiers: Modifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// The shortcut until the user records another: ⌥, (beside ⌘, for Settings). ⌥Space,
    /// the default before v0.1.5, collides with other assistants' launchers; ⌥H, the default
    /// until v0.1.8, with other apps' shortcuts (e.g. WeChat). A recorded ⌥H stays.
    public static let standard = HotKeyCombo(keyCode: 43, modifiers: .option, keyLabel: ",")

    /// ⌥Space, the default until v0.1.5. Only the old Reset button stored it, so a stored
    /// copy found on upgrade means "the default", not a choice.
    public static let previousStandard = HotKeyCombo(keyCode: spaceKeyCode, modifiers: .option, keyLabel: "Space")

    public static let spaceKeyCode: UInt32 = 49

    /// The shortcut to use for what settings hold: a missing or invalid combo means the default.
    public static func effective(stored: HotKeyCombo?) -> HotKeyCombo {
        guard let stored, stored.isValid else { return standard }
        return stored
    }

    /// Applied once, on the first launch after the default moved off ⌥Space: a stored ⌥Space is
    /// dropped so it follows the default. After that, ⌥Space recorded on purpose stays.
    public static func storedAfterDefaultChange(_ stored: HotKeyCombo?) -> HotKeyCombo? {
        stored == previousStandard ? nil : stored
    }

    /// "⌃⌥⇧⌘K" — Apple's canonical modifier order.
    public var display: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + keyLabel
    }

    /// A global shortcut needs ⌃, ⌥ or ⌘ (⇧ alone would eat ordinary typing), except
    /// function keys, which are fine bare. Esc is reserved for closing the panel.
    /// Standard editing and system shortcuts stay with the system; a global hotkey would
    /// steal them from every app.
    public var isValid: Bool {
        guard keyCode != Self.escapeKeyCode, !isReserved else { return false }
        if Self.functionKeys[keyCode] != nil { return true }
        return !modifiers.isDisjoint(with: [.command, .control, .option])
    }

    static let escapeKeyCode: UInt32 = 53

    /// ⌘A ⌘C ⌘V ⌘X ⌘Z ⌘Q ⌘W ⌘H ⌘M, ⌘Space (Spotlight) and ⌘Tab (app switcher).
    private static let reservedWithCommand: Set<UInt32> = [0, 8, 9, 7, 6, 12, 13, 4, 46, 49, 48]

    private var isReserved: Bool {
        modifiers == .command && Self.reservedWithCommand.contains(keyCode)
    }

    /// Display label for a virtual key code; `characters` is what the key types on the
    /// current layout (`NSEvent.charactersIgnoringModifiers`).
    public static func label(keyCode: UInt32, characters: String?) -> String? {
        if let name = specialKeys[keyCode] ?? functionKeys[keyCode] { return name }
        let typed = characters?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return typed.isEmpty ? nil : typed
    }

    private static let specialKeys: [UInt32: String] = [
        49: "Space", 36: "↩", 76: "⌤", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]

    private static let functionKeys: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]
}
