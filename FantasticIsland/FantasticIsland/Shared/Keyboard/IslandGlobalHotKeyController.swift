import Carbon
import Foundation

enum IslandExpandShortcut {
    static let keyCode: UInt32 = UInt32(kVK_ANSI_E)
    static let carbonModifiers: UInt32 = UInt32(optionKey)
    static let displayText = "Option + E"
}

final class IslandGlobalHotKeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        installHandler()
        registerHotKey()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event,
                      let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                let controller = Unmanaged<IslandGlobalHotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                return controller.handleHotKeyEvent(event)
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
    }

    private func registerHotKey() {
        var hotKeyID = EventHotKeyID(
            signature: fourCharCode(from: "isld"),
            id: 1
        )

        RegisterEventHotKey(
            IslandExpandShortcut.keyCode,
            IslandExpandShortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr,
              hotKeyID.signature == fourCharCode(from: "isld"),
              hotKeyID.id == 1 else {
            return status
        }

        action()
        return noErr
    }

    private func fourCharCode(from string: String) -> FourCharCode {
        string.utf8.reduce(0) { result, byte in
            (result << 8) + FourCharCode(byte)
        }
    }
}
