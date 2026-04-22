import Foundation

enum IslandDesignTokenGroup: String, CaseIterable, Identifiable {
    case shell = "Shell"
    case peek = "Peek"
    case windDrive = "Wind Drive"
    case codexExpanded = "Codex Expanded"
    case clashExpanded = "Clash Expanded"
    case playerExpanded = "Player Expanded"

    var id: String { rawValue }
}

enum IslandDesignTokenEditorKind: Equatable {
    case slider(range: ClosedRange<Double>, step: Double)
    case number(step: Double)
    case color
}

enum IslandDesignTokenKey: String, CaseIterable, Identifiable {
    case shellOpenedShadowHorizontalInset
    case shellOpenedSurfaceContentHorizontalInset
    case shellClosedHoverScale
    case shellClosedHorizontalPadding
    case shellClosedFanModuleSpacing
    case shellClosedModuleSpacing
    case shellClosedModuleContentSpacing
    case shellClosedIconSize
    case shellClosedPrimaryFontSize
    case shellClosedTrafficFontSize
    case shellClosedTrafficLineSpacing
    case shellOpenedBodyRevealDelay
    case shellOpenLayoutSettleDuration
    case shellCloseLayoutSettleDuration
    case shellExpandedContentBottomPadding
    case shellExpandedContentTopPadding
    case shellModuleColumnSpacing
    case shellModuleNavigationRowHeight
    case shellModuleTabSpacing
    case shellModuleTabHorizontalPadding
    case shellModuleTabVerticalPadding
    case shellModuleHeaderToolbarSpacing
    case shellModuleToolbarButtonGroupSpacing
    case peekContentHorizontalInset
    case peekContentTopPadding
    case peekContentBottomPadding
    case peekMinimumContentWidth
    case peekMaximumContentWidth
    case peekContentWidthFactor
    case peekOpenAnimationDuration
    case peekCloseAnimationDuration
    case peekChromeRevealAnimationDuration
    case peekBodyCloseFadeDuration
    case peekClosedHeaderRevealDuration
    case peekClosedHeaderRevealLeadTime
    case windDrivePanelSide
    case windDriveHeroCornerRadius
    case windDriveHeroShadowOpacity
    case windDriveHeroShadowRadius
    case windDriveHeroShadowYOffset
    case windDriveBasePlateOpacity
    case windDriveHubDiameter
    case windDriveLogoSize
    case codexPeekRowSpacing
    case codexPeekContentSpacing
    case codexPeekBadgeSpacing
    case codexPeekCardHorizontalPadding
    case codexPeekCardVerticalPadding
    case codexPeekStatusDotSize
    case codexPeekStatusDotTopPadding
    case codexPeekTitleFontSize
    case codexPeekPromptFontSize
    case codexPeekSummaryFontSize
    case codexPeekPromptOpacity
    case codexPeekSummaryOpacity
    case codexPeekBackgroundOpacity
    case codexPeekStatusDotColor
    case playerPeekHorizontalSpacing
    case playerPeekTextSpacing
    case playerPeekTitleFontSize
    case playerPeekArtistFontSize
    case playerPeekContentHorizontalPadding
    case playerPeekContentVerticalPadding
    case playerPeekMinimumHeight
    case playerPeekArtworkCornerRadius
    case playerPeekArtworkSize
    case playerPeekPlaceholderSymbolSize
    case playerPeekTitleOpacity
    case playerPeekArtistOpacity
    case playerPeekPlaceholderOpacity
    case playerPeekArtworkBackgroundStartOpacity
    case playerPeekArtworkBackgroundEndOpacity
    case codexExpandedContentSpacing
    case codexExpandedSectionRowSpacing
    case codexExpandedGlobalInfoBadgeSpacing
    case codexExpandedEmptyStateMinimumHeight
    case codexExpandedCardCornerRadius
    case codexExpandedCardBackgroundOpacity
    case codexExpandedCardBorderOpacity
    case codexExpandedTitleFontSize
    case codexExpandedSummaryFontSize
    case clashExpandedOuterSpacing
    case clashExpandedCardSpacing
    case clashExpandedSectionTitleSpacing
    case clashExpandedCardCornerRadius
    case clashExpandedCardBackgroundOpacity
    case clashExpandedCardBorderOpacity
    case clashExpandedActionPillCornerRadius
    case clashExpandedActionPillVerticalPadding
    case playerExpandedOuterSpacing
    case playerExpandedPrimaryColumnSpacing
    case playerExpandedTitleBlockSpacing
    case playerExpandedControlsSpacing
    case playerExpandedArtworkCornerRadius
    case playerExpandedArtworkSize
    case playerExpandedProgressSectionSpacing
    case playerExpandedControlButtonOpacityDisabled

    var id: String { rawValue }

    var writebackSymbolName: String? {
        let prefixes = [
            "shell",
            "peek",
            "windDrive",
            "codexPeek",
            "playerPeek",
            "codexExpanded",
            "clashExpanded",
            "playerExpanded",
        ]

        guard let prefix = prefixes.first(where: { rawValue.hasPrefix($0) }) else {
            return nil
        }

        let suffix = rawValue.dropFirst(prefix.count)
        guard let firstCharacter = suffix.first else {
            return nil
        }

        return "default" + String(firstCharacter).uppercased() + suffix.dropFirst()
    }
}

struct IslandDesignTokenDescriptor: Identifiable {
    let key: IslandDesignTokenKey
    let group: IslandDesignTokenGroup
    let title: String
    let detail: String
    let kind: IslandDesignTokenEditorKind
    let getNumber: (IslandDesignTokens) -> Double
    let setNumber: (inout IslandDesignTokens, Double) -> Void
    let getColor: (IslandDesignTokens) -> IslandColorToken
    let setColor: (inout IslandDesignTokens, IslandColorToken) -> Void

    var id: IslandDesignTokenKey { key }

    init(
        key: IslandDesignTokenKey,
        group: IslandDesignTokenGroup,
        title: String,
        detail: String,
        kind: IslandDesignTokenEditorKind,
        getNumber: @escaping (IslandDesignTokens) -> Double = { _ in 0 },
        setNumber: @escaping (inout IslandDesignTokens, Double) -> Void = { _, _ in },
        getColor: @escaping (IslandDesignTokens) -> IslandColorToken = { _ in IslandColorToken(red: 1, green: 1, blue: 1) },
        setColor: @escaping (inout IslandDesignTokens, IslandColorToken) -> Void = { _, _ in }
    ) {
        self.key = key
        self.group = group
        self.title = title
        self.detail = detail
        self.kind = kind
        self.getNumber = getNumber
        self.setNumber = setNumber
        self.getColor = getColor
        self.setColor = setColor
    }
}

enum IslandDesignTokenSchema {
    static let descriptors: [IslandDesignTokenDescriptor] = [
        descriptor(.shellOpenedShadowHorizontalInset, .shell, "Shadow Horizontal Inset", "Opened shell outer shadow width.", .slider(range: 0 ... 40, step: 1), \.shell.openedShadowHorizontalInset),
        descriptor(.shellOpenedSurfaceContentHorizontalInset, .shell, "Surface Horizontal Inset", "Opened shell content safe inset.", .slider(range: 0 ... 40, step: 1), \.shell.openedSurfaceContentHorizontalInset),
        descriptor(.shellClosedHoverScale, .shell, "Closed Hover Scale", "Hover scale applied in collapsed state.", .slider(range: 1 ... 1.1, step: 0.001), \.shell.closedHoverScale),
        descriptor(.shellClosedHorizontalPadding, .shell, "Closed Horizontal Padding", "Left and right inset for the collapsed header row.", .slider(range: 0 ... 30, step: 1), \.shell.closedHorizontalPadding),
        descriptor(.shellClosedFanModuleSpacing, .shell, "Closed Fan-to-Modules Spacing", "Gap between the fan icon and the compact module summary area.", .slider(range: 0 ... 30, step: 1), \.shell.closedFanModuleSpacing),
        descriptor(.shellClosedModuleSpacing, .shell, "Closed Module Spacing", "Gap between compact module summaries.", .slider(range: 0 ... 40, step: 1), \.shell.closedModuleSpacing),
        descriptor(.shellClosedModuleContentSpacing, .shell, "Closed Module Content Spacing", "Gap between icon and text inside one compact module summary.", .slider(range: 0 ... 24, step: 1), \.shell.closedModuleContentSpacing),
        descriptor(.shellClosedIconSize, .shell, "Closed Icon Size", "Compact module icon size in collapsed state.", .slider(range: 12 ... 28, step: 1), \.shell.closedIconSize),
        descriptor(.shellClosedPrimaryFontSize, .shell, "Closed Primary Font Size", "Main compact summary font size.", .slider(range: 8 ... 16, step: 0.5), \.shell.closedPrimaryFontSize),
        descriptor(.shellClosedTrafficFontSize, .shell, "Closed Traffic Font Size", "Compact Clash traffic text font size.", .slider(range: 7 ... 14, step: 0.5), \.shell.closedTrafficFontSize),
        descriptor(.shellClosedTrafficLineSpacing, .shell, "Closed Traffic Line Spacing", "Vertical spacing between upload and download lines.", .slider(range: 0 ... 6, step: 0.5), \.shell.closedTrafficLineSpacing),
        descriptor(.shellOpenedBodyRevealDelay, .shell, "Opened Body Delay", "Delay before expanded body reveal.", .slider(range: 0 ... 0.5, step: 0.01), \.shell.openedBodyRevealDelay),
        descriptor(.shellOpenLayoutSettleDuration, .shell, "Open Layout Settle", "Layout lock duration during expansion.", .slider(range: 0.1 ... 1.0, step: 0.01), \.shell.openLayoutSettleDuration),
        descriptor(.shellCloseLayoutSettleDuration, .shell, "Close Layout Settle", "Layout lock duration during collapse.", .slider(range: 0.1 ... 1.0, step: 0.01), \.shell.closeLayoutSettleDuration),
        descriptor(.shellExpandedContentBottomPadding, .shell, "Expanded Bottom Padding", "Bottom breathing room for module content.", .slider(range: 0 ... 40, step: 1), \.shell.expandedContentBottomPadding),
        descriptor(.shellExpandedContentTopPadding, .shell, "Expanded Top Padding", "Top gap above expanded content.", .slider(range: 0 ... 40, step: 1), \.shell.expandedContentTopPadding),
        descriptor(.shellModuleColumnSpacing, .shell, "Module Column Spacing", "Gap between Wind Drive and right column.", .slider(range: 0 ... 40, step: 1), \.shell.moduleColumnSpacing),
        descriptor(.shellModuleNavigationRowHeight, .shell, "Navigation Row Height", "Expanded top row baseline height.", .slider(range: 24 ... 64, step: 1), \.shell.moduleNavigationRowHeight),
        descriptor(.shellModuleTabSpacing, .shell, "Tab Spacing", "Gap between module tabs.", .slider(range: 0 ... 30, step: 1), \.shell.moduleTabSpacing),
        descriptor(.shellModuleTabHorizontalPadding, .shell, "Tab Horizontal Padding", "Single tab horizontal inset.", .slider(range: 0 ... 30, step: 1), \.shell.moduleTabHorizontalPadding),
        descriptor(.shellModuleTabVerticalPadding, .shell, "Tab Vertical Padding", "Single tab vertical inset.", .slider(range: 0 ... 20, step: 1), \.shell.moduleTabVerticalPadding),
        descriptor(.shellModuleHeaderToolbarSpacing, .shell, "Header Toolbar Spacing", "Gap between tabs and toolbar.", .slider(range: 0 ... 30, step: 1), \.shell.moduleHeaderToolbarSpacing),
        descriptor(.shellModuleToolbarButtonGroupSpacing, .shell, "Toolbar Button Group Spacing", "Gap inside toolbar button group.", .slider(range: 0 ... 30, step: 1), \.shell.moduleToolbarButtonGroupSpacing),
        descriptor(.peekContentHorizontalInset, .peek, "Peek Horizontal Inset", "Horizontal inset for peek content.", .slider(range: 0 ... 40, step: 1), \.peek.contentHorizontalInset),
        descriptor(.peekContentTopPadding, .peek, "Peek Top Padding", "Top breathing room for peek content.", .slider(range: 0 ... 24, step: 1), \.peek.contentTopPadding),
        descriptor(.peekContentBottomPadding, .peek, "Peek Bottom Padding", "Bottom breathing room for peek content.", .slider(range: 0 ... 24, step: 1), \.peek.contentBottomPadding),
        descriptor(.peekMinimumContentWidth, .peek, "Peek Min Width", "Minimum width on narrow screens.", .slider(range: 300 ... 600, step: 4), \.peek.minimumContentWidth),
        descriptor(.peekMaximumContentWidth, .peek, "Peek Max Width", "Maximum width on wide screens.", .slider(range: 400 ... 760, step: 4), \.peek.maximumContentWidth),
        descriptor(.peekContentWidthFactor, .peek, "Peek Width Factor", "Viewport width ratio for peek content.", .slider(range: 0.2 ... 0.6, step: 0.01), \.peek.contentWidthFactor),
        descriptor(.peekOpenAnimationDuration, .peek, "Open Animation", "Closed to peek/expanded morph duration.", .slider(range: 0.1 ... 0.8, step: 0.01), \.peek.openAnimationDuration),
        descriptor(.peekCloseAnimationDuration, .peek, "Close Animation", "Peek/expanded to closed duration.", .slider(range: 0.1 ... 0.8, step: 0.01), \.peek.closeAnimationDuration),
        descriptor(.peekChromeRevealAnimationDuration, .peek, "Chrome Reveal", "Reveal duration for opened chrome.", .slider(range: 0.05 ... 0.5, step: 0.01), \.peek.chromeRevealAnimationDuration),
        descriptor(.peekBodyCloseFadeDuration, .peek, "Body Close Fade", "Body fade-out duration during close.", .slider(range: 0.05 ... 0.5, step: 0.01), \.peek.bodyCloseFadeDuration),
        descriptor(.peekClosedHeaderRevealDuration, .peek, "Header Reveal Duration", "Collapsed header re-entry fade duration.", .slider(range: 0.05 ... 0.3, step: 0.01), \.peek.closedHeaderRevealDuration),
        descriptor(.peekClosedHeaderRevealLeadTime, .peek, "Header Reveal Lead", "How early header starts returning before close ends.", .slider(range: 0.01 ... 0.2, step: 0.01), \.peek.closedHeaderRevealLeadTime),
        descriptor(.windDrivePanelSide, .windDrive, "Panel Side", "Expanded Wind Drive panel width/height.", .slider(range: 160 ... 280, step: 2), \.windDrive.panelSide),
        descriptor(.windDriveHeroCornerRadius, .windDrive, "Hero Corner Radius", "Wind Drive hero tile radius.", .slider(range: 0 ... 48, step: 1), \.windDrive.heroCornerRadius),
        descriptor(.windDriveHeroShadowOpacity, .windDrive, "Hero Shadow Opacity", "Wind Drive hero shadow opacity.", .slider(range: 0 ... 1, step: 0.01), \.windDrive.heroShadowOpacity),
        descriptor(.windDriveHeroShadowRadius, .windDrive, "Hero Shadow Radius", "Wind Drive hero shadow blur radius.", .slider(range: 0 ... 40, step: 1), \.windDrive.heroShadowRadius),
        descriptor(.windDriveHeroShadowYOffset, .windDrive, "Hero Shadow Y", "Wind Drive hero shadow y offset.", .slider(range: 0 ... 20, step: 1), \.windDrive.heroShadowYOffset),
        descriptor(.windDriveBasePlateOpacity, .windDrive, "Base Plate Opacity", "Base plate fill opacity.", .slider(range: 0 ... 1, step: 0.01), \.windDrive.basePlateOpacity),
        descriptor(.windDriveHubDiameter, .windDrive, "Hub Diameter", "Center hub diameter.", .slider(range: 24 ... 72, step: 1), \.windDrive.hubDiameter),
        descriptor(.windDriveLogoSize, .windDrive, "Logo Size", "Logo mark size inside hub.", .slider(range: 16 ... 48, step: 1), \.windDrive.logoSize),
        descriptor(.codexPeekRowSpacing, .peek, "Codex Peek Row Spacing", "Gap between dot and text column.", .slider(range: 0 ... 24, step: 1), \.codexPeek.rowSpacing),
        descriptor(.codexPeekContentSpacing, .peek, "Codex Peek Content Spacing", "Gap between Codex peek text rows.", .slider(range: 0 ... 20, step: 1), \.codexPeek.contentSpacing),
        descriptor(.codexPeekBadgeSpacing, .peek, "Codex Peek Badge Spacing", "Gap between badge pills.", .slider(range: 0 ... 20, step: 1), \.codexPeek.badgeSpacing),
        descriptor(.codexPeekCardHorizontalPadding, .peek, "Codex Peek Horizontal Padding", "Horizontal padding inside Codex peek card.", .slider(range: 0 ... 32, step: 1), \.codexPeek.cardHorizontalPadding),
        descriptor(.codexPeekCardVerticalPadding, .peek, "Codex Peek Vertical Padding", "Vertical padding inside Codex peek card.", .slider(range: 0 ... 32, step: 1), \.codexPeek.cardVerticalPadding),
        descriptor(.codexPeekStatusDotSize, .peek, "Codex Peek Dot Size", "Completion dot size.", .slider(range: 4 ... 16, step: 1), \.codexPeek.statusDotSize),
        descriptor(.codexPeekStatusDotTopPadding, .peek, "Codex Peek Dot Top Padding", "Visual vertical correction for status dot.", .slider(range: 0 ... 10, step: 1), \.codexPeek.statusDotTopPadding),
        descriptor(.codexPeekTitleFontSize, .peek, "Codex Peek Title Size", "Title font size for Codex peek.", .slider(range: 10 ... 20, step: 0.5), \.codexPeek.titleFontSize),
        descriptor(.codexPeekPromptFontSize, .peek, "Codex Peek Prompt Size", "Prompt font size for Codex peek.", .slider(range: 9 ... 18, step: 0.5), \.codexPeek.promptFontSize),
        descriptor(.codexPeekSummaryFontSize, .peek, "Codex Peek Summary Size", "Summary font size for Codex peek.", .slider(range: 9 ... 18, step: 0.5), \.codexPeek.summaryFontSize),
        descriptor(.codexPeekPromptOpacity, .peek, "Codex Peek Prompt Opacity", "Prompt text opacity.", .slider(range: 0 ... 1, step: 0.01), \.codexPeek.promptOpacity),
        descriptor(.codexPeekSummaryOpacity, .peek, "Codex Peek Summary Opacity", "Summary text opacity.", .slider(range: 0 ... 1, step: 0.01), \.codexPeek.summaryOpacity),
        descriptor(.codexPeekBackgroundOpacity, .peek, "Codex Peek Background Opacity", "Peek card background opacity.", .slider(range: 0 ... 0.2, step: 0.005), \.codexPeek.backgroundOpacity),
        colorDescriptor(.codexPeekStatusDotColor, .peek, "Codex Peek Status Color", "Semantic status color for completion dot.", \.statusDotColor),
        descriptor(.playerPeekHorizontalSpacing, .peek, "Player Peek Horizontal Spacing", "Gap between artwork and text block.", .slider(range: 0 ... 24, step: 1), \.playerPeek.horizontalSpacing),
        descriptor(.playerPeekTextSpacing, .peek, "Player Peek Text Spacing", "Gap between title and artist lines.", .slider(range: 0 ... 20, step: 1), \.playerPeek.textSpacing),
        descriptor(.playerPeekTitleFontSize, .peek, "Player Peek Title Size", "Player peek title size.", .slider(range: 10 ... 24, step: 0.5), \.playerPeek.titleFontSize),
        descriptor(.playerPeekArtistFontSize, .peek, "Player Peek Artist Size", "Player peek artist size.", .slider(range: 9 ... 18, step: 0.5), \.playerPeek.artistFontSize),
        descriptor(.playerPeekContentHorizontalPadding, .peek, "Player Peek Horizontal Padding", "Inner horizontal padding inside Player peek content.", .slider(range: 0 ... 16, step: 1), \.playerPeek.contentHorizontalPadding),
        descriptor(.playerPeekContentVerticalPadding, .peek, "Player Peek Vertical Padding", "Inner vertical padding inside Player peek content.", .slider(range: 0 ... 16, step: 1), \.playerPeek.contentVerticalPadding),
        descriptor(.playerPeekMinimumHeight, .peek, "Player Peek Minimum Height", "Minimum content height for Player peek.", .slider(range: 40 ... 120, step: 1), \.playerPeek.minimumHeight),
        descriptor(.playerPeekArtworkCornerRadius, .peek, "Player Peek Artwork Radius", "Corner radius for peek artwork.", .slider(range: 0 ... 24, step: 1), \.playerPeek.artworkCornerRadius),
        descriptor(.playerPeekArtworkSize, .peek, "Player Peek Artwork Size", "Artwork size in peek mode.", .slider(range: 32 ... 96, step: 1), \.playerPeek.artworkSize),
        descriptor(.playerPeekPlaceholderSymbolSize, .peek, "Player Peek Placeholder Size", "Placeholder symbol size.", .slider(range: 8 ... 32, step: 1), \.playerPeek.placeholderSymbolSize),
        descriptor(.playerPeekTitleOpacity, .peek, "Player Peek Title Opacity", "Title opacity for player peek.", .slider(range: 0 ... 1, step: 0.01), \.playerPeek.titleOpacity),
        descriptor(.playerPeekArtistOpacity, .peek, "Player Peek Artist Opacity", "Artist opacity for player peek.", .slider(range: 0 ... 1, step: 0.01), \.playerPeek.artistOpacity),
        descriptor(.playerPeekPlaceholderOpacity, .peek, "Player Peek Placeholder Opacity", "Placeholder icon opacity.", .slider(range: 0 ... 1, step: 0.01), \.playerPeek.placeholderOpacity),
        descriptor(.playerPeekArtworkBackgroundStartOpacity, .peek, "Player Peek Artwork Start Opacity", "Gradient start opacity behind artwork.", .slider(range: 0 ... 0.3, step: 0.01), \.playerPeek.artworkBackgroundStartOpacity),
        descriptor(.playerPeekArtworkBackgroundEndOpacity, .peek, "Player Peek Artwork End Opacity", "Gradient end opacity behind artwork.", .slider(range: 0 ... 0.3, step: 0.01), \.playerPeek.artworkBackgroundEndOpacity),
        descriptor(.codexExpandedContentSpacing, .codexExpanded, "Codex Content Spacing", "Primary vertical spacing inside Codex expanded content.", .slider(range: 0 ... 24, step: 1), \.codexExpanded.contentSpacing),
        descriptor(.codexExpandedSectionRowSpacing, .codexExpanded, "Codex Section Row Spacing", "Gap between session cards.", .slider(range: 0 ... 20, step: 1), \.codexExpanded.sectionRowSpacing),
        descriptor(.codexExpandedGlobalInfoBadgeSpacing, .codexExpanded, "Codex Badge Spacing", "Spacing inside Global Info badge row.", .slider(range: 0 ... 20, step: 1), \.codexExpanded.globalInfoBadgeSpacing),
        descriptor(.codexExpandedEmptyStateMinimumHeight, .codexExpanded, "Codex Empty Min Height", "Minimum height for Codex empty state.", .slider(range: 40 ... 160, step: 1), \.codexExpanded.emptyStateMinimumHeight),
        descriptor(.codexExpandedCardCornerRadius, .codexExpanded, "Codex Card Radius", "Common Codex card radius.", .slider(range: 0 ... 30, step: 1), \.codexExpanded.cardCornerRadius),
        descriptor(.codexExpandedCardBackgroundOpacity, .codexExpanded, "Codex Card Background", "Common Codex card background opacity.", .slider(range: 0 ... 0.2, step: 0.005), \.codexExpanded.cardBackgroundOpacity),
        descriptor(.codexExpandedCardBorderOpacity, .codexExpanded, "Codex Card Border", "Common Codex card border opacity.", .slider(range: 0 ... 0.2, step: 0.005), \.codexExpanded.cardBorderOpacity),
        descriptor(.codexExpandedTitleFontSize, .codexExpanded, "Codex Title Size", "Primary title size in Codex cards.", .slider(range: 11 ... 22, step: 0.5), \.codexExpanded.titleFontSize),
        descriptor(.codexExpandedSummaryFontSize, .codexExpanded, "Codex Summary Size", "Summary text size in Codex cards.", .slider(range: 10 ... 18, step: 0.5), \.codexExpanded.summaryFontSize),
        descriptor(.clashExpandedOuterSpacing, .clashExpanded, "Clash Outer Spacing", "Primary vertical spacing inside Clash content.", .slider(range: 0 ... 24, step: 1), \.clashExpanded.outerSpacing),
        descriptor(.clashExpandedCardSpacing, .clashExpanded, "Clash Card Spacing", "Gap between Clash cards.", .slider(range: 0 ... 16, step: 1), \.clashExpanded.cardSpacing),
        descriptor(.clashExpandedSectionTitleSpacing, .clashExpanded, "Clash Section Spacing", "Spacing below section title.", .slider(range: 0 ... 20, step: 1), \.clashExpanded.sectionTitleSpacing),
        descriptor(.clashExpandedCardCornerRadius, .clashExpanded, "Clash Card Radius", "Common Clash card radius.", .slider(range: 0 ... 30, step: 1), \.clashExpanded.cardCornerRadius),
        descriptor(.clashExpandedCardBackgroundOpacity, .clashExpanded, "Clash Card Background", "Common Clash card background opacity.", .slider(range: 0 ... 0.2, step: 0.005), \.clashExpanded.cardBackgroundOpacity),
        descriptor(.clashExpandedCardBorderOpacity, .clashExpanded, "Clash Card Border", "Common Clash card border opacity.", .slider(range: 0 ... 0.2, step: 0.005), \.clashExpanded.cardBorderOpacity),
        descriptor(.clashExpandedActionPillCornerRadius, .clashExpanded, "Clash Pill Radius", "Corner radius for action pills.", .slider(range: 0 ... 24, step: 1), \.clashExpanded.actionPillCornerRadius),
        descriptor(.clashExpandedActionPillVerticalPadding, .clashExpanded, "Clash Pill Vertical Padding", "Vertical padding for action pills.", .slider(range: 0 ... 16, step: 1), \.clashExpanded.actionPillVerticalPadding),
        descriptor(.playerExpandedOuterSpacing, .playerExpanded, "Player Outer Spacing", "Primary vertical spacing inside Player content.", .slider(range: 0 ... 30, step: 1), \.playerExpanded.outerSpacing),
        descriptor(.playerExpandedPrimaryColumnSpacing, .playerExpanded, "Player Column Spacing", "Gap between text column and artwork.", .slider(range: 0 ... 40, step: 1), \.playerExpanded.primaryColumnSpacing),
        descriptor(.playerExpandedTitleBlockSpacing, .playerExpanded, "Player Title Block Spacing", "Gap in title block.", .slider(range: 0 ... 16, step: 1), \.playerExpanded.titleBlockSpacing),
        descriptor(.playerExpandedControlsSpacing, .playerExpanded, "Player Controls Spacing", "Gap between transport controls.", .slider(range: 0 ... 30, step: 1), \.playerExpanded.controlsSpacing),
        descriptor(.playerExpandedArtworkCornerRadius, .playerExpanded, "Player Artwork Radius", "Artwork radius in expanded mode.", .slider(range: 0 ... 30, step: 1), \.playerExpanded.artworkCornerRadius),
        descriptor(.playerExpandedArtworkSize, .playerExpanded, "Player Artwork Size", "Artwork size in expanded mode.", .slider(range: 72 ... 160, step: 1), \.playerExpanded.artworkSize),
        descriptor(.playerExpandedProgressSectionSpacing, .playerExpanded, "Player Progress Spacing", "Gap inside progress section.", .slider(range: 0 ... 16, step: 1), \.playerExpanded.progressSectionSpacing),
        descriptor(.playerExpandedControlButtonOpacityDisabled, .playerExpanded, "Player Disabled Controls Opacity", "Opacity for disabled transport controls.", .slider(range: 0 ... 1, step: 0.01), \.playerExpanded.controlButtonOpacityDisabled),
    ]

    static func descriptors(for group: IslandDesignTokenGroup) -> [IslandDesignTokenDescriptor] {
        descriptors.filter { $0.group == group }
    }

    private static func descriptor(
        _ key: IslandDesignTokenKey,
        _ group: IslandDesignTokenGroup,
        _ title: String,
        _ detail: String,
        _ kind: IslandDesignTokenEditorKind,
        _ keyPath: WritableKeyPath<IslandDesignTokens, Double>
    ) -> IslandDesignTokenDescriptor {
        IslandDesignTokenDescriptor(
            key: key,
            group: group,
            title: title,
            detail: detail,
            kind: kind,
            getNumber: { $0[keyPath: keyPath] },
            setNumber: { $0[keyPath: keyPath] = $1 }
        )
    }

    private static func descriptor<Root>(
        _ key: IslandDesignTokenKey,
        _ group: IslandDesignTokenGroup,
        _ title: String,
        _ detail: String,
        _ kind: IslandDesignTokenEditorKind,
        _ keyPath: WritableKeyPath<Root, Double>,
        in rootKeyPath: WritableKeyPath<IslandDesignTokens, Root>
    ) -> IslandDesignTokenDescriptor {
        IslandDesignTokenDescriptor(
            key: key,
            group: group,
            title: title,
            detail: detail,
            kind: kind,
            getNumber: { $0[keyPath: rootKeyPath][keyPath: keyPath] },
            setNumber: { $0[keyPath: rootKeyPath][keyPath: keyPath] = $1 }
        )
    }

    private static func descriptor(
        _ key: IslandDesignTokenKey,
        _ group: IslandDesignTokenGroup,
        _ title: String,
        _ detail: String,
        _ kind: IslandDesignTokenEditorKind,
        _ keyPath: WritableKeyPath<IslandDesignTokens.ShellTokens, Double>
    ) -> IslandDesignTokenDescriptor {
        descriptor(key, group, title, detail, kind, keyPath, in: \.shell)
    }

    private static func descriptor(
        _ key: IslandDesignTokenKey,
        _ group: IslandDesignTokenGroup,
        _ title: String,
        _ detail: String,
        _ kind: IslandDesignTokenEditorKind,
        _ keyPath: WritableKeyPath<IslandDesignTokens.PeekTokens, Double>
    ) -> IslandDesignTokenDescriptor {
        descriptor(key, group, title, detail, kind, keyPath, in: \.peek)
    }

    private static func descriptor(
        _ key: IslandDesignTokenKey,
        _ group: IslandDesignTokenGroup,
        _ title: String,
        _ detail: String,
        _ kind: IslandDesignTokenEditorKind,
        _ keyPath: WritableKeyPath<IslandDesignTokens.WindDriveTokens, Double>
    ) -> IslandDesignTokenDescriptor {
        descriptor(key, group, title, detail, kind, keyPath, in: \.windDrive)
    }

    private static func descriptor(
        _ key: IslandDesignTokenKey,
        _ group: IslandDesignTokenGroup,
        _ title: String,
        _ detail: String,
        _ kind: IslandDesignTokenEditorKind,
        _ keyPath: WritableKeyPath<IslandDesignTokens.CodexPeekTokens, Double>
    ) -> IslandDesignTokenDescriptor {
        descriptor(key, group, title, detail, kind, keyPath, in: \.codexPeek)
    }

    private static func descriptor(
        _ key: IslandDesignTokenKey,
        _ group: IslandDesignTokenGroup,
        _ title: String,
        _ detail: String,
        _ kind: IslandDesignTokenEditorKind,
        _ keyPath: WritableKeyPath<IslandDesignTokens.PlayerPeekTokens, Double>
    ) -> IslandDesignTokenDescriptor {
        descriptor(key, group, title, detail, kind, keyPath, in: \.playerPeek)
    }

    private static func descriptor(
        _ key: IslandDesignTokenKey,
        _ group: IslandDesignTokenGroup,
        _ title: String,
        _ detail: String,
        _ kind: IslandDesignTokenEditorKind,
        _ keyPath: WritableKeyPath<IslandDesignTokens.CodexExpandedTokens, Double>
    ) -> IslandDesignTokenDescriptor {
        descriptor(key, group, title, detail, kind, keyPath, in: \.codexExpanded)
    }

    private static func descriptor(
        _ key: IslandDesignTokenKey,
        _ group: IslandDesignTokenGroup,
        _ title: String,
        _ detail: String,
        _ kind: IslandDesignTokenEditorKind,
        _ keyPath: WritableKeyPath<IslandDesignTokens.ClashExpandedTokens, Double>
    ) -> IslandDesignTokenDescriptor {
        descriptor(key, group, title, detail, kind, keyPath, in: \.clashExpanded)
    }

    private static func descriptor(
        _ key: IslandDesignTokenKey,
        _ group: IslandDesignTokenGroup,
        _ title: String,
        _ detail: String,
        _ kind: IslandDesignTokenEditorKind,
        _ keyPath: WritableKeyPath<IslandDesignTokens.PlayerExpandedTokens, Double>
    ) -> IslandDesignTokenDescriptor {
        descriptor(key, group, title, detail, kind, keyPath, in: \.playerExpanded)
    }

    private static func colorDescriptor(
        _ key: IslandDesignTokenKey,
        _ group: IslandDesignTokenGroup,
        _ title: String,
        _ detail: String,
        _ keyPath: WritableKeyPath<IslandDesignTokens.CodexPeekTokens, IslandColorToken>
    ) -> IslandDesignTokenDescriptor {
        IslandDesignTokenDescriptor(
            key: key,
            group: group,
            title: title,
            detail: detail,
            kind: .color,
            getColor: { $0.codexPeek[keyPath: keyPath] },
            setColor: { $0.codexPeek[keyPath: keyPath] = $1 }
        )
    }
}
