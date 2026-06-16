import CoreGraphics

@MainActor
enum PlayerExpandedMetrics {
    static let defaultOuterSpacing: CGFloat = 9
    static let defaultPrimaryColumnSpacing: CGFloat = 10
    static let defaultTitleBlockSpacing: CGFloat = 5
    static let defaultControlsSpacing: CGFloat = 7
    static let defaultArtworkCornerRadius: CGFloat = 8
    static let defaultArtworkSize: CGFloat = 58
    static let defaultProgressSectionSpacing: CGFloat = 5
    static let defaultControlButtonOpacityDisabled: CGFloat = 0.42

    static var outerSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerExpanded.outerSpacing) }
    static var primaryColumnSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerExpanded.primaryColumnSpacing) }
    static var titleBlockSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerExpanded.titleBlockSpacing) }
    static var controlsSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerExpanded.controlsSpacing) }
    static var artworkCornerRadius: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerExpanded.artworkCornerRadius) }
    static var artworkSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerExpanded.artworkSize) }
    static var progressSectionSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerExpanded.progressSectionSpacing) }
    static var controlButtonOpacityDisabled: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerExpanded.controlButtonOpacityDisabled) }
}
