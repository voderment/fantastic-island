import Foundation

enum IslandDefaults {
    static let audioMutedKey = "island.audioMuted"
    static let collapsedSummaryVisibleIDsKey = "island.collapsedSummary.visibleIDs"
    static let launchAtLoginKey = "island.settings.launchAtLogin"
    static let interfaceLanguageKey = "island.settings.interfaceLanguage"
    static let enabledModuleIDsKey = "island.settings.enabledModuleIDs"
    static let hideInFullscreenKey = "island.settings.hideInFullscreen"
    static let detachedModeKey = "island.settings.detachedMode"
    static let horizonUtilityModulesMigrationKey = "island.migrations.horizonUtilityModules.20260616"
    static let systemModuleMigrationKey = "island.migrations.systemModule.20260616"
    static let systemCollapsedSummaryMigrationKey = "island.migrations.systemCollapsedSummary.20260616"

    private static let legacyAudioMutedKey = "audioMuted"
    private static let silentAgentIslandMigrationKey = "island.migrations.silentAgentIsland.20260615"

    static func migrateLegacyValues() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: audioMutedKey) == nil,
           defaults.object(forKey: legacyAudioMutedKey) != nil {
            defaults.set(defaults.bool(forKey: legacyAudioMutedKey), forKey: audioMutedKey)
        }

        if defaults.object(forKey: silentAgentIslandMigrationKey) == nil {
            defaults.set(true, forKey: audioMutedKey)
            defaults.set(true, forKey: silentAgentIslandMigrationKey)
        }
    }
}

enum IslandInterfaceLanguage: String, CaseIterable, Identifiable {
    case followSystem
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followSystem:
            return "Follow System"
        case .english:
            return "English"
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .followSystem:
            return nil
        case .english:
            return "en"
        }
    }
}
