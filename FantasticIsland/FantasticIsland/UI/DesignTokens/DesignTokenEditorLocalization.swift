import Foundation

struct DesignTokenLocalizedText {
    let english: String

    init(_ english: String) {
        self.english = english
    }

    func resolve(for _: Locale) -> String {
        english
    }
}

enum DesignTokenEditorLocalization {
    enum ChromeText {
        case windowTitle
        case sidebarSection
        case writebackSection
        case sessionSection
        case debugSurfaceSection
        case panelLockTitle
        case mockScenarioTitle
        case triggerMockScenario
        case debugActiveState
        case savedConfigsSection
        case noSavedConfigs
        case revert
        case resetSingleToken
        case loadSavedConfig
        case saveConfig
        case writeBack
        case writeBackAll
        case openWorkspace
        case ready
        case dirty
        case selected
        case writebackCount
        case yes
        case no
        case none
        case unsavedChangesTitle
        case unsavedChangesMessage
        case discard
        case cancel
        case saveSucceededPrefix
        case saveFailedPrefix
        case writebackSucceededPrefix
        case writebackFailedPrefix
        case writebackAllSucceededPrefix
        case writebackAllFailedPrefix
        case revertedMessage
    }

    static func text(_ chromeText: ChromeText, locale: Locale) -> String {
        chromeText.localizedText.resolve(for: locale)
    }

    static func groupTitle(_ group: IslandDesignTokenGroup, locale _: Locale) -> String {
        group.rawValue
    }

    static func title(for descriptor: IslandDesignTokenDescriptor, locale _: Locale) -> String {
        descriptor.title
    }

    static func detail(for descriptor: IslandDesignTokenDescriptor, locale _: Locale) -> String {
        descriptor.detail
    }

    static func saveSucceededMessage(path: String, locale _: Locale) -> String {
        "Saved config to \(path)"
    }

    static func writebackSucceededMessage(fileCount: Int, locale _: Locale) -> String {
        "Wrote \(fileCount) file(s)."
    }

    static func writebackGroupCountMessage(groupCount: Int, locale _: Locale) -> String {
        "\(groupCount) group(s)"
    }

    static func singleTokenRevertedMessage(tokenName: String, locale _: Locale) -> String {
        "Reset \(tokenName) to the last saved value."
    }

    static func loadedSavedConfigMessage(configName: String, locale _: Locale) -> String {
        "Loaded \(configName)"
    }

#if DEBUG
    static func debugLockModeTitle(_ mode: IslandDebugPanelLockMode, locale _: Locale) -> String {
        switch mode {
        case .automatic:
            return "Auto"
        case .peek:
            return "Lock Peek"
        case .expanded:
            return "Lock Expanded"
        }
    }

    static func debugScenarioTitle(_ scenario: IslandDebugMockScenario, locale _: Locale) -> String {
        switch scenario {
        case .none:
            return "Live Data"
        case .codexApprovalPeek:
            return "Codex Approval Peek"
        case .codexCompletedPeek:
            return "Codex Completed Peek"
        case .playerTrackSwitchPeek:
            return "Player Track Peek"
        }
    }

    static func debugScenarioDetail(_ scenario: IslandDebugMockScenario, locale _: Locale) -> String {
        switch scenario {
        case .none:
            return "Use the current runtime activity stream without injecting a mock scene."
        case .codexApprovalPeek:
            return "Actionable Codex permission card for tuning interactive peek layout and hit targets."
        case .codexCompletedPeek:
            return "Transient Codex completion card for tuning notification-style peek spacing and text rhythm."
        case .playerTrackSwitchPeek:
            return "Player artwork-and-text peek for tuning media notification spacing and minimum height."
        }
    }

    static func debugLockModeChangedMessage(mode: IslandDebugPanelLockMode, locale: Locale) -> String {
        "Updated panel lock mode to \(debugLockModeTitle(mode, locale: locale))."
    }

    static func debugScenarioSelectedMessage(scenario: IslandDebugMockScenario, locale: Locale) -> String {
        "Selected mock scene: \(debugScenarioTitle(scenario, locale: locale))."
    }

    static func debugTriggerSucceededMessage(scenario: IslandDebugMockScenario, locale: Locale) -> String {
        "Triggered \(debugScenarioTitle(scenario, locale: locale))."
    }
#endif
}

private extension DesignTokenEditorLocalization.ChromeText {
    var localizedText: DesignTokenLocalizedText {
        switch self {
        case .windowTitle:
            return DesignTokenLocalizedText("Design Tokens")
        case .sidebarSection:
            return DesignTokenLocalizedText("DESIGN TOKENS")
        case .debugSurfaceSection:
            return DesignTokenLocalizedText("DEBUG SURFACE")
        case .panelLockTitle:
            return DesignTokenLocalizedText("PANEL LOCK")
        case .mockScenarioTitle:
            return DesignTokenLocalizedText("MOCK SCENE")
        case .triggerMockScenario:
            return DesignTokenLocalizedText("Trigger Mock")
        case .debugActiveState:
            return DesignTokenLocalizedText("Active Debug State")
        case .writebackSection:
            return DesignTokenLocalizedText("WRITE BACK")
        case .sessionSection:
            return DesignTokenLocalizedText("SESSION")
        case .savedConfigsSection:
            return DesignTokenLocalizedText("SAVED CONFIGS")
        case .noSavedConfigs:
            return DesignTokenLocalizedText("No saved configs yet.")
        case .revert:
            return DesignTokenLocalizedText("Revert")
        case .resetSingleToken:
            return DesignTokenLocalizedText("Reset")
        case .loadSavedConfig:
            return DesignTokenLocalizedText("Load")
        case .saveConfig:
            return DesignTokenLocalizedText("Save Config")
        case .writeBack:
            return DesignTokenLocalizedText("Write Back")
        case .writeBackAll:
            return DesignTokenLocalizedText("Write Back All")
        case .openWorkspace:
            return DesignTokenLocalizedText("Open Workspace")
        case .ready:
            return DesignTokenLocalizedText("Ready")
        case .dirty:
            return DesignTokenLocalizedText("Dirty")
        case .selected:
            return DesignTokenLocalizedText("Selected")
        case .writebackCount:
            return DesignTokenLocalizedText("Writeback")
        case .yes:
            return DesignTokenLocalizedText("YES")
        case .no:
            return DesignTokenLocalizedText("NO")
        case .none:
            return DesignTokenLocalizedText("None")
        case .unsavedChangesTitle:
            return DesignTokenLocalizedText("Unsaved token changes")
        case .unsavedChangesMessage:
            return DesignTokenLocalizedText("Save the current design token config before closing?")
        case .discard:
            return DesignTokenLocalizedText("Discard")
        case .cancel:
            return DesignTokenLocalizedText("Cancel")
        case .saveSucceededPrefix:
            return DesignTokenLocalizedText("Saved config to")
        case .saveFailedPrefix:
            return DesignTokenLocalizedText("Save failed")
        case .writebackSucceededPrefix:
            return DesignTokenLocalizedText("Wrote")
        case .writebackFailedPrefix:
            return DesignTokenLocalizedText("Write Back failed")
        case .writebackAllSucceededPrefix:
            return DesignTokenLocalizedText("Wrote")
        case .writebackAllFailedPrefix:
            return DesignTokenLocalizedText("Write Back All failed")
        case .revertedMessage:
            return DesignTokenLocalizedText("Reverted to last saved config.")
        }
    }
}
