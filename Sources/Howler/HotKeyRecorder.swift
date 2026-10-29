import AppKit
import HowlerCore
import SwiftUI

/// Click, then press the new shortcut. Esc cancels. The global hotkey is suspended while
/// recording so pressing the current shortcut doesn't toggle the letter instead. Only
/// keys typed into the Settings window count, and recording ends if that window loses
/// focus or closes.
struct HotKeyRecorder: View {
    @ObservedObject var settings: AppSettings

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
            // Reset sits to the left so the shortcut button keeps to the row's trailing edge.
            if settings.hotKey != .standard && !settings.isRecordingHotKey {
                Button {
                    settings.resetHotKey()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Reset to \(HotKeyCombo.standard.display)")
            }
            Button {
                settings.isRecordingHotKey ? stopRecording() : startRecording()
            } label: {
                Text(settings.isRecordingHotKey ? "Type a shortcut…" : settings.hotKey.display)
                    .frame(minWidth: 64)
            }
        }
        .onDisappear(perform: stopRecording)
        // Settings ends recording when its page is switched away (the page stays mounted).
        .onChange(of: settings.isRecordingHotKey) { _, recording in
            if !recording { stopRecording() }
        }
    }

    private func startRecording() {
        guard let window = NSApp.keyWindow else { return }
        hint = nil
        settings.isRecordingHotKey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === window else { return event }
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
        if event.keyCode == 53 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            stopRecording() // bare Esc cancels
            return
        }
        // The unshifted character, so ⇧⌘1 reads "⇧⌘1" rather than "⇧⌘!".
        let typed = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers
        guard let label = HotKeyCombo.label(keyCode: UInt32(event.keyCode), characters: typed) else {
            hint = "That key can't be used"
            return
        }
        let combo = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: Self.modifiers(event.modifierFlags), keyLabel: label)
        if combo.isSettings {
            hint = "\(HotKeyCombo.settings.display) opens Settings"
            return
        }
        guard combo.isValid else {
            hint = combo.modifiers.isDisjoint(with: [.command, .option, .control])
                ? "Add ⌘, ⌥ or ⌃"
                : "\(combo.display) belongs to the system"
            return
        }
        settings.setHotKey(combo)
        stopRecording()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if settings.isRecordingHotKey { settings.isRecordingHotKey = false }
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
