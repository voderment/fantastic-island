import AppKit
import SwiftUI

private let islandDefaultNotchSize = CGSize(width: 224, height: 38)

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
// Original file: Sources/OpenIslandApp/OverlayPanelController.swift
// Modified for Fantastic Island on 2026-04-14.
@MainActor
final class IslandShellController {
    static let defaultNotchSize = islandDefaultNotchSize
    private static let minimumExpandedContentWidth: CGFloat = 720
    private static let maximumExpandedContentWidth: CGFloat = 780
    private static let expandedContentWidthFactor: CGFloat = 0.46
    private static let openedContentBottomPadding: CGFloat = CodexIslandChromeMetrics.openedSurfaceBottomInset

    fileprivate weak var model: IslandAppModel?
    private var panel: IslandShellPanel?
    private var screenObserver: NSObjectProtocol?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var pendingCloseResize: DispatchWorkItem?
    private(set) var notchRect: NSRect = .zero

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.reposition(refreshRootView: true)
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func show(using model: IslandAppModel) {
        self.model = model
        cancelPendingCloseResize(resetCollapseState: true)
        let panel = self.panel ?? makePanel(using: model)
        self.panel = panel
        updateRootView(using: model)
        guard let screen = resolvedPanelScreen(for: panel) else {
            return
        }
        let targetFrame = holdingPanelFrame(for: model, on: screen)
        if panel.frame != targetFrame {
            panel.setFrame(targetFrame, display: true)
        }
        computeNotchRect(screen: screen)
        panel.ignoresMouseEvents = !isPanelInteractive(for: model)
        panel.acceptsMouseMovedEvents = isPanelInteractive(for: model)
        panel.orderFrontRegardless()
        startEventMonitoring()
    }

    func prepareForExpansion(using model: IslandAppModel) {
        self.model = model
        cancelPendingCloseResize(resetCollapseState: true)

        let panel = self.panel ?? makePanel(using: model)
        self.panel = panel
        updateRootView(using: model)

        guard let screen = resolvedPanelScreen(for: panel) else {
            return
        }

        let openedFrame = holdingPanelFrame(for: model, on: screen)
        if panel.frame != openedFrame {
            panel.setFrame(openedFrame, display: true)
        }

        computeNotchRect(screen: screen)
        panel.orderFrontRegardless()
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        startEventMonitoring()
    }

    func prepareForPeek(using model: IslandAppModel) {
        self.model = model
        cancelPendingCloseResize(resetCollapseState: true)

        let panel = self.panel ?? makePanel(using: model)
        self.panel = panel
        updateRootView(using: model)

        guard let screen = resolvedPanelScreen(for: panel) else {
            return
        }

        let targetFrame = holdingPanelFrame(for: model, on: screen)
        if panel.frame != targetFrame {
            panel.setFrame(targetFrame, display: true)
        }

        computeNotchRect(screen: screen)
        panel.orderFrontRegardless()
        let isInteractive = model.isInteractivePeeking
        panel.ignoresMouseEvents = !isInteractive
        panel.acceptsMouseMovedEvents = isInteractive
        startEventMonitoring()
    }

    func hide() {
        cancelPendingCloseResize(resetCollapseState: true)
        panel?.orderOut(nil)
        stopEventMonitoring()
    }

    func reposition(refreshRootView: Bool = false) {
        guard let model,
              let panel,
              let screen = resolvedPanelScreen(for: panel) else {
            return
        }

        if refreshRootView {
            updateRootView(using: model)
        }
        updatePanelFrame(panel, using: model, on: screen)
        computeNotchRect(screen: screen)
    }

    func contentRect(for model: IslandAppModel, in bounds: NSRect) -> NSRect {
        let insets = panelShadowInsets
        return NSRect(
            x: bounds.minX + insets.horizontal,
            y: bounds.minY + insets.bottom,
            width: max(0, bounds.width - (insets.horizontal * 2)),
            height: max(0, bounds.height - insets.bottom)
        )
    }

    func hitTestRect(for model: IslandAppModel, in bounds: NSRect) -> NSRect {
        let contentRect = contentRect(for: model, in: bounds)
        guard let screen = resolvedPanelScreen(for: panel) else {
            return contentRect
        }

        if model.islandExpanded {
            return contentRect
        }

        if model.isInteractivePeeking {
            return centeredShellRect(
                in: contentRect,
                width: peekShellWidth(for: screen),
                height: max(closedNotchHeight(for: screen), model.peekContentHeight)
            )
        }

        return .zero
    }

    func isPointInExpandedArea(_ screenPoint: NSPoint) -> Bool {
        guard let model, model.islandExpanded, let panel else {
            return false
        }

        return Self.rectContainsIncludingEdges(contentRect(for: model, in: panel.frame), point: screenPoint)
    }

    func isPointInCollapsedActivationArea(_ screenPoint: NSPoint) -> Bool {
        guard let model,
              let closedRect = closedActivationRect(for: model) else {
            return false
        }

        return Self.rectContainsIncludingEdges(closedRect, point: screenPoint)
    }

    func expandedContentWidth(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return 820 }
        return min(
            max(screen.visibleFrame.width * Self.expandedContentWidthFactor, Self.minimumExpandedContentWidth),
            min(Self.maximumExpandedContentWidth, screen.visibleFrame.width - 32)
        )
    }

    func peekContentWidth(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return CodexIslandPeekMetrics.maximumContentWidth }
        return min(
            max(screen.visibleFrame.width * CodexIslandPeekMetrics.contentWidthFactor, CodexIslandPeekMetrics.minimumContentWidth),
            min(CodexIslandPeekMetrics.maximumContentWidth, screen.visibleFrame.width - 32)
        )
    }

    func closedPanelWidth(for model: IslandAppModel, on screen: NSScreen?) -> CGFloat {
        let notchWidth = screen?.codexIslandNotchSize.width ?? Self.defaultNotchSize.width
        return model.closedSurfaceWidth(baseCompactWidth: notchWidth)
    }

    private var panelShadowInsets: (horizontal: CGFloat, bottom: CGFloat) {
        (
            horizontal: CodexIslandChromeMetrics.openedShadowHorizontalInset,
            bottom: CodexIslandChromeMetrics.openedShadowBottomInset
        )
    }

    private var targetScreen: NSScreen? {
        let screens = NSScreen.screens
        if let notchScreen = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notchScreen
        }

        return NSScreen.main ?? screens.first
    }

    private func makePanel(using model: IslandAppModel) -> IslandShellPanel {
        let screen = targetScreen ?? NSScreen.main ?? NSScreen.screens[0]
        let panel = IslandShellPanel(
            contentRect: holdingPanelFrame(for: model, on: screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .statusBar
        panel.sharingType = .readOnly
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.ignoresMouseEvents = false

        let hostingView = IslandShellHostingView(rootView: makeShellView(using: model, on: screen))
        hostingView.notchController = self
        panel.contentView = hostingView

        computeNotchRect(screen: screen)
        return panel
    }

    private func updateRootView(using model: IslandAppModel) {
        guard let hostingView = panel?.contentView as? NSHostingView<IslandShellView> else {
            return
        }

        hostingView.rootView = makeShellView(using: model, on: resolvedPanelScreen(for: panel))
    }

    private func makeShellView(using model: IslandAppModel, on screen: NSScreen?) -> IslandShellView {
        let compactWidth = screen?.codexIslandCompactWidth ?? Self.defaultNotchSize.width
        let closedHeight = closedNotchHeight(for: screen)
        let expandedContentWidth = expandedContentWidth(for: screen)
        let peekContentWidth = peekContentWidth(for: screen)
        return IslandShellView(
            model: model,
            compactWidth: compactWidth,
            closedHeight: closedHeight,
            expandedContentWidth: expandedContentWidth,
            peekContentWidth: peekContentWidth
        )
    }

    private func holdingPanelFrame(for model: IslandAppModel, on screen: NSScreen) -> NSRect {
        let size = holdingPanelSize(for: model, on: screen)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func holdingPanelSize(for model: IslandAppModel, on screen: NSScreen) -> CGSize {
        let insets = panelShadowInsets
        let panelWidth = expandedShellWidth(for: screen)
        let contentHeight = max(closedNotchHeight(for: screen), openedContentHeight(for: model))
        let height = contentHeight + Self.openedContentBottomPadding + insets.bottom

        return CGSize(
            width: panelWidth + (insets.horizontal * 2),
            height: height
        )
    }

    private func openedContentHeight(for model: IslandAppModel) -> CGFloat {
        model.selectedModuleContentHeight
    }

    private func expandedShellWidth(for screen: NSScreen?) -> CGFloat {
        expandedContentWidth(for: screen)
            + (CodexIslandChromeMetrics.openedSurfaceContentHorizontalInset * 2)
    }

    private func peekShellWidth(for screen: NSScreen?) -> CGFloat {
        peekContentWidth(for: screen)
            + (CodexIslandChromeMetrics.openedSurfaceContentHorizontalInset * 2)
    }

    private func centeredShellRect(in bounds: NSRect, width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(
            x: bounds.midX - (width / 2),
            y: bounds.maxY - height,
            width: width,
            height: height
        )
    }

    private func closedActivationRect(for model: IslandAppModel) -> NSRect? {
        guard let screen = resolvedPanelScreen(for: panel) else {
            return nil
        }

        let width = closedPanelWidth(for: model, on: screen)
        let height = closedNotchHeight(for: screen)
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private func resolvedPanelScreen(for panel: IslandShellPanel?) -> NSScreen? {
        if let panelScreen = panel?.screen {
            return panelScreen
        }

        return targetScreen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func updatePanelFrame(_ panel: IslandShellPanel, using model: IslandAppModel, on screen: NSScreen) {
        let openedFrame = holdingPanelFrame(for: model, on: screen)

        if panel.frame != openedFrame {
            panel.setFrame(openedFrame, display: true)
        }

        if model.islandUsesOpenedVisualState {
            cancelPendingCloseResize(resetCollapseState: true)
            panel.ignoresMouseEvents = !isPanelInteractive(for: model)
            panel.acceptsMouseMovedEvents = isPanelInteractive(for: model)
            return
        }

        scheduleCloseResize(for: panel)
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = false
    }

    private func computeNotchRect(screen: NSScreen?) {
        guard let screen else {
            notchRect = .zero
            return
        }

        let notchSize = screen.codexIslandNotchSize
        let screenFrame = screen.frame
        let notchX = screenFrame.midX - notchSize.width / 2
        let notchY = screenFrame.maxY - notchSize.height
        notchRect = NSRect(x: notchX, y: notchY, width: notchSize.width, height: notchSize.height)
    }

    private func closedNotchHeight(for screen: NSScreen?) -> CGFloat {
        screen?.codexIslandClosedHeight ?? Self.defaultNotchSize.height
    }

    private func isPanelInteractive(for model: IslandAppModel) -> Bool {
        model.islandExpanded || model.isInteractivePeeking
    }

    private func scheduleCloseResize(for panel: IslandShellPanel) {
        cancelPendingCloseResize(resetCollapseState: false)
        model?.beginIslandCollapseAnimation()

        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = false

        let workItem = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel else {
                return
            }

            panel.ignoresMouseEvents = true
            panel.acceptsMouseMovedEvents = false
            self.model?.finishIslandCollapseAnimation()
            self.pendingCloseResize = nil
        }

        pendingCloseResize = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + CodexIslandChromeMetrics.closeLayoutSettleDuration,
            execute: workItem
        )
    }

    private func cancelPendingCloseResize(resetCollapseState: Bool) {
        pendingCloseResize?.cancel()
        pendingCloseResize = nil

        guard resetCollapseState else {
            return
        }

        model?.finishIslandCollapseAnimation()
    }

    private func startEventMonitoring() {
        guard globalClickMonitor == nil, localClickMonitor == nil else {
            return
        }

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                self?.handleClickEvent(event)
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                self?.handleClickEvent(event)
            }
            return event
        }
    }

    private func stopEventMonitoring() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    private func handleClickEvent(_ event: NSEvent) {
        guard let model else {
            return
        }

        let point = screenPoint(for: event)

        if model.islandExpanded {
            guard !isPointInExpandedArea(point) else {
                return
            }

            model.collapseIsland()
            return
        }

        guard event.type == .leftMouseDown, isPointInCollapsedActivationArea(point) else {
            return
        }

        // Gesture recognizers can miss edge taps during rapid state switches;
        // event-monitor fallback keeps first-click expansion reliable.
        model.expandIsland(reason: .manualTap)
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        if let window = event.window {
            return window.convertPoint(toScreen: event.locationInWindow)
        }

        return NSEvent.mouseLocation
    }

    static func rectContainsIncludingEdges(_ rect: NSRect, point: NSPoint) -> Bool {
        // NSRect.contains excludes maxX/maxY; closed-notch top-edge clicks
        // should still count as valid interactions.
        point.x >= rect.minX
            && point.x <= rect.maxX
            && point.y >= rect.minY
            && point.y <= rect.maxY
    }
}

private final class IslandShellPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class IslandShellHostingView<Content: View>: NSHostingView<Content> {
    weak var notchController: IslandShellController?

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let controller = notchController,
              let model = controller.model else {
            return nil
        }

        let rect = controller.hitTestRect(for: model, in: bounds)
        guard IslandShellController.rectContainsIncludingEdges(rect, point: point) else {
            return nil
        }

        return super.hitTest(point) ?? self
    }
}

extension NSScreen {
    var codexIslandNotchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return islandDefaultNotchSize
        }

        let notchHeight = safeAreaInsets.top
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        let notchWidth = frame.width - leftPadding - rightPadding + 4
        return CGSize(width: notchWidth, height: notchHeight)
    }

    var codexIslandCompactWidth: CGFloat {
        codexIslandNotchSize.width
    }

    var codexIslandClosedHeight: CGFloat {
        if safeAreaInsets.top > 0 {
            return safeAreaInsets.top
        }

        return islandDefaultNotchSize.height
    }
}
