import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut.
///
/// Carbon's `RegisterEventHotKey` rather than an event monitor on purpose: it
/// needs no Accessibility permission, and Companion should not ask for a
/// permission it does not otherwise use.
final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    private static let signature: OSType = 0x434D_5041 // 'CMPA'
    private static var registry: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1

    private let identifier: UInt32

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        identifier = Self.nextID
        Self.nextID += 1

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                HotKey.registry[hotKeyID.id]?.action()
                return noErr
            },
            1,
            &eventType,
            nil,
            &handler
        )
        guard status == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let registered = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        // Another app may already own this shortcut. Fail cleanly so the caller
        // can tell the user, instead of leaving a hotkey that silently does
        // nothing.
        guard registered == noErr else { return nil }

        Self.registry[identifier] = self
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        Self.registry[identifier] = nil
    }
}
