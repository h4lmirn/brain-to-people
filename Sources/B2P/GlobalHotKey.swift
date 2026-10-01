import Carbon.HIToolbox

/// どのアプリを使っているときでも押せるショートカット。アクセシビリティの許可はいらない。
final class GlobalHotKey {
    var onPress: (@Sendable () -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    var isRegistered: Bool { hotKeyRef != nil }

    func register(keyCode: Int, modifiers: Int) {
        unregister()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().onPress?()
            return noErr
        }, 1, &spec, pointer, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x42325048), id: 1) // 'B2PH'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    deinit { unregister() }
}
