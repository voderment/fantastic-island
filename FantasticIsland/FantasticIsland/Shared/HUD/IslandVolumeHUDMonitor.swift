// Patterns adapted from TheBoredTeam/boring.notch VolumeManager (OSS)

import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation

enum IslandHUDOverlayKind: Equatable {
    case volume(level: Float, isMuted: Bool)
    case brightness(level: Float)
}

struct IslandHUDOverlayState: Equatable {
    let kind: IslandHUDOverlayKind
    let updatedAt: Date

    var isVisible: Bool {
        Date().timeIntervalSince(updatedAt) < 1.25
    }
}

@MainActor
final class IslandVolumeHUDMonitor: NSObject, ObservableObject {
    @Published private(set) var overlay: IslandHUDOverlayState?

    private var didInitialFetch = false

    override init() {
        super.init()
        setupAudioListener()
        setupBrightnessListener()
        fetchCurrentVolume(touchDate: false)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func refreshOverlayVisibility() {
        guard let overlay, !overlay.isVisible else {
            return
        }

        self.overlay = nil
    }

    func setOverlayLevel(_ level: Float) {
        let clamped = max(0, min(1, level))
        guard let overlay else {
            return
        }

        switch overlay.kind {
        case .volume:
            guard writeAudioVolume(clamped) else {
                fetchCurrentVolume(touchDate: true)
                return
            }
            publish(volume: clamped, muted: clamped <= 0.001, touchDate: true)
        case .brightness:
            guard Self.writeDisplayBrightness(clamped) else {
                return
            }
            publish(brightness: clamped)
        }
    }

    private func publish(volume: Float, muted: Bool, touchDate: Bool) {
        if touchDate || didInitialFetch {
            overlay = IslandHUDOverlayState(
                kind: .volume(level: volume, isMuted: muted),
                updatedAt: .now
            )
        }
        didInitialFetch = true
    }

    private func publish(brightness: Float) {
        overlay = IslandHUDOverlayState(
            kind: .brightness(level: brightness),
            updatedAt: .now
        )
    }

    private func setupAudioListener() {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else {
            return
        }

        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            nil
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.fetchCurrentVolume(touchDate: true)
            }
        }

        var masterAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &masterAddress) {
            AudioObjectAddPropertyListenerBlock(deviceID, &masterAddress, nil) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.fetchCurrentVolume(touchDate: true)
                }
            }
        }
    }

    private func setupBrightnessListener() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(brightnessChanged(_:)),
            name: Notification.Name("com.apple.BrightnessChanged"),
            object: nil
        )
    }

    @objc private func brightnessChanged(_ notification: Notification) {
        Task { @MainActor [weak self] in
            if let brightness = Self.brightnessLevel(from: notification.userInfo) {
                self?.publish(brightness: brightness)
            }
        }
    }

    private func fetchCurrentVolume(touchDate: Bool) {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown,
              let volume = readValidatedScalar(deviceID: deviceID, element: kAudioObjectPropertyElementMain) else {
            return
        }

        publish(volume: volume, muted: isMuted(deviceID: deviceID), touchDate: touchDate)
    }

    private func systemOutputDeviceID() -> AudioObjectID {
        var defaultDeviceID = kAudioObjectUnknown
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &defaultDeviceID
        )
        if status != noErr {
            return kAudioObjectUnknown
        }
        return defaultDeviceID
    }

    private func readValidatedScalar(deviceID: AudioObjectID, element: UInt32) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }

        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr else {
            return nil
        }

        return max(0, min(1, volume))
    }

    private func isMuted(deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else {
            return false
        }

        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted) == noErr else {
            return false
        }

        return muted != 0
    }

    private func writeAudioVolume(_ level: Float) -> Bool {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else {
            return false
        }

        var didWrite = false
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: UInt32(element)
            )
            guard AudioObjectHasProperty(deviceID, &address) else {
                continue
            }

            var mutableLevel = Float32(level)
            let size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &mutableLevel) == noErr {
                didWrite = true
            }
        }

        if didWrite, level > 0.001 {
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(deviceID, &muteAddress) {
                var muted: UInt32 = 0
                let size = UInt32(MemoryLayout<UInt32>.size)
                _ = AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil, size, &muted)
            }
        }

        return didWrite
    }

    private static func brightnessLevel(from userInfo: [AnyHashable: Any]?) -> Float? {
        guard let userInfo else {
            return nil
        }

        let value = userInfo["Brightness"]
            ?? userInfo["brightness"]
            ?? userInfo["level"]
        switch value {
        case let value as Float:
            return max(0, min(1, value))
        case let value as Double:
            return max(0, min(1, Float(value)))
        case let value as NSNumber:
            return max(0, min(1, value.floatValue))
        default:
            return nil
        }
    }

    private static func writeDisplayBrightness(_ level: Float) -> Bool {
        let frameworkPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(frameworkPath, RTLD_LAZY) else {
            return false
        }
        defer { dlclose(handle) }

        typealias DisplayServicesSetBrightnessFunction =
            @convention(c) (CGDirectDisplayID, Float) -> Int32

        guard let symbol = dlsym(handle, "DisplayServicesSetBrightness") else {
            return false
        }

        let function = unsafeBitCast(symbol, to: DisplayServicesSetBrightnessFunction.self)
        return function(CGMainDisplayID(), max(0, min(1, level))) == 0
    }
}
