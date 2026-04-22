import Foundation

struct DesignTokenWritebackService {
    private static let sourceFileURL = URL(fileURLWithPath: #filePath)

    private struct WritebackTarget {
        let group: IslandDesignTokenGroup
        let path: String
        let replacements: [Replacement]
    }

    private struct Replacement {
        let pattern: String
        let renderedValue: String
        let valueCaptureGroup: Int
        let debugName: String
    }

    enum WritebackError: LocalizedError {
        case missingMatch(name: String, path: String)
        case ambiguousMatch(name: String, path: String, count: Int)

        var errorDescription: String? {
            switch self {
            case let .missingMatch(name, path):
                return "Write back could not find a unique value span for `\(name)` in `\(path)`."
            case let .ambiguousMatch(name, path, count):
                return "Write back matched `\(name)` \(count) times in `\(path)`. It only supports one exact value span."
            }
        }
    }

    func writeBack(tokens: IslandDesignTokens, groups: Set<IslandDesignTokenGroup>) throws -> [URL] {
        let repositoryRoot = repositoryRootDirectory()
        var touched: [URL] = []

        for target in targets(tokens: tokens) where groups.contains(target.group) {
            let url = repositoryRoot.appendingPathComponent(target.path)
            var contents = try String(contentsOf: url, encoding: .utf8)
            let originalContents = contents
            for replacement in target.replacements {
                contents = try replace(replacement, in: contents, path: target.path)
            }
            if contents != originalContents {
                try contents.write(to: url, atomically: true, encoding: .utf8)
                touched.append(url)
            }
        }

        return touched
    }

    private func targets(tokens: IslandDesignTokens) -> [WritebackTarget] {
        [
            WritebackTarget(
                group: .shell,
                path: "FantasticIsland/FantasticIsland/Shell/IslandShellChromeMetrics.swift",
                replacements: [
                    number("defaultOpenedShadowHorizontalInset", tokens.shell.openedShadowHorizontalInset),
                    number("defaultOpenedSurfaceContentHorizontalInset", tokens.shell.openedSurfaceContentHorizontalInset),
                    number("defaultClosedHoverScale", tokens.shell.closedHoverScale),
                    number("defaultClosedHorizontalPadding", tokens.shell.closedHorizontalPadding),
                    number("defaultClosedFanModuleSpacing", tokens.shell.closedFanModuleSpacing),
                    number("defaultClosedModuleSpacing", tokens.shell.closedModuleSpacing),
                    number("defaultClosedModuleContentSpacing", tokens.shell.closedModuleContentSpacing),
                    number("defaultClosedIconSize", tokens.shell.closedIconSize),
                    number("defaultClosedPrimaryFontSize", tokens.shell.closedPrimaryFontSize),
                    number("defaultClosedTrafficFontSize", tokens.shell.closedTrafficFontSize),
                    number("defaultClosedTrafficLineSpacing", tokens.shell.closedTrafficLineSpacing),
                    number("defaultOpenedBodyRevealDelay", tokens.shell.openedBodyRevealDelay),
                    number("defaultOpenLayoutSettleDuration", tokens.shell.openLayoutSettleDuration),
                    number("defaultCloseLayoutSettleDuration", tokens.shell.closeLayoutSettleDuration),
                    number("defaultExpandedContentBottomPadding", tokens.shell.expandedContentBottomPadding),
                    number("defaultExpandedContentTopPadding", tokens.shell.expandedContentTopPadding),
                    number("defaultModuleColumnSpacing", tokens.shell.moduleColumnSpacing),
                    number("defaultModuleNavigationRowHeight", tokens.shell.moduleNavigationRowHeight),
                    number("defaultModuleTabSpacing", tokens.shell.moduleTabSpacing),
                    number("defaultModuleTabHorizontalPadding", tokens.shell.moduleTabHorizontalPadding),
                    number("defaultModuleTabVerticalPadding", tokens.shell.moduleTabVerticalPadding),
                    number("defaultModuleHeaderToolbarSpacing", tokens.shell.moduleHeaderToolbarSpacing),
                    number("defaultModuleToolbarButtonGroupSpacing", tokens.shell.moduleToolbarButtonGroupSpacing),
                ]
            ),
            WritebackTarget(
                group: .peek,
                path: "FantasticIsland/FantasticIsland/Shell/IslandShellChromeMetrics.swift",
                replacements: [
                    number("defaultContentHorizontalInset", tokens.peek.contentHorizontalInset),
                    number("defaultContentTopPadding", tokens.peek.contentTopPadding),
                    number("defaultContentBottomPadding", tokens.peek.contentBottomPadding),
                    number("defaultMinimumContentWidth", tokens.peek.minimumContentWidth),
                    number("defaultMaximumContentWidth", tokens.peek.maximumContentWidth),
                    number("defaultContentWidthFactor", tokens.peek.contentWidthFactor),
                    number("defaultOpenAnimationDuration", tokens.peek.openAnimationDuration),
                    number("defaultCloseAnimationDuration", tokens.peek.closeAnimationDuration),
                    number("defaultChromeRevealAnimationDuration", tokens.peek.chromeRevealAnimationDuration),
                    number("defaultBodyCloseFadeDuration", tokens.peek.bodyCloseFadeDuration),
                    number("defaultClosedHeaderRevealDuration", tokens.peek.closedHeaderRevealDuration),
                    number("defaultClosedHeaderRevealLeadTime", tokens.peek.closedHeaderRevealLeadTime),
                ]
            ),
            WritebackTarget(
                group: .windDrive,
                path: "FantasticIsland/FantasticIsland/UI/Shared/IslandWindDriveMetrics.swift",
                replacements: [
                    number("defaultPanelSide", tokens.windDrive.panelSide),
                    number("defaultHeroCornerRadius", tokens.windDrive.heroCornerRadius),
                    number("defaultHeroShadowOpacity", tokens.windDrive.heroShadowOpacity),
                    number("defaultHeroShadowRadius", tokens.windDrive.heroShadowRadius),
                    number("defaultHeroShadowYOffset", tokens.windDrive.heroShadowYOffset),
                    number("defaultBasePlateOpacity", tokens.windDrive.basePlateOpacity),
                    number("defaultHubDiameter", tokens.windDrive.hubDiameter),
                    number("defaultLogoSize", tokens.windDrive.logoSize),
                ]
            ),
            WritebackTarget(
                group: .peek,
                path: "FantasticIsland/FantasticIsland/Modules/Codex/Views/CodexPeekMetrics.swift",
                replacements: [
                    number("defaultRowSpacing", tokens.codexPeek.rowSpacing),
                    number("defaultContentSpacing", tokens.codexPeek.contentSpacing),
                    number("defaultBadgeSpacing", tokens.codexPeek.badgeSpacing),
                    number("defaultCardHorizontalPadding", tokens.codexPeek.cardHorizontalPadding),
                    number("defaultCardVerticalPadding", tokens.codexPeek.cardVerticalPadding),
                    number("defaultStatusDotSize", tokens.codexPeek.statusDotSize),
                    number("defaultStatusDotTopPadding", tokens.codexPeek.statusDotTopPadding),
                    number("defaultTitleFontSize", tokens.codexPeek.titleFontSize),
                    number("defaultPromptFontSize", tokens.codexPeek.promptFontSize),
                    number("defaultSummaryFontSize", tokens.codexPeek.summaryFontSize),
                    number("defaultPromptOpacity", tokens.codexPeek.promptOpacity),
                    number("defaultSummaryOpacity", tokens.codexPeek.summaryOpacity),
                    number("defaultBackgroundOpacity", tokens.codexPeek.backgroundOpacity),
                    color("defaultStatusDotColor", tokens.codexPeek.statusDotColor),
                ]
            ),
            WritebackTarget(
                group: .peek,
                path: "FantasticIsland/FantasticIsland/Modules/Player/Views/PlayerPeekMetrics.swift",
                replacements: [
                    number("defaultHorizontalSpacing", tokens.playerPeek.horizontalSpacing),
                    number("defaultTextSpacing", tokens.playerPeek.textSpacing),
                    number("defaultTitleFontSize", tokens.playerPeek.titleFontSize),
                    number("defaultArtistFontSize", tokens.playerPeek.artistFontSize),
                    number("defaultContentHorizontalPadding", tokens.playerPeek.contentHorizontalPadding),
                    number("defaultContentVerticalPadding", tokens.playerPeek.contentVerticalPadding),
                    number("defaultMinimumHeight", tokens.playerPeek.minimumHeight),
                    number("defaultArtworkCornerRadius", tokens.playerPeek.artworkCornerRadius),
                    number("defaultArtworkSize", tokens.playerPeek.artworkSize),
                    number("defaultPlaceholderSymbolSize", tokens.playerPeek.placeholderSymbolSize),
                    number("defaultTitleOpacity", tokens.playerPeek.titleOpacity),
                    number("defaultArtistOpacity", tokens.playerPeek.artistOpacity),
                    number("defaultPlaceholderOpacity", tokens.playerPeek.placeholderOpacity),
                    number("defaultArtworkBackgroundStartOpacity", tokens.playerPeek.artworkBackgroundStartOpacity),
                    number("defaultArtworkBackgroundEndOpacity", tokens.playerPeek.artworkBackgroundEndOpacity),
                ]
            ),
            WritebackTarget(
                group: .codexExpanded,
                path: "FantasticIsland/FantasticIsland/UI/Modules/Codex/CodexExpandedMetrics.swift",
                replacements: [
                    number("defaultContentSpacing", tokens.codexExpanded.contentSpacing),
                    number("defaultSectionRowSpacing", tokens.codexExpanded.sectionRowSpacing),
                    number("defaultGlobalInfoBadgeSpacing", tokens.codexExpanded.globalInfoBadgeSpacing),
                    number("defaultEmptyStateMinimumHeight", tokens.codexExpanded.emptyStateMinimumHeight),
                    number("defaultCardCornerRadius", tokens.codexExpanded.cardCornerRadius),
                    number("defaultCardBackgroundOpacity", tokens.codexExpanded.cardBackgroundOpacity),
                    number("defaultCardBorderOpacity", tokens.codexExpanded.cardBorderOpacity),
                    number("defaultTitleFontSize", tokens.codexExpanded.titleFontSize),
                    number("defaultSummaryFontSize", tokens.codexExpanded.summaryFontSize),
                ]
            ),
            WritebackTarget(
                group: .clashExpanded,
                path: "FantasticIsland/FantasticIsland/UI/Modules/Clash/ClashExpandedMetrics.swift",
                replacements: [
                    number("defaultOuterSpacing", tokens.clashExpanded.outerSpacing),
                    number("defaultCardSpacing", tokens.clashExpanded.cardSpacing),
                    number("defaultSectionTitleSpacing", tokens.clashExpanded.sectionTitleSpacing),
                    number("defaultCardCornerRadius", tokens.clashExpanded.cardCornerRadius),
                    number("defaultCardBackgroundOpacity", tokens.clashExpanded.cardBackgroundOpacity),
                    number("defaultCardBorderOpacity", tokens.clashExpanded.cardBorderOpacity),
                    number("defaultActionPillCornerRadius", tokens.clashExpanded.actionPillCornerRadius),
                    number("defaultActionPillVerticalPadding", tokens.clashExpanded.actionPillVerticalPadding),
                ]
            ),
            WritebackTarget(
                group: .playerExpanded,
                path: "FantasticIsland/FantasticIsland/UI/Modules/Player/PlayerExpandedMetrics.swift",
                replacements: [
                    number("defaultOuterSpacing", tokens.playerExpanded.outerSpacing),
                    number("defaultPrimaryColumnSpacing", tokens.playerExpanded.primaryColumnSpacing),
                    number("defaultTitleBlockSpacing", tokens.playerExpanded.titleBlockSpacing),
                    number("defaultControlsSpacing", tokens.playerExpanded.controlsSpacing),
                    number("defaultArtworkCornerRadius", tokens.playerExpanded.artworkCornerRadius),
                    number("defaultArtworkSize", tokens.playerExpanded.artworkSize),
                    number("defaultProgressSectionSpacing", tokens.playerExpanded.progressSectionSpacing),
                    number("defaultControlButtonOpacityDisabled", tokens.playerExpanded.controlButtonOpacityDisabled),
                ]
            ),
        ]
    }

    private func repositoryRootDirectory() -> URL {
        var repositoryRoot = Self.sourceFileURL
        for _ in 0..<5 {
            repositoryRoot.deleteLastPathComponent()
        }
        return repositoryRoot
    }

    private func number(_ name: String, _ value: Double) -> Replacement {
        Replacement(
            pattern: #"(?m)(^\s*static let \#(name):\s*CGFloat\s*=\s*)(-?(?:\d+(?:\.\d+)?|\.\d+))(\s*(?://.*)?$)"#,
            renderedValue: formatted(value),
            valueCaptureGroup: 2,
            debugName: name
        )
    }

    private func color(_ name: String, _ value: IslandColorToken) -> Replacement {
        Replacement(
            pattern: #"(?m)(^\s*static let \#(name)\s*=\s*)(Color\([^\n]+\))(\s*(?://.*)?$)"#,
            renderedValue: "Color(red: \(formatted(value.red)), green: \(formatted(value.green)), blue: \(formatted(value.blue)), opacity: \(formatted(value.opacity)))",
            valueCaptureGroup: 2,
            debugName: name
        )
    }

    private func replace(_ replacement: Replacement, in source: String, path: String) throws -> String {
        let regex = try NSRegularExpression(pattern: replacement.pattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = regex.matches(in: source, range: range)

        guard let match = matches.first else {
            throw WritebackError.missingMatch(name: replacement.debugName, path: path)
        }

        guard matches.count == 1 else {
            throw WritebackError.ambiguousMatch(name: replacement.debugName, path: path, count: matches.count)
        }

        let valueRange = match.range(at: replacement.valueCaptureGroup)
        guard let swiftRange = Range(valueRange, in: source) else {
            throw WritebackError.missingMatch(name: replacement.debugName, path: path)
        }

        var next = source
        next.replaceSubrange(swiftRange, with: replacement.renderedValue)
        return next
    }

    private func formatted(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.4f", value).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression).replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}
