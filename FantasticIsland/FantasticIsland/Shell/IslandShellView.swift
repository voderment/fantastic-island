import SwiftUI

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
// Original file: Sources/OpenIslandApp/Views/IslandPanelView.swift
// Modified for Fantastic Island on 2026-04-14.
struct IslandShellView: View {
    @ObservedObject var model: IslandAppModel
    let compactWidth: CGFloat
    let closedHeight: CGFloat
    let expandedContentWidth: CGFloat
    let peekContentWidth: CGFloat
    let expandedContentTopClearance: CGFloat
    let closedContentNotchExclusionWidth: CGFloat

    @State private var isHovering = false
    @State private var moduleScrollOffsets: [String: CGFloat] = [:]

    private var usesOpenedVisualState: Bool {
        visualMode != .closed
    }

    private var usesExpandedLayoutBounds: Bool {
        usesOpenedVisualState || model.islandLayoutTransitionInFlight
    }

    private var closedContentWidth: CGFloat {
        model.closedSurfaceWidth(
            baseCompactWidth: compactWidth,
            hardwareNotchExclusionWidth: closedContentNotchExclusionWidth
        )
    }

    private var transitionPlan: IslandTransitionPlan? {
        model.currentTransitionPlan
    }

    private var visualMode: IslandPresentationVisualMode {
        if let transitionPlan {
            switch model.transitionPhase {
            case .morphing, .revealingContent:
                return transitionPlan.to.visualMode
            case .preparing, .stable:
                return transitionPlan.from.visualMode
            }
        }

        return model.renderedPresentationState.visualMode
    }

    private var outgoingPeekSnapshot: IslandModuleRenderSnapshot? {
        guard let transitionPlan,
              transitionPlan.from.visualMode == .peek,
              transitionPlan.to.visualMode != .closed else {
            return nil
        }

        return model.activePeekSnapshot
    }

    private var incomingPeekSnapshot: IslandModuleRenderSnapshot? {
        if transitionPlan?.to.visualMode == .peek {
            return model.frozenPeekSnapshot
        }

        return transitionPlan == nil ? model.currentPeekSnapshot : nil
    }

    private var outgoingExpandedSnapshot: IslandModuleRenderSnapshot? {
        guard transitionPlan?.from.visualMode == .expanded else {
            return nil
        }

        return model.activeExpandedSnapshot
    }

    private var incomingExpandedSnapshot: IslandModuleRenderSnapshot? {
        if transitionPlan?.to.visualMode == .expanded {
            return model.frozenExpandedSnapshot
        }

        return transitionPlan == nil && model.islandExpanded ? model.currentExpandedSnapshot : nil
    }

    private var renderedPeekContentHeight: CGFloat {
        if let transitionPlan,
           transitionPlan.to.visualMode == .peek || transitionPlan.from.visualMode == .peek {
            return transitionPlan.lockedHeight
        }

        return model.peekContentHeight
    }

    private var showsClosedHeader: Bool {
        guard let transitionPlan else {
            return visualMode == .closed
        }

        if transitionPlan.to == .closed {
            return model.transitionPhase == .revealingContent || model.transitionPhase == .stable
        }

        return model.transitionPhase == .preparing && transitionPlan.from == .closed
    }

    private var stableLiveExpandedVisible: Bool {
        model.islandExpanded && transitionPlan == nil && model.transitionPhase == .stable
    }

    private var expandedLiveHostsMounted: Bool {
        if stableLiveExpandedVisible {
            return true
        }

        guard let transitionPlan else {
            return false
        }

        return transitionPlan.from.visualMode == .expanded
            && transitionPlan.to.visualMode == .expanded
    }

    private var showsExpandedChrome: Bool {
        guard let transitionPlan else {
            return model.islandExpanded
        }

        return transitionPlan.from.visualMode == .expanded
            || transitionPlan.to.visualMode == .expanded
    }

    private var expandedChromeOpacity: Double {
        guard let transitionPlan else {
            return model.islandExpanded ? 1 : 0
        }

        if transitionPlan.from.visualMode == .expanded,
           transitionPlan.to.visualMode == .expanded {
            return 1
        }

        if transitionPlan.to.visualMode == .expanded {
            return model.transitionPhase == .revealingContent || model.transitionPhase == .stable ? 1 : 0
        }

        if transitionPlan.from.visualMode == .expanded,
           transitionPlan.to.visualMode == .peek {
            return model.transitionPhase == .revealingContent || model.transitionPhase == .stable ? 0 : 1
        }

        return 0
    }

    private var expandedContentAllowsHitTesting: Bool {
        if stableLiveExpandedVisible {
            return true
        }

        if let transitionPlan,
           transitionPlan.from.visualMode == .expanded,
           transitionPlan.to.visualMode == .expanded {
            return true
        }

        return model.peekCapturesMouseEvents && transitionPlan == nil && visualMode == .peek
    }

    private var outgoingPeekOpacity: Double {
        guard let transitionPlan, transitionPlan.from.visualMode == .peek else {
            return 0
        }

        switch transitionPlan.to.visualMode {
        case .peek, .expanded:
            return model.transitionPhase == .revealingContent || model.transitionPhase == .stable ? 0 : 1
        case .closed:
            return 0
        }
    }

    private var incomingPeekOpacity: Double {
        guard incomingPeekSnapshot != nil else {
            return 0
        }

        if transitionPlan == nil {
            return visualMode == .peek ? 1 : 0
        }

        return model.transitionPhase == .revealingContent || model.transitionPhase == .stable ? 1 : 0
    }

    private var outgoingExpandedOpacity: Double {
        guard let transitionPlan, transitionPlan.from.visualMode == .expanded else {
            return 0
        }

        switch transitionPlan.to.visualMode {
        case .expanded, .peek:
            return model.transitionPhase == .revealingContent || model.transitionPhase == .stable ? 0 : 1
        case .closed:
            return 0
        }
    }

    private var incomingExpandedOpacity: Double {
        guard incomingExpandedSnapshot != nil else {
            return 0
        }

        if transitionPlan == nil {
            return 0
        }

        return model.transitionPhase == .revealingContent || model.transitionPhase == .stable ? 1 : 0
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
        let resolvedExpandedContentWidth = CodexIslandChromeMetrics.resolvedExpandedContentWidth(
            baseContentWidth: expandedContentWidth,
            showsWindDrivePanel: model.showsExpandedWindDrivePanel
        )
        let expandedSurfaceWidth = min(
            layoutWidth,
            resolvedExpandedContentWidth + (openSurfaceHorizontalInset * 2)
        )
        let peekSurfaceWidth = min(
            layoutWidth,
            peekContentWidth + (openSurfaceHorizontalInset * 2)
        )
        let expandedSurfaceHeight = min(
            layoutHeight,
            max(
                closedHeight,
                model.selectedModuleContentHeight
                    + expandedContentTopClearance
                    + CodexIslandChromeMetrics.openedSurfaceBottomInset
            )
        )
        let peekSurfaceHeight = min(
            layoutHeight,
            max(
                closedHeight,
                renderedPeekContentHeight
                    + expandedContentTopClearance
                    + CodexIslandChromeMetrics.openedSurfaceBottomInset
            )
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
        let targetOpenBodyWidth = max(0, expandedSurfaceWidth - (openSurfaceHorizontalInset * 2))
        let expandedContentFrameWidth: CGFloat = {
            guard let transitionPlan else {
                return visualMode == .expanded ? targetOpenBodyWidth : openBodyWidth
            }

            if transitionPlan.from.visualMode == .expanded || transitionPlan.to.visualMode == .expanded {
                return targetOpenBodyWidth
            }

            return openBodyWidth
        }()
        let stableLayerWidth: CGFloat = {
            guard let transitionPlan else {
                return surfaceWidth
            }

            if transitionPlan.from.visualMode == .expanded || transitionPlan.to.visualMode == .expanded {
                return expandedSurfaceWidth
            }

            return surfaceWidth
        }()
        let premeasuredModuleColumnWidth = expandedModuleColumnWidth(for: resolvedExpandedContentWidth)
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

                    peekContentLayer
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

                if showsExpandedChrome {
                    expandedChromeContentLayer
                        .frame(width: expandedContentFrameWidth, height: surfaceHeight, alignment: .top)
                        .mask {
                            surfaceShape
                                .frame(width: surfaceWidth, height: surfaceHeight)
                        }
                }
            }
            .frame(width: stableLayerWidth, height: surfaceHeight, alignment: .top)
        }
        .scaleEffect(usesOpenedVisualState ? 1 : (isHovering ? CodexIslandChromeMetrics.closedHoverScale : 1), anchor: .top)
        .padding(.horizontal, panelShadowHorizontalInset)
        .padding(.bottom, panelShadowBottomInset)
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

    @ViewBuilder
    private var headerRow: some View {
        IslandClosedHeaderView(
            state: IslandShellClosedHeaderRenderState(
                fanAnimationState: model.fanAnimationState,
                compactModules: model.visibleCompactModules
            ),
            notchExclusionWidth: closedContentNotchExclusionWidth
        )
            .opacity(showsClosedHeader ? 1 : 0)
            .allowsHitTesting(visualMode == .closed && showsClosedHeader)
            .frame(height: closedHeight)
            .clipped()
    }

    private var peekContentLayer: some View {
        ZStack(alignment: .topLeading) {
            if let snapshot = outgoingPeekSnapshot {
                peekContent(snapshot: snapshot)
                    .opacity(outgoingPeekOpacity)
                    .padding(.horizontal, CodexIslandPeekMetrics.contentHorizontalInset) // peek 内容的左右边距由壳层统一提供
                    .padding(.bottom, CodexIslandPeekMetrics.contentBottomPadding) // peek 内容的底部留白由容器统一控制
            }

            if let snapshot = incomingPeekSnapshot {
                peekContent(snapshot: snapshot)
                    .opacity(incomingPeekOpacity)
                    .padding(.horizontal, CodexIslandPeekMetrics.contentHorizontalInset)
                    .padding(.bottom, CodexIslandPeekMetrics.contentBottomPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(
            .top,
            visualMode == .peek
                ? CodexIslandPeekMetrics.contentTopPadding + expandedContentTopClearance
                : CodexIslandChromeMetrics.expandedContentTopPadding + expandedContentTopClearance
        ) // peek 与 expanded 分别使用各自的顶部留白；带硬件刘海时让 opened 内容整体下移
        .foregroundStyle(.white)
        .allowsHitTesting(model.peekCapturesMouseEvents && transitionPlan == nil && visualMode == .peek)
    }

    private var expandedChromeContentLayer: some View {
        ZStack(alignment: .topLeading) {
            expandedChromeSection
                .opacity(expandedChromeOpacity)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(
            .top,
            CodexIslandChromeMetrics.expandedContentTopPadding + expandedContentTopClearance
        )
        .foregroundStyle(.white)
        .allowsHitTesting(expandedContentAllowsHitTesting)
        .transaction { transaction in
            if model.islandLayoutTransitionInFlight {
                transaction.animation = nil
            }
        }
    }

    private func peekContent(snapshot: IslandModuleRenderSnapshot) -> some View {
        snapshot.view
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
                    for: snapshot.moduleID,
                    presentation: snapshot.presentation
                )
            }
            .transaction { transaction in
                if model.islandLayoutTransitionInFlight {
                    transaction.animation = nil
                }
            }
    }

    private var expandedChromeSection: some View {
        expandedChromeSection {
            expandedModuleContentSwitcher
        }
    }

    private func expandedChromeSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: model.showsExpandedWindDrivePanel ? CodexIslandChromeMetrics.moduleColumnSpacing : 0) { // Wind Drive 与右侧内容列的间距
            if model.showsExpandedWindDrivePanel {
                fanColumn
                    .frame(width: CodexIslandChromeMetrics.windDrivePanelWidth, alignment: .top)
            }
            rightColumn(content: content)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, CodexIslandChromeMetrics.expandedContentHorizontalInset) // 展开态主容器统一左右边距，模块自己不要再加外层 horizontal padding
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var expandedModuleContentSwitcher: some View {
        ZStack(alignment: .topLeading) {
            if let snapshot = outgoingExpandedSnapshot {
                snapshotModuleContentViewport(snapshot: snapshot)
                    .opacity(outgoingExpandedOpacity)
            }

            if let snapshot = incomingExpandedSnapshot {
                snapshotModuleContentViewport(snapshot: snapshot)
                    .opacity(incomingExpandedOpacity)
            }

            if expandedLiveHostsMounted {
                liveModuleContentViewport
                    .opacity(stableLiveExpandedVisible ? 1 : 0)
                    .allowsHitTesting(stableLiveExpandedVisible)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: model.selectedModuleViewportHeight,
            maxHeight: model.selectedModuleViewportHeight,
            alignment: .topLeading
        )
        .clipped()
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

    private func rightColumn<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CodexIslandChromeMetrics.moduleColumnSpacing) { // tab/header 行与模块内容区的纵向间距
            expandedNavigationRow

            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var liveModuleContentViewport: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.enabledModules, id: \.id) { module in
                let moduleID = module.id
                let presentation = model.expandedLivePresentationContext(for: moduleID)
                let isSelected = moduleID == model.selectedModuleID

                liveModuleContentHost(module: module, presentation: presentation)
                    .opacity(isSelected ? 1 : 0)
                    .allowsHitTesting(isSelected && stableLiveExpandedVisible)
                    .accessibilityHidden(!isSelected)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: model.selectedModuleViewportHeight,
            maxHeight: model.selectedModuleViewportHeight,
            alignment: .topLeading
        )
        .clipped()
    }

    private func liveModuleContentHost(
        module: any IslandModule,
        presentation: IslandModulePresentationContext
    ) -> some View {
        let moduleID = module.id
        let needsScrolling = model.moduleNeedsScrolling(for: moduleID, presentation: presentation)
        let viewportHeight = model.moduleViewportHeight(for: moduleID, presentation: presentation)

        return Group {
            if needsScrolling {
                ScrollViewReader { proxy in
                    ScrollView {
                        moduleContentStack(
                            contentView: module.makeLiveContentView(presentation: presentation),
                            presentation: presentation,
                            scrollAction: IslandModuleScrollAction { id, anchor in
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    proxy.scrollTo(id, anchor: anchor)
                                }
                            },
                            scrollOffset: moduleScrollOffset(for: moduleID)
                        )
                    }
                    .coordinateSpace(name: IslandModuleScrollCoordinateSpace.name)
                    .onScrollGeometryChange(for: CGFloat.self, of: { geometry in
                        max(0, geometry.contentOffset.y)
                    }, action: { _, newValue in
                        guard !model.islandLayoutTransitionInFlight else {
                            return
                        }
                        setModuleScrollOffset(newValue, for: moduleID)
                    })
                    .scrollIndicators(.automatic)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: viewportHeight,
                        maxHeight: viewportHeight,
                        alignment: .topLeading
                    )
                }
            } else {
                moduleContentStack(
                    contentView: module.makeLiveContentView(presentation: presentation),
                    presentation: presentation,
                    scrollAction: IslandModuleScrollAction(),
                    scrollOffset: 0
                )
                .onAppear {
                    setModuleScrollOffset(0, for: moduleID, force: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: needsScrolling) { _, needsScrolling in
            if !needsScrolling {
                setModuleScrollOffset(0, for: moduleID, force: true)
            }
        }
        .onPreferenceChange(ModuleContentHeightKey.self) { height in
            model.updateMeasuredModuleContentHeight(
                height,
                for: moduleID,
                presentation: presentation
            )
        }
    }

    private func moduleScrollOffset(for moduleID: String) -> CGFloat {
        moduleScrollOffsets[moduleID] ?? 0
    }

    private func setModuleScrollOffset(_ offset: CGFloat, for moduleID: String, force: Bool = false) {
        let resolvedOffset = max(0, offset)
        let previousOffset = moduleScrollOffsets[moduleID] ?? 0
        guard force || abs(previousOffset - resolvedOffset) >= 0.5 else {
            return
        }

        moduleScrollOffsets[moduleID] = resolvedOffset
    }

    private func snapshotModuleContentViewport(snapshot: IslandModuleRenderSnapshot) -> some View {
        moduleContentStack(
            contentView: snapshot.view,
            presentation: snapshot.presentation,
            scrollAction: IslandModuleScrollAction(),
            scrollOffset: 0
        )
        .onPreferenceChange(ModuleContentHeightKey.self) { height in
            model.updateMeasuredModuleContentHeight(
                height,
                for: snapshot.moduleID,
                presentation: snapshot.presentation
            )
        }
    }

    private func moduleContentStack(
        contentView: AnyView,
        presentation: IslandModulePresentationContext,
        scrollAction: IslandModuleScrollAction,
        scrollOffset: CGFloat
    ) -> some View {
        contentView
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
            .transaction { transaction in
                if model.islandLayoutTransitionInFlight {
                    transaction.animation = nil
                }
            }
    }

    @ViewBuilder
    private func collapsedModulePremeasurementView(width: CGFloat) -> some View {
        let selectedModule = model.selectedModule
        let presentation = model.selectedModulePresentationContext

        if shouldPremeasureModuleContent(width: width) {
            VStack(alignment: .leading, spacing: 0) {
                selectedModule.makeRenderSnapshot(presentation: presentation).view
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
