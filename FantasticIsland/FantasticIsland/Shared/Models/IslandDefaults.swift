import Foundation

enum IslandDefaults {
    static let audioMutedKey = "island.audioMuted"
    static let collapsedSummaryVisibleIDsKey = "island.collapsedSummary.visibleIDs"
    static let launchAtLoginKey = "island.settings.launchAtLogin"
    static let interfaceLanguageKey = "island.settings.interfaceLanguage"
    static let windDriveLogoPresetKey = "island.settings.windDrive.logoPreset"
    static let windDriveUsesCustomLogoKey = "island.settings.windDrive.usesCustomLogo"
    static let windDriveCustomLogoPathKey = "island.settings.windDrive.customLogoPath"
    static let windDriveShowsExpandedPanelKey = "island.settings.windDrive.showsExpandedPanel"
    static let enabledModuleIDsKey = "island.settings.enabledModuleIDs"

    private static let legacyAudioMutedKey = "audioMuted"

    static func migrateLegacyValues() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: audioMutedKey) == nil,
           defaults.object(forKey: legacyAudioMutedKey) != nil {
            defaults.set(defaults.bool(forKey: legacyAudioMutedKey), forKey: audioMutedKey)
        }
    }
}

enum IslandInterfaceLanguage: String, CaseIterable, Identifiable {
    case followSystem
    case english
    case simplifiedChinese
    case traditionalChinese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followSystem:
            return "Follow System"
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .followSystem:
            return nil
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .traditionalChinese:
            return "zh-Hant"
        }
    }
}

enum WindDriveLogoPreset: String, CaseIterable, Identifiable {
    case defaultMark
    case appleTV
    case appleTerminal
    case terminal
    case network
    case shield
    case treadmill
    case barre
    case outdoorCycle
    case openWaterSwim
    case tortoise
    case ladybug

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultMark:
            return "Apple"
        case .appleTV:
            return "Apple TV"
        case .appleTerminal:
            return "Apple Terminal"
        case .terminal:
            return "Intelligence"
        case .network:
            return "Gamepad"
        case .shield:
            return "Sparkles"
        case .treadmill:
            return "Treadmill"
        case .barre:
            return "Barre"
        case .outdoorCycle:
            return "Outdoor Cycle"
        case .openWaterSwim:
            return "Open Water Swim"
        case .tortoise:
            return "Tortoise"
        case .ladybug:
            return "Ladybug"
        }
    }

    var symbolName: String? {
        switch self {
        case .defaultMark:
            return "apple.logo"
        case .appleTV:
            return "appletv.fill"
        case .appleTerminal:
            return "apple.terminal.fill"
        case .terminal:
            return "apple.intelligence"
        case .network:
            return "gamecontroller.fill"
        case .shield:
            return "hands.and.sparkles.fill"
        case .treadmill:
            return "figure.walk.treadmill"
        case .barre:
            return "figure.barre"
        case .outdoorCycle:
            return "figure.outdoor.cycle"
        case .openWaterSwim:
            return "figure.open.water.swim"
        case .tortoise:
            return "tortoise.fill"
        case .ladybug:
            return "ladybug.fill"
        }
    }
}
