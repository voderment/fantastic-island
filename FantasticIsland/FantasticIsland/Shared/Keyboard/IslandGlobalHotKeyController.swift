import Carbon
import Foundation

enum IslandExpandShortcut {
    static let keyCode: UInt32 = UInt32(kVK_ANSI_E)
    static let carbonModifiers: UInt32 = UInt32(optionKey)
    static let displayText = "Option + E"
}

enum IslandAgentsShortcut {
    static let keyCode: UInt32 = UInt32(kVK_ANSI_J)
    static let carbonModifiers: UInt32 = UInt32(optionKey)
    static let displayText = "Option + J"
}

enum IslandPreviousModuleShortcut {
    static let keyCode: UInt32 = UInt32(kVK_LeftArrow)
    static let carbonModifiers: UInt32 = UInt32(optionKey)
    static let displayText = "Option + Left"
}

enum IslandNextModuleShortcut {
    static let keyCode: UInt32 = UInt32(kVK_RightArrow)
    static let carbonModifiers: UInt32 = UInt32(optionKey)
    static let displayText = "Option + Right"
}

enum IslandDetachedModeShortcut {
    static let keyCode: UInt32 = UInt32(kVK_ANSI_D)
    static let carbonModifiers: UInt32 = UInt32(optionKey)
    static let displayText = "Option + D"
}

enum IslandHotKeyAction {
    case toggleExpansion
    case openAgents
    case previousModule
    case nextModule
    case toggleDetachedMode
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
            keyCode: IslandAgentsShortcut.keyCode,
            modifiers: IslandAgentsShortcut.carbonModifiers
        )
        registerHotKey(
            id: 3,
            keyCode: IslandPreviousModuleShortcut.keyCode,
            modifiers: IslandPreviousModuleShortcut.carbonModifiers
        )
        registerHotKey(
            id: 4,
            keyCode: IslandNextModuleShortcut.keyCode,
            modifiers: IslandNextModuleShortcut.carbonModifiers
        )
        registerHotKey(
            id: 5,
            keyCode: IslandDetachedModeShortcut.keyCode,
            modifiers: IslandDetachedModeShortcut.carbonModifiers
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
            action(.openAgents)
            return noErr
        case 3:
            action(.previousModule)
            return noErr
        case 4:
            action(.nextModule)
            return noErr
        case 5:
            action(.toggleDetachedMode)
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
