import Foundation
import CoreGraphics
import SwiftUI

// Copyright 2026 Fantastic Island contributors
// Portions adapted from open-vibe-island contributors
//
// This file is part of Fantastic Island.
//
// Fantastic Island is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3.
//
// Fantastic Island is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Fantastic Island. If not, see <https://www.gnu.org/licenses/>.
//
// This file adapts work from open-vibe-island:
// https://github.com/Octane0411/open-vibe-island
// Original file: Sources/OpenIslandApp/IslandChromeMetrics.swift
// Modified for Fantastic Island on 2026-04-13.
@MainActor
enum CodexIslandChromeMetrics {
    static let defaultOpenedShadowHorizontalInset: CGFloat = 0
    static let defaultOpenedShadowBottomInset: CGFloat = 0
    static let defaultOpenedSurfaceBottomInset: CGFloat = 0
    static let defaultOpenedSurfaceContentHorizontalInset: CGFloat = 14
    static let defaultClosedHoverScale: CGFloat = 1.014
    static let defaultClosedHorizontalPadding: CGFloat = 14
    static let defaultClosedModuleSpacing: CGFloat = 6
    static let defaultClosedModuleContentSpacing: CGFloat = 6
    static let defaultClosedIconSize: CGFloat = 16
    static let defaultClosedPrimaryFontSize: CGFloat = 10
    static let defaultClosedSecondaryFontSize: CGFloat = 8.5
    static let defaultClosedSecondaryLineSpacing: CGFloat = 1
    static let defaultOpenedBodyRevealDelay: CGFloat = 0.05
    static let defaultOpenLayoutSettleDuration: CGFloat = 0.46
    static let defaultCloseLayoutSettleDuration: CGFloat = 0.3

    static let defaultExpandedContentBottomPadding: CGFloat = 14
    static let defaultExpandedContentTopPadding: CGFloat = 8

    static let defaultModuleColumnSpacing: CGFloat = 12
    static let defaultModuleNavigationRowHeight: CGFloat = 28

    static let defaultModuleTabSpacing: CGFloat = 6
    static let defaultModuleTabHorizontalPadding: CGFloat = 10
    static let defaultModuleTabVerticalPadding: CGFloat = 5
    static let defaultModuleHeaderToolbarSpacing: CGFloat = 8
    static let defaultModuleToolbarButtonGroupSpacing: CGFloat = 8

    static let defaultPreferredTallModuleOpenedContentHeight: CGFloat = 460
    static let defaultMinimumExpandedContentWidth: CGFloat = 340

    static var openedShadowHorizontalInset: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.openedShadowHorizontalInset) }
    static var openedShadowBottomInset: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.openedShadowBottomInset) }
    static var openedSurfaceBottomInset: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.openedSurfaceBottomInset) }
    static var openedSurfaceContentHorizontalInset: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.openedSurfaceContentHorizontalInset) }
    static var closedHoverScale: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedHoverScale) }
    static var closedHorizontalPadding: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedHorizontalPadding) }
    static var closedModuleSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedModuleSpacing) }
    static var closedModuleContentSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedModuleContentSpacing) }
    static var closedIconSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedIconSize) }
    static var closedPrimaryFontSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedPrimaryFontSize) }
    static var closedSecondaryFontSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedSecondaryFontSize) }
    static var closedSecondaryLineSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedSecondaryLineSpacing) }
    static var compactSecondaryBlockWidth: CGFloat { max(54, ceil(closedSecondaryFontSize * 6.4)) }
    static var openedBodyRevealDelay: TimeInterval { IslandDesignTokenRuntime.current.shell.openedBodyRevealDelay }
    static var openLayoutSettleDuration: TimeInterval { IslandDesignTokenRuntime.current.shell.openLayoutSettleDuration }
    static var openedChromeRevealDelay: TimeInterval { openedBodyRevealDelay }
    static var closeLayoutSettleDuration: TimeInterval { IslandDesignTokenRuntime.current.shell.closeLayoutSettleDuration }

    static var expandedContentBottomPadding: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.expandedContentBottomPadding) }
    static var expandedContentHorizontalInset: CGFloat { openedSurfaceContentHorizontalInset }
    static var expandedContentTopPadding: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.expandedContentTopPadding) }

    static var moduleColumnSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.moduleColumnSpacing) }
    static var moduleNavigationRowHeight: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.moduleNavigationRowHeight) }

    static var moduleTabSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.moduleTabSpacing) }
    static var moduleTabHorizontalPadding: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.moduleTabHorizontalPadding) }
    static var moduleTabVerticalPadding: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.moduleTabVerticalPadding) }
    static var moduleHeaderToolbarSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.moduleHeaderToolbarSpacing) }
    static var moduleToolbarButtonGroupSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.moduleToolbarButtonGroupSpacing) }

    static var preferredTallModuleOpenedContentHeight: CGFloat { defaultPreferredTallModuleOpenedContentHeight }
    static var minimumExpandedContentWidth: CGFloat { defaultMinimumExpandedContentWidth }

    static var moduleChromeHeight: CGFloat =
        expandedContentTopPadding + moduleColumnSpacing + moduleNavigationRowHeight

    static func resolvedExpandedContentWidth(baseContentWidth: CGFloat) -> CGFloat {
        max(minimumExpandedContentWidth, baseContentWidth)
    }
}

@MainActor
enum CodexIslandPeekMetrics {
    static let defaultContentHorizontalInset: CGFloat = 12
    static let defaultContentTopPadding: CGFloat = 8
    static let defaultContentBottomPadding: CGFloat = 12

    static let defaultMinimumContentWidth: CGFloat = 340
    static let defaultMaximumContentWidth: CGFloat = 430
    static let defaultContentWidthFactor: CGFloat = 0.28

    static let defaultOpenAnimationDuration: CGFloat = 0.3
    static let defaultCloseAnimationDuration: CGFloat = 0.26
    static let defaultChromeRevealAnimationDuration: CGFloat = 0.1
    static let defaultBodyCloseFadeDuration: CGFloat = 0.05
    static let defaultClosedHeaderRevealDuration: CGFloat = 0.22
    static let defaultClosedHeaderRevealLeadTime: CGFloat = 0.15

    static var contentHorizontalInset: CGFloat { CGFloat(IslandDesignTokenRuntime.current.peek.contentHorizontalInset) }
    static var contentTopPadding: CGFloat { CGFloat(IslandDesignTokenRuntime.current.peek.contentTopPadding) }
    static var contentBottomPadding: CGFloat { CGFloat(IslandDesignTokenRuntime.current.peek.contentBottomPadding) }

    static var minimumContentWidth: CGFloat { CGFloat(IslandDesignTokenRuntime.current.peek.minimumContentWidth) }
    static var maximumContentWidth: CGFloat { CGFloat(IslandDesignTokenRuntime.current.peek.maximumContentWidth) }
    static var contentWidthFactor: CGFloat { CGFloat(IslandDesignTokenRuntime.current.peek.contentWidthFactor) }

    static var openAnimationDuration: TimeInterval { IslandDesignTokenRuntime.current.peek.openAnimationDuration }
    static var closeAnimationDuration: TimeInterval { IslandDesignTokenRuntime.current.peek.closeAnimationDuration }
    static var chromeRevealAnimationDuration: TimeInterval { IslandDesignTokenRuntime.current.peek.chromeRevealAnimationDuration }
    static var bodyCloseFadeDuration: TimeInterval { IslandDesignTokenRuntime.current.peek.bodyCloseFadeDuration }
    static var closedHeaderRevealDuration: TimeInterval { IslandDesignTokenRuntime.current.peek.closedHeaderRevealDuration }
    static var closedHeaderRevealLeadTime: TimeInterval { IslandDesignTokenRuntime.current.peek.closedHeaderRevealLeadTime }

    static var renderCleanupDelay: TimeInterval =
        max(
            closeAnimationDuration,
            closeAnimationDuration - closedHeaderRevealLeadTime + closedHeaderRevealDuration
        )

    static var openAnimation: Animation { .snappy(duration: openAnimationDuration, extraBounce: 0) }
    static var closeAnimation: Animation { .smooth(duration: closeAnimationDuration) }
    static var chromeRevealAnimation: Animation { .easeOut(duration: chromeRevealAnimationDuration) }
    static var bodyCloseFadeAnimation: Animation { .easeOut(duration: bodyCloseFadeDuration) }
    static var closedHeaderRevealAnimation: Animation { .easeOut(duration: closedHeaderRevealDuration) }
}
