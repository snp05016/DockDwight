import Carbon
import Foundation

public final class HotKeyController: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    private let hotKeyID = EventHotKeyID(signature: 0x44574754, id: 1) // DWGT

    public init(action: @escaping () -> Void) {
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
                guard result == noErr, receivedID.signature == 0x44574754, receivedID.id == 1 else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
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
            UInt32(kVK_ANSI_D),
            UInt32(controlKey | optionKey),
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

