import CoreGraphics

@MainActor
enum PlayerExpandedMetrics {
    static let defaultOuterSpacing: CGFloat = 24
    static let defaultPrimaryColumnSpacing: CGFloat = 12
    static let defaultTitleBlockSpacing: CGFloat = 6
    static let defaultControlsSpacing: CGFloat = 18
    static let defaultArtworkCornerRadius: CGFloat = 18
    static let defaultArtworkSize: CGFloat = 90
    static let defaultProgressSectionSpacing: CGFloat = 8
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
