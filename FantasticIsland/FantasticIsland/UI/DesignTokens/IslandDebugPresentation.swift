#if DEBUG
import Foundation

enum IslandDebugPanelLockMode: String, CaseIterable, Identifiable {
    case automatic
    case peek
    case expanded

    var id: String { rawValue }
}

enum IslandDebugMockScenario: String, CaseIterable, Identifiable {
    case none
    case codexApprovalPeek
    case codexCompletedPeek
    case playerTrackSwitchPeek

    var id: String { rawValue }

    var activity: IslandActivity? {
        let now = Date()

        switch self {
        case .none:
            return nil
        case .codexApprovalPeek:
            return IslandActivity(
                id: "debug.codex.peek.approval",
                moduleID: CodexModuleModel.moduleID,
                sourceID: "debug.codex.session.approval",
                kind: .actionRequired,
                priority: 999,
                createdAt: now,
                updatedAt: now,
                presentationPolicy: .manualOnly
            )
        case .codexCompletedPeek:
            return IslandActivity(
                id: "debug.codex.peek.completed",
                moduleID: CodexModuleModel.moduleID,
                sourceID: "debug.codex.session.completed",
                kind: .transientNotification,
                priority: 998,
                createdAt: now,
                updatedAt: now,
                presentationPolicy: .manualOnly
            )
        case .playerTrackSwitchPeek:
            return IslandActivity(
                id: "debug.player.peek.trackswitch",
                moduleID: PlayerModuleModel.moduleID,
                sourceID: "debug.player.trackswitch",
                kind: .transientNotification,
                priority: 997,
                createdAt: now,
                updatedAt: now,
                presentationPolicy: .manualOnly
            )
        }
    }
}
#endif
