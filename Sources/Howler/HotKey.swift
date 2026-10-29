import Carbon.HIToolbox

/// A system-wide hotkey registered with Carbon's `RegisterEventHotKey`.
/// Needs no Accessibility permission and no third-party dependency.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    /// Every hotkey's handler sees every hotkey press; each answers only to its own id.
    private let id: UInt32
    private static var nextID: UInt32 = 1

    /// Returns nil if the shortcut is already taken by another app.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
                )
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                guard status == noErr, pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
                hotKey.action()
                return noErr
            },
            1, &eventType, context, &handlerRef
        )
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x484F_574C), id: id) // 'HOWL'
        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registerStatus == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
