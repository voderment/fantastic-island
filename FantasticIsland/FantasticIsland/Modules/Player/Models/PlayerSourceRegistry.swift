import AppKit
import Foundation

enum PlayerSourceKind: String, CaseIterable, Equatable, Hashable, Identifiable {
    case music
    case spotify

    var id: String { rawValue }

    var displayName: String {
        PlayerSourceRegistry.descriptor(for: self)?.displayName ?? rawValue.capitalized
    }

    var bundleIdentifier: String {
        PlayerSourceRegistry.descriptor(for: self)?.bundleIdentifier ?? ""
    }
}

struct PlayerAppDescriptor: Identifiable, Equatable {
    let id: String
    let displayName: String
    let bundleIdentifier: String
    let supportsTransportControls: Bool
    let sourceKind: PlayerSourceKind?
}

enum PlayerSourceRegistry {
    private static let candidateApps: [PlayerAppDescriptor] = [
        PlayerAppDescriptor(
            id: PlayerSourceKind.music.rawValue,
            displayName: "Apple Music",
            bundleIdentifier: "com.apple.Music",
            supportsTransportControls: true,
            sourceKind: .music
        ),
        PlayerAppDescriptor(
            id: PlayerSourceKind.spotify.rawValue,
            displayName: "Spotify",
            bundleIdentifier: "com.spotify.client",
            supportsTransportControls: true,
            sourceKind: .spotify
        ),
        PlayerAppDescriptor(
            id: "podcasts",
            displayName: "Podcasts",
            bundleIdentifier: "com.apple.podcasts",
            supportsTransportControls: false,
            sourceKind: nil
        ),
        PlayerAppDescriptor(
            id: "netease_music",
            displayName: "网易云音乐",
            bundleIdentifier: "com.netease.163music",
            supportsTransportControls: false,
            sourceKind: nil
        ),
        PlayerAppDescriptor(
            id: "qq_music",
            displayName: "QQMusic",
            bundleIdentifier: "com.tencent.QQMusicMac",
            supportsTransportControls: false,
            sourceKind: nil
        ),
    ]

    static func descriptor(for sourceKind: PlayerSourceKind) -> PlayerAppDescriptor? {
        candidateApps.first { $0.sourceKind == sourceKind }
    }

    static func installedDescriptors() -> [PlayerAppDescriptor] {
        candidateApps.filter { isInstalled(bundleIdentifier: $0.bundleIdentifier) }
    }

    static func installedControllableSources() -> [PlayerSourceKind] {
        installedDescriptors().compactMap(\.sourceKind)
    }

    static func isInstalled(_ sourceKind: PlayerSourceKind) -> Bool {
        isInstalled(bundleIdentifier: sourceKind.bundleIdentifier)
    }

    static func isInstalled(bundleIdentifier: String) -> Bool {
        applicationURL(for: bundleIdentifier) != nil
            || !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    static func appIcon(for sourceKind: PlayerSourceKind) -> NSImage? {
        guard let applicationURL = applicationURL(for: sourceKind.bundleIdentifier) else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        icon.size = NSSize(width: 64, height: 64)
        return icon
    }

    private static func applicationURL(for bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}
