import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

private let islandOpenTransitionAnimation = CodexIslandPeekMetrics.openAnimation
private let islandCloseTransitionAnimation = CodexIslandPeekMetrics.closeAnimation
private let islandOpenedRevealAnimation = CodexIslandPeekMetrics.chromeRevealAnimation
private let islandClosedHeaderRevealAnimation = CodexIslandPeekMetrics.closedHeaderRevealAnimation

struct CompactModuleSummary: Identifiable, Equatable {
    enum Content: Equatable {
        case singleLine(String)
        case agentGrid([CompactAgentIndicator], overflow: Int)
    }

    let moduleID: String
    let title: String
    let symbolName: String
    let iconAssetName: String?
    let content: Content

    var id: String { moduleID }

    var contentSpacing: CGFloat {
        CodexIslandChromeMetrics.closedModuleContentSpacing
    }

    var accessibilityText: String {
        switch content {
        case let .singleLine(text):
            return text
        case let .agentGrid(indicators, overflow):
            let count = indicators.count + overflow
            return count == 1 ? "1 active session" : "\(count) active sessions"
        }
    }

    var estimatedWidth: CGFloat {
        let iconWidth = CodexIslandChromeMetrics.closedIconSize
        let textWidth: CGFloat

        switch content {
        case let .singleLine(text):
            let minimumTextWidth = max(44, CodexIslandChromeMetrics.closedPrimaryFontSize * 4.4)
            let estimatedCharacterWidth = max(5.2, CodexIslandChromeMetrics.closedPrimaryFontSize * 0.62)
            textWidth = max(minimumTextWidth, ceil(CGFloat(text.count) * estimatedCharacterWidth))
        case let .agentGrid(indicators, overflow):
            let count = indicators.count + overflow
            let countBadgeWidth = max(16, ceil(CGFloat(String(count).count) * 6.4) + 10)
            textWidth = CompactAgentGridMetrics.intrinsicWidth(
                count: indicators.count + (overflow > 0 ? 1 : 0)
            ) + 5 + countBadgeWidth
        }

        return iconWidth + contentSpacing + textWidth
    }
}

enum CompactAgentIndicatorState: Equatable {
    case running
    case waiting
    case idle
}

struct CompactAgentIndicator: Identifiable, Equatable {
    let id: String
    let provider: AgentProvider
    let state: CompactAgentIndicatorState
}

enum CompactAgentGridMetrics {
    static func balancedRows(_ count: Int) -> [Int] {
        switch count {
        case ..<1: []
        case 1: [1]
        case 2: [2]
        case 3: [3]
        case 4: [2, 2]
        case 5: [3, 2]
        case 6: [3, 3]
        case 7: [4, 3]
        case 8: [4, 4]
        default: [4, 4, count - 8]
        }
    }

    static func cellGeometry(rowCount: Int) -> (cell: CGFloat, gap: CGFloat, radius: CGFloat) {
        rowCount >= 3 ? (cell: 6, gap: 1.5, radius: 1.0) : (cell: 8, gap: 2, radius: 1.5)
    }

    static func intrinsicWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let rows = balancedRows(count)
        let maxRow = rows.max() ?? 0
        let geometry = cellGeometry(rowCount: rows.count)
        return CGFloat(maxRow) * geometry.cell + CGFloat(max(0, maxRow - 1)) * geometry.gap
    }
}

@MainActor
final class IslandAppModel: ObservableObject {
    @Published private(set) var activityState = AgentActivityState()
    @Published private(set) var isAudioMuted = true
    @Published private(set) var hideInFullscreen = true
    @Published private(set) var detachedModeEnabled = false
    @Published private(set) var hudOverlay: IslandHUDOverlayState?
    @Published private(set) var collapsedSummaryConfiguration = CollapsedSummaryConfiguration.load()
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginStatusText = "Fantastic Island won't launch automatically when you sign in."
    @Published private(set) var interfaceLanguage: IslandInterfaceLanguage = .followSystem
    @Published private(set) var enabledModuleIDs: Set<String> = []
    @Published var islandExpanded = false
    @Published private(set) var islandPeeking = false
    @Published private(set) var islandClosedHovering = false
    @Published private(set) var islandExpansionAnimationInFlight = false
    @Published private(set) var islandCollapseAnimationInFlight = false
    @Published private(set) var transitionPhase: IslandTransitionPhase = .stable
    @Published private(set) var currentTransitionPlan: IslandTransitionPlan?
    @Published var selectedModuleID: String
    @Published private(set) var allActivities: [IslandActivity] = []
    @Published private(set) var frontmostActivity: IslandActivity?
    @Published private(set) var presentedActivity: IslandActivity?
    @Published private(set) var openReason: IslandOpenReason?
    @Published private(set) var currentPeekSnapshot: IslandModuleRenderSnapshot?
    @Published private(set) var currentExpandedSnapshot: IslandModuleRenderSnapshot?
    @Published private(set) var frozenPeekSnapshot: IslandModuleRenderSnapshot?
    @Published private(set) var frozenExpandedSnapshot: IslandModuleRenderSnapshot?

    let agentsModule: CodexModuleModel
    let playerModule: PlayerModuleModel
    let horizonModule: HorizonModuleModel
    let timerModule: TimerModuleModel
    let shelfModule: ShelfModuleModel
    let systemModule: SystemModuleModel
    let diagnosticsModule: DiagnosticsModuleModel
    let postModule: XPostModuleModel
    let moduleRegistry: IslandModuleRegistry
    let designTokenStore = IslandDebugTokenStore()

    private let shellController = IslandShellController()
    private let audioController = CodexAudioController()
    private let volumeHUDMonitor = IslandVolumeHUDMonitor()
    private lazy var settingsWindowController = IslandSettingsWindowController(model: self)
#if DEBUG
    @Published private(set) var debugPanelLockMode: IslandDebugPanelLockMode = .automatic
    @Published private(set) var debugSelectedMockScenario: IslandDebugMockScenario = .none
    @Published private(set) var debugActiveMockScenario: IslandDebugMockScenario?
    private lazy var designTokenEditorWindowController = DesignTokenEditorWindowController(
        model: self,
        store: designTokenStore,
        localeProvider: { [weak self] in self?.resolvedLocale ?? .current }
    )
#endif
    private lazy var globalHotKeyController = IslandGlobalHotKeyController { [weak self] action in
        Task { @MainActor [weak self] in
            switch action {
            case .toggleExpansion:
                self?.toggleIslandExpansionFromShortcut()
            case .openAgents:
                self?.openAgentsFromShortcut()
            case .previousModule:
                self?.selectAdjacentModuleFromShortcut(offset: -1)
            case .nextModule:
                self?.selectAdjacentModuleFromShortcut(offset: 1)
            case .toggleDetachedMode:
                self?.toggleDetachedModeFromShortcut()
            }
        }
    }
    private var cancellables: Set<AnyCancellable> = []
    private var measuredModuleContentHeights: [String: CGFloat] = [:]
    private var lockedExpandedContentHeight: CGFloat?
    private var pendingExpandedLayoutRefresh = false
    private var pendingAggregateRefresh = false
    private var pendingDirtyModules: Set<String> = []
    private var pendingActivityReconcile = false
    private var pendingMeasuredHeights: [String: CGFloat] = [:]
    private var lastAggregateRefreshAt = Date()
    private var displayedScore = 0.0
    private var hasPrimedAudioState = false
    private var pendingTransitionRevealWorkItem: DispatchWorkItem?
    private var pendingTransitionSettleWorkItem: DispatchWorkItem?
    private var dismissedActivityIDs: Set<String> = []
    private var notificationAutoCollapseTask: Task<Void, Never>?
    private var notificationAutoCollapseActivityID: String?
    private var notificationAutoCollapseDelay: TimeInterval?
    private var notificationAutoCollapseShouldCollapsePanel = false
    private var shellHiddenForFullscreen = false
    private var hudVisibilityTimer: Timer?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var lastPointerModuleSwitchAt = Date.distantPast
    private let pointerModuleSwitchThrottle: TimeInterval = 0.28

    init() {
        let agentsModule = CodexModuleModel()
        let playerModule = PlayerModuleModel()
        let horizonModule = HorizonModuleModel()
        let timerModule = TimerModuleModel(timerController: horizonModule.timerController)
        let shelfModule = ShelfModuleModel(horizonModule: horizonModule)
        let systemModule = SystemModuleModel(horizonModule: horizonModule)
        let diagnosticsModule = DiagnosticsModuleModel(agentsModule: agentsModule)
        let postModule = XPostModuleModel()
        IslandDefaults.migrateLegacyValues()
        let allModules: [any IslandModule] = [
            agentsModule,
            playerModule,
            horizonModule,
            timerModule,
            shelfModule,
            systemModule,
        ]
        let defaults = UserDefaults.standard
        let loadedEnabledModuleIDs = Self.loadEnabledModuleIDs(defaults: defaults, availableModules: allModules)

        self.agentsModule = agentsModule
        self.playerModule = playerModule
        self.horizonModule = horizonModule
        self.timerModule = timerModule
        self.shelfModule = shelfModule
        self.systemModule = systemModule
        self.diagnosticsModule = diagnosticsModule
        self.postModule = postModule
        self.moduleRegistry = IslandModuleRegistry(modules: allModules)
        self.isAudioMuted = defaults.object(forKey: IslandDefaults.audioMutedKey) as? Bool ?? true
        self.hideInFullscreen = defaults.object(forKey: IslandDefaults.hideInFullscreenKey) as? Bool ?? true
        self.detachedModeEnabled = defaults.bool(forKey: IslandDefaults.detachedModeKey)
        self.launchAtLoginEnabled = defaults.bool(forKey: IslandDefaults.launchAtLoginKey)
        self.interfaceLanguage = IslandInterfaceLanguage(
            rawValue: defaults.string(forKey: IslandDefaults.interfaceLanguageKey) ?? ""
        ) ?? .followSystem
        self.enabledModuleIDs = loadedEnabledModuleIDs
        self.selectedModuleID = loadedEnabledModuleIDs.contains(agentsModule.id)
            ? agentsModule.id
            : (allModules.first { loadedEnabledModuleIDs.contains($0.id) }?.id ?? agentsModule.id)
        Self.migrateSystemCollapsedSummary(defaults: defaults)
        self.collapsedSummaryConfiguration = CollapsedSummaryConfiguration.load()
        normalizeSelectedModuleID()
        refreshLaunchAtLoginState()

        audioController.setMuted(isAudioMuted)
        bindModules()
        bindSystemMonitors()
        refreshFromModules(now: .now)
        refreshShellVisibility()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.shellController.show(using: self)
        }
        _ = globalHotKeyController
    }

    var agentsShortcutDisplayText: String {
        IslandAgentsShortcut.displayText
    }

    var previousModuleShortcutDisplayText: String {
        IslandPreviousModuleShortcut.displayText
    }

    var nextModuleShortcutDisplayText: String {
        IslandNextModuleShortcut.displayText
    }

    var detachedModeShortcutDisplayText: String {
        IslandDetachedModeShortcut.displayText
    }

    var modules: [any IslandModule] {
        moduleRegistry.modules
    }

    var enabledModules: [any IslandModule] {
        modules.filter { enabledModuleIDs.contains($0.id) }
    }

    var selectedModule: any IslandModule {
        enabledModules.first(where: { $0.id == selectedModuleID })
            ?? enabledModules.first
            ?? moduleRegistry.module(id: selectedModuleID)
            ?? agentsModule
    }

    var logicalPresentationState: IslandPresentationState {
        if islandExpanded {
            let activityID = presentedActivity?.moduleID == selectedModuleID ? presentedActivity?.id : nil
            return .expanded(moduleID: selectedModuleID, activityID: activityID)
        }

        if islandPeeking, let activity = presentedPeekActivity {
            return .peek(activityID: activity.id)
        }

        return .closed
    }

    var renderedPresentationState: IslandPresentationState {
        currentTransitionPlan?.to ?? logicalPresentationState
    }

    var activePeekSnapshot: IslandModuleRenderSnapshot? {
        frozenPeekSnapshot ?? currentPeekSnapshot
    }

    var activeExpandedSnapshot: IslandModuleRenderSnapshot? {
        frozenExpandedSnapshot ?? currentExpandedSnapshot
    }

    var islandUsesOpenedVisualState: Bool {
        logicalPresentationState != .closed || currentTransitionPlan != nil
    }

    var presentedPeekActivity: IslandActivity? {
        guard islandPeeking else {
            return nil
        }

#if DEBUG
        if let debugActivity = debugActiveMockScenario?.activity {
            return debugActivity
        }
#endif
        return presentedActivity
    }

    var presentedPeekModule: (any IslandModule)? {
        guard let presentedPeekActivity else {
            return nil
        }

        return moduleRegistry.module(id: presentedPeekActivity.moduleID)
    }

    var peekCapturesMouseEvents: Bool {
        islandPeeking
    }

    var selectedModulePresentationContext: IslandModulePresentationContext {
        guard islandExpanded,
              let presentedActivity,
              presentedActivity.moduleID == selectedModuleID else {
            return .standard
        }

        return .activity(presentedActivity)
    }

    var visibleCollapsedSummaryItems: [CollapsedSummaryItem] {
        allCollapsedSummaryItems.filter {
            enabledModuleIDs.contains($0.moduleID) && collapsedSummaryConfiguration.isVisible($0)
        }
    }

    var visibleCompactModules: [CompactModuleSummary] {
        let compactModuleOrder: [String] = [
            CodexModuleModel.moduleID,
        ]
        let supportedCompactModuleIDs = Set(compactModuleOrder)

        let summaries: [CompactModuleSummary] = enabledModules.compactMap { module in
            guard supportedCompactModuleIDs.contains(module.id) else {
                return nil
            }

            if module.id == CodexModuleModel.moduleID {
                let indicators = agentsModule.closedAgentIndicators
                return CompactModuleSummary(
                    moduleID: module.id,
                    title: module.title,
                    symbolName: module.symbolName,
                    iconAssetName: module.iconAssetName,
                    content: .agentGrid(indicators.visible, overflow: indicators.overflow)
                )
            }

            guard let firstVisibleItem = module.collapsedSummaryItems.first(where: collapsedSummaryConfiguration.isVisible) else {
                return nil
            }

            return CompactModuleSummary(
                moduleID: module.id,
                title: module.title,
                symbolName: module.symbolName,
                iconAssetName: module.iconAssetName,
                content: .singleLine(firstVisibleItem.text)
            )
        }

        return summaries.sorted { lhs, rhs in
            let lhsIndex = compactModuleOrder.firstIndex(of: lhs.moduleID) ?? .max
            let rhsIndex = compactModuleOrder.firstIndex(of: rhs.moduleID) ?? .max
            return lhsIndex < rhsIndex
        }
    }

    var allCollapsedSummaryItems: [CollapsedSummaryItem] {
        modules.flatMap { $0.collapsedSummaryItems }
    }

    var audioToggleSymbolName: String {
        isAudioMuted ? "speaker.slash.circle.fill" : "speaker.wave.2.circle.fill"
    }
    var islandLayoutTransitionInFlight: Bool {
        currentTransitionPlan != nil
            || islandExpansionAnimationInFlight
            || islandCollapseAnimationInFlight
            || transitionPhase != .stable
    }
    var closedSurfaceHeight: CGFloat {
        IslandShellController.defaultNotchSize.height
    }
    var peekContentHeight: CGFloat {
        if let plan = currentTransitionPlan {
            switch (plan.from.visualMode, plan.to.visualMode) {
            case (.peek, _), (_, .peek):
                return plan.lockedHeight
            default:
                break
            }
        }

        guard let activity = presentedPeekActivity else {
            return closedSurfaceHeight
        }

        return peekContentHeight(for: activity)
    }
    var selectedModuleContentHeight: CGFloat {
        if let plan = currentTransitionPlan {
            switch (plan.from.visualMode, plan.to.visualMode) {
            case (.expanded, _), (_, .expanded):
                return plan.lockedHeight
            default:
                break
            }
        }

        if islandLayoutTransitionInFlight, let lockedExpandedContentHeight {
            return lockedExpandedContentHeight
        }

        return resolvedExpandedContentHeight(
            for: selectedModule.id,
            presentation: selectedModulePresentationContext
        )
    }
    var selectedModuleViewportHeight: CGFloat {
        max(0, selectedModuleContentHeight - CodexIslandChromeMetrics.moduleChromeHeight)
    }
    var selectedModuleNeedsScrolling: Bool {
        moduleNeedsScrolling(for: selectedModule.id, presentation: selectedModulePresentationContext)
    }

    func expandedLivePresentationContext(for moduleID: String) -> IslandModulePresentationContext {
        let activityID = presentedActivity?.moduleID == moduleID ? presentedActivity?.id : nil
        return expandedPresentationContext(for: moduleID, activityID: activityID)
    }

    func moduleViewportHeight(
        for moduleID: String,
        presentation: IslandModulePresentationContext? = nil
    ) -> CGFloat {
        max(0, resolvedExpandedContentHeight(for: moduleID, presentation: presentation) - CodexIslandChromeMetrics.moduleChromeHeight)
    }

    func moduleNeedsScrolling(
        for moduleID: String,
        presentation: IslandModulePresentationContext? = nil
    ) -> Bool {
        let module =
            enabledModules.first(where: { $0.id == moduleID })
            ?? moduleRegistry.module(id: moduleID)
            ?? selectedModule
        guard module.allowsInternalScrolling else {
            return false
        }

        let resolvedPresentation =
            presentation
            ?? (module.id == selectedModuleID ? selectedModulePresentationContext : .standard)
        let measurementKey = moduleContentMeasurementKey(
            for: module.id,
            presentation: resolvedPresentation
        )
        guard let measuredContentHeight = measuredModuleContentHeights[measurementKey], measuredContentHeight > 0 else {
            return false
        }

        return measuredContentHeight
            + CodexIslandChromeMetrics.expandedContentBottomPadding
            - moduleViewportHeight(for: module.id, presentation: resolvedPresentation) >= 2
    }
    func moduleHasPendingBadge(_ moduleID: String) -> Bool {
        allActivities.contains { activity in
            activity.moduleID == moduleID
                && activity.moduleID != selectedModuleID
                && activity.kind == .actionRequired
        }
    }
    var expandShortcutDisplayText: String { IslandExpandShortcut.displayText }
    var resolvedLocale: Locale {
        Locale(identifier: "en")
    }

    func closedSurfaceWidth(baseCompactWidth: CGFloat, hardwareNotchExclusionWidth: CGFloat = 0) -> CGFloat {
        let contentWidth = visibleCompactModules.first?.estimatedWidth ?? 0
        if hardwareNotchExclusionWidth > 0 {
            let wingWidth = max(36, min(54, contentWidth + 8))
            return max(baseCompactWidth, hardwareNotchExclusionWidth + (wingWidth * 2))
        }

        return max(baseCompactWidth, contentWidth + 28, 112)
    }

    func expandIsland(reason: IslandOpenReason = .manualTap) {
        guard !islandExpanded else {
            if openReason == nil {
                openReason = reason
            }
            return
        }

        let fromState = logicalPresentationState
        openReason = reason
        if !reason.isNotification {
            presentedActivity = nil
            prepareModuleForUserIntent(selectedModuleID)
        }
        islandPeeking = false
        setIslandExpanded(true, shouldReposition: false)
        startTransition(from: fromState, to: logicalPresentationState) { [weak self] in
            guard let self else {
                return
            }
            self.shellController.prepareForExpansion(using: self)
        }
        updateNotificationAutoCollapse()
    }

    func collapseIsland() {
#if DEBUG
        guard debugPanelLockMode == .automatic else {
            return
        }
#endif
        let fromState = logicalPresentationState
        notificationAutoCollapseTask?.cancel()
        notificationAutoCollapseTask = nil
        openReason = nil
        startTransition(from: fromState, to: .closed)
        islandPeeking = false
        presentedActivity = nil
#if DEBUG
        debugActiveMockScenario = nil
#endif
        setIslandExpanded(false, shouldReposition: false)
    }

    func presentPeek(for activity: IslandActivity) {
        guard !islandExpanded else {
            return
        }

        let fromState = logicalPresentationState
        presentedActivity = activity
        openReason = nil
        islandPeeking = true
        startTransition(from: fromState, to: logicalPresentationState) { [weak self] in
            guard let self else {
                return
            }
            self.shellController.prepareForPeek(using: self)
        }
        updateNotificationAutoCollapse()
    }

    func peekModule(for activity: IslandActivity) -> (any IslandModule)? {
        moduleRegistry.module(id: activity.moduleID)
    }

    func peekContentHeight(for activity: IslandActivity) -> CGFloat {
        guard let module = peekModule(for: activity) else {
            return closedSurfaceHeight
        }

        return resolvedExpandedContentHeight(for: module.id, presentation: .peek(activity))
    }

    func setIslandClosedHovering(_ hovering: Bool) {
        let resolvedHovering = hovering && !islandUsesOpenedVisualState
        guard islandClosedHovering != resolvedHovering else {
            return
        }

        islandClosedHovering = resolvedHovering
    }

    func toggleIslandExpansionFromShortcut() {
        if islandExpanded {
            collapseIsland()
        } else {
            expandIsland(reason: .shortcut)
        }
    }

    func beginIslandCollapseAnimation() {
        lockExpandedLayoutHeight()
        islandCollapseAnimationInFlight = true
    }

    func finishIslandCollapseAnimation() {
        islandCollapseAnimationInFlight = false
        if !islandExpansionAnimationInFlight {
            lockedExpandedContentHeight = nil
            pendingExpandedLayoutRefresh = false
            flushDeferredAggregateRefreshIfNeeded()
        }
    }

    func selectModule(id: String) {
        if enabledModuleIDs.contains(id) || moduleRegistry.module(id: id) != nil {
            let fromState = logicalPresentationState
            let didChange = selectedModuleID != id
            selectedModuleID = id
            prepareModuleForUserIntent(id)
            if didChange {
                reconcileActivities(allowAutoPresentation: false)
            }
            if didChange, islandExpanded {
                if islandLayoutTransitionInFlight {
                    if let plan = currentTransitionPlan,
                       plan.from.visualMode == .expanded,
                       plan.to.visualMode == .expanded {
                        startTransition(from: plan.to, to: logicalPresentationState) { [weak self] in
                            guard let self else {
                                return
                            }
                            self.shellController.prepareForExpansion(using: self)
                        }
                    } else {
                        pendingExpandedLayoutRefresh = true
                    }
                } else {
                    startTransition(from: fromState, to: logicalPresentationState) { [weak self] in
                        guard let self else {
                            return
                        }
                        self.shellController.prepareForExpansion(using: self)
                    }
                }
            } else if didChange {
                rebuildStableRenderSnapshots()
            }
        }
    }

    func selectAdjacentModule(offset: Int) {
        guard offset != 0,
              !islandLayoutTransitionInFlight else {
            return
        }

        let modules = enabledModules
        let count = modules.count
        guard count > 1 else {
            return
        }

        guard let selectedIndex = modules.firstIndex(where: { $0.id == selectedModuleID }) else {
            selectModule(id: modules[0].id)
            return
        }

        let step = offset > 0 ? 1 : -1
        let nextIndex = (selectedIndex + step + count) % count
        guard nextIndex != selectedIndex else {
            return
        }

        selectModule(id: modules[nextIndex].id)
    }

    @discardableResult
    func selectAdjacentModuleFromPointer(offset: Int, now: Date = .now) -> Bool {
        guard islandExpanded,
              now.timeIntervalSince(lastPointerModuleSwitchAt) >= pointerModuleSwitchThrottle else {
            return false
        }

        let previousModuleID = selectedModuleID
        selectAdjacentModule(offset: offset)
        let didSwitch = selectedModuleID != previousModuleID
        if didSwitch {
            lastPointerModuleSwitchAt = now
        }
        return didSwitch
    }

    func selectAdjacentModuleFromShortcut(offset: Int) {
        selectAdjacentModule(offset: offset)
        if !islandExpanded {
            expandIsland(reason: .shortcut)
        }
    }

    func prepareShelfForFileDrop() {
        if !enabledModuleIDs.contains(ShelfModuleModel.moduleID) {
            enabledModuleIDs.insert(ShelfModuleModel.moduleID)
            persistEnabledModuleIDs()
        }

        selectModule(id: ShelfModuleModel.moduleID)
        if !islandExpanded {
            expandIsland(reason: .hover)
        }
    }

    func addFilesToShelf(_ urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        prepareShelfForFileDrop()
        shelfModule.horizonModule.addShelfURLs(urls)
    }

    func updateMeasuredModuleContentHeight(
        _ height: CGFloat,
        for moduleID: String,
        presentation: IslandModulePresentationContext
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.applyMeasuredModuleContentHeight(height, for: moduleID, presentation: presentation)
        }
    }

    private func applyMeasuredModuleContentHeight(
        _ height: CGFloat,
        for moduleID: String,
        presentation: IslandModulePresentationContext
    ) {
        guard height > 0 else {
            return
        }
        let measurementKey = moduleContentMeasurementKey(for: moduleID, presentation: presentation)
        let previousHeight = measuredModuleContentHeights[measurementKey] ?? 0
        guard abs(previousHeight - height) >= 2 else {
            return
        }

        measuredModuleContentHeights[measurementKey] = height
        let updatesVisiblePresentation: Bool
        switch presentation {
        case .standard, .activity:
            updatesVisiblePresentation = moduleID == selectedModuleID
        case let .peek(activity):
            updatesVisiblePresentation = islandPeeking && presentedPeekActivity?.id == activity.id
        }
        guard updatesVisiblePresentation else {
            return
        }

        if islandLayoutTransitionInFlight {
            pendingMeasuredHeights[measurementKey] = height
            pendingExpandedLayoutRefresh = true
            return
        }

        objectWillChange.send()

        if islandExpanded || islandPeeking {
            shellController.reposition()
        }
    }

    func isCollapsedSummaryVisible(_ item: CollapsedSummaryItem) -> Bool {
        collapsedSummaryConfiguration.isVisible(item)
    }

    func setCollapsedSummaryVisibility(_ isVisible: Bool, for item: CollapsedSummaryItem) {
        collapsedSummaryConfiguration = collapsedSummaryConfiguration.settingVisibility(
            isVisible,
            for: item,
            availableItems: allCollapsedSummaryItems
        )
        collapsedSummaryConfiguration.persist()
    }

    func toggleAudioMuted() {
        setAgentSoundsEnabled(isAudioMuted)
    }

    func setAgentSoundsEnabled(_ enabled: Bool) {
        isAudioMuted = !enabled
        UserDefaults.standard.set(isAudioMuted, forKey: IslandDefaults.audioMutedKey)
        audioController.setMuted(isAudioMuted)
    }

    func setHideInFullscreen(_ enabled: Bool) {
        hideInFullscreen = enabled
        UserDefaults.standard.set(enabled, forKey: IslandDefaults.hideInFullscreenKey)
        refreshShellVisibility()
    }

    func setDetachedModeEnabled(_ enabled: Bool) {
        guard detachedModeEnabled != enabled else {
            return
        }

        detachedModeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: IslandDefaults.detachedModeKey)
        shellController.reposition(refreshRootView: true)
    }

    func toggleDetachedModeFromShortcut() {
        setDetachedModeEnabled(!detachedModeEnabled)
        if detachedModeEnabled, !islandExpanded {
            expandIsland(reason: .shortcut)
        }
    }

    func openAgentsFromShortcut() {
        guard enabledModuleIDs.contains(agentsModule.id) else {
            return
        }

        let wasAlreadyExpandedOnAgents = islandExpanded && selectedModuleID == agentsModule.id
        selectedModuleID = agentsModule.id
        if wasAlreadyExpandedOnAgents {
            collapseIsland()
            return
        }

        expandIsland(reason: .shortcut)
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            refreshLaunchAtLoginState()
        } catch {
            refreshLaunchAtLoginState()
            launchAtLoginStatusText = "Couldn't update launch at login."
        }
    }

    func setInterfaceLanguage(_ language: IslandInterfaceLanguage) {
        interfaceLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: IslandDefaults.interfaceLanguageKey)
    }

    func isModuleEnabled(_ moduleID: String) -> Bool {
        enabledModuleIDs.contains(moduleID)
    }

    func canDisableModule(_ moduleID: String) -> Bool {
        enabledModuleIDs.contains(moduleID) && enabledModuleIDs.count > 1
    }

    func setModuleEnabled(_ isEnabled: Bool, for moduleID: String) {
        guard moduleRegistry.module(id: moduleID) != nil else {
            return
        }

        if isEnabled {
            enabledModuleIDs.insert(moduleID)
        } else {
            guard canDisableModule(moduleID) else {
                return
            }
            enabledModuleIDs.remove(moduleID)
        }

        normalizeSelectedModuleID()
        persistEnabledModuleIDs()
        reconcileActivities(allowAutoPresentation: false)
    }

    func openSettings() {
        settingsWindowController.show()
    }

#if DEBUG
    func openDesignTokenEditor() {
        designTokenEditorWindowController.show()
    }

    func setDebugPanelLockMode(_ mode: IslandDebugPanelLockMode) {
        guard debugPanelLockMode != mode else {
            return
        }

        debugPanelLockMode = mode
        applyDebugPresentationMode()
    }

    func setDebugSelectedMockScenario(_ scenario: IslandDebugMockScenario) {
        guard debugSelectedMockScenario != scenario else {
            return
        }

        debugSelectedMockScenario = scenario
        if debugPanelLockMode == .peek {
            applyDebugPresentationMode()
        }
    }

    func triggerSelectedDebugMockScenario() {
        guard let activity = debugSelectedMockScenario.activity else {
            return
        }

        presentDebugMockPeek(activity: activity, scenario: debugSelectedMockScenario)
    }
#endif

    func quit() {
        audioController.stopAllPlayback()
        NSApplication.shared.terminate(nil)
    }

    private func bindModules() {
        bindModule(agentsModule)
        bindModule(playerModule)
        bindModule(horizonModule)
        bindModule(timerModule)
        bindModule(shelfModule)
        bindModule(systemModule)
        bindModule(postModule)

        designTokenStore.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        return
                    }

                    self.objectWillChange.send()
                    if self.islandExpanded || self.islandPeeking {
                        self.shellController.reposition(refreshRootView: true)
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func bindSystemMonitors() {
        volumeHUDMonitor.$overlay
            .receive(on: RunLoop.main)
            .sink { [weak self] overlay in
                self?.hudOverlay = overlay
            }
            .store(in: &cancellables)

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.volumeHUDMonitor.refreshOverlayVisibility()
                if self?.hudOverlay == nil {
                    self?.objectWillChange.send()
                }
            }
        }
        hudVisibilityTimer = timer
        RunLoop.main.add(timer, forMode: .common)

        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshShellVisibility()
            }
        }
    }

    private func refreshShellVisibility() {
        let hasUrgentAgentIntervention = allActivities.contains {
            $0.moduleID == CodexModuleModel.moduleID && $0.kind == .actionRequired
        }
        let shouldHide = hideInFullscreen
            && !hasUrgentAgentIntervention
            && IslandFullscreenMonitor.frontmostAppIsFullscreen()
        if shouldHide {
            guard !shellHiddenForFullscreen else {
                return
            }
            shellHiddenForFullscreen = true
            shellController.hide()
            return
        }

        guard shellHiddenForFullscreen else {
            return
        }

        shellHiddenForFullscreen = false
        shellController.show(using: self)
    }

    private func bindModule<Module: IslandModule & ObservableObject>(_ module: Module)
        where Module.ObjectWillChangePublisher == ObservableObjectPublisher {
        module.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        return
                    }

                    if self.islandLayoutTransitionInFlight {
                        IslandTransitionDiagnostics.publish("defer module publish id=\(module.id)")
                        self.pendingDirtyModules.insert(module.id)
                        self.pendingAggregateRefresh = true
                        self.pendingActivityReconcile = true
                        return
                    }

                    self.objectWillChange.send()
                    self.refreshFromModules(now: .now)
                    self.refreshShellVisibility()
                }
            }
            .store(in: &cancellables)
    }

    private func setIslandExpanded(_ expanded: Bool, shouldReposition: Bool = true) {
        guard islandExpanded != expanded else {
            return
        }

        if expanded {
            islandCollapseAnimationInFlight = false
            islandPeeking = false
        }

        islandExpanded = expanded
        if expanded, islandExpansionAnimationInFlight {
            lockExpandedLayoutHeight()
        }
        if shouldReposition {
            shellController.reposition()
        }
    }

    private func startTransition(
        from explicitFrom: IslandPresentationState? = nil,
        to target: IslandPresentationState,
        panelPreparation: (() -> Void)? = nil
    ) {
        cancelPendingTransitionWork()
        if target.visualMode != .closed {
            setIslandClosedHovering(false)
        }
        pendingExpandedLayoutRefresh = false
        let fromState = explicitFrom ?? logicalPresentationState
        let preparedTransition = prepareTransitionState(from: fromState, to: target)
        let plan = IslandTransitionPlan(
            id: UUID(),
            from: fromState,
            to: target,
            targetEnvelope: IslandTransitionEnvelope(
                presentation: target,
                lockedHeight: preparedTransition.lockedHeight
            ),
            lockedHeight: preparedTransition.lockedHeight,
            startedAt: .now
        )

        islandExpansionAnimationInFlight = target != .closed
        islandCollapseAnimationInFlight = target == .closed
        if fromState.visualMode == .expanded || target.visualMode == .expanded {
            lockedExpandedContentHeight = preparedTransition.lockedHeight
        }

        frozenPeekSnapshot = preparedTransition.peekSnapshot
        frozenExpandedSnapshot = preparedTransition.expandedSnapshot
        currentTransitionPlan = plan
        transitionPhase = .preparing
        IslandTransitionDiagnostics.transition(
            "start token=\(plan.id.uuidString) from=\(String(describing: fromState)) to=\(String(describing: target)) lockedHeight=\(plan.lockedHeight)"
        )

        panelPreparation?()
        advanceTransitionToMorph(planID: plan.id)

        let revealWorkItem = DispatchWorkItem { [weak self, planID = plan.id] in
            self?.advanceTransitionToReveal(planID: planID)
        }
        pendingTransitionRevealWorkItem = revealWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + revealDelay(from: fromState, to: target),
            execute: revealWorkItem
        )

        let settleWorkItem = DispatchWorkItem { [weak self, planID = plan.id] in
            self?.completeTransition(planID: planID)
        }
        pendingTransitionSettleWorkItem = settleWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + settleDelay(from: fromState, to: target),
            execute: settleWorkItem
        )
    }

    private func advanceTransitionToMorph(planID: UUID) {
        guard let plan = currentTransitionPlan,
              plan.id == planID,
              transitionPhase == .preparing else {
            return
        }

        IslandTransitionDiagnostics.transition("morph token=\(planID.uuidString)")
        withAnimation(plan.to == .closed ? islandCloseTransitionAnimation : islandOpenTransitionAnimation) {
            transitionPhase = .morphing
        }
    }

    private func advanceTransitionToReveal(planID: UUID) {
        guard currentTransitionPlan?.id == planID else {
            return
        }

        IslandTransitionDiagnostics.transition("reveal token=\(planID.uuidString)")
        withAnimation(
            currentTransitionPlan?.to == .closed
                ? islandClosedHeaderRevealAnimation
                : islandOpenedRevealAnimation
        ) {
            transitionPhase = .revealingContent
        }
    }

    private func completeTransition(planID: UUID) {
        guard let plan = currentTransitionPlan, plan.id == planID else {
            return
        }

        IslandTransitionDiagnostics.transition("settle token=\(planID.uuidString)")
        cancelPendingTransitionWork()
        currentTransitionPlan = nil
        transitionPhase = .stable
        islandExpansionAnimationInFlight = false
        islandCollapseAnimationInFlight = false
        frozenPeekSnapshot = nil
        frozenExpandedSnapshot = nil

        if !islandExpanded {
            lockedExpandedContentHeight = nil
        }

        if (islandExpanded || islandPeeking) && pendingExpandedLayoutRefresh {
            pendingExpandedLayoutRefresh = false
            shellController.reposition()
        } else {
            pendingExpandedLayoutRefresh = false
        }

        if plan.to == .closed {
            shellController.reposition()
        }

        rebuildStableRenderSnapshots()
        flushDeferredAggregateRefreshIfNeeded()
    }

    private func cancelPendingTransitionWork() {
        pendingTransitionRevealWorkItem?.cancel()
        pendingTransitionRevealWorkItem = nil
        pendingTransitionSettleWorkItem?.cancel()
        pendingTransitionSettleWorkItem = nil
    }

    private func revealDelay(from: IslandPresentationState, to target: IslandPresentationState) -> TimeInterval {
        if target == .closed {
            return max(0, CodexIslandPeekMetrics.closeAnimationDuration - CodexIslandPeekMetrics.closedHeaderRevealLeadTime)
        }

        if from.visualMode == .expanded, target.visualMode == .expanded {
            return 0
        }

        if target.visualMode == .expanded {
            return CodexIslandChromeMetrics.openedChromeRevealDelay
        }

        return CodexIslandChromeMetrics.openedChromeRevealDelay
    }

    private func settleDelay(from: IslandPresentationState, to target: IslandPresentationState) -> TimeInterval {
        if target == .closed {
            return max(CodexIslandChromeMetrics.closeLayoutSettleDuration, CodexIslandPeekMetrics.renderCleanupDelay)
        }

        if from.visualMode == .expanded, target.visualMode == .expanded {
            return max(0.08, CodexIslandPeekMetrics.chromeRevealAnimationDuration)
        }

        return max(
            CodexIslandChromeMetrics.openLayoutSettleDuration,
            CodexIslandChromeMetrics.openedChromeRevealDelay + CodexIslandPeekMetrics.chromeRevealAnimationDuration
        )
    }

    private func prepareTransitionState(
        from: IslandPresentationState,
        to target: IslandPresentationState
    ) -> (peekSnapshot: IslandModuleRenderSnapshot?, expandedSnapshot: IslandModuleRenderSnapshot?, lockedHeight: CGFloat) {
        var nextPeekSnapshot = from.visualMode == .peek ? activePeekSnapshot : nil
        var nextExpandedSnapshot = from.visualMode == .expanded ? activeExpandedSnapshot : nil
        var lockedHeight = closedSurfaceHeight

        switch target {
        case let .peek(activityID):
            if let activity = activity(withID: activityID),
               let module = moduleRegistry.module(id: activity.moduleID) {
                nextPeekSnapshot = module.makeRenderSnapshot(presentation: .peek(activity))
                lockedHeight = resolvedExpandedContentHeight(for: module.id, presentation: .peek(activity))
            }
        case let .expanded(moduleID, activityID):
            let presentation = expandedPresentationContext(for: moduleID, activityID: activityID)
            let module = moduleRegistry.module(id: moduleID) ?? selectedModule
            nextExpandedSnapshot = module.makeRenderSnapshot(presentation: presentation)
            lockedHeight = resolvedExpandedContentHeight(for: moduleID, presentation: presentation)
            if from.visualMode == .peek {
                nextPeekSnapshot = activePeekSnapshot
            }
        case .closed:
            switch from.visualMode {
            case .peek:
                lockedHeight = peekContentHeight
            case .expanded:
                lockedHeight = selectedModuleContentHeight
            case .closed:
                lockedHeight = closedSurfaceHeight
            }
        }

        return (nextPeekSnapshot, nextExpandedSnapshot, lockedHeight)
    }

    private func activity(withID id: String?) -> IslandActivity? {
        guard let id else {
            return nil
        }

        return allActivities.first(where: { $0.id == id })
            ?? presentedActivity.flatMap { $0.id == id ? $0 : nil }
            ?? frontmostActivity.flatMap { $0.id == id ? $0 : nil }
    }

    private func expandedPresentationContext(for moduleID: String, activityID: String?) -> IslandModulePresentationContext {
        guard let activity = activity(withID: activityID), activity.moduleID == moduleID else {
            return .standard
        }

        return .activity(activity)
    }

    private func refreshFromModules(now: Date) {
        let delta = min(max(now.timeIntervalSince(lastAggregateRefreshAt), 0), 2.0)
        lastAggregateRefreshAt = now

        let aggregated = TaskActivityAggregator.aggregate(modules.map { $0.taskActivityContribution })
        let decayFactor = pow(0.92, delta / 0.2)
        displayedScore = max(aggregated.activityScore, displayedScore * decayFactor)
        activityState = AgentActivityState(
            activityScore: displayedScore,
            activeSessionCount: aggregated.activeTaskCount,
            inProgressSessionCount: aggregated.inProgressTaskCount,
            busySessionCount: aggregated.busyTaskCount,
            lastEventAt: aggregated.lastEventAt
        )

        reconcileActivities(allowAutoPresentation: true)
        rebuildStableRenderSnapshots()
        syncAudioState()
    }

    private func reconcileActivities(allowAutoPresentation: Bool) {
        let previousActivitiesByID = Dictionary(uniqueKeysWithValues: allActivities.map { ($0.id, $0) })
        let previousPresentedActivityID = presentedActivity?.id
        let previousPresentedModuleID = presentedActivity?.moduleID
        let wasPeeking = islandPeeking
        let selectedModuleCandidateBeforeUpdate = allActivities.first(where: { $0.moduleID == selectedModuleID })

        let rawActivities = sortActivities(enabledModules.flatMap { $0.islandActivities })
        let rawActivityIDs = Set(rawActivities.map(\.id))
        dismissedActivityIDs.formIntersection(rawActivityIDs)

        let filteredActivities = rawActivities.filter { !dismissedActivityIDs.contains($0.id) }
        allActivities = filteredActivities
        frontmostActivity = filteredActivities.first
        let selectedModuleCandidate = filteredActivities.first(where: { $0.moduleID == selectedModuleID })
        let currentPresentedActivity = presentedActivity.flatMap { activity in
            filteredActivities.first(where: { $0.id == activity.id })
        }

        var nextPresentedActivity = currentPresentedActivity

        if islandPeeking, let currentPresentedActivity {
            nextPresentedActivity = currentPresentedActivity
        } else if let notificationActivityID = openReason?.notificationActivityID {
            nextPresentedActivity = filteredActivities.first(where: {
                $0.id == notificationActivityID && $0.moduleID == selectedModuleID
            })
        } else if allowAutoPresentation,
                  islandExpanded,
                  let expandedPromotionCandidate = expandedPromotionCandidate(
                    selectedModuleCandidate: selectedModuleCandidate,
                    from: filteredActivities
                  ),
                  shouldPromoteActivityWhileExpanded(
                    expandedPromotionCandidate,
                    comparedTo: previousActivitiesByID,
                    previousSelectedCandidate: selectedModuleCandidateBeforeUpdate
                  ) {
            selectModuleIfNeededForAutoPresentation(expandedPromotionCandidate)
            nextPresentedActivity = expandedPromotionCandidate
        } else if currentPresentedActivity?.moduleID != selectedModuleID {
            nextPresentedActivity = nil
        }

        presentedActivity = nextPresentedActivity

        if allowAutoPresentation,
           islandPeeking,
           let autoPresentationCandidate = autoPresentationCandidate(
            from: filteredActivities,
            comparedTo: previousActivitiesByID,
            allowDuringPeek: true
           ) {
            selectModuleIfNeededForAutoPresentation(autoPresentationCandidate)
            presentedActivity = autoPresentationCandidate
            presentPeek(for: autoPresentationCandidate)
        } else if allowAutoPresentation,
                  let autoPresentationCandidate = autoPresentationCandidate(
                    from: filteredActivities,
                    comparedTo: previousActivitiesByID
                  ) {
            selectModuleIfNeededForAutoPresentation(autoPresentationCandidate)
            presentedActivity = autoPresentationCandidate
            presentPeek(for: autoPresentationCandidate)
        }

        if openReason?.isNotification == true {
            if let presentedActivity {
                openReason = .notification(activityID: presentedActivity.id)
            } else if frontmostActivity == nil {
                collapseIsland()
            }
        } else if islandPeeking, presentedActivity == nil {
#if DEBUG
            if debugActiveMockScenario == nil {
                islandPeeking = false
            }
#else
            islandPeeking = false
#endif
        }

        let presentedActivityChanged =
            previousPresentedActivityID != presentedActivity?.id
            || previousPresentedModuleID != presentedActivity?.moduleID

        if (presentedActivityChanged || wasPeeking != islandPeeking),
           !islandLayoutTransitionInFlight {
            shellController.reposition()
        }

        updateNotificationAutoCollapse()
    }

    private func sortActivities(_ activities: [IslandActivity]) -> [IslandActivity] {
        activities.sorted { lhs, rhs in
            if lhs.kind.sortPriority != rhs.kind.sortPriority {
                return lhs.kind.sortPriority > rhs.kind.sortPriority
            }

            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }

            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.id < rhs.id
        }
    }

    private func autoPresentationCandidate(
        from activities: [IslandActivity],
        comparedTo previousActivitiesByID: [String: IslandActivity],
        allowDuringPeek: Bool = false
    ) -> IslandActivity? {
        activities.first {
            shouldAutoPresent(
                $0,
                comparedTo: previousActivitiesByID,
                allowDuringPeek: allowDuringPeek
            )
        }
    }

    private func shouldAutoPresent(
        _ activity: IslandActivity,
        comparedTo previousActivitiesByID: [String: IslandActivity],
        allowDuringPeek: Bool = false
    ) -> Bool {
        guard !islandExpanded,
              (allowDuringPeek || !islandPeeking),
              supportsAutoPresentation(activity) else {
            return false
        }

        guard let previousActivity = previousActivitiesByID[activity.id] else {
            return true
        }

        return previousActivity.updatedAt != activity.updatedAt
            || previousActivity.kind != activity.kind
            || previousActivity.priority != activity.priority
    }

    private func shouldPromoteActivityWhileExpanded(
        _ activity: IslandActivity,
        comparedTo previousActivitiesByID: [String: IslandActivity],
        previousSelectedCandidate: IslandActivity?
    ) -> Bool {
        guard openReason?.isNotification != true,
              activity.presentationPolicy.promoteWhileExpanded else {
            return false
        }

        switch activity.presentationPolicy.autoPresentationScope {
        case .selectedModuleOnly:
            guard activity.moduleID == selectedModuleID else {
                return false
            }
        case .global:
            break
        case .manualOnly:
            return false
        }

        guard let previousActivity = previousActivitiesByID[activity.id] else {
            return previousSelectedCandidate?.id != activity.id
        }

        return previousActivity.updatedAt != activity.updatedAt
            || previousActivity.kind != activity.kind
            || previousActivity.priority != activity.priority
    }

    private func supportsAutoPresentation(_ activity: IslandActivity) -> Bool {
        switch activity.presentationPolicy.autoPresentationScope {
        case .selectedModuleOnly:
            return activity.moduleID == selectedModuleID
        case .global:
            return true
        case .manualOnly:
            return false
        }
    }

    private func expandedPromotionCandidate(
        selectedModuleCandidate: IslandActivity?,
        from activities: [IslandActivity]
    ) -> IslandActivity? {
        if let selectedModuleCandidate {
            return selectedModuleCandidate
        }

        return activities.first(where: {
            $0.kind == .actionRequired && $0.presentationPolicy.autoPresentationScope == .global
        })
    }

    private func selectModuleIfNeededForAutoPresentation(_ activity: IslandActivity) {
        guard activity.presentationPolicy.autoPresentationScope == .global,
              activity.presentationPolicy.switchSelectedModuleOnAutoPresentation,
              selectedModuleID != activity.moduleID,
              enabledModuleIDs.contains(activity.moduleID) else {
            return
        }

        selectedModuleID = activity.moduleID
        prepareModuleForUserIntent(activity.moduleID)
    }

    private func updateNotificationAutoCollapse() {
#if DEBUG
        guard debugActiveMockScenario == nil else {
            resetNotificationAutoCollapse()
            return
        }
#endif
        guard let presentedActivity,
              let autoDismissDelay = presentedActivity.presentationPolicy.autoDismissDelay else {
            resetNotificationAutoCollapse()
            return
        }

        guard islandPeeking || islandExpanded else {
            resetNotificationAutoCollapse()
            return
        }

        let shouldCollapsePanel = islandPeeking || openReason?.isNotification == true
        if notificationAutoCollapseActivityID == presentedActivity.id,
           notificationAutoCollapseDelay == autoDismissDelay,
           notificationAutoCollapseShouldCollapsePanel == shouldCollapsePanel {
            return
        }

        resetNotificationAutoCollapse()

        let activityID = presentedActivity.id
        notificationAutoCollapseActivityID = activityID
        notificationAutoCollapseDelay = autoDismissDelay
        notificationAutoCollapseShouldCollapsePanel = shouldCollapsePanel
        notificationAutoCollapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(autoDismissDelay))
            guard let self, !Task.isCancelled else {
                return
            }

            self.dismissActivity(id: activityID, collapseIfNeeded: shouldCollapsePanel)
        }
    }

    private func resetNotificationAutoCollapse() {
        notificationAutoCollapseTask?.cancel()
        notificationAutoCollapseTask = nil
        notificationAutoCollapseActivityID = nil
        notificationAutoCollapseDelay = nil
        notificationAutoCollapseShouldCollapsePanel = false
    }

    private func dismissActivity(id: String, collapseIfNeeded: Bool) {
        let shouldAnimatePeekCollapse = collapseIfNeeded && islandPeeking && presentedActivity?.id == id
        let fromState = logicalPresentationState

        dismissedActivityIDs.insert(id)

        if shouldAnimatePeekCollapse {
            startTransition(from: fromState, to: .closed)
            islandPeeking = false
            presentedActivity = nil
            reconcileActivities(allowAutoPresentation: false)
            return
        }

        reconcileActivities(allowAutoPresentation: false)

        if collapseIfNeeded, openReason?.notificationActivityID == id {
            collapseIsland()
        }
    }

#if DEBUG
    private func applyDebugPresentationMode() {
        switch debugPanelLockMode {
        case .automatic:
            if debugActiveMockScenario != nil || islandPeeking || islandExpanded {
                debugActiveMockScenario = nil
                collapseIslandFromDebugTool()
            }
        case .peek:
            if let activity = debugSelectedMockScenario.activity {
                presentDebugMockPeek(activity: activity, scenario: debugSelectedMockScenario)
            } else if let liveActivity = presentedActivity ?? frontmostActivity {
                selectModule(id: liveActivity.moduleID)
                presentPeekIgnoringExpansionGuard(for: liveActivity)
            } else {
                collapseIslandFromDebugTool()
            }
        case .expanded:
            debugActiveMockScenario = nil
            expandIsland(reason: .manualTap)
        }
    }

    private func presentDebugMockPeek(activity: IslandActivity, scenario: IslandDebugMockScenario) {
        debugActiveMockScenario = scenario
        selectModule(id: activity.moduleID)
        presentPeekIgnoringExpansionGuard(for: activity)
    }

    private func presentPeekIgnoringExpansionGuard(for activity: IslandActivity) {
        resetNotificationAutoCollapse()
        let fromState = logicalPresentationState
        presentedActivity = activity
        openReason = nil
        islandPeeking = true
        setIslandExpanded(false, shouldReposition: false)
        startTransition(from: fromState, to: logicalPresentationState) { [weak self] in
            guard let self else {
                return
            }
            self.shellController.prepareForPeek(using: self)
        }
    }

    private func collapseIslandFromDebugTool() {
        let fromState = logicalPresentationState
        resetNotificationAutoCollapse()
        openReason = nil
        startTransition(from: fromState, to: .closed)
        islandPeeking = false
        presentedActivity = nil
        setIslandExpanded(false, shouldReposition: false)
    }
#endif

    private func syncAudioState() {
        let approvalCount = allActivities.filter { $0.kind == .actionRequired }.count
        let completedCount = allActivities.filter { $0.id.contains(".activity.completed.") }.count

        if !hasPrimedAudioState {
            audioController.primePlayback(approvalCount: approvalCount, completedCount: completedCount)
            hasPrimedAudioState = true
            return
        }

        audioController.syncPlayback(approvalCount: approvalCount, completedCount: completedCount)
    }

    private func flushDeferredAggregateRefreshIfNeeded() {
        let hadPendingHeights = applyPendingMeasuredHeights()
        let shouldRefresh = pendingAggregateRefresh || pendingActivityReconcile || !pendingDirtyModules.isEmpty

        guard shouldRefresh || hadPendingHeights else {
            return
        }

        pendingAggregateRefresh = false
        pendingActivityReconcile = false
        pendingDirtyModules.removeAll()
        objectWillChange.send()
        refreshFromModules(now: .now)

        if (islandExpanded || islandPeeking) && !islandLayoutTransitionInFlight {
            shellController.reposition()
        }
    }

    private func applyPendingMeasuredHeights() -> Bool {
        guard !pendingMeasuredHeights.isEmpty else {
            return false
        }

        var didChange = false
        for (key, height) in pendingMeasuredHeights {
            let previousHeight = measuredModuleContentHeights[key] ?? 0
            if abs(previousHeight - height) >= 2 {
                measuredModuleContentHeights[key] = height
                didChange = true
            }
        }
        pendingMeasuredHeights.removeAll()
        return didChange
    }

    private func rebuildStableRenderSnapshots() {
        if let activity = presentedPeekActivity,
           let module = moduleRegistry.module(id: activity.moduleID) {
            currentPeekSnapshot = module.makeRenderSnapshot(presentation: .peek(activity))
        } else {
            currentPeekSnapshot = nil
        }

        let expandedPresentation = selectedModulePresentationContext
        currentExpandedSnapshot = selectedModule.makeRenderSnapshot(presentation: expandedPresentation)
    }

    private func lockExpandedLayoutHeight() {
        lockedExpandedContentHeight = resolvedExpandedContentHeight(
            for: selectedModuleID,
            presentation: selectedModulePresentationContext
        )
    }

    private func resolvedExpandedContentHeight(
        for moduleID: String,
        presentation: IslandModulePresentationContext? = nil
    ) -> CGFloat {
        let module =
            enabledModules.first(where: { $0.id == moduleID })
            ?? moduleRegistry.module(id: moduleID)
            ?? selectedModule
        let resolvedPresentation =
            presentation
            ?? (module.id == selectedModuleID ? selectedModulePresentationContext : .standard)
        let preferredHeight = module.preferredOpenedContentHeight(for: resolvedPresentation)
        let preferredHeightWithStandardBottomPadding: CGFloat
        switch resolvedPresentation {
        case .standard:
            preferredHeightWithStandardBottomPadding = preferredHeight + CodexIslandChromeMetrics.expandedContentBottomPadding
        case .activity, .peek:
            preferredHeightWithStandardBottomPadding = preferredHeight
        }
        let measurementKey = moduleContentMeasurementKey(for: module.id, presentation: resolvedPresentation)
        let measuredContentHeight = measuredModuleContentHeights[measurementKey] ?? 0
        let minimumHeight = minimumExpandedContentHeight(for: resolvedPresentation)
        let maximumHeight: CGFloat
        switch resolvedPresentation {
        case .standard, .peek:
            maximumHeight = max(preferredHeightWithStandardBottomPadding, minimumHeight)
        case .activity:
            maximumHeight = max(
                CodexIslandChromeMetrics.preferredTallModuleOpenedContentHeight,
                preferredHeightWithStandardBottomPadding,
                minimumHeight
            )
        }

        guard measuredContentHeight > 0 else {
            return maximumHeight
        }

        switch resolvedPresentation {
        case .standard, .activity:
            guard module.allowsInternalScrolling else {
                return max(
                    measuredContentHeight
                    + CodexIslandChromeMetrics.moduleChromeHeight
                    + CodexIslandChromeMetrics.expandedContentBottomPadding,
                    maximumHeight
                )
            }

            return min(
                max(
                    measuredContentHeight
                    + CodexIslandChromeMetrics.moduleChromeHeight
                    + CodexIslandChromeMetrics.expandedContentBottomPadding,
                    minimumHeight
                ),
                maximumHeight
            )
        case .peek:
            return CodexIslandPeekMetrics.contentTopPadding
                + measuredContentHeight
                + CodexIslandPeekMetrics.contentBottomPadding
        }
    }

    private func minimumExpandedContentHeight(for presentation: IslandModulePresentationContext) -> CGFloat {
        switch presentation {
        case .peek:
            return 0
        case .standard, .activity:
            return 0
        }
    }

    private func moduleContentMeasurementKey(
        for moduleID: String,
        presentation: IslandModulePresentationContext
    ) -> String {
        switch presentation {
        case .standard:
            return "\(moduleID)::standard"
        case let .activity(activity):
            return "\(moduleID)::activity::\(activity.id)"
        case let .peek(activity):
            return "\(moduleID)::peek::\(activity.id)"
        }
    }

    private func persistEnabledModuleIDs() {
        let storedIDs = modules.map(\.id).filter { enabledModuleIDs.contains($0) }
        UserDefaults.standard.set(storedIDs, forKey: IslandDefaults.enabledModuleIDsKey)
    }

    private func normalizeSelectedModuleID() {
        if !enabledModuleIDs.contains(selectedModuleID) {
            selectedModuleID = enabledModules.first?.id ?? modules.first?.id ?? selectedModuleID
        }
    }

    private func refreshLaunchAtLoginState() {
        let status = SMAppService.mainApp.status
        let isEnabled = status == .enabled || status == .requiresApproval

        launchAtLoginEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: IslandDefaults.launchAtLoginKey)

        switch status {
        case .enabled:
            launchAtLoginStatusText = "Fantastic Island launches automatically when you sign in."
        case .requiresApproval:
            launchAtLoginStatusText = "Pending approval in System Settings > General > Login Items."
        case .notFound:
            launchAtLoginStatusText = "Move Fantastic Island to /Applications, then enable launch at login."
        case .notRegistered:
            launchAtLoginStatusText = "Fantastic Island won't launch automatically when you sign in."
        @unknown default:
            launchAtLoginStatusText = "Launch at login status is unavailable right now."
        }
    }

    private static func loadEnabledModuleIDs(
        defaults: UserDefaults,
        availableModules: [any IslandModule]
    ) -> Set<String> {
        let availableIDs = Set(availableModules.map(\.id))
        let storedIDs = Set(defaults.stringArray(forKey: IslandDefaults.enabledModuleIDsKey) ?? [])
        let defaultIDs: Set<String> = [
            CodexModuleModel.moduleID,
            PlayerModuleModel.moduleID,
            HorizonModuleModel.moduleID,
            TimerModuleModel.moduleID,
            ShelfModuleModel.moduleID,
            SystemModuleModel.moduleID,
        ]
        let sanitizedDefaults = availableIDs.intersection(defaultIDs)

        guard !storedIDs.isEmpty else {
            return sanitizedDefaults.isEmpty ? availableIDs : sanitizedDefaults
        }

        var sanitizedIDs = availableIDs.intersection(storedIDs)
        if defaults.object(forKey: IslandDefaults.horizonUtilityModulesMigrationKey) == nil,
           sanitizedIDs.contains(HorizonModuleModel.moduleID) {
            sanitizedIDs.insert(TimerModuleModel.moduleID)
            sanitizedIDs.insert(ShelfModuleModel.moduleID)
            defaults.set(Array(sanitizedIDs), forKey: IslandDefaults.enabledModuleIDsKey)
        }
        defaults.set(true, forKey: IslandDefaults.horizonUtilityModulesMigrationKey)
        if defaults.object(forKey: IslandDefaults.systemModuleMigrationKey) == nil,
           sanitizedIDs.contains(HorizonModuleModel.moduleID) {
            sanitizedIDs.insert(SystemModuleModel.moduleID)
            defaults.set(Array(sanitizedIDs), forKey: IslandDefaults.enabledModuleIDsKey)
        }
        defaults.set(true, forKey: IslandDefaults.systemModuleMigrationKey)
        sanitizedIDs.remove(XPostModuleModel.moduleID)
        defaults.set(true, forKey: IslandDefaults.xPostModuleMigrationKey)
        sanitizedIDs.remove(DiagnosticsModuleModel.moduleID)
        defaults.set(true, forKey: IslandDefaults.diagnosticsModuleMigrationKey)
        defaults.set(Array(sanitizedIDs), forKey: IslandDefaults.enabledModuleIDsKey)
        return sanitizedIDs.isEmpty ? (sanitizedDefaults.isEmpty ? availableIDs : sanitizedDefaults) : sanitizedIDs
    }

    private static func migrateSystemCollapsedSummary(defaults: UserDefaults) {
        guard defaults.object(forKey: IslandDefaults.systemCollapsedSummaryMigrationKey) == nil else {
            return
        }

        defer {
            defaults.set(true, forKey: IslandDefaults.systemCollapsedSummaryMigrationKey)
        }

        let legacyBatteryID = "\(HorizonModuleModel.moduleID).summary.battery"
        let systemBatteryID = "\(SystemModuleModel.moduleID).summary.battery"
        guard var storedIDs = defaults.stringArray(forKey: IslandDefaults.collapsedSummaryVisibleIDsKey),
              storedIDs.contains(legacyBatteryID),
              !storedIDs.contains(systemBatteryID) else {
            return
        }

        storedIDs.append(systemBatteryID)
        defaults.set(storedIDs, forKey: IslandDefaults.collapsedSummaryVisibleIDsKey)
    }

    private func prepareModuleForUserIntent(_ moduleID: String) {
        if moduleID == HorizonModuleModel.moduleID {
            horizonModule.activateForUserIntent()
        } else if moduleID == SystemModuleModel.moduleID {
            systemModule.refresh()
        }
    }

}
