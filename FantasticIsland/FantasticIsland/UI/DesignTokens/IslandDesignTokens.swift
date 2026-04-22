import AppKit
import CoreGraphics
import SwiftUI

struct IslandColorToken: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double = 1

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }

    var nsColor: NSColor {
        NSColor(
            calibratedRed: red,
            green: green,
            blue: blue,
            alpha: opacity
        )
    }
}

struct IslandDesignTokens: Codable, Equatable {
    // These member defaults are Codable/model fallbacks only.
    // The app's runtime startup baseline must come from `sourceDefaults()`,
    // which reads the current writeback-owned source constants.
    struct ShellTokens: Codable, Equatable {
        var openedShadowHorizontalInset: Double = 18
        var openedShadowBottomInset: Double = 0
        var openedSurfaceBottomInset: Double = 0
        var openedSurfaceContentHorizontalInset: Double = 22
        var closedHoverScale: Double = 1.028
        var closedHorizontalPadding: Double = 14
        var closedFanModuleSpacing: Double = 16
        var closedModuleSpacing: Double = 26
        var closedModuleContentSpacing: Double = 10
        var closedIconSize: Double = 18
        var closedPrimaryFontSize: Double = 10
        var closedTrafficFontSize: Double = 8.5
        var closedTrafficLineSpacing: Double = 1
        var openedBodyRevealDelay: Double = 0.12
        var openLayoutSettleDuration: Double = 0.46
        var closeLayoutSettleDuration: Double = 0.30
        var expandedContentBottomPadding: Double = 16
        var expandedContentTopPadding: Double = 24
        var moduleColumnSpacing: Double = 20
        var moduleNavigationRowHeight: Double = 38
        var moduleTabSpacing: Double = 10
        var moduleTabHorizontalPadding: Double = 16
        var moduleTabVerticalPadding: Double = 9
        var moduleHeaderToolbarSpacing: Double = 16
        var moduleToolbarButtonGroupSpacing: Double = 12
    }

    struct PeekTokens: Codable, Equatable {
        var contentHorizontalInset: Double = 16
        var contentTopPadding: Double = 12
        var contentBottomPadding: Double = 12
        var minimumContentWidth: Double = 420
        var maximumContentWidth: Double = 560
        var contentWidthFactor: Double = 0.32
        var openAnimationDuration: Double = 0.34
        var closeAnimationDuration: Double = 0.28
        var chromeRevealAnimationDuration: Double = 0.12
        var bodyCloseFadeDuration: Double = 0.20
        var closedHeaderRevealDuration: Double = 0.10
        var closedHeaderRevealLeadTime: Double = 0.10
    }

    struct WindDriveTokens: Codable, Equatable {
        var panelSide: Double = 220
        var heroCornerRadius: Double = 32
        var heroShadowOpacity: Double = 0.28
        var heroShadowRadius: Double = 24
        var heroShadowYOffset: Double = 14
        var basePlateOpacity: Double = 0.2
        var hubDiameter: Double = 46
        var logoSize: Double = 28
    }

    struct CodexPeekTokens: Codable, Equatable {
        var rowSpacing: Double = 12
        var contentSpacing: Double = 8
        var badgeSpacing: Double = 6
        var titleTrailingSpacerMinLength: Double = 8
        var cardHorizontalPadding: Double = 16
        var cardVerticalPadding: Double = 14
        var statusDotSize: Double = 9
        var statusDotTopPadding: Double = 4
        var statusDotColor = IslandColorToken(red: 0.29, green: 0.86, blue: 0.46)
        var titleFontSize: Double = 14
        var promptFontSize: Double = 11.5
        var summaryFontSize: Double = 12.5
        var promptOpacity: Double = 0.6
        var summaryOpacity: Double = 0.82
        var backgroundOpacity: Double = 0.045
    }

    struct PlayerPeekTokens: Codable, Equatable {
        var horizontalSpacing: Double = 14
        var textSpacing: Double = 6
        var titleFontSize: Double = 17
        var artistFontSize: Double = 13
        var contentHorizontalPadding: Double = 2
        var contentVerticalPadding: Double = 4
        var minimumHeight: Double = 64
        var artworkCornerRadius: Double = 16
        var artworkSize: Double = 52
        var placeholderSymbolSize: Double = 20
        var titleOpacity: Double = 0.96
        var artistOpacity: Double = 0.62
        var placeholderOpacity: Double = 0.28
        var artworkBackgroundStartOpacity: Double = 0.08
        var artworkBackgroundEndOpacity: Double = 0.03
    }

    struct CodexExpandedTokens: Codable, Equatable {
        var contentSpacing: Double = 12
        var sectionRowSpacing: Double = 6
        var globalInfoBadgeSpacing: Double = 8
        var emptyStateMinimumHeight: Double = 72
        var cardCornerRadius: Double = 18
        var cardBackgroundOpacity: Double = 0.045
        var cardBorderOpacity: Double = 0.08
        var titleFontSize: Double = 15
        var summaryFontSize: Double = 13
    }

    struct ClashExpandedTokens: Codable, Equatable {
        var outerSpacing: Double = 12
        var cardSpacing: Double = 6
        var sectionTitleSpacing: Double = 8
        var cardCornerRadius: Double = 18
        var cardBackgroundOpacity: Double = 0.04
        var cardBorderOpacity: Double = 0.08
        var actionPillCornerRadius: Double = 10
        var actionPillVerticalPadding: Double = 6
    }

    struct PlayerExpandedTokens: Codable, Equatable {
        var outerSpacing: Double = 18
        var primaryColumnSpacing: Double = 24
        var titleBlockSpacing: Double = 6
        var controlsSpacing: Double = 18
        var artworkCornerRadius: Double = 18
        var artworkSize: Double = 112
        var progressSectionSpacing: Double = 8
        var controlButtonOpacityDisabled: Double = 0.42
    }

    var shell = ShellTokens()
    var peek = PeekTokens()
    var windDrive = WindDriveTokens()
    var codexPeek = CodexPeekTokens()
    var playerPeek = PlayerPeekTokens()
    var codexExpanded = CodexExpandedTokens()
    var clashExpanded = ClashExpandedTokens()
    var playerExpanded = PlayerExpandedTokens()

    @MainActor
    static func sourceDefaults() -> IslandDesignTokens {
        IslandDesignTokens(
            shell: ShellTokens(
                openedShadowHorizontalInset: Double(CodexIslandChromeMetrics.defaultOpenedShadowHorizontalInset),
                openedShadowBottomInset: Double(CodexIslandChromeMetrics.defaultOpenedShadowBottomInset),
                openedSurfaceBottomInset: Double(CodexIslandChromeMetrics.defaultOpenedSurfaceBottomInset),
                openedSurfaceContentHorizontalInset: Double(CodexIslandChromeMetrics.defaultOpenedSurfaceContentHorizontalInset),
                closedHoverScale: Double(CodexIslandChromeMetrics.defaultClosedHoverScale),
                closedHorizontalPadding: Double(CodexIslandChromeMetrics.defaultClosedHorizontalPadding),
                closedFanModuleSpacing: Double(CodexIslandChromeMetrics.defaultClosedFanModuleSpacing),
                closedModuleSpacing: Double(CodexIslandChromeMetrics.defaultClosedModuleSpacing),
                closedModuleContentSpacing: Double(CodexIslandChromeMetrics.defaultClosedModuleContentSpacing),
                closedIconSize: Double(CodexIslandChromeMetrics.defaultClosedIconSize),
                closedPrimaryFontSize: Double(CodexIslandChromeMetrics.defaultClosedPrimaryFontSize),
                closedTrafficFontSize: Double(CodexIslandChromeMetrics.defaultClosedTrafficFontSize),
                closedTrafficLineSpacing: Double(CodexIslandChromeMetrics.defaultClosedTrafficLineSpacing),
                openedBodyRevealDelay: Double(CodexIslandChromeMetrics.defaultOpenedBodyRevealDelay),
                openLayoutSettleDuration: Double(CodexIslandChromeMetrics.defaultOpenLayoutSettleDuration),
                closeLayoutSettleDuration: Double(CodexIslandChromeMetrics.defaultCloseLayoutSettleDuration),
                expandedContentBottomPadding: Double(CodexIslandChromeMetrics.defaultExpandedContentBottomPadding),
                expandedContentTopPadding: Double(CodexIslandChromeMetrics.defaultExpandedContentTopPadding),
                moduleColumnSpacing: Double(CodexIslandChromeMetrics.defaultModuleColumnSpacing),
                moduleNavigationRowHeight: Double(CodexIslandChromeMetrics.defaultModuleNavigationRowHeight),
                moduleTabSpacing: Double(CodexIslandChromeMetrics.defaultModuleTabSpacing),
                moduleTabHorizontalPadding: Double(CodexIslandChromeMetrics.defaultModuleTabHorizontalPadding),
                moduleTabVerticalPadding: Double(CodexIslandChromeMetrics.defaultModuleTabVerticalPadding),
                moduleHeaderToolbarSpacing: Double(CodexIslandChromeMetrics.defaultModuleHeaderToolbarSpacing),
                moduleToolbarButtonGroupSpacing: Double(CodexIslandChromeMetrics.defaultModuleToolbarButtonGroupSpacing)
            ),
            peek: PeekTokens(
                contentHorizontalInset: Double(CodexIslandPeekMetrics.defaultContentHorizontalInset),
                contentTopPadding: Double(CodexIslandPeekMetrics.defaultContentTopPadding),
                contentBottomPadding: Double(CodexIslandPeekMetrics.defaultContentBottomPadding),
                minimumContentWidth: Double(CodexIslandPeekMetrics.defaultMinimumContentWidth),
                maximumContentWidth: Double(CodexIslandPeekMetrics.defaultMaximumContentWidth),
                contentWidthFactor: Double(CodexIslandPeekMetrics.defaultContentWidthFactor),
                openAnimationDuration: Double(CodexIslandPeekMetrics.defaultOpenAnimationDuration),
                closeAnimationDuration: Double(CodexIslandPeekMetrics.defaultCloseAnimationDuration),
                chromeRevealAnimationDuration: Double(CodexIslandPeekMetrics.defaultChromeRevealAnimationDuration),
                bodyCloseFadeDuration: Double(CodexIslandPeekMetrics.defaultBodyCloseFadeDuration),
                closedHeaderRevealDuration: Double(CodexIslandPeekMetrics.defaultClosedHeaderRevealDuration),
                closedHeaderRevealLeadTime: Double(CodexIslandPeekMetrics.defaultClosedHeaderRevealLeadTime)
            ),
            windDrive: WindDriveTokens(
                panelSide: Double(IslandWindDriveMetrics.defaultPanelSide),
                heroCornerRadius: Double(IslandWindDriveMetrics.defaultHeroCornerRadius),
                heroShadowOpacity: Double(IslandWindDriveMetrics.defaultHeroShadowOpacity),
                heroShadowRadius: Double(IslandWindDriveMetrics.defaultHeroShadowRadius),
                heroShadowYOffset: Double(IslandWindDriveMetrics.defaultHeroShadowYOffset),
                basePlateOpacity: Double(IslandWindDriveMetrics.defaultBasePlateOpacity),
                hubDiameter: Double(IslandWindDriveMetrics.defaultHubDiameter),
                logoSize: Double(IslandWindDriveMetrics.defaultLogoSize)
            ),
            codexPeek: CodexPeekTokens(
                rowSpacing: Double(CodexPeekMetrics.defaultRowSpacing),
                contentSpacing: Double(CodexPeekMetrics.defaultContentSpacing),
                badgeSpacing: Double(CodexPeekMetrics.defaultBadgeSpacing),
                titleTrailingSpacerMinLength: Double(CodexPeekMetrics.defaultTitleTrailingSpacerMinLength),
                cardHorizontalPadding: Double(CodexPeekMetrics.defaultCardHorizontalPadding),
                cardVerticalPadding: Double(CodexPeekMetrics.defaultCardVerticalPadding),
                statusDotSize: Double(CodexPeekMetrics.defaultStatusDotSize),
                statusDotTopPadding: Double(CodexPeekMetrics.defaultStatusDotTopPadding),
                statusDotColor: IslandColorToken(red: 0.29, green: 0.86, blue: 0.46, opacity: 1),
                titleFontSize: Double(CodexPeekMetrics.defaultTitleFontSize),
                promptFontSize: Double(CodexPeekMetrics.defaultPromptFontSize),
                summaryFontSize: Double(CodexPeekMetrics.defaultSummaryFontSize),
                promptOpacity: Double(CodexPeekMetrics.defaultPromptOpacity),
                summaryOpacity: Double(CodexPeekMetrics.defaultSummaryOpacity),
                backgroundOpacity: Double(CodexPeekMetrics.defaultBackgroundOpacity)
            ),
            playerPeek: PlayerPeekTokens(
                horizontalSpacing: Double(PlayerPeekMetrics.defaultHorizontalSpacing),
                textSpacing: Double(PlayerPeekMetrics.defaultTextSpacing),
                titleFontSize: Double(PlayerPeekMetrics.defaultTitleFontSize),
                artistFontSize: Double(PlayerPeekMetrics.defaultArtistFontSize),
                contentHorizontalPadding: Double(PlayerPeekMetrics.defaultContentHorizontalPadding),
                contentVerticalPadding: Double(PlayerPeekMetrics.defaultContentVerticalPadding),
                minimumHeight: Double(PlayerPeekMetrics.defaultMinimumHeight),
                artworkCornerRadius: Double(PlayerPeekMetrics.defaultArtworkCornerRadius),
                artworkSize: Double(PlayerPeekMetrics.defaultArtworkSize),
                placeholderSymbolSize: Double(PlayerPeekMetrics.defaultPlaceholderSymbolSize),
                titleOpacity: Double(PlayerPeekMetrics.defaultTitleOpacity),
                artistOpacity: Double(PlayerPeekMetrics.defaultArtistOpacity),
                placeholderOpacity: Double(PlayerPeekMetrics.defaultPlaceholderOpacity),
                artworkBackgroundStartOpacity: Double(PlayerPeekMetrics.defaultArtworkBackgroundStartOpacity),
                artworkBackgroundEndOpacity: Double(PlayerPeekMetrics.defaultArtworkBackgroundEndOpacity)
            ),
            codexExpanded: CodexExpandedTokens(
                contentSpacing: Double(CodexExpandedMetrics.defaultContentSpacing),
                sectionRowSpacing: Double(CodexExpandedMetrics.defaultSectionRowSpacing),
                globalInfoBadgeSpacing: Double(CodexExpandedMetrics.defaultGlobalInfoBadgeSpacing),
                emptyStateMinimumHeight: Double(CodexExpandedMetrics.defaultEmptyStateMinimumHeight),
                cardCornerRadius: Double(CodexExpandedMetrics.defaultCardCornerRadius),
                cardBackgroundOpacity: Double(CodexExpandedMetrics.defaultCardBackgroundOpacity),
                cardBorderOpacity: Double(CodexExpandedMetrics.defaultCardBorderOpacity),
                titleFontSize: Double(CodexExpandedMetrics.defaultTitleFontSize),
                summaryFontSize: Double(CodexExpandedMetrics.defaultSummaryFontSize)
            ),
            clashExpanded: ClashExpandedTokens(
                outerSpacing: Double(ClashExpandedMetrics.defaultOuterSpacing),
                cardSpacing: Double(ClashExpandedMetrics.defaultCardSpacing),
                sectionTitleSpacing: Double(ClashExpandedMetrics.defaultSectionTitleSpacing),
                cardCornerRadius: Double(ClashExpandedMetrics.defaultCardCornerRadius),
                cardBackgroundOpacity: Double(ClashExpandedMetrics.defaultCardBackgroundOpacity),
                cardBorderOpacity: Double(ClashExpandedMetrics.defaultCardBorderOpacity),
                actionPillCornerRadius: Double(ClashExpandedMetrics.defaultActionPillCornerRadius),
                actionPillVerticalPadding: Double(ClashExpandedMetrics.defaultActionPillVerticalPadding)
            ),
            playerExpanded: PlayerExpandedTokens(
                outerSpacing: Double(PlayerExpandedMetrics.defaultOuterSpacing),
                primaryColumnSpacing: Double(PlayerExpandedMetrics.defaultPrimaryColumnSpacing),
                titleBlockSpacing: Double(PlayerExpandedMetrics.defaultTitleBlockSpacing),
                controlsSpacing: Double(PlayerExpandedMetrics.defaultControlsSpacing),
                artworkCornerRadius: Double(PlayerExpandedMetrics.defaultArtworkCornerRadius),
                artworkSize: Double(PlayerExpandedMetrics.defaultArtworkSize),
                progressSectionSpacing: Double(PlayerExpandedMetrics.defaultProgressSectionSpacing),
                controlButtonOpacityDisabled: Double(PlayerExpandedMetrics.defaultControlButtonOpacityDisabled)
            )
        )
    }
}

@MainActor
enum IslandDesignTokenRuntime {
    static var current = IslandDesignTokens.sourceDefaults()
}
