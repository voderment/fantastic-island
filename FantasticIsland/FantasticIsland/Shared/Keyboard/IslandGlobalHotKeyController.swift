import Carbon
import Foundation

enum IslandExpandShortcut {
    static let keyCode: UInt32 = UInt32(kVK_ANSI_E)
    static let carbonModifiers: UInt32 = UInt32(optionKey)
    static let displayText = "Option + E"
}

enum IslandTwitterShortcut {
    static let keyCode: UInt32 = UInt32(kVK_ANSI_S)
    static let carbonModifiers: UInt32 = UInt32(cmdKey) | UInt32(shiftKey)
    static let displayText = "Command + Shift + S"
}

enum IslandHotKeyAction {
    case toggleExpansion
    case openTwitterComposer
}

final class IslandGlobalHotKeyController {
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private let action: (IslandHotKeyAction) -> Void

    init(action: @escaping (IslandHotKeyAction) -> Void) {
        self.action = action
        installHandler()
        registerHotKeys()
    }

    deinit {
        for hotKeyRef in hotKeyRefs {
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

    private func registerHotKeys() {
        registerHotKey(
            id: 1,
            keyCode: IslandExpandShortcut.keyCode,
            modifiers: IslandExpandShortcut.carbonModifiers
        )
        registerHotKey(
            id: 2,
            keyCode: IslandTwitterShortcut.keyCode,
            modifiers: IslandTwitterShortcut.carbonModifiers
        )
    }

    private func registerHotKey(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(
            signature: fourCharCode(from: "isld"),
            id: id
        )
        var hotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let hotKeyRef {
            hotKeyRefs.append(hotKeyRef)
        }
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
              hotKeyID.signature == fourCharCode(from: "isld") else {
            return status
        }

        switch hotKeyID.id {
        case 1:
            action(.toggleExpansion)
            return noErr
        case 2:
            action(.openTwitterComposer)
            return noErr
        default:
            return OSStatus(eventNotHandledErr)
        }
    }

    private func fourCharCode(from string: String) -> FourCharCode {
        string.utf8.reduce(0) { result, byte in
            (result << 8) + FourCharCode(byte)
        }
    }
}
