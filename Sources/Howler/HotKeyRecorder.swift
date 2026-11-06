import AppKit
import HowlerCore
import SwiftUI

/// Click, then press the new shortcut. Esc cancels. The global hotkey is suspended while
/// recording so pressing the current shortcut doesn't toggle the letter instead. Only
/// keys typed into the Settings window count, and recording ends if that window loses
/// focus or closes.
struct HotKeyRecorder: View {
    @ObservedObject var settings: AppSettings

    var action: ShortcutAction = .letter
    private var combo: HotKeyCombo? { settings.shortcut(for: action) }
    private var standard: HotKeyCombo { action.standard }
    private var recording: Bool { settings.isRecordingHotKey && settings.recordingAction == action }

    @State private var monitor: Any?
    @State private var observers: [NSObjectProtocol] = []
    @State private var hint: String?

    var body: some View {
        HStack(spacing: 8) {
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Reset precedes the recorder; reserve the clear slot even when empty.
            if combo != standard && !recording {
                Button {
                    hint = nil
                    if let conflict = settings.shortcutConflict(standard, for: action) {
                        hint = "\(standard.display) is used by \(conflict.name)"
                    } else {
                        settings.resetShortcut(for: action)
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Reset to \(standard.display)")
                .accessibilityLabel("Reset \(action.name) shortcut")
            }
            Button {
                recording ? stopRecording() : startRecording()
            } label: {
                Text(recording ? "Type a shortcut…" : combo?.display ?? "Not set")
                    .foregroundStyle(combo == nil && !recording ? .secondary : .primary)
                    .frame(minWidth: 64)
            }
            .accessibilityLabel("\(action.name) shortcut")
            .accessibilityValue(recording ? "Recording" : combo?.display ?? "Not set, disabled")
            .help("Click to record. Delete clears the shortcut; Esc cancels.")
            if combo != nil && !recording {
                Button {
                    hint = nil
                    settings.setShortcut(nil, for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Clear shortcut")
                .accessibilityLabel("Clear \(action.name) shortcut")
            } else {
                Color.clear.frame(width: 20, height: 20).accessibilityHidden(true)
            }
        }
        .onDisappear(perform: stopRecording)
        // Settings ends recording when its page is switched away (the page stays mounted).
        .onChange(of: recording) { _, recording in
            if !recording { stopRecording() }
        }
    }

    private func startRecording() {
        guard let window = NSApp.keyWindow else { return }
        hint = nil
        settings.recordingAction = action
        settings.isRecordingHotKey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === window, recording else { return event }
            MainActor.assumeIsolated { record(event) }
            return nil
        }
        let center = NotificationCenter.default
        observers = [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification].map { name in
            center.addObserver(forName: name, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { stopRecording() }
            }
        }
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == 53 && Self.modifiers(event.modifierFlags).isEmpty {
            stopRecording() // bare Esc cancels
            return
        }
        if [51, 117].contains(event.keyCode),
           Self.modifiers(event.modifierFlags).isEmpty {
            settings.setShortcut(nil, for: action)
            stopRecording()
            return
        }
        // The unshifted character, so ⇧⌘1 reads "⇧⌘1" rather than "⇧⌘!".
        let typed = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers
        guard let label = HotKeyCombo.label(keyCode: UInt32(event.keyCode), characters: typed) else {
            hint = "That key can't be used"
            return
        }
        let combo = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: Self.modifiers(event.modifierFlags), keyLabel: label)
        guard combo.isValid else {
            hint = combo.modifiers.isDisjoint(with: [.command, .option, .control])
                ? "Add ⌘, ⌥ or ⌃"
                : "\(combo.display) belongs to the system"
            return
        }
        if let conflict = settings.shortcutConflict(combo, for: action) {
            hint = "\(combo.display) is used by \(conflict.name)"
            return
        }
        settings.setShortcut(combo, for: action)
        stopRecording()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if recording { settings.isRecordingHotKey = false }
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> HotKeyCombo.Modifiers {
        var result: HotKeyCombo.Modifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }
}
