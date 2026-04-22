import CoreGraphics

@MainActor
enum CodexExpandedMetrics {
    static let defaultContentSpacing: CGFloat = 10
    static let defaultSectionRowSpacing: CGFloat = 6
    static let defaultGlobalInfoBadgeSpacing: CGFloat = 8
    static let defaultEmptyStateMinimumHeight: CGFloat = 72
    static let defaultCardCornerRadius: CGFloat = 18
    static let defaultCardBackgroundOpacity: CGFloat = 0.045
    static let defaultCardBorderOpacity: CGFloat = 0.08
    static let defaultTitleFontSize: CGFloat = 15
    static let defaultSummaryFontSize: CGFloat = 13

    static var contentSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexExpanded.contentSpacing) }
    static var sectionRowSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexExpanded.sectionRowSpacing) }
    static var globalInfoBadgeSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexExpanded.globalInfoBadgeSpacing) }
    static var emptyStateMinimumHeight: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexExpanded.emptyStateMinimumHeight) }
    static var cardCornerRadius: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexExpanded.cardCornerRadius) }
    static var cardBackgroundOpacity: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexExpanded.cardBackgroundOpacity) }
    static var cardBorderOpacity: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexExpanded.cardBorderOpacity) }
    static var titleFontSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexExpanded.titleFontSize) }
    static var summaryFontSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexExpanded.summaryFontSize) }
}
