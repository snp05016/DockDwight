import Carbon
import Foundation

public final class HotKeyController: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    private let hotKeyID: EventHotKeyID
    private let keyCode: UInt32
    private let modifiers: UInt32

    public init(
        keyCode: UInt32 = UInt32(kVK_ANSI_D),
        modifiers: UInt32 = UInt32(controlKey | optionKey),
        id: UInt32 = 1,
        action: @escaping () -> Void
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.hotKeyID = EventHotKeyID(signature: 0x44574754, id: id) // DWGT
        self.action = action
    }

    deinit { unregister() }

    @discardableResult
    public func register() -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var receivedID = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &receivedID)
                let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
                guard result == noErr,
                      receivedID.signature == controller.hotKeyID.signature,
                      receivedID.id == controller.hotKeyID.id else { return OSStatus(eventNotHandledErr) }
                controller.action()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard status == noErr else { return false }
        return RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        ) == noErr
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        if let handlerRef { RemoveEventHandler(handlerRef); self.handlerRef = nil }
    }
}
