import CoreGraphics
import SwiftUI

@MainActor
enum CodexPeekMetrics {
    static let defaultRowSpacing: CGFloat = 12
    static let defaultContentSpacing: CGFloat = 8
    static let defaultBadgeSpacing: CGFloat = 6
    static let defaultTitleTrailingSpacerMinLength: CGFloat = 8 // 标题和 badge 组之间的最小缓冲

    static let defaultCardHorizontalPadding: CGFloat = 16
    static let defaultCardVerticalPadding: CGFloat = 14

    static let defaultStatusDotSize: CGFloat = 9
    static let defaultStatusDotTopPadding: CGFloat = 4
    static let defaultStatusDotColor = Color(red: 0.29, green: 0.86, blue: 0.46, opacity: 1)

    static let defaultTitleFontSize: CGFloat = 14
    static let defaultPromptFontSize: CGFloat = 11.5
    static let defaultSummaryFontSize: CGFloat = 12.5

    static let defaultPromptOpacity: CGFloat = 0.4
    static let defaultSummaryOpacity: CGFloat = 0.82
    static let defaultBackgroundOpacity: CGFloat = 0.095

    static var rowSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexPeek.rowSpacing) }
    static var contentSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexPeek.contentSpacing) }
    static var badgeSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexPeek.badgeSpacing) }
    static var titleTrailingSpacerMinLength: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexPeek.titleTrailingSpacerMinLength) }

    static var cardHorizontalPadding: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexPeek.cardHorizontalPadding) }
    static var cardVerticalPadding: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexPeek.cardVerticalPadding) }

    static var statusDotSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexPeek.statusDotSize) }
    static var statusDotTopPadding: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexPeek.statusDotTopPadding) }
    static var statusDotColor: Color { IslandDesignTokenRuntime.current.codexPeek.statusDotColor.swiftUIColor }

    static var titleFontSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexPeek.titleFontSize) }
    static var promptFontSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexPeek.promptFontSize) }
    static var summaryFontSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexPeek.summaryFontSize) }

    static var promptOpacity: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexPeek.promptOpacity) }
    static var summaryOpacity: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexPeek.summaryOpacity) }
    static var backgroundOpacity: CGFloat { CGFloat(IslandDesignTokenRuntime.current.codexPeek.backgroundOpacity) }
}
