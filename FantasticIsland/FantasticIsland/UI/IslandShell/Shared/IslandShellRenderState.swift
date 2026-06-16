import AppKit
import SwiftUI

struct IslandShellClosedHeaderRenderState {
    let compactModules: [CompactModuleSummary]
}

struct IslandShellTabRenderState: Identifiable {
    let id: String
    let title: String
    let symbolName: String
    let iconAssetName: String?
    let isSelected: Bool
    let showsPendingBadge: Bool
    let action: () -> Void
}

struct IslandShellExpandedNavigationRenderState {
    let tabs: [IslandShellTabRenderState]
    let openSettings: () -> Void
}
