import AppKit
import Combine
import Foundation
import SwiftUI

private final class PendingHookApprovalDecision: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    let eventName: CodexHookEventName
    nonisolated(unsafe) private var resolved = false
    nonisolated(unsafe) private var directive: CodexHookDirective?

    nonisolated init(eventName: CodexHookEventName) {
        self.eventName = eventName
    }

    nonisolated
    func resolve(_ directive: CodexHookDirective?) {
        lock.lock()
        defer { lock.unlock() }
        guard !resolved else {
            return
        }
        resolved = true
        self.directive = directive
        semaphore.signal()
    }

    nonisolated
    func wait(timeout: TimeInterval) -> (resolved: Bool, directive: CodexHookDirective?) {
        let result = semaphore.wait(timeout: .now() + timeout)
        lock.lock()
        defer { lock.unlock() }
        if result == .success {
            return (true, directive)
        }
        return (false, nil)
    }
}

private func firstNonEmpty(_ values: [String?]) -> String? {
    values
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
}

@MainActor
final class CodexModuleModel: ObservableObject, IslandModule {
    static let moduleID = "codex"
    nonisolated private static let hookApprovalTimeout: TimeInterval = 35
    private static let preferredExpandedContentHeight: CGFloat =
        CodexIslandChromeMetrics.preferredTallModuleOpenedContentHeight
    private static let preferredEmptyExpandedContentHeight: CGFloat =
        CodexIslandChromeMetrics.expandedContentTopPadding
        + CodexIslandChromeMetrics.windDrivePanelHeight
    private static let estimatedGlobalInfoCardHeight: CGFloat = 58
    private static let estimatedContentSpacing: CGFloat = 12
    private static let estimatedSessionRowHeight: CGFloat = 88
    private static let estimatedSessionRowSpacing: CGFloat = 6
    private static let estimatedActionableSessionHeight: CGFloat = 196
    private static let estimatedApprovalSessionHeight: CGFloat = 248
    private static let estimatedTransientSessionHeight: CGFloat = 196
    private static let estimatedPeekNotificationHeight: CGFloat = 120
    private static let estimatedFooterButtonHeight: CGFloat = 28
    private static let transientNotificationAutoDismissDelay: TimeInterval = 3

    @Published private(set) var activityState = FanActivityState()
    @Published private(set) var hooksStatus = HookInstallStatus.notInstalled
    @Published private(set) var bridgeStatusText = "Starting"
    @Published private(set) var appServerStatusText = "Disconnected"
    @Published private(set) var sessionSurface: CodexIslandSurface = .sessionList(actionableSessionID: nil)
    @Published private(set) var isNotificationMode = false
    @Published private(set) var lastActionMessage: String?

    let id = CodexModuleModel.moduleID
    let title = "Codex"
    let symbolName = "terminal"
    let iconAssetName: String? = "codexicon"

    private let monitoringEngine = CodexMonitoringEngine()
    private let hookManager = CodexHookManager()
    private let hookBridgeServer = HookBridgeServer()
    private let appServerCoordinator = CodexAppServerCoordinator()
    private let terminalJumpService = CodexTerminalJumpService()
    private let terminalTextSender = CodexTerminalTextSender()

    private var pollTimer: Timer?
    private var monitoredSessions: [SessionSnapshot] = []
    private var latestQuotaSnapshot: CodexQuotaSnapshot?
    private var lastActivityRefreshAt = Date()
    private var displayedScore = 0.0
    private let pollInterval = 1.0
    private let activeRolloutPollInterval: TimeInterval = 5
    private let idleRolloutPollInterval: TimeInterval = 20
    private var lastRolloutPollAt = Date.distantPast
    private var isRolloutPollInFlight = false
    private var isCodexCurrentlyRunning = false
    private var pendingHookApprovals: [String: PendingHookApprovalDecision] = [:]

    init() {
        hookBridgeServer.onPayload = { [weak self] payload in
            guard let self else {
                return nil
            }
            return self.handleHookBridgePayload(payload)
        }

        appServerCoordinator.onEvent = { [weak self] event in
            self?.handleAgentEvent(event)
        }
        appServerCoordinator.onStatusMessage = { [weak self] message in
            self?.appServerStatusText = message
        }

        do {
            try hookBridgeServer.start()
            bridgeStatusText = "Ready"
        } catch {
            bridgeStatusText = "Unavailable"
            hooksStatus = .error("Bridge unavailable: \(error.localizedDescription)")
        }

        refreshHooksStatus()
        refreshActivityState(now: .now)
        let codexRunning = CodexProcessMonitor.isCodexRunning()
        isCodexCurrentlyRunning = codexRunning
        pollRollouts(force: true, codexRunning: codexRunning)
        refreshAppServerConnection(codexRunning: codexRunning)
        startPollingTimer()
    }

    deinit {
        pollTimer?.invalidate()
    }

    var quotaSnapshot: CodexQuotaSnapshot? { latestQuotaSnapshot }

    var sessionBuckets: CodexIslandSessionBuckets {
        CodexIslandSessionPresentation.computeBuckets(from: monitoredSessions)
    }

    var islandListSessions: [SessionSnapshot] {
        sessionBuckets.primary
    }

    var activeNotificationSession: SessionSnapshot? {
        guard isNotificationMode,
              let actionableSessionID = sessionSurface.sessionID else {
            return nil
        }

        return monitoredSessions.first { $0.id == actionableSessionID }
    }

    var shouldShowShowAllButton: Bool {
        isNotificationMode
            && activeNotificationSession != nil
            && islandListSessions.count > 1
    }

    var canCollapseSessionList: Bool {
        !isNotificationMode && sessionSurface.sessionID != nil
    }

    var compactFiveHourQuotaText: String { compactQuotaText(prefix: "5H", value: quotaSnapshot?.fiveHourRemainingPercent) }
    var compactWeekQuotaText: String { compactQuotaText(prefix: "W", value: quotaSnapshot?.weekRemainingPercent) }
    var compactLiveSessionsText: String { "LIVE \(activityState.inProgressSessionCount)" }
    var globalInfoLiveCountText: String { "\(activityState.inProgressSessionCount)" }
    var globalInfoFiveHourValueText: String { quotaValueText(quotaSnapshot?.fiveHourRemainingPercent) }
    var globalInfoWeekValueText: String { quotaValueText(quotaSnapshot?.weekRemainingPercent) }
    var globalInfoFiveHourResetCompactText: String { quotaResetTimeCompactText(quotaSnapshot?.fiveHourResetAt) }
    var globalInfoWeekResetCompactText: String { quotaResetCompactText(quotaSnapshot?.weekResetAt) }
    var expandedFiveHourQuotaText: String { expandedQuotaText(title: "5H Left", value: quotaSnapshot?.fiveHourRemainingPercent) }
    var expandedWeekQuotaText: String { expandedQuotaText(title: "Week Left", value: quotaSnapshot?.weekRemainingPercent) }
    var fiveHourResetDescriptionText: String { quotaResetText(quotaSnapshot?.fiveHourResetAt) }
    var weekResetDescriptionText: String { quotaResetText(quotaSnapshot?.weekResetAt) }

    var hooksActionTitle: String {
        hooksStatus.isInstalled
            ? NSLocalizedString("Reinstall Hooks", comment: "")
            : NSLocalizedString("Install", comment: "")
    }

    var hooksMenuStatusText: String {
        switch hooksStatus {
        case .installed:
            return NSLocalizedString("Installed", comment: "")
        case .notInstalled:
            return NSLocalizedString("Not installed", comment: "")
        case let .error(message):
            return String(
                format: NSLocalizedString("Error: %@", comment: ""),
                locale: .current,
                message
            )
        }
    }

    var collapsedSummaryItems: [CollapsedSummaryItem] {
        [
            CollapsedSummaryItem(
                id: "\(id).summary.5h",
                moduleID: id,
                title: "5H quota",
                text: compactFiveHourQuotaText,
                isEnabledByDefault: true
            ),
            CollapsedSummaryItem(
                id: "\(id).summary.week",
                moduleID: id,
                title: "Week quota",
                text: compactWeekQuotaText,
                isEnabledByDefault: true
            ),
            CollapsedSummaryItem(
                id: "\(id).summary.live",
                moduleID: id,
                title: "Live sessions",
                text: compactLiveSessionsText,
                isEnabledByDefault: true
            ),
        ]
    }

    var taskActivityContribution: TaskActivityContribution {
        TaskActivityContribution(
            activityScore: activityState.activityScore,
            activeTaskCount: activityState.activeSessionCount,
            inProgressTaskCount: activityState.inProgressSessionCount,
            busyTaskCount: activityState.busySessionCount,
            lastEventAt: activityState.lastEventAt,
            supportsIdleSpin: isCodexCurrentlyRunning
        )
    }

    var islandActivities: [IslandActivity] {
        monitoredSessions.compactMap { session in
            let updatedAt = session.islandActivityDate
            guard updatedAt > .distantPast else {
                return nil
            }

            switch session.phase {
            case .waitingForApproval:
                return IslandActivity(
                    id: "\(id).activity.permission.\(session.id)",
                    moduleID: id,
                    sourceID: session.id,
                    kind: .actionRequired,
                    priority: 300,
                    createdAt: updatedAt,
                    updatedAt: updatedAt,
                    presentationPolicy: IslandActivityPresentationPolicy(
                        autoPresentationScope: .global,
                        autoDismissDelay: nil
                    )
                )
            case .waitingForAnswer:
                return IslandActivity(
                    id: "\(id).activity.question.\(session.id)",
                    moduleID: id,
                    sourceID: session.id,
                    kind: .actionRequired,
                    priority: 290,
                    createdAt: updatedAt,
                    updatedAt: updatedAt,
                    presentationPolicy: IslandActivityPresentationPolicy(
                        autoPresentationScope: .global,
                        autoDismissDelay: nil
                    )
                )
            case .completed:
                guard !session.isSessionEnded else {
                    return nil
                }

                return IslandActivity(
                    id: "\(id).activity.completed.\(session.id)",
                    moduleID: id,
                    sourceID: session.id,
                    kind: .transientNotification,
                    priority: 180,
                    createdAt: updatedAt,
                    updatedAt: updatedAt,
                    presentationPolicy: IslandActivityPresentationPolicy(
                        autoPresentationScope: .selectedModuleOnly,
                        autoDismissDelay: Self.transientNotificationAutoDismissDelay
                    )
                )
            case .running, .busy:
                return nil
            }
        }
    }

    var preferredOpenedContentHeight: CGFloat {
        guard !islandListSessions.isEmpty else {
            return Self.preferredEmptyExpandedContentHeight
        }

        let estimatedContentHeight =
            Self.estimatedGlobalInfoCardHeight
            + Self.estimatedContentSpacing
            + estimatedSessionSectionHeight
        let estimatedOpenedHeight = CodexIslandChromeMetrics.moduleChromeHeight + estimatedContentHeight
        return min(
            Self.preferredExpandedContentHeight,
            max(Self.preferredEmptyExpandedContentHeight, estimatedOpenedHeight)
        )
    }

    private var estimatedSessionSectionHeight: CGFloat {
        if isNotificationMode, activeNotificationSession != nil {
            let showsFooter = shouldShowShowAllButton
            return estimatedActionableSessionHeight(for: activeNotificationSession)
                + (showsFooter ? Self.estimatedContentSpacing + Self.estimatedFooterButtonHeight : 0)
        }

        let sessionCount = islandListSessions.count
        let rowsHeight =
            (CGFloat(sessionCount) * Self.estimatedSessionRowHeight)
            + (CGFloat(max(sessionCount - 1, 0)) * Self.estimatedSessionRowSpacing)
        let showsFooter = canCollapseSessionList
        return rowsHeight
            + (showsFooter ? Self.estimatedContentSpacing + Self.estimatedFooterButtonHeight : 0)
    }

    func preferredOpenedContentHeight(for presentation: IslandModulePresentationContext) -> CGFloat {
        switch presentation {
        case .standard:
            return preferredOpenedContentHeight
        case let .activity(activity):
            let estimatedBodyHeight: CGFloat
            switch activity.kind {
            case .actionRequired:
                estimatedBodyHeight = estimatedActionableSessionHeight(for: session(for: activity))
            case .transientNotification:
                estimatedBodyHeight = Self.estimatedTransientSessionHeight
            case .persistentPresence:
                estimatedBodyHeight = Self.estimatedSessionRowHeight
            }

            return CodexIslandChromeMetrics.moduleChromeHeight
                + estimatedBodyHeight
                + CodexIslandChromeMetrics.expandedContentBottomPadding
        case .peek:
            if case let .peek(activity) = presentation,
               activity.kind == .actionRequired {
                return CodexIslandPeekMetrics.contentTopPadding
                    + estimatedActionableSessionHeight(for: session(for: activity))
                    + CodexIslandPeekMetrics.contentBottomPadding
            }

            return CodexIslandPeekMetrics.contentTopPadding
                + Self.estimatedPeekNotificationHeight
                + CodexIslandPeekMetrics.contentBottomPadding
        }
    }

    func makeRenderSnapshot(presentation: IslandModulePresentationContext) -> IslandModuleRenderSnapshot {
        IslandModuleRenderSnapshot(
            id: "\(id)::\(presentation.cacheKey)",
            moduleID: id,
            presentation: presentation,
            preferredHeight: preferredOpenedContentHeight(for: presentation),
            allowsInternalScrolling: allowsInternalScrolling,
            view: AnyView(CodexModuleContentView(state: makeRenderState(for: presentation)))
        )
    }

    func makeLiveContentView(presentation: IslandModulePresentationContext) -> AnyView {
        AnyView(CodexModuleLiveContentView(model: self, presentation: presentation))
    }

    func makeRenderState(for presentation: IslandModulePresentationContext) -> CodexModuleRenderState {
        let presentedSession: SessionSnapshot?
        switch presentation {
        case let .activity(activity), let .peek(activity):
            presentedSession = session(for: activity)
        case .standard:
            presentedSession = nil
        }

        return CodexModuleRenderState(
            presentation: presentation,
            activityState: activityState,
            sessionSurface: sessionSurface,
            isNotificationMode: isNotificationMode,
            islandListSessions: islandListSessions,
            activeNotificationSession: activeNotificationSession,
            presentedSession: presentedSession,
            shouldShowShowAllButton: shouldShowShowAllButton,
            canCollapseSessionList: canCollapseSessionList,
            globalInfoLiveCountText: globalInfoLiveCountText,
            globalInfoFiveHourValueText: globalInfoFiveHourValueText,
            globalInfoWeekValueText: globalInfoWeekValueText,
            globalInfoFiveHourResetCompactText: globalInfoFiveHourResetCompactText,
            globalInfoWeekResetCompactText: globalInfoWeekResetCompactText,
            approvePermission: { [weak self] sessionID, action in
                Task { @MainActor in
                    self?.approvePermission(for: sessionID, action: action)
                }
            },
            answerQuestion: { [weak self] sessionID, response in
                Task { @MainActor in
                    self?.answerQuestion(for: sessionID, response: response)
                }
            },
            replyToSession: { [weak self] sessionID, text in
                Task { @MainActor in
                    _ = self?.replyToSession(sessionID, text: text)
                }
            },
            jumpToSession: { [weak self] sessionID in
                Task { @MainActor in
                    self?.jumpToSession(sessionID)
                }
            },
            showAllSessions: { [weak self] in
                Task { @MainActor in
                    self?.showAllSessions()
                }
            },
            collapseSessionList: { [weak self] in
                Task { @MainActor in
                    self?.collapseSessionList()
                }
            }
        )
    }

    private func estimatedActionableSessionHeight(for session: SessionSnapshot?) -> CGFloat {
        session?.phase == .waitingForApproval
            ? Self.estimatedApprovalSessionHeight
            : Self.estimatedActionableSessionHeight
    }

    func session(for activity: IslandActivity) -> SessionSnapshot? {
        monitoredSessions.first(where: { $0.id == activity.sourceID })
            ?? Self.debugSession(for: activity)
    }

    func installOrReinstallHooks() {
        let alert = NSAlert()
        alert.messageText = hooksStatus.isInstalled
            ? NSLocalizedString("Reinstall Fantastic Island Hooks?", comment: "")
            : NSLocalizedString("Install Fantastic Island Hooks?", comment: "")
        alert.informativeText = NSLocalizedString(
            "This will update ~/.codex/config.toml and ~/.codex/hooks.json so the codex module can receive SessionStart, PreToolUse, PermissionRequest, PostToolUse, UserPromptSubmit, and Stop events.",
            comment: ""
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: hooksStatus.isInstalled ? NSLocalizedString("Reinstall", comment: "") : NSLocalizedString("Install", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try hookManager.install()
            refreshHooksStatus()
        } catch {
            hooksStatus = .error(error.localizedDescription)
            presentErrorAlert(
                title: NSLocalizedString("Failed to install hooks", comment: ""),
                message: error.localizedDescription
            )
        }
    }

    func uninstallHooks() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Uninstall Fantastic Island Hooks?", comment: "")
        alert.informativeText = NSLocalizedString(
            "This removes Fantastic Island managed hook entries and turns off the managed codex_hooks flag.",
            comment: ""
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Uninstall", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try hookManager.uninstall()
            refreshHooksStatus()
        } catch {
            hooksStatus = .error(error.localizedDescription)
            presentErrorAlert(
                title: NSLocalizedString("Failed to uninstall hooks", comment: ""),
                message: error.localizedDescription
            )
        }
    }

    func openCodexDirectory() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    func refreshModuleStatus() {
        refreshHooksStatus()
        let codexRunning = CodexProcessMonitor.isCodexRunning()
        isCodexCurrentlyRunning = codexRunning
        refreshAppServerConnection(codexRunning: codexRunning)
    }

    func showAllSessions() {
        isNotificationMode = false
    }

    func collapseSessionList() {
        guard sessionSurface.sessionID != nil else {
            return
        }
        isNotificationMode = true
    }

    func jumpToSession(_ sessionID: String) {
        guard let session = monitoredSessions.first(where: { $0.id == sessionID }),
              let jumpTarget = session.jumpTarget,
              jumpTarget.canActivate else {
            return
        }

        do {
            try terminalJumpService.jump(to: jumpTarget)
        } catch {
            presentErrorAlert(title: "Failed to Jump Back", message: error.localizedDescription)
        }
    }

    private static func debugSession(for activity: IslandActivity) -> SessionSnapshot? {
        let now = Date()

        switch activity.sourceID {
        case "debug.codex.session.approval":
            return SessionSnapshot(
                id: activity.sourceID,
                cwd: "/tmp/fantastic-island-debug",
                title: "Approve design-token writeback",
                phase: .waitingForApproval,
                lastEventAt: now,
                currentTool: "write_file",
                currentCommandPreview: "write IslandShellChromeMetrics.swift",
                latestUserPrompt: "Apply the approved design token values to the governed shell metrics.",
                assistantSummary: "Awaiting confirmation before replacing the saved shell metrics values.",
                permissionRequest: CodexPermissionRequest(
                    title: "Allow source writeback?",
                    summary: "This mock approval card lets you tune actionable Codex peek layouts without needing a live permission request.",
                    affectedPath: "~/.fantastic-island/Shell/IslandShellChromeMetrics.swift",
                    primaryActionTitle: "Approve",
                    secondaryActionTitle: "Deny",
                    alwaysActionTitle: "Always Allow",
                    toolName: "write_file"
                ),
                pendingRequestContext: CodexPendingRequestContext(
                    requestID: "debug.codex.permission",
                    source: .appServer,
                    kind: .permission
                ),
                sessionSurface: .codexApp,
                sourceFlags: [.appServer],
                isSessionEnded: false
            )
        case "debug.codex.session.completed":
            return SessionSnapshot(
                id: activity.sourceID,
                cwd: "/tmp/fantastic-island-debug",
                title: "Refined notch timing",
                phase: .completed,
                lastEventAt: now,
                latestUserPrompt: "Tighten the notch reveal choreography and keep the compact pills stable during expansion.",
                latestAssistantMessage: "Adjusted the reveal sequence and kept the compact header anchored while the body fades in.",
                completionMessageMarkdown: "Updated the shell transition timings and verified the expanded body no longer flashes during open.",
                assistantSummary: "Shell reveal timing retuned and validated.",
                sessionSurface: .codexApp,
                sourceFlags: [.appServer],
                isSessionEnded: false
            )
        default:
            return nil
        }
    }

    func replyToSession(_ sessionID: String, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        guard let session = monitoredSessions.first(where: { $0.id == sessionID }),
              let jumpTarget = session.jumpTarget,
              jumpTarget.canReply else {
            return false
        }

        do {
            try terminalTextSender.send(trimmed, to: jumpTarget)
            return true
        } catch {
            presentErrorAlert(title: "Failed to send text", message: error.localizedDescription)
            return false
        }
    }

    func approvePermission(for sessionID: String, action: CodexApprovalAction) {
        guard let session = monitoredSessions.first(where: { $0.id == sessionID }),
              let requestContext = session.pendingRequestContext else {
            return
        }

        switch requestContext.source {
        case .appServer:
            Task { [weak self] in
                guard let self else { return }
                let success = await appServerCoordinator.resolvePermission(requestContext: requestContext, action: action)
                await MainActor.run {
                    if !success {
                        self.lastActionMessage = "Approval backend unavailable, fail-open."
                        self.handleAgentEvent(.actionableStateResolved(
                            ActionableStateResolvedEvent(
                                sessionID: sessionID,
                                summary: action.isApproved ? "Approval sent (local)." : "Denied (local).",
                                timestamp: .now
                            )
                        ))
                    } else {
                        self.lastActionMessage = nil
                    }
                }
            }

        case .hook:
            resolveHookApproval(requestID: requestContext.requestID, sessionID: sessionID, action: action)
        }
    }

    func answerQuestion(for sessionID: String, response: CodexQuestionResponse) {
        guard let session = monitoredSessions.first(where: { $0.id == sessionID }),
              let requestContext = session.pendingRequestContext else {
            return
        }

        switch requestContext.source {
        case .appServer:
            Task { [weak self] in
                guard let self else { return }
                let success = await appServerCoordinator.resolveQuestion(requestContext: requestContext, response: response)
                await MainActor.run {
                    if !success {
                        self.lastActionMessage = "Question backend unavailable, fail-open."
                        self.handleAgentEvent(.actionableStateResolved(
                            ActionableStateResolvedEvent(
                                sessionID: sessionID,
                                summary: "Answer sent (local).",
                                timestamp: .now
                            )
                        ))
                    } else {
                        self.lastActionMessage = nil
                    }
                }
            }

        case .hook:
            if let rawAnswer = response.rawAnswer {
                _ = replyToSession(sessionID, text: rawAnswer)
            }
            handleAgentEvent(.actionableStateResolved(
                ActionableStateResolvedEvent(
                    sessionID: sessionID,
                    summary: "Answer sent.",
                    timestamp: .now
                )
            ))
        }
    }

    private func refreshHooksStatus() {
        do {
            hooksStatus = try hookManager.status()
        } catch {
            hooksStatus = .error(error.localizedDescription)
        }
    }

    private func startPollingTimer() {
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollIfNeeded()
            }
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func pollIfNeeded() {
        let codexRunning = CodexProcessMonitor.isCodexRunning()
        isCodexCurrentlyRunning = codexRunning
        refreshActivityState(now: .now)
        pollRollouts(codexRunning: codexRunning)
        refreshAppServerConnection(codexRunning: codexRunning)
    }

    private func refreshActivityState(now: Date) {
        let delta = min(max(now.timeIntervalSince(lastActivityRefreshAt), 0), max(pollInterval * 2, 0.25))
        lastActivityRefreshAt = now
        let freshState = FanActivityModel.recompute(
            from: monitoredSessions,
            now: now
        )
        let decayFactor = pow(0.92, delta / 0.2)
        displayedScore = max(freshState.activityScore, displayedScore * decayFactor)
        activityState = FanActivityState(
            activityScore: displayedScore,
            isSpinning: freshState.isSpinning,
            rotationPeriod: freshState.rotationPeriod,
            activeSessionCount: freshState.activeSessionCount,
            inProgressSessionCount: freshState.inProgressSessionCount,
            busySessionCount: freshState.busySessionCount,
            lastEventAt: freshState.lastEventAt
        )
    }

    private func pollRollouts(force: Bool = false, codexRunning: Bool) {
        if isRolloutPollInFlight && !force {
            return
        }

        let now = Date()
        let pollInterval = rolloutPollInterval(codexRunning: codexRunning)
        if !force, now.timeIntervalSince(lastRolloutPollAt) < pollInterval {
            return
        }

        isRolloutPollInFlight = true
        lastRolloutPollAt = now
        monitoringEngine.poll { [weak self] snapshot in
            self?.isRolloutPollInFlight = false
            self?.applyMonitoringSnapshot(snapshot, refreshedAt: .now)
        }
    }

    private func rolloutPollInterval(codexRunning: Bool) -> TimeInterval {
        if codexRunning || activityState.inProgressSessionCount > 0 || isNotificationMode {
            return activeRolloutPollInterval
        }

        return idleRolloutPollInterval
    }

    private func refreshAppServerConnection(codexRunning: Bool) {
        if codexRunning {
            appServerCoordinator.ensureConnected()
        } else {
            appServerCoordinator.disconnect()
        }
    }

    nonisolated private func handleHookBridgePayload(_ payload: CodexHookPayload) -> CodexHookDirective? {
        let needsInteractiveApproval =
            payload.sessionSurface != .codexApp
            && (
                payload.hookEventName == .permissionRequest
                    || (
                        payload.hookEventName == .preToolUse
                            && payload.permissionMode != .dontAsk
                            && payload.permissionMode != .bypassPermissions
                    )
            )

        guard needsInteractiveApproval else {
            Task { @MainActor [weak self] in
                self?.handleHookPayload(payload)
            }
            return nil
        }

        let requestID = "hook:\(UUID().uuidString)"
        let pendingDecision = PendingHookApprovalDecision(eventName: payload.hookEventName)

        Task { @MainActor [weak self] in
            self?.registerHookApproval(payload: payload, requestID: requestID, decision: pendingDecision)
        }

        let result = pendingDecision.wait(timeout: Self.hookApprovalTimeout)
        if !result.resolved {
            Task { @MainActor [weak self] in
                self?.handleHookApprovalTimeout(requestID: requestID)
            }
            return nil
        }

        return result.directive
    }

    private func registerHookApproval(payload: CodexHookPayload, requestID: String, decision: PendingHookApprovalDecision) {
        pendingHookApprovals[requestID] = decision
        let summary =
            firstNonEmpty([
                payload.toolInput?.description,
                payload.toolInput?.command,
                payload.prompt,
                "\(payload.toolName ?? "Tool") needs approval.",
            ]) ?? "Approval required."
        let request = CodexPermissionRequest(
            title: "Approval Required",
            summary: clipped(summary, limit: 260) ?? "Approval required.",
            affectedPath: payload.cwd,
            toolName: payload.toolName,
            toolUseID: payload.toolUseID,
            requiresTerminalApproval: true
        )
        let event = CodexAgentEvent.permissionRequested(
            PermissionRequestedEvent(
                sessionID: payload.sessionID,
                request: request,
                requestContext: CodexPendingRequestContext(
                    requestID: requestID,
                    source: .hook,
                    kind: .permission,
                    method: payload.hookEventName == .permissionRequest ? "hook/permissionRequest" : "hook/preToolUse",
                    itemID: payload.toolUseID,
                    turnID: payload.turnID,
                    threadID: payload.sessionID,
                    createdAt: .now
                ),
                timestamp: .now
            )
        )

        refreshHooksStatus()
        monitoringEngine.applyHookPayload(payload, followedBy: event) { [weak self] snapshot in
            self?.applyMonitoringSnapshot(snapshot, refreshedAt: .now)
            self?.presentActionableSurfaceIfNeeded(for: event)
        }
    }

    private func resolveHookApproval(requestID: String, sessionID: String, action: CodexApprovalAction) {
        guard let pendingDecision = pendingHookApprovals.removeValue(forKey: requestID) else {
            return
        }

        if action.isApproved {
            pendingDecision.resolve(CodexHookDirective.allow(for: pendingDecision.eventName))
            handleAgentEvent(.actionableStateResolved(
                ActionableStateResolvedEvent(
                    sessionID: sessionID,
                    summary: "Approval sent.",
                    timestamp: .now
                )
            ))
        } else {
            pendingDecision.resolve(CodexHookDirective.deny(
                reason: "Permission denied in Fantastic Island.",
                for: pendingDecision.eventName
            ))
            handleAgentEvent(.sessionCompleted(
                SessionCompletedEvent(
                    sessionID: sessionID,
                    summary: "Permission denied in Fantastic Island.",
                    timestamp: .now,
                    isSessionEnd: false
                )
            ))
        }
    }

    private func handleHookApprovalTimeout(requestID: String) {
        guard pendingHookApprovals.removeValue(forKey: requestID) != nil else {
            return
        }

        guard let sessionID = monitoredSessions.first(where: { $0.pendingRequestContext?.requestID == requestID })?.id else {
            return
        }

        handleAgentEvent(.actionableStateResolved(
            ActionableStateResolvedEvent(
                sessionID: sessionID,
                summary: "Approval timed out (fail-open).",
                timestamp: .now
            )
        ))
    }

    private func handleHookPayload(_ payload: CodexHookPayload) {
        refreshHooksStatus()
        monitoringEngine.applyHookPayload(payload) { [weak self] snapshot in
            self?.applyMonitoringSnapshot(snapshot, refreshedAt: .now)
        }
    }

    private func handleAgentEvent(_ event: CodexAgentEvent) {
        monitoringEngine.applyEvent(event) { [weak self] snapshot in
            self?.applyMonitoringSnapshot(snapshot, refreshedAt: .now)
            self?.presentActionableSurfaceIfNeeded(for: event)
        }
    }

    private func presentActionableSurfaceIfNeeded(for event: CodexAgentEvent) {
        switch event {
        case .permissionRequested, .questionAsked:
            guard let notificationSurface = CodexIslandSurface.notificationSurface(for: event) else {
                return
            }
            sessionSurface = notificationSurface
            isNotificationMode = true
        default:
            break
        }
    }

    private func applyMonitoringSnapshot(_ snapshot: CodexMonitoringSnapshot, refreshedAt now: Date) {
        monitoredSessions = snapshot.sessions.filter { !$0.isInternalSupportSession }
        latestQuotaSnapshot = snapshot.quotaSnapshot
        reconcileSessionSurface()
        refreshActivityState(now: now)
    }

    private func reconcileSessionSurface() {
        guard case let .sessionList(actionableSessionID) = sessionSurface else {
            return
        }

        if let actionableSessionID {
            let session = monitoredSessions.first(where: { $0.id == actionableSessionID })
            if !sessionSurface.matchesCurrentState(of: session) {
                sessionSurface = .sessionList(actionableSessionID: nil)
                isNotificationMode = false
            }
        } else if isNotificationMode {
            isNotificationMode = false
        }
    }

    private func presentErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }

    private func compactQuotaText(prefix: String, value: Int?) -> String {
        guard let value else {
            return "\(prefix) --"
        }

        return "\(prefix) \(value)%"
    }

    private func expandedQuotaText(title: String, value: Int?) -> String {
        guard let value else {
            return "\(title) --"
        }

        return "\(title) \(value)%"
    }

    private func quotaValueText(_ value: Int?) -> String {
        guard let value else {
            return "--"
        }

        return "\(value)%"
    }

    private func quotaResetText(_ date: Date?) -> String {
        guard let date else {
            return "--"
        }

        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .abbreviated
        relativeFormatter.dateTimeStyle = .named
        let relativeText = relativeFormatter.localizedString(for: date, relativeTo: .now)
        let absoluteText = date.formatted(date: .abbreviated, time: .shortened)
        return "\(relativeText) · \(absoluteText)"
    }

    private func quotaResetCompactText(_ date: Date?) -> String {
        guard let date else {
            return "--"
        }

        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }

        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month().day())
        }

        return date.formatted(.dateTime.year().month().day())
    }

    private func quotaResetTimeCompactText(_ date: Date?) -> String {
        guard let date else {
            return "--"
        }

        return date.formatted(date: .omitted, time: .shortened)
    }
}
