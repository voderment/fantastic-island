import AppKit
import SwiftUI

enum IslandShellPreviewMocks {
    static let closedHeader = IslandShellClosedHeaderRenderState(
        compactModules: [
            CompactModuleSummary(
                moduleID: "codex",
                title: "Agents",
                symbolName: "sparkles",
                iconAssetName: nil,
                content: .agentGrid([
                    CompactAgentIndicator(id: "preview-codex", provider: .codex, state: .running),
                    CompactAgentIndicator(id: "preview-claude", provider: .claudeCode, state: .waiting),
                ], overflow: 1)
            ),
            CompactModuleSummary(
                moduleID: "horizon",
                title: "Horizon",
                symbolName: "sun.max",
                iconAssetName: nil,
                content: .singleLine("82%")
            ),
        ]
    )

    static let expandedTabs = IslandShellExpandedNavigationRenderState(
        tabs: [
            IslandShellTabRenderState(id: "codex", title: "Agents", symbolName: "sparkles", iconAssetName: nil, isSelected: true, showsPendingBadge: true, action: {}),
            IslandShellTabRenderState(id: "player", title: "Player", symbolName: "play.square.fill", iconAssetName: nil, isSelected: false, showsPendingBadge: false, action: {}),
            IslandShellTabRenderState(id: "horizon", title: "Horizon", symbolName: "sun.max", iconAssetName: nil, isSelected: false, showsPendingBadge: false, action: {}),
        ],
        openSettings: {}
    )

    static let playerOnlyTabs = IslandShellExpandedNavigationRenderState(
        tabs: [
            IslandShellTabRenderState(id: "player", title: "Player", symbolName: "play.square.fill", iconAssetName: nil, isSelected: true, showsPendingBadge: false, action: {}),
        ],
        openSettings: {}
    )
}
