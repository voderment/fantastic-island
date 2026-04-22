import Foundation
import CoreGraphics
import SwiftUI

// Adapted from Open Island:
// https://github.com/Octane0411/open-vibe-island
// Original file: Sources/OpenIslandApp/IslandChromeMetrics.swift
// Upstream license: GPL-3.0
// Modified for Fantastic Island on 2026-04-13.
@MainActor
enum CodexIslandChromeMetrics {
    static let defaultOpenedShadowHorizontalInset: CGFloat = 18
    static let defaultOpenedShadowBottomInset: CGFloat = 0 // 展开态外层阴影为面板额外占用的底部空间
    static let defaultOpenedSurfaceBottomInset: CGFloat = 0 // 展开态黑色壳体本身相对底边预留的安全距离
    static let defaultOpenedSurfaceContentHorizontalInset: CGFloat = 22
    static let defaultClosedHoverScale: CGFloat = 1.028
    static let defaultClosedHorizontalPadding: CGFloat = 20
    static let defaultClosedFanModuleSpacing: CGFloat = 16
    static let defaultClosedModuleSpacing: CGFloat = 8
    static let defaultClosedModuleContentSpacing: CGFloat = 8
    static let defaultClosedIconSize: CGFloat = 18
    static let defaultClosedPrimaryFontSize: CGFloat = 10
    static let defaultClosedTrafficFontSize: CGFloat = 8.5
    static let defaultClosedTrafficLineSpacing: CGFloat = 1
    static let defaultOpenedBodyRevealDelay: CGFloat = 0.05
    static let defaultOpenLayoutSettleDuration: CGFloat = 0.46
    static let defaultCloseLayoutSettleDuration: CGFloat = 0.3

    static let defaultExpandedContentBottomPadding: CGFloat = 20
    static let defaultExpandedContentTopPadding: CGFloat = 10

    static let defaultModuleColumnSpacing: CGFloat = 20
    static let defaultModuleNavigationRowHeight: CGFloat = 38

    static let defaultModuleTabSpacing: CGFloat = 10
    static let defaultModuleTabHorizontalPadding: CGFloat = 16
    static let defaultModuleTabVerticalPadding: CGFloat = 9
    static let defaultModuleHeaderToolbarSpacing: CGFloat = 16
    static let defaultModuleToolbarButtonGroupSpacing: CGFloat = 12

    static let defaultPreferredTallModuleOpenedContentHeight: CGFloat = 560 // 高内容模块的默认目标展开高度

    static var openedShadowHorizontalInset: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.openedShadowHorizontalInset) }
    static var openedShadowBottomInset: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.openedShadowBottomInset) }
    static var openedSurfaceBottomInset: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.openedSurfaceBottomInset) }
    static var openedSurfaceContentHorizontalInset: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.openedSurfaceContentHorizontalInset) }
    static var closedHoverScale: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedHoverScale) }
    static var closedHorizontalPadding: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedHorizontalPadding) }
    static var closedFanModuleSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedFanModuleSpacing) }
    static var closedModuleSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedModuleSpacing) }
    static var closedModuleContentSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedModuleContentSpacing) }
    static var closedIconSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedIconSize) }
    static var closedPrimaryFontSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedPrimaryFontSize) }
    static var closedTrafficFontSize: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedTrafficFontSize) }
    static var closedTrafficLineSpacing: CGFloat { CGFloat(IslandDesignTokenRuntime.current.shell.closedTrafficLineSpacing) }
    static var compactClashTrafficBlockWidth: CGFloat { max(54, ceil(closedTrafficFontSize * 6.4)) }
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

    static var windDrivePanelSide: CGFloat { CGFloat(IslandDesignTokenRuntime.current.windDrive.panelSide) }
    static var preferredTallModuleOpenedContentHeight: CGFloat { defaultPreferredTallModuleOpenedContentHeight }

    static var moduleChromeHeight: CGFloat =
        expandedContentTopPadding + moduleColumnSpacing + moduleNavigationRowHeight
    static var windDrivePanelWidth: CGFloat { windDrivePanelSide }
    static var windDrivePanelHeight: CGFloat { windDrivePanelSide }
    static var minimumExpandedHeightWithWindDrivePanel: CGFloat =
        expandedContentTopPadding + windDrivePanelHeight + expandedContentBottomPadding
}

@MainActor
enum CodexIslandPeekMetrics {
    static let defaultContentHorizontalInset: CGFloat = 16
    static let defaultContentTopPadding: CGFloat = 10
    static let defaultContentBottomPadding: CGFloat = 16

    static let defaultMinimumContentWidth: CGFloat = 420
    static let defaultMaximumContentWidth: CGFloat = 480
    static let defaultContentWidthFactor: CGFloat = 0.32

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
        ) // 等尾段所有可见动画结束后，再真正移除 peek 渲染快照，避免最后一拍卡顿

    static var openAnimation: Animation { .snappy(duration: openAnimationDuration, extraBounce: 0) }
    static var closeAnimation: Animation { .smooth(duration: closeAnimationDuration) }
    static var chromeRevealAnimation: Animation { .easeOut(duration: chromeRevealAnimationDuration) }
    static var bodyCloseFadeAnimation: Animation { .easeOut(duration: bodyCloseFadeDuration) }
    static var closedHeaderRevealAnimation: Animation { .easeOut(duration: closedHeaderRevealDuration) }
}
