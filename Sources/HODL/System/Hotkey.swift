import Carbon.HIToolbox

/// The global ⌥⌘L shortcut. Carbon hot keys need no Accessibility permission.
@MainActor
enum Hotkey {
    private static var hotKey: EventHotKeyRef?
    private static var handler: EventHandlerRef?
    static var action: (() -> Void)?

    static func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    private static func register() {
        guard hotKey == nil else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                MainActor.assumeIsolated { Hotkey.action?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x484F_444C), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    private static func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }
}
