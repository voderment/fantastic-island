import Foundation

enum PlayerModuleSettings {
    private static let defaultSourceKey = "player.module.defaultSource"
    private static let migratedNowPlayingDefaultKey = "player.module.defaultSource.migratedNowPlayingV2"

    static var storedDefaultSource: PlayerSourceKind? {
        PlayerSourceKind(rawValue: UserDefaults.standard.string(forKey: defaultSourceKey) ?? "")
    }

    static func resolvedDefaultSource(installedControllableSources: [PlayerSourceKind]) -> PlayerSourceKind? {
        if !UserDefaults.standard.bool(forKey: migratedNowPlayingDefaultKey),
           installedControllableSources.contains(.nowPlaying) {
            return .nowPlaying
        }

        if let storedDefaultSource, installedControllableSources.contains(storedDefaultSource) {
            return storedDefaultSource
        }

        if installedControllableSources.contains(.nowPlaying) {
            return .nowPlaying
        }

        return installedControllableSources.first
    }

    @discardableResult
    static func reconcileDefaultSource(installedControllableSources: [PlayerSourceKind]) -> PlayerSourceKind? {
        let resolvedSource = resolvedDefaultSource(installedControllableSources: installedControllableSources)
        persistDefaultSource(resolvedSource)
        return resolvedSource
    }

    @discardableResult
    static func setDefaultSource(
        _ sourceKind: PlayerSourceKind?,
        installedControllableSources: [PlayerSourceKind]
    ) -> PlayerSourceKind? {
        if let sourceKind, installedControllableSources.contains(sourceKind) {
            persistDefaultSource(sourceKind)
            return sourceKind
        }

        return reconcileDefaultSource(installedControllableSources: installedControllableSources)
    }

    private static func persistDefaultSource(_ sourceKind: PlayerSourceKind?) {
        UserDefaults.standard.set(true, forKey: migratedNowPlayingDefaultKey)

        if let sourceKind {
            UserDefaults.standard.set(sourceKind.rawValue, forKey: defaultSourceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultSourceKey)
        }
    }
}
