import SwiftUI

private let islandOpenAnimation = CodexIslandPeekMetrics.openAnimation
private let islandCloseAnimation = CodexIslandPeekMetrics.closeAnimation
private let openedChromeRevealAnimation = CodexIslandPeekMetrics.chromeRevealAnimation
private let peekBodyCloseFadeAnimation = CodexIslandPeekMetrics.bodyCloseFadeAnimation
private let closedHeaderRevealAnimation = CodexIslandPeekMetrics.closedHeaderRevealAnimation

private struct ModuleContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private struct PremeasuredModuleContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private struct PeekContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private enum IslandShellVisualMode: Equatable {
    case closed
    case peek
    case expanded
}

private struct PeekRenderState {
    let activity: IslandActivity
}

// This notch surface is adapted from Open Island's island panel approach:
// https://github.com/Octane0411/open-vibe-island
// Original file: Sources/OpenIslandApp/Views/IslandPanelView.swift
// Upstream license: GPL-3.0
// Modified for island on 2026-04-14.
struct IslandShellView: View {
    @ObservedObject var model: IslandAppModel
    let compactWidth: CGFloat
    let closedHeight: CGFloat
    let expandedContentWidth: CGFloat
    let peekContentWidth: CGFloat

    @State private var isHovering = false
    @State private var visualMode: IslandShellVisualMode = .closed
    @State private var peekRenderState: PeekRenderState?
    @State private var showsClosedHeader = true
    @State private var showsPeekBody = false
    @State private var showsExpandedBody = false
    @State private var pendingExpandedBodyReveal: DispatchWorkItem?
    @State private var pendingClosedHeaderReveal: DispatchWorkItem?
    @State private var pendingRenderCleanup: DispatchWorkItem?
    @State private var moduleScrollOffset: CGFloat = 0

    private var usesOpenedVisualState: Bool {
        visualMode != .closed
    }

    private var usesExpandedLayoutBounds: Bool {
        usesOpenedVisualState || model.islandExpansionAnimationInFlight || model.islandCollapseAnimationInFlight
    }

    private var islandTransitionAnimation: Animation {
        switch visualMode {
        case .closed:
            return islandCloseAnimation
        case .peek, .expanded:
            return islandOpenAnimation
        }
    }

    private var closedContentWidth: CGFloat {
        model.closedSurfaceWidth(baseCompactWidth: compactWidth)
    }

    private var renderedPeekActivity: IslandActivity? {
        peekRenderState?.activity ?? model.presentedPeekActivity
    }

    private var renderedPeekContentHeight: CGFloat {
        guard let activity = renderedPeekActivity else {
            return closedHeight
        }

        return model.peekContentHeight(for: activity)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.clear
                shellContent(availableSize: geometry.size)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .environment(\.locale, model.resolvedLocale)
    }

    @ViewBuilder
    private func shellContent(availableSize: CGSize) -> some View {
        let panelShadowHorizontalInset = usesExpandedLayoutBounds ? CodexIslandChromeMetrics.openedShadowHorizontalInset : 0
        let panelShadowBottomInset = usesExpandedLayoutBounds ? CodexIslandChromeMetrics.openedShadowBottomInset : 0
        let layoutWidth = max(0, availableSize.width - (panelShadowHorizontalInset * 2))
        let layoutHeight = max(0, availableSize.height - panelShadowBottomInset)
        let openSurfaceHorizontalInset = CodexIslandChromeMetrics.openedSurfaceContentHorizontalInset

        let closedTotalWidth = closedContentWidth
        let expandedSurfaceWidth = min(
            layoutWidth,
            expandedContentWidth + (openSurfaceHorizontalInset * 2)
        )
        let peekSurfaceWidth = min(
            layoutWidth,
            peekContentWidth + (openSurfaceHorizontalInset * 2)
        )
        let expandedSurfaceHeight = min(
            layoutHeight,
            max(closedHeight, model.selectedModuleContentHeight + CodexIslandChromeMetrics.openedSurfaceBottomInset)
        )
        let peekSurfaceHeight = min(
            layoutHeight,
            max(closedHeight, renderedPeekContentHeight + CodexIslandChromeMetrics.openedSurfaceBottomInset)
        )

        let surfaceMetrics: (width: CGFloat, height: CGFloat) = {
            switch visualMode {
            case .closed:
                return (closedTotalWidth, closedHeight)
            case .peek:
                return (peekSurfaceWidth, peekSurfaceHeight)
            case .expanded:
                return (expandedSurfaceWidth, expandedSurfaceHeight)
            }
        }()
        let surfaceWidth = surfaceMetrics.width
        let surfaceHeight = surfaceMetrics.height

        let openBodyWidth = max(0, surfaceWidth - (openSurfaceHorizontalInset * 2))
        let premeasuredModuleColumnWidth = expandedModuleColumnWidth(for: expandedContentWidth)
        let surfaceShape = CodexNotchShape(
            topCornerRadius: usesOpenedVisualState ? CodexNotchShape.openedTopRadius : CodexNotchShape.closedTopRadius,
            bottomCornerRadius: usesOpenedVisualState ? CodexNotchShape.openedBottomRadius : CodexNotchShape.closedBottomRadius
        )

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                surfaceShape
                    .fill(Color.black)
                    .frame(width: surfaceWidth, height: surfaceHeight)

                ZStack(alignment: .top) {
                    headerRow
                        .frame(width: closedTotalWidth, alignment: .center)
                        .frame(height: closedHeight)
                        .frame(maxWidth: .infinity, alignment: .top)

                    expandedContent
                        .frame(width: openBodyWidth, height: surfaceHeight, alignment: .top)
                        .clipped()
                }
                .frame(width: surfaceWidth, height: surfaceHeight, alignment: .top)
                .clipShape(surfaceShape)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 1)
                        .padding(.horizontal, usesOpenedVisualState ? CodexNotchShape.openedTopRadius : CodexNotchShape.closedTopRadius)
                }
                .overlay {
                    surfaceShape
                        .strokeBorder(Color.white.opacity(usesOpenedVisualState ? 0.07 : 0.04), lineWidth: 1)
                }
            }
            .frame(width: surfaceWidth, height: surfaceHeight, alignment: .top)
        }
        .scaleEffect(usesOpenedVisualState ? 1 : (isHovering ? CodexIslandChromeMetrics.closedHoverScale : 1), anchor: .top)
        .padding(.horizontal, panelShadowHorizontalInset)
        .padding(.bottom, panelShadowBottomInset)
        .animation(islandTransitionAnimation, value: visualMode)
        .overlay(alignment: .topLeading) {
            collapsedModulePremeasurementView(width: premeasuredModuleColumnWidth)
        }
        .onPreferenceChange(PremeasuredModuleContentHeightKey.self) { height in
            let selectedModule = model.selectedModule
            model.updateMeasuredModuleContentHeight(
                height,
                for: selectedModule.id,
                presentation: model.selectedModulePresentationContext
            )
        }
        .contentShape(Rectangle())
        .onAppear {
            syncRenderState(immediate: true)
        }
        .onChange(of: model.islandExpanded) { _, _ in
            syncRenderState(immediate: false)
        }
        .onChange(of: model.islandPeeking) { _, _ in
            syncRenderState(immediate: false)
        }
        .onChange(of: model.presentedActivity?.id) { _, _ in
            if model.islandPeeking {
                syncRenderState(immediate: false)
            }
        }
        .onDisappear {
            cancelPendingRenderWork()
            visualMode = .closed
            showsExpandedBody = false
            showsClosedHeader = true
            showsPeekBody = false
            peekRenderState = nil
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            if !model.islandExpanded {
                model.expandIsland(reason: .manualTap)
            }
        }
    }

    private func cancelPendingRenderWork() {
        pendingExpandedBodyReveal?.cancel()
        pendingExpandedBodyReveal = nil
        pendingClosedHeaderReveal?.cancel()
        pendingClosedHeaderReveal = nil
        pendingRenderCleanup?.cancel()
        pendingRenderCleanup = nil
    }

    private func syncRenderState(immediate: Bool) {
        cancelPendingRenderWork()

        if model.islandExpanded {
            transitionToExpanded(immediate: immediate)
            return
        }

        if model.islandPeeking, let activity = model.presentedPeekActivity {
            transitionToPeek(activity: activity, immediate: immediate)
            return
        }

        transitionToClosed(immediate: immediate)
    }

    private func transitionToPeek(activity: IslandActivity, immediate: Bool) {
        let isSameActivity = peekRenderState?.activity.id == activity.id
        peekRenderState = PeekRenderState(activity: activity)
        showsExpandedBody = false

        guard !immediate else {
            visualMode = .peek
            showsClosedHeader = false
            showsPeekBody = true
            return
        }

        if visualMode == .peek, isSameActivity {
            showsClosedHeader = false
            showsPeekBody = true
            return
        }

        withAnimation(islandOpenAnimation) {
            visualMode = .peek
            showsClosedHeader = false
            showsPeekBody = true
        }
    }

    private func transitionToExpanded(immediate: Bool) {
        guard !immediate else {
            visualMode = .expanded
            showsClosedHeader = false
            showsPeekBody = false
            showsExpandedBody = true
            peekRenderState = nil
            return
        }

        if visualMode == .expanded, showsExpandedBody, peekRenderState == nil {
            showsClosedHeader = false
            showsPeekBody = false
            return
        }

        withAnimation(islandOpenAnimation) {
            visualMode = .expanded
            showsClosedHeader = false
            showsPeekBody = false
        }

        let reveal = DispatchWorkItem {
            withAnimation(openedChromeRevealAnimation) {
                showsExpandedBody = true
            }

            guard peekRenderState != nil else {
                return
            }

            let cleanup = DispatchWorkItem {
                if visualMode == .expanded {
                    peekRenderState = nil
                }
            }

            pendingRenderCleanup = cleanup
            DispatchQueue.main.asyncAfter(
                deadline: .now() + CodexIslandPeekMetrics.chromeRevealAnimationDuration,
                execute: cleanup
            )
        }

        pendingExpandedBodyReveal = reveal
        DispatchQueue.main.asyncAfter(
            deadline: .now() + CodexIslandChromeMetrics.openedChromeRevealDelay,
            execute: reveal
        )
    }

    private func transitionToClosed(immediate: Bool) {
        let hadPeekSnapshot = peekRenderState != nil
        let wasOpen = visualMode != .closed || showsExpandedBody || hadPeekSnapshot || !showsClosedHeader || showsPeekBody

        guard !immediate else {
            visualMode = .closed
            showsClosedHeader = true
            showsPeekBody = false
            showsExpandedBody = false
            peekRenderState = nil
            return
        }

        guard wasOpen else {
            visualMode = .closed
            showsClosedHeader = true
            showsPeekBody = false
            showsExpandedBody = false
            peekRenderState = nil
            return
        }

        showsExpandedBody = false
        withAnimation(peekBodyCloseFadeAnimation) {
            showsPeekBody = false
        }
        withAnimation(islandCloseAnimation) {
            visualMode = .closed
            showsClosedHeader = false
        }

        let headerReveal = DispatchWorkItem {
            if visualMode == .closed {
                withAnimation(closedHeaderRevealAnimation) {
                    showsClosedHeader = true
                }
            }
        }
        pendingClosedHeaderReveal = headerReveal
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, CodexIslandPeekMetrics.closeAnimationDuration - CodexIslandPeekMetrics.closedHeaderRevealLeadTime),
            execute: headerReveal
        )

        let completion = DispatchWorkItem {
            if visualMode == .closed {
                peekRenderState = nil
            }
        }

        pendingRenderCleanup = completion
        DispatchQueue.main.asyncAfter(
            deadline: .now() + CodexIslandPeekMetrics.renderCleanupDelay,
            execute: completion
        )
    }

    @ViewBuilder
    private var headerRow: some View {
        IslandClosedHeaderView(
            state: IslandShellClosedHeaderRenderState(
                fanAnimationState: model.fanAnimationState,
                compactModules: model.visibleCompactModules
            )
        )
            .opacity(showsClosedHeader ? 1 : 0)
            .allowsHitTesting(visualMode == .closed && showsClosedHeader)
            .frame(height: closedHeight)
            .clipped()
    }

    private var expandedContent: some View {
        ZStack(alignment: .topLeading) {
            if let peekRenderState,
               let module = model.peekModule(for: peekRenderState.activity) {
                peekContent(activity: peekRenderState.activity, module: module)
                    .opacity(showsPeekBody ? 1 : 0)
                    .padding(.horizontal, CodexIslandPeekMetrics.contentHorizontalInset) // peek 内容的左右边距由壳层统一提供
                    .padding(.bottom, CodexIslandPeekMetrics.contentBottomPadding) // peek 内容的底部留白由容器统一控制
            }

            if showsExpandedBody || visualMode == .expanded {
                mainContentSection
                    .opacity(showsExpandedBody && visualMode == .expanded ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, visualMode == .peek ? CodexIslandPeekMetrics.contentTopPadding : CodexIslandChromeMetrics.expandedContentTopPadding) // peek 与 expanded 分别使用各自的顶部留白
        .foregroundStyle(.white)
        .allowsHitTesting(
            (model.islandExpanded && visualMode == .expanded && showsExpandedBody)
                || (model.isInteractivePeeking && visualMode == .peek)
        )
    }

    private func peekContent(activity: IslandActivity, module: any IslandModule) -> some View {
        module.makeContentView(presentation: .peek(activity))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: PeekContentHeightKey.self, value: geometry.size.height)
                }
            }
            .onPreferenceChange(PeekContentHeightKey.self) { height in
                model.updateMeasuredModuleContentHeight(
                    height,
                    for: module.id,
                    presentation: .peek(activity)
                )
            }
    }

    private var mainContentSection: some View {
        HStack(alignment: .top, spacing: model.showsExpandedWindDrivePanel ? CodexIslandChromeMetrics.moduleColumnSpacing : 0) { // Wind Drive 与右侧内容列的间距
            if model.showsExpandedWindDrivePanel {
                fanColumn
                    .frame(width: CodexIslandChromeMetrics.windDrivePanelWidth, alignment: .top)
            }
            rightColumn
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, CodexIslandChromeMetrics.expandedContentHorizontalInset) // 展开态主容器统一左右边距，模块自己不要再加外层 horizontal padding
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var fanColumn: some View {
        fanPanel
    }

    private var fanPanel: some View {
        IslandWindDrivePanelView(
            state: IslandWindDrivePanelRenderState(
                animationState: model.fanAnimationState,
                logoPreset: model.windDriveLogoPreset,
                customImage: model.usesCustomWindDriveLogo ? model.windDriveCustomLogoImage : nil
            )
        )
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: CodexIslandChromeMetrics.moduleColumnSpacing) { // tab/header 行与模块内容区的纵向间距
            expandedNavigationRow

            moduleContentViewport
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var moduleContentViewport: some View {
        let selectedModule = model.selectedModule
        let presentation = model.selectedModulePresentationContext

        return Group {
            if model.selectedModuleNeedsScrolling {
                ScrollViewReader { proxy in
                    ScrollView {
                        moduleContentStack(
                            selectedModule: selectedModule,
                            presentation: presentation,
                            scrollAction: IslandModuleScrollAction { id, anchor in
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    proxy.scrollTo(id, anchor: anchor)
                                }
                            },
                            scrollOffset: moduleScrollOffset
                        )
                    }
                    .coordinateSpace(name: IslandModuleScrollCoordinateSpace.name)
                    .onScrollGeometryChange(for: CGFloat.self, of: { geometry in
                        max(0, geometry.contentOffset.y)
                    }, action: { _, newValue in
                        moduleScrollOffset = newValue
                    })
                    .scrollIndicators(.automatic)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: model.selectedModuleViewportHeight,
                        maxHeight: model.selectedModuleViewportHeight,
                        alignment: .topLeading
                    )
                }
            } else {
                moduleContentStack(
                    selectedModule: selectedModule,
                    presentation: presentation,
                    scrollAction: IslandModuleScrollAction(),
                    scrollOffset: 0
                )
                .onAppear {
                    moduleScrollOffset = 0
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: selectedModule.id) { _, _ in
            moduleScrollOffset = 0
        }
        .onChange(of: model.selectedModuleNeedsScrolling) { _, needsScrolling in
            if !needsScrolling {
                moduleScrollOffset = 0
            }
        }
        .onPreferenceChange(ModuleContentHeightKey.self) { height in
            model.updateMeasuredModuleContentHeight(
                height,
                for: selectedModule.id,
                presentation: presentation
            )
        }
    }

    private func moduleContentStack(
        selectedModule: any IslandModule,
        presentation: IslandModulePresentationContext,
        scrollAction: IslandModuleScrollAction,
        scrollOffset: CGFloat
    ) -> some View {
        selectedModule.makeContentView(presentation: presentation)
            .environment(\.islandModuleScrollAction, scrollAction)
            .environment(\.islandModuleScrollOffset, scrollOffset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: ModuleContentHeightKey.self, value: geometry.size.height)
                }
            }
            .padding(.bottom, CodexIslandChromeMetrics.expandedContentBottomPadding) // 模块内容容器自己的底部留白，不再使用假 spacer 撑高度
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func collapsedModulePremeasurementView(width: CGFloat) -> some View {
        let selectedModule = model.selectedModule
        let presentation = model.selectedModulePresentationContext

        if shouldPremeasureModuleContent(width: width) {
            VStack(alignment: .leading, spacing: 0) {
                selectedModule.makeContentView(presentation: presentation)
            }
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: PremeasuredModuleContentHeightKey.self, value: geometry.size.height)
                }
            }
            .opacity(0.001)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func shouldPremeasureModuleContent(width: CGFloat) -> Bool {
        width > 0
            && !model.islandExpanded
            && !model.islandPeeking
            && !model.islandExpansionAnimationInFlight
            && !model.islandCollapseAnimationInFlight
    }

    private func expandedModuleColumnWidth(for openedWidth: CGFloat) -> CGFloat {
        let expandedBodyWidth = max(0, openedWidth - (CodexIslandChromeMetrics.expandedContentHorizontalInset * 2))
        let leadingColumnWidth =
            model.showsExpandedWindDrivePanel
            ? CodexIslandChromeMetrics.windDrivePanelWidth + CodexIslandChromeMetrics.moduleColumnSpacing
            : 0
        return max(0, expandedBodyWidth - leadingColumnWidth)
    }

    private var moduleTabRow: some View {
        IslandExpandedNavigationView(
            state: IslandShellExpandedNavigationRenderState(
                tabs: model.enabledModules.map { module in
                    IslandShellTabRenderState(
                        id: module.id,
                        title: module.title,
                        symbolName: module.symbolName,
                        iconAssetName: module.iconAssetName,
                        isSelected: model.selectedModuleID == module.id,
                        showsPendingBadge: model.moduleHasPendingBadge(module.id),
                        action: { model.selectModule(id: module.id) }
                    )
                },
                openSettings: model.openSettings
            )
        )
    }

    private var expandedNavigationRow: some View {
        moduleTabRow
    }

    private var toolbarButtonSize: CGFloat { 28 }

    private var actionToolbar: some View {
        EmptyView()
    }
}
