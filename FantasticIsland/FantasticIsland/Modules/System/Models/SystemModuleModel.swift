import AppKit
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import SwiftUI

struct SystemAudioSnapshot: Equatable {
    var level: Float?
    var isMuted: Bool

    static let unavailable = SystemAudioSnapshot(level: nil, isMuted: false)

    var title: String {
        guard let level else { return "--" }
        return "\(Int((level * 100).rounded()))%"
    }

    var subtitle: String {
        isMuted ? "Muted" : "Output"
    }

    var symbolName: String {
        if isMuted { return "speaker.slash.fill" }
        guard let level else { return "speaker.wave.2.fill" }
        switch level {
        case ..<0.01:
            return "speaker.fill"
        case ..<0.45:
            return "speaker.wave.1.fill"
        default:
            return "speaker.wave.2.fill"
        }
    }
}

struct SystemBrightnessSnapshot: Equatable {
    var level: Float?
    var updatedAt: Date?

    static let unavailable = SystemBrightnessSnapshot(level: nil, updatedAt: nil)

    var title: String {
        guard let level else { return "--" }
        return "\(Int((level * 100).rounded()))%"
    }

    var subtitle: String {
        if updatedAt == nil {
            return "Adjust to sync"
        }
        return "Display"
    }
}

@MainActor
final class SystemModuleModel: NSObject, ObservableObject, IslandModule {
    static let moduleID = "system"

    let id = SystemModuleModel.moduleID
    let title = "System"
    let symbolName = "switch.2"
    let horizonModule: HorizonModuleModel

    @Published private(set) var audioSnapshot = SystemAudioSnapshot.unavailable
    @Published private(set) var brightnessSnapshot = SystemBrightnessSnapshot.unavailable

    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(horizonModule: HorizonModuleModel) {
        self.horizonModule = horizonModule
        super.init()

        horizonModule.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(brightnessChanged(_:)),
            name: Notification.Name("com.apple.BrightnessChanged"),
            object: nil
        )

        refresh()
        startRefreshTimer()
    }

    deinit {
        timer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    var collapsedSummaryItems: [CollapsedSummaryItem] {
        [
            CollapsedSummaryItem(
                id: "\(id).summary.battery",
                moduleID: id,
                title: "System",
                text: horizonModule.batterySnapshot.title,
                isEnabledByDefault: false
            ),
        ]
    }

    var taskActivityContribution: TaskActivityContribution { TaskActivityContribution() }
    var preferredOpenedContentHeight: CGFloat { 150 }
    var allowsInternalScrolling: Bool { false }

    func makeLiveContentView(presentation _: IslandModulePresentationContext) -> AnyView {
        AnyView(SystemModuleContentView(model: self))
    }

    func refresh() {
        audioSnapshot = Self.readAudioSnapshot()
        if let brightness = Self.readDisplayBrightness() {
            brightnessSnapshot = SystemBrightnessSnapshot(level: brightness, updatedAt: brightnessSnapshot.updatedAt ?? .now)
        }
    }

    func setVolume(_ level: CGFloat) {
        let clamped = Float(max(0, min(1, level)))
        guard Self.writeAudioVolume(clamped) else {
            refresh()
            return
        }

        audioSnapshot = SystemAudioSnapshot(level: clamped, isMuted: clamped <= 0.001)
    }

    func setBrightness(_ level: CGFloat) {
        let clamped = Float(max(0, min(1, level)))
        guard Self.writeDisplayBrightness(clamped) else {
            refresh()
            return
        }

        brightnessSnapshot = SystemBrightnessSnapshot(level: clamped, updatedAt: .now)
    }

    private func startRefreshTimer() {
        let timer = Timer(timeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func brightnessChanged(_ notification: Notification) {
        guard let level = Self.brightnessLevel(from: notification.userInfo) else {
            return
        }

        brightnessSnapshot = SystemBrightnessSnapshot(level: level, updatedAt: .now)
    }

    private static func readAudioSnapshot() -> SystemAudioSnapshot {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown,
              let level = readValidatedScalar(deviceID: deviceID, element: kAudioObjectPropertyElementMain) else {
            return .unavailable
        }

        return SystemAudioSnapshot(level: level, isMuted: isMuted(deviceID: deviceID))
    }

    private static func systemOutputDeviceID() -> AudioObjectID {
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

    private static func readValidatedScalar(deviceID: AudioObjectID, element: UInt32) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
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

    private static func isMuted(deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
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

    private static func writeAudioVolume(_ level: Float) -> Bool {
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

    private static func readDisplayBrightness() -> Float? {
        let frameworkPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(frameworkPath, RTLD_LAZY) else {
            return nil
        }
        defer { dlclose(handle) }

        typealias DisplayServicesGetBrightnessFunction =
            @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

        guard let symbol = dlsym(handle, "DisplayServicesGetBrightness") else {
            return nil
        }

        let function = unsafeBitCast(symbol, to: DisplayServicesGetBrightnessFunction.self)
        var brightness = Float(0)
        let result = function(CGMainDisplayID(), &brightness)
        guard result == 0 else {
            return nil
        }

        return max(0, min(1, brightness))
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

private struct SystemModuleContentView: View {
    @ObservedObject var model: SystemModuleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
            metrics
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "switch.2")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            Text("System")
                .font(IslandVisualLanguage.islandLabel(12))
                .foregroundStyle(.white.opacity(0.62))
            Spacer(minLength: 0)
            Text(ProcessInfo.processInfo.isLowPowerModeEnabled ? "LOW POWER" : "NORMAL")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(ProcessInfo.processInfo.isLowPowerModeEnabled ? .yellow.opacity(0.82) : .white.opacity(0.38))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            SystemMetricCell(
                symbolName: model.horizonModule.batterySnapshot.symbolName,
                title: model.horizonModule.batterySnapshot.title,
                subtitle: model.horizonModule.batterySnapshot.subtitle,
                fill: CGFloat((model.horizonModule.batterySnapshot.percentage ?? 0)) / 100,
                onChange: nil
            )

            divider

            SystemMetricCell(
                symbolName: model.audioSnapshot.symbolName,
                title: model.audioSnapshot.title,
                subtitle: model.audioSnapshot.subtitle,
                fill: CGFloat(model.audioSnapshot.level ?? 0),
                onChange: model.setVolume
            )

            divider

            SystemMetricCell(
                symbolName: "sun.max.fill",
                title: model.brightnessSnapshot.title,
                subtitle: model.brightnessSnapshot.subtitle,
                fill: CGFloat(model.brightnessSnapshot.level ?? 0),
                onChange: model.setBrightness
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(width: 1)
            .padding(.vertical, 2)
    }
}

private struct SystemMetricCell: View {
    let symbolName: String
    let title: String
    let subtitle: String
    let fill: CGFloat
    let onChange: ((CGFloat) -> Void)?
    @State private var isDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
            }

            levelControl

            Text(subtitle)
                .font(IslandVisualLanguage.islandBody(10))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 9)
        .help(onChange == nil ? subtitle : "Drag to adjust \(subtitle.lowercased())")
    }

    private var levelControl: some View {
        GeometryReader { proxy in
            let clampedFill = max(0, min(1, fill))
            let fillWidth = proxy.size.width * clampedFill
            let isEditable = onChange != nil

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(isEditable ? 0.11 : 0.07))
                    .frame(height: 5)

                Capsule()
                    .fill(IslandVisualLanguage.accent.opacity(isEditable ? 0.74 : 0.38))
                    .frame(width: fillWidth, height: 5)

                Circle()
                    .fill(Color.white.opacity(isEditable ? 0.92 : 0.34))
                    .frame(width: isDragging ? 9 : 7, height: isDragging ? 9 : 7)
                    .shadow(color: .black.opacity(isEditable ? 0.24 : 0), radius: 2, y: 1)
                    .offset(x: max(0, min(proxy.size.width - 7, fillWidth - 3.5)))
                    .opacity(isEditable || clampedFill > 0 ? 1 : 0)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let onChange else { return }
                        isDragging = true
                        onChange(progress(for: value.location.x, width: proxy.size.width))
                    }
                    .onEnded { value in
                        guard let onChange else { return }
                        onChange(progress(for: value.location.x, width: proxy.size.width))
                        isDragging = false
                    }
            )
            .animation(.easeOut(duration: 0.12), value: isDragging)
        }
        .frame(height: 18)
    }

    private func progress(for locationX: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return max(0, min(1, locationX / width))
    }
}
