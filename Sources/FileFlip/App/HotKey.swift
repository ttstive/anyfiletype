import Carbon.HIToolbox

/// A system-wide shortcut. Carbon hotkeys need no Accessibility permission.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    private(set) var isRegistered = false

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, me, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x4646_4C50), id: 1)  // "FFLP"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = status == noErr
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
