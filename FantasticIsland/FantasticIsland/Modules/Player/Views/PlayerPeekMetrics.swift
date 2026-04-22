import CoreGraphics

@MainActor
enum PlayerPeekMetrics {
    static let defaultHorizontalSpacing: CGFloat = 14
    static let defaultTextSpacing: CGFloat = 6
    static let defaultTitleFontSize: CGFloat = 17
    static let defaultArtistFontSize: CGFloat = 13

    static let defaultContentHorizontalPadding: CGFloat = 2
    static let defaultContentVerticalPadding: CGFloat = 4
    static let defaultMinimumHeight: CGFloat = 64

    static let defaultArtworkCornerRadius: CGFloat = 12
    static let defaultArtworkSize: CGFloat = 52
    static let defaultPlaceholderSymbolSize: CGFloat = 20

    static let defaultTitleOpacity: CGFloat = 0.96
    static let defaultArtistOpacity: CGFloat = 0.62
    static let defaultPlaceholderOpacity: CGFloat = 0.28
    static let defaultArtworkBackgroundStartOpacity: CGFloat = 0.08
    static let defaultArtworkBackgroundEndOpacity: CGFloat = 0.03

    static var horizontalSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerPeek.horizontalSpacing) }
    static var textSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerPeek.textSpacing) }
    static var titleFontSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerPeek.titleFontSize) }
    static var artistFontSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerPeek.artistFontSize) }

    static var contentHorizontalPadding: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerPeek.contentHorizontalPadding) }
    static var contentVerticalPadding: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerPeek.contentVerticalPadding) }
    static var minimumHeight: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerPeek.minimumHeight) }

    static var artworkCornerRadius: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerPeek.artworkCornerRadius) }
    static var artworkSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerPeek.artworkSize) }
    static var placeholderSymbolSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerPeek.placeholderSymbolSize) }

    static var titleOpacity: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerPeek.titleOpacity) }
    static var artistOpacity: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerPeek.artistOpacity) }
    static var placeholderOpacity: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerPeek.placeholderOpacity) }
    static var artworkBackgroundStartOpacity: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerPeek.artworkBackgroundStartOpacity) }
    static var artworkBackgroundEndOpacity: CGFloat { CGFloat(IslandDesignTokenRuntime.current.playerPeek.artworkBackgroundEndOpacity) }
}
