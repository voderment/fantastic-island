import AppKit
import Combine
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

private let islandFanRotationRetuneThreshold: Double = 0.03

struct CompactModuleSummary: Identifiable, Equatable {
    enum Content: Equatable {
        case singleLine(String)
        case clashTraffic(upload: String, download: String)
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
        case let .clashTraffic(upload, download):
            return "upload \(upload), download \(download)"
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
        case .clashTraffic:
            textWidth = CodexIslandChromeMetrics.compactClashTrafficBlockWidth
        }

        return iconWidth + contentSpacing + textWidth
    }
}

@MainActor
final class IslandAppModel: ObservableObject {
    @Published private(set) var activityState = FanActivityState()
    @Published private(set) var isAudioMuted = false
    @Published private(set) var collapsedSummaryConfiguration = CollapsedSummaryConfiguration.load()
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginStatusText = "Fantastic Island won't launch automatically when you sign in."
    @Published private(set) var interfaceLanguage: IslandInterfaceLanguage = .followSystem
    @Published private(set) var windDriveLogoPreset: WindDriveLogoPreset = .defaultMark
    @Published private(set) var usesCustomWindDriveLogo = false
    @Published private(set) var windDriveCustomLogoPath = ""
    @Published private(set) var windDriveCustomLogoImage: NSImage?
    @Published private(set) var showsExpandedWindDrivePanel = true
    @Published private(set) var enabledModuleIDs: Set<String> = []
    @Published var islandExpanded = false
    @Published private(set) var islandPeeking = false
    @Published private(set) var islandExpansionAnimationInFlight = false
    @Published private(set) var islandCollapseAnimationInFlight = false
    @Published var selectedModuleID: String
    @Published private(set) var allActivities: [IslandActivity] = []
    @Published private(set) var frontmostActivity: IslandActivity?
    @Published private(set) var presentedActivity: IslandActivity?
    @Published private(set) var openReason: IslandOpenReason?

    let codexFanModule: CodexModuleModel
    let clashModule: ClashModuleModel
    let playerModule: PlayerModuleModel
    let moduleRegistry: IslandModuleRegistry
    let designTokenStore = IslandDebugTokenStore()

    private let shellController = IslandShellController()
    private let audioController = CodexAudioController()
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
    private lazy var globalHotKeyController = IslandGlobalHotKeyController { [weak self] in
        Task { @MainActor [weak self] in
            self?.toggleIslandExpansionFromShortcut()
        }
    }
    private var cancellables: Set<AnyCancellable> = []
    private var measuredModuleContentHeights: [String: CGFloat] = [:]
    private var lockedExpandedContentHeight: CGFloat?
    private var pendingExpandedLayoutRefresh = false
    private var pendingAggregateRefresh = false
    private var spinAnchorDate = Date()
    private var spinAnchorDegrees = 0.0
    private var lastAggregateRefreshAt = Date()
    private var displayedScore = 0.0
    private var hasPrimedAudioState = false
    private var pendingExpansionSettleWorkItem: DispatchWorkItem?
    private var dismissedActivityIDs: Set<String> = []
    private var notificationAutoCollapseTask: Task<Void, Never>?
    private var notificationAutoCollapseActivityID: String?
    private var notificationAutoCollapseDelay: TimeInterval?
    private var notificationAutoCollapseShouldCollapsePanel = false

    init() {
        let codexFanModule = CodexModuleModel()
        let clashModule = ClashModuleModel()
        let playerModule = PlayerModuleModel()
        IslandDefaults.migrateLegacyValues()
        let allModules: [any IslandModule] = [codexFanModule, clashModule, playerModule]
        let defaults = UserDefaults.standard
        let loadedEnabledModuleIDs = Self.loadEnabledModuleIDs(defaults: defaults, availableModules: allModules)

        self.codexFanModule = codexFanModule
        self.clashModule = clashModule
        self.playerModule = playerModule
        self.moduleRegistry = IslandModuleRegistry(modules: allModules)
        self.isAudioMuted = defaults.bool(forKey: IslandDefaults.audioMutedKey)
        self.launchAtLoginEnabled = defaults.bool(forKey: IslandDefaults.launchAtLoginKey)
        self.interfaceLanguage = IslandInterfaceLanguage(
            rawValue: defaults.string(forKey: IslandDefaults.interfaceLanguageKey) ?? ""
        ) ?? .followSystem
        self.windDriveLogoPreset = WindDriveLogoPreset(
            rawValue: defaults.string(forKey: IslandDefaults.windDriveLogoPresetKey) ?? ""
        ) ?? .defaultMark
        self.usesCustomWindDriveLogo = defaults.bool(forKey: IslandDefaults.windDriveUsesCustomLogoKey)
        self.windDriveCustomLogoPath = defaults.string(forKey: IslandDefaults.windDriveCustomLogoPathKey) ?? ""
        self.showsExpandedWindDrivePanel =
            defaults.object(forKey: IslandDefaults.windDriveShowsExpandedPanelKey) as? Bool ?? true
        self.enabledModuleIDs = loadedEnabledModuleIDs
        self.selectedModuleID = loadedEnabledModuleIDs.first ?? codexFanModule.id
        self.windDriveCustomLogoImage = Self.loadImage(at: windDriveCustomLogoPath)
        normalizeSelectedModuleID()
        refreshLaunchAtLoginState()

        audioController.setMuted(isAudioMuted)
        bindModules()
        refreshFromModules(now: .now)
        shellController.show(using: self)
        _ = globalHotKeyController
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
            ?? codexFanModule
    }

    var islandUsesOpenedVisualState: Bool {
        islandExpanded || islandPeeking
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

    var isInteractivePeeking: Bool {
        islandPeeking && presentedPeekActivity?.kind == .actionRequired
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
            ClashModuleModel.moduleID,
            CodexModuleModel.moduleID,
        ]
        let supportedCompactModuleIDs = Set(compactModuleOrder)

        let summaries: [CompactModuleSummary] = enabledModules.compactMap { module in
            guard supportedCompactModuleIDs.contains(module.id) else {
                return nil
            }

            if module.id == ClashModuleModel.moduleID,
               let trafficItem = module.collapsedSummaryItems.first(where: { $0.id == "\(module.id).summary.traffic" }),
               collapsedSummaryConfiguration.isVisible(trafficItem) {
                return CompactModuleSummary(
                    moduleID: module.id,
                    title: module.title,
                    symbolName: module.symbolName,
                    iconAssetName: module.iconAssetName,
                    content: .clashTraffic(
                        upload: clashModule.uploadRateText,
                        download: clashModule.downloadRateText
                    )
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

    var isSpinning: Bool { activityState.isSpinning }
    var fanAnimationState: IslandFanAnimationState {
        IslandFanAnimationState(
            anchorDate: spinAnchorDate,
            anchorDegrees: spinAnchorDegrees,
            rotationPeriod: activityState.rotationPeriod,
            isSpinning: activityState.isSpinning
        )
    }
    var audioToggleSymbolName: String {
        isAudioMuted ? "speaker.slash.circle.fill" : "speaker.wave.2.circle.fill"
    }
    var islandLayoutTransitionInFlight: Bool {
        islandExpansionAnimationInFlight || islandCollapseAnimationInFlight
    }
    var closedSurfaceHeight: CGFloat {
        IslandShellController.defaultNotchSize.height
    }
    var peekContentHeight: CGFloat {
        guard let activity = presentedPeekActivity else {
            return closedSurfaceHeight
        }

        return peekContentHeight(for: activity)
    }
    var selectedModuleContentHeight: CGFloat {
        if islandCollapseAnimationInFlight, let lockedExpandedContentHeight {
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
        guard selectedModule.allowsInternalScrolling else {
            return false
        }

        let measurementKey = moduleContentMeasurementKey(
            for: selectedModule.id,
            presentation: selectedModulePresentationContext
        )
        guard let measuredContentHeight = measuredModuleContentHeights[measurementKey], measuredContentHeight > 0 else {
            return false
        }

        return measuredContentHeight
            + CodexIslandChromeMetrics.expandedContentBottomPadding
            - selectedModuleViewportHeight >= 2
    }
    func moduleHasPendingBadge(_ moduleID: String) -> Bool {
        allActivities.contains { activity in
            activity.moduleID == moduleID
                && activity.moduleID != selectedModuleID
                && activity.kind == .actionRequired
        }
    }
    var windDriveLogoDisplayPath: String? {
        guard usesCustomWindDriveLogo, !windDriveCustomLogoPath.isEmpty else {
            return nil
        }

        return windDriveCustomLogoPath
    }
    var canUseCustomWindDriveLogo: Bool { windDriveCustomLogoImage != nil }
    var expandShortcutDisplayText: String { IslandExpandShortcut.displayText }
    var resolvedLocale: Locale {
        if let localeIdentifier = interfaceLanguage.localeIdentifier {
            return Locale(identifier: localeIdentifier)
        }

        return .autoupdatingCurrent
    }

    func closedSurfaceWidth(baseCompactWidth: CGFloat) -> CGFloat {
        let moduleSpacing = CodexIslandChromeMetrics.closedModuleSpacing
        let horizontalPadding = CodexIslandChromeMetrics.closedHorizontalPadding * 2
        let fanWidth: CGFloat = 20
        let minimumGapAfterFan = CodexIslandChromeMetrics.closedFanModuleSpacing
        let modulesWidth = visibleCompactModules.reduce(0) { $0 + $1.estimatedWidth }
        let totalModuleSpacing = CGFloat(max(visibleCompactModules.count - 1, 0)) * moduleSpacing
        let preferredWidth = horizontalPadding + fanWidth + minimumGapAfterFan + modulesWidth + totalModuleSpacing
        return max(baseCompactWidth + 92, 332, preferredWidth)
    }

    func expandIsland(reason: IslandOpenReason = .manualTap) {
        guard !islandExpanded else {
            if openReason == nil {
                openReason = reason
            }
            return
        }

        beginIslandExpansionAnimation()
        islandPeeking = false
        shellController.prepareForExpansion(using: self)
        openReason = reason
        if !reason.isNotification {
            presentedActivity = nil
        }
        setIslandExpanded(true)
        updateNotificationAutoCollapse()
    }

    func collapseIsland() {
#if DEBUG
        guard debugPanelLockMode == .automatic else {
            return
        }
#endif
        notificationAutoCollapseTask?.cancel()
        notificationAutoCollapseTask = nil
        openReason = nil
        islandPeeking = false
        presentedActivity = nil
#if DEBUG
        debugActiveMockScenario = nil
#endif
        setIslandExpanded(false)
    }

    func presentPeek(for activity: IslandActivity) {
        guard !islandExpanded else {
            return
        }

        beginIslandExpansionAnimation()
        presentedActivity = activity
        openReason = nil
        islandPeeking = true
        shellController.prepareForPeek(using: self)
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

    func toggleIslandExpansionFromShortcut() {
        NSApplication.shared.activate(ignoringOtherApps: true)

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
            let didChange = selectedModuleID != id
            selectedModuleID = id
            if didChange {
                reconcileActivities(allowAutoPresentation: false)
            }
            if didChange, islandLayoutTransitionInFlight {
                lockExpandedLayoutHeight()
                pendingExpandedLayoutRefresh = true
            }
            if didChange, islandExpanded, !islandLayoutTransitionInFlight {
                shellController.reposition()
            }
        }
    }

    func updateMeasuredModuleContentHeight(
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
        guard moduleID == selectedModuleID else {
            return
        }

        if islandCollapseAnimationInFlight {
            pendingExpandedLayoutRefresh = true
            return
        }

        objectWillChange.send()

        if islandExpanded {
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
        isAudioMuted.toggle()
        UserDefaults.standard.set(isAudioMuted, forKey: IslandDefaults.audioMutedKey)
        audioController.setMuted(isAudioMuted)
        if !isAudioMuted {
            syncAudioState()
        }
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

    func setWindDriveLogoPreset(_ preset: WindDriveLogoPreset) {
        windDriveLogoPreset = preset
        usesCustomWindDriveLogo = false
        let defaults = UserDefaults.standard
        defaults.set(preset.rawValue, forKey: IslandDefaults.windDriveLogoPresetKey)
        defaults.set(false, forKey: IslandDefaults.windDriveUsesCustomLogoKey)
    }

    func selectCustomWindDriveLogo() {
        let panel = NSOpenPanel()
        panel.title = NSLocalizedString("Choose a Wind Drive Logo", comment: "")
        panel.prompt = NSLocalizedString("Use Image", comment: "")
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let path = url.path
        windDriveCustomLogoPath = path
        windDriveCustomLogoImage = Self.loadImage(at: path)
        usesCustomWindDriveLogo = windDriveCustomLogoImage != nil

        let defaults = UserDefaults.standard
        defaults.set(path, forKey: IslandDefaults.windDriveCustomLogoPathKey)
        defaults.set(usesCustomWindDriveLogo, forKey: IslandDefaults.windDriveUsesCustomLogoKey)
    }

    func clearCustomWindDriveLogo() {
        usesCustomWindDriveLogo = false
        UserDefaults.standard.set(false, forKey: IslandDefaults.windDriveUsesCustomLogoKey)
    }

    func setShowsExpandedWindDrivePanel(_ showsPanel: Bool) {
        showsExpandedWindDrivePanel = showsPanel
        UserDefaults.standard.set(showsPanel, forKey: IslandDefaults.windDriveShowsExpandedPanelKey)

        if islandExpanded, !islandLayoutTransitionInFlight {
            shellController.reposition()
        }
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
        [codexFanModule.objectWillChange, clashModule.objectWillChange, playerModule.objectWillChange].forEach { publisher in
            publisher
                .sink { [weak self] _ in
                    DispatchQueue.main.async { [weak self] in
                        guard let self else {
                            return
                        }

                        if self.islandLayoutTransitionInFlight {
                            self.pendingAggregateRefresh = true
                            return
                        }

                        self.objectWillChange.send()
                        self.refreshFromModules(now: .now)
                    }
                }
                .store(in: &cancellables)
        }

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

    private func setIslandExpanded(_ expanded: Bool) {
        guard islandExpanded != expanded else {
            return
        }

        if expanded {
            islandCollapseAnimationInFlight = false
            islandPeeking = false
        }

        islandExpanded = expanded
        shellController.reposition()
    }

    private func beginIslandExpansionAnimation() {
        pendingExpansionSettleWorkItem?.cancel()
        pendingExpandedLayoutRefresh = false
        islandExpansionAnimationInFlight = true

        let workItem = DispatchWorkItem { [weak self] in
            self?.finishIslandExpansionAnimation()
        }

        pendingExpansionSettleWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + CodexIslandChromeMetrics.openLayoutSettleDuration,
            execute: workItem
        )
    }

    private func finishIslandExpansionAnimation() {
        pendingExpansionSettleWorkItem?.cancel()
        pendingExpansionSettleWorkItem = nil

        guard islandExpansionAnimationInFlight else {
            return
        }

        islandExpansionAnimationInFlight = false
        if !islandCollapseAnimationInFlight {
            lockedExpandedContentHeight = nil
            flushDeferredAggregateRefreshIfNeeded()
        }

        guard islandExpanded, pendingExpandedLayoutRefresh else {
            pendingExpandedLayoutRefresh = false
            return
        }

        pendingExpandedLayoutRefresh = false
        shellController.reposition()
    }

    private func refreshFromModules(now: Date) {
        let previousState = activityState
        let preservedRotation = normalizedRotation(
            FanRotationMath.degrees(
                anchorDate: spinAnchorDate,
                anchorDegrees: spinAnchorDegrees,
                rotationPeriod: previousState.rotationPeriod,
                isSpinning: previousState.isSpinning,
                at: now
            )
        )
        let delta = min(max(now.timeIntervalSince(lastAggregateRefreshAt), 0), 2.0)
        lastAggregateRefreshAt = now

        let aggregated = TaskActivityAggregator.aggregate(modules.map { $0.taskActivityContribution })
        let speedTier = FanSpeedTier.resolve(
            hasActivitySource: aggregated.supportsIdleSpin,
            inProgressTaskCount: aggregated.inProgressTaskCount
        )
        let decayFactor = pow(0.92, delta / 0.2)
        displayedScore = max(aggregated.activityScore, displayedScore * decayFactor)
        activityState = FanActivityState(
            activityScore: displayedScore,
            isSpinning: speedTier.isSpinning,
            rotationPeriod: speedTier.rotationPeriod,
            activeSessionCount: aggregated.activeTaskCount,
            inProgressSessionCount: aggregated.inProgressTaskCount,
            busySessionCount: aggregated.busyTaskCount,
            lastEventAt: aggregated.lastEventAt
        )

        updateSpinAnchor(
            previousState: previousState,
            nextState: activityState,
            preservedRotation: preservedRotation,
            now: now
        )
        reconcileActivities(allowAutoPresentation: true)
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
           let frontmostActivity,
           islandPeeking,
           shouldAutoPresent(frontmostActivity, comparedTo: previousActivitiesByID, allowDuringPeek: true) {
            selectModuleIfNeededForAutoPresentation(frontmostActivity)
            presentedActivity = frontmostActivity
            presentPeek(for: frontmostActivity)
        } else if allowAutoPresentation,
                  let frontmostActivity,
                  shouldAutoPresent(frontmostActivity, comparedTo: previousActivitiesByID) {
            selectModuleIfNeededForAutoPresentation(frontmostActivity)
            presentedActivity = frontmostActivity
            presentPeek(for: frontmostActivity)
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
        dismissedActivityIDs.insert(id)
        reconcileActivities(allowAutoPresentation: false)

        if collapseIfNeeded, islandPeeking, presentedActivity?.id == id {
            islandPeeking = false
            presentedActivity = nil
            shellController.reposition()
            return
        }

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
        beginIslandExpansionAnimation()
        presentedActivity = activity
        openReason = nil
        islandPeeking = true
        setIslandExpanded(false)
        shellController.prepareForPeek(using: self)
    }

    private func collapseIslandFromDebugTool() {
        resetNotificationAutoCollapse()
        openReason = nil
        islandPeeking = false
        presentedActivity = nil
        setIslandExpanded(false)
    }
#endif

    private func updateSpinAnchor(
        previousState: FanActivityState,
        nextState: FanActivityState,
        preservedRotation: Double,
        now: Date
    ) {
        guard nextState.isSpinning else {
            spinAnchorDate = now
            spinAnchorDegrees = preservedRotation
            return
        }

        if !previousState.isSpinning || FanRotationMath.shouldRetuneRotationPeriod(
            from: previousState.rotationPeriod,
            to: nextState.rotationPeriod,
            threshold: islandFanRotationRetuneThreshold
        ) {
            spinAnchorDate = now
            spinAnchorDegrees = preservedRotation
        }
    }

    private func syncAudioState() {
        if !hasPrimedAudioState {
            audioController.primePlayback(inProgressSessionCount: activityState.inProgressSessionCount)
            hasPrimedAudioState = true
            return
        }

        audioController.syncPlayback(inProgressSessionCount: activityState.inProgressSessionCount)
    }

    private func normalizedRotation(_ degrees: Double) -> Double {
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }

    private func flushDeferredAggregateRefreshIfNeeded() {
        guard pendingAggregateRefresh else {
            return
        }

        pendingAggregateRefresh = false
        objectWillChange.send()
        refreshFromModules(now: .now)
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
        let maximumHeight = max(preferredHeightWithStandardBottomPadding, minimumHeight)

        guard measuredContentHeight > 0 else {
            return maximumHeight
        }

        switch resolvedPresentation {
        case .standard, .activity:
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
            return showsExpandedWindDrivePanel
                ? CodexIslandChromeMetrics.minimumExpandedHeightWithWindDrivePanel
                : 0
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
        let sanitizedIDs = availableIDs.intersection(storedIDs)
        return sanitizedIDs.isEmpty ? availableIDs : sanitizedIDs
    }

    private static func loadImage(at path: String) -> NSImage? {
        guard !path.isEmpty else {
            return nil
        }

        return NSImage(contentsOf: URL(fileURLWithPath: path))
    }
}
