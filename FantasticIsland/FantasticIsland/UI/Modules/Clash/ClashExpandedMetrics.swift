import CoreGraphics

@MainActor
enum ClashExpandedMetrics {
    static let defaultOuterSpacing: CGFloat = 12
    static let defaultCardSpacing: CGFloat = 6
    static let defaultSectionTitleSpacing: CGFloat = 8
    static let defaultCardCornerRadius: CGFloat = 18
    static let defaultCardBackgroundOpacity: CGFloat = 0.04
    static let defaultCardBorderOpacity: CGFloat = 0.08
    static let defaultActionPillCornerRadius: CGFloat = 10
    static let defaultActionPillVerticalPadding: CGFloat = 6

    static var outerSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.clashExpanded.outerSpacing) }
    static var cardSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.clashExpanded.cardSpacing) }
    static var sectionTitleSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.clashExpanded.sectionTitleSpacing) }
    static var cardCornerRadius: CGFloat { CGFloat(IslandDesignTokenRuntime.current.clashExpanded.cardCornerRadius) }
    static var cardBackgroundOpacity: CGFloat { CGFloat(IslandDesignTokenRuntime.current.clashExpanded.cardBackgroundOpacity) }
    static var cardBorderOpacity: CGFloat { CGFloat(IslandDesignTokenRuntime.current.clashExpanded.cardBorderOpacity) }
    static var actionPillCornerRadius: CGFloat { CGFloat(IslandDesignTokenRuntime.current.clashExpanded.actionPillCornerRadius) }
    static var actionPillVerticalPadding: CGFloat { CGFloat(IslandDesignTokenRuntime.current.clashExpanded.actionPillVerticalPadding) }
}
