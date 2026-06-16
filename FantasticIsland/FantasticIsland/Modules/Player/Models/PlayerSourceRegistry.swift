import AppKit
import Foundation

enum PlayerSourceKind: String, CaseIterable, Equatable, Hashable, Identifiable {
    case nowPlaying
    case music
    case podcasts
    case spotify

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        PlayerSourceRegistry.descriptor(for: self)?.displayName ?? rawValue.capitalized
    }

    nonisolated var bundleIdentifier: String {
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
    nonisolated private static let candidateApps: [PlayerAppDescriptor] = [
        PlayerAppDescriptor(
            id: PlayerSourceKind.nowPlaying.rawValue,
            displayName: "Now Playing",
            bundleIdentifier: "",
            supportsTransportControls: true,
            sourceKind: .nowPlaying
        ),
        PlayerAppDescriptor(
            id: PlayerSourceKind.music.rawValue,
            displayName: "Apple Music",
            bundleIdentifier: "com.apple.Music",
            supportsTransportControls: true,
            sourceKind: .music
        ),
        PlayerAppDescriptor(
            id: PlayerSourceKind.podcasts.rawValue,
            displayName: "Apple Podcasts",
            bundleIdentifier: "com.apple.podcasts",
            supportsTransportControls: true,
            sourceKind: .podcasts
        ),
        PlayerAppDescriptor(
            id: PlayerSourceKind.spotify.rawValue,
            displayName: "Spotify",
            bundleIdentifier: "com.spotify.client",
            supportsTransportControls: true,
            sourceKind: .spotify
        ),
        PlayerAppDescriptor(
            id: "netease_music",
            displayName: "NetEase Cloud Music",
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
        PlayerAppDescriptor(
            id: "youtube_music",
            displayName: "YouTube Music",
            bundleIdentifier: "com.google.Chrome.app.kbnhkkgcjpjdkpdekfomdphmmdfmdhkc",
            supportsTransportControls: false,
            sourceKind: nil
        ),
        PlayerAppDescriptor(
            id: "safari",
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            supportsTransportControls: false,
            sourceKind: nil
        ),
        PlayerAppDescriptor(
            id: "chrome",
            displayName: "Chrome",
            bundleIdentifier: "com.google.Chrome",
            supportsTransportControls: false,
            sourceKind: nil
        ),
        PlayerAppDescriptor(
            id: "arc",
            displayName: "Arc",
            bundleIdentifier: "company.thebrowser.Browser",
            supportsTransportControls: false,
            sourceKind: nil
        ),
    ]

    nonisolated static func descriptor(for sourceKind: PlayerSourceKind) -> PlayerAppDescriptor? {
        candidateApps.first { $0.sourceKind == sourceKind }
    }

    static func installedDescriptors() -> [PlayerAppDescriptor] {
        candidateApps.filter { isInstalled(bundleIdentifier: $0.bundleIdentifier) }
    }

    static func installedControllableSources() -> [PlayerSourceKind] {
        let installed = installedDescriptors().compactMap(\.sourceKind)
        return [.nowPlaying] + installed.filter { $0 != .nowPlaying }
    }

    static func installedApplePlaybackSources() -> [PlayerSourceKind] {
        installedControllableSources()
    }

    static func runningControllableSources() -> [PlayerSourceKind] {
        candidateApps.compactMap { descriptor in
            guard let sourceKind = descriptor.sourceKind,
                  !NSRunningApplication.runningApplications(withBundleIdentifier: descriptor.bundleIdentifier).isEmpty else {
                return nil
            }

            return sourceKind
        }
    }

    static func isInstalled(_ sourceKind: PlayerSourceKind) -> Bool {
        isInstalled(bundleIdentifier: sourceKind.bundleIdentifier)
    }

    static func isInstalled(bundleIdentifier: String) -> Bool {
        guard !bundleIdentifier.isEmpty else {
            return true
        }

        return applicationURL(for: bundleIdentifier) != nil
            || !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    static func appIcon(for sourceKind: PlayerSourceKind) -> NSImage? {
        guard !sourceKind.bundleIdentifier.isEmpty else {
            return nil
        }

        return appIcon(bundleIdentifier: sourceKind.bundleIdentifier)
    }

    static func appIcon(bundleIdentifier: String) -> NSImage? {
        guard let applicationURL = applicationURL(for: bundleIdentifier) else {
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
