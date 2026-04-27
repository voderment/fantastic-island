import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class PlayerModuleModel: ObservableObject, IslandModule {
    static let moduleID = "player"
    private static let transientNotificationAutoDismissDelay: TimeInterval = 1.5
    private static let trackSwitchActivityPriority = 240
    private static let minimumRefreshInterval: TimeInterval = 0.18
    private static let estimatedArtworkBlockHeight: CGFloat = 112
    private static let estimatedProgressSectionHeight: CGFloat = 30
    private static let estimatedOuterSpacing: CGFloat = 18

    private struct TrackIdentity: Equatable {
        let source: PlayerSourceKind
        let title: String
        let artist: String
        let album: String

        init?(state: PlayerNowPlayingState) {
            guard let source = state.source,
                  let track = state.track else {
                return nil
            }

            self.init(source: source, track: track)
        }

        init(source: PlayerSourceKind, track: PlayerTrackMetadata) {
            self.source = source
            self.title = track.title
            self.artist = track.artist
            self.album = track.album ?? ""
        }
    }

    struct TrackSwitchNotification {
        let activityID: String
        let source: PlayerSourceKind
        let track: PlayerTrackMetadata
        let artworkImage: NSImage?
        let createdAt: Date
        let updatedAt: Date
    }

    private enum PollCadence {
        static let playing: Duration = .milliseconds(750)
        static let activeSourceApp: Duration = .seconds(1)
        static let idle: Duration = .seconds(15)
    }

    let id = PlayerModuleModel.moduleID
    let title = "Player"
    let symbolName = "play.square.fill"
    let iconAssetName: String? = nil

    @Published private(set) var nowPlayingState: PlayerNowPlayingState = .empty
    @Published private(set) var installedSourceApps: [PlayerAppDescriptor] = []
    @Published private(set) var defaultSourceOptions: [PlayerSourceKind] = []
    @Published private(set) var defaultSource: PlayerSourceKind?
    @Published private(set) var trackSwitchNotification: TrackSwitchNotification?
    @Published private(set) var isResolvingAutomationAccess = false

    private let mediaCoordinator = PlayerMediaCoordinator()
    private var pollingTask: Task<Void, Never>?
    private var artworkLoadTask: Task<Void, Never>?
    private var artworkLoadIdentity: TrackIdentity?
    private var isRefreshing = false
    private var needsRefreshAfterCurrentPass = false
    private var pendingRefreshWorkItem: DispatchWorkItem?
    private var pendingRefreshDeadline: Date?
    private var lastRefreshCompletedAt: Date = .distantPast
    private var lastObservedTrackIdentity: TrackIdentity?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private static let automationSettingsURLs: [URL] = [
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation"),
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"),
    ].compactMap { $0 }
    private static let playbackNotificationNames: [Notification.Name] = [
        Notification.Name("com.apple.Music.playerInfo"),
        Notification.Name("com.apple.iTunes.playerInfo"),
        Notification.Name("com.spotify.client.PlaybackStateChanged"),
    ]

    init() {
        syncSourceAvailability()
        configureWorkspaceObservers()
        configureDistributedPlaybackObservers()
        pollingTask = Task { [weak self] in
            await self?.runPollingLoop()
        }
    }

    deinit {
        pollingTask?.cancel()
        artworkLoadTask?.cancel()
        pendingRefreshWorkItem?.cancel()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        for observer in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    var collapsedSummaryItems: [CollapsedSummaryItem] {
        [
            CollapsedSummaryItem(
                id: "\(id).summary.playback",
                moduleID: id,
                title: "Playback",
                text: nowPlayingState.collapsedSummaryText,
                isEnabledByDefault: false
            ),
        ]
    }

    var taskActivityContribution: TaskActivityContribution {
        TaskActivityContribution()
    }

    var islandActivities: [IslandActivity] {
        guard let trackSwitchNotification else {
            return []
        }

        return [
            IslandActivity(
                id: trackSwitchNotification.activityID,
                moduleID: id,
                sourceID: trackSwitchNotification.activityID,
                kind: .transientNotification,
                priority: Self.trackSwitchActivityPriority,
                createdAt: trackSwitchNotification.createdAt,
                updatedAt: trackSwitchNotification.updatedAt,
                presentationPolicy: IslandActivityPresentationPolicy(
                    autoPresentationScope: .global,
                    autoDismissDelay: Self.transientNotificationAutoDismissDelay,
                    switchSelectedModuleOnAutoPresentation: false,
                    promoteWhileExpanded: false
                )
            ),
        ]
    }

    var preferredOpenedContentHeight: CGFloat {
        let estimatedBodyHeight =
            Self.estimatedArtworkBlockHeight
            + Self.estimatedOuterSpacing
            + Self.estimatedProgressSectionHeight
        let alignedBodyHeight =
            CodexIslandChromeMetrics.windDrivePanelHeight
            - CodexIslandChromeMetrics.moduleNavigationRowHeight
            - CodexIslandChromeMetrics.moduleColumnSpacing

        return CodexIslandChromeMetrics.moduleChromeHeight + max(estimatedBodyHeight, alignedBodyHeight)
    }
    var allowsInternalScrolling: Bool { false }

    var supportsTransportControls: Bool {
        guard nowPlayingState.automationIssue == nil else {
            return false
        }

        return nowPlayingState.supportsTransportControls || defaultSource != nil
    }

    var automationIssue: PlayerAutomationIssue? {
        nowPlayingState.automationIssue
    }

    var canRequestAutomationAccess: Bool {
        automationIssue != nil && !isResolvingAutomationAccess
    }

    var defaultSourceSelection: PlayerSourceKind {
        defaultSource ?? defaultSourceOptions.first ?? .music
    }

    var installedSourceDisplayText: String {
        joinedSourceNames(from: installedSourceApps.map(\.displayName))
    }

    var controllableSourceDisplayText: String {
        joinedSourceNames(from: defaultSourceOptions.map(\.displayName))
    }

    func preferredOpenedContentHeight(for presentation: IslandModulePresentationContext) -> CGFloat {
        switch presentation {
        case .peek:
            return CodexIslandPeekMetrics.contentTopPadding
                + PlayerPeekMetrics.minimumHeight
                + CodexIslandPeekMetrics.contentBottomPadding
        case .standard, .activity:
            return preferredOpenedContentHeight
        }
    }

    func makeRenderSnapshot(presentation: IslandModulePresentationContext) -> IslandModuleRenderSnapshot {
        IslandModuleRenderSnapshot(
            id: "\(id)::\(presentation.cacheKey)",
            moduleID: id,
            presentation: presentation,
            preferredHeight: preferredOpenedContentHeight(for: presentation),
            allowsInternalScrolling: allowsInternalScrolling,
            view: AnyView(PlayerModuleContentView(state: makeRenderState(for: presentation)))
        )
    }

    func makeLiveContentView(presentation: IslandModulePresentationContext) -> AnyView {
        AnyView(PlayerModuleLiveContentView(model: self, presentation: presentation))
    }

    func makeRenderState(for presentation: IslandModulePresentationContext) -> PlayerModuleRenderState {
        let resolvedNotification: TrackSwitchNotification?
        switch presentation {
        case let .peek(activity):
            resolvedNotification = trackSwitchNotification(for: activity)
        case .standard, .activity:
            resolvedNotification = nil
        }

        let sourceBadgeImage: NSImage?
        if nowPlayingState.track != nil, let source = nowPlayingState.source {
            sourceBadgeImage = PlayerSourceRegistry.appIcon(for: source)
        } else {
            sourceBadgeImage = nil
        }

        return PlayerModuleRenderState(
            presentation: presentation,
            nowPlayingState: nowPlayingState,
            trackSwitchNotification: resolvedNotification,
            supportsTransportControls: supportsTransportControls,
            canActivateCurrentSource: canActivateCurrentSource,
            automationIssue: automationIssue,
            canRequestAutomationAccess: canRequestAutomationAccess,
            isResolvingAutomationAccess: isResolvingAutomationAccess,
            sourceBadgeImage: sourceBadgeImage,
            previousTrack: { [weak self] in Task { @MainActor in self?.previousTrack() } },
            togglePlayPause: { [weak self] in Task { @MainActor in self?.togglePlayPause() } },
            nextTrack: { [weak self] in Task { @MainActor in self?.nextTrack() } },
            seek: { [weak self] progress in Task { @MainActor in self?.seek(toProgress: progress) } },
            toggleShuffle: { [weak self] in Task { @MainActor in self?.toggleShuffle() } },
            cycleRepeat: { [weak self] in Task { @MainActor in self?.cycleRepeat() } },
            requestAutomationAccess: { [weak self] in Task { @MainActor in self?.requestAutomationAccess() } },
            openAutomationSettings: { [weak self] in Task { @MainActor in self?.openAutomationSettings() } },
            refresh: { [weak self] in Task { @MainActor in self?.refresh() } },
            activateCurrentSource: { [weak self] in Task { @MainActor in self?.activateCurrentSource() } }
        )
    }

    func refresh() {
        guard !isRefreshing else {
            needsRefreshAfterCurrentPass = true
            return
        }

        pendingRefreshWorkItem?.cancel()
        pendingRefreshWorkItem = nil
        pendingRefreshDeadline = nil
        isRefreshing = true
        syncSourceAvailability()

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let nextState = await self.mediaCoordinator.fetchCurrentState()
            self.finishRefresh(with: nextState)
        }
    }

    func previousTrack() {
        if let refreshDelay = mediaCoordinator.previousTrack(for: nowPlayingState.source) {
            refreshSoon(after: refreshDelay)
        }
    }

    func togglePlayPause() {
        if let refreshDelay = mediaCoordinator.togglePlayPause(for: nowPlayingState.source) {
            refreshSoon(after: refreshDelay)
        }
    }

    func nextTrack() {
        if let refreshDelay = mediaCoordinator.nextTrack(for: nowPlayingState.source) {
            refreshSoon(after: refreshDelay)
        }
    }

    func seek(toProgress progress: Double) {
        guard let track = nowPlayingState.track, track.duration > 0 else {
            return
        }

        let clampedProgress = min(max(progress, 0), 1)
        let targetElapsed = track.duration * clampedProgress
        mediaCoordinator.seek(to: targetElapsed, for: nowPlayingState.source)
        nowPlayingState.track?.elapsed = targetElapsed
        refreshSoon()
    }

    func activateCurrentSource() {
        guard canActivateCurrentSource else {
            return
        }

        mediaCoordinator.activateSourceApplication(for: nowPlayingState.source)
    }

    func toggleShuffle() {
        mediaCoordinator.toggleShuffle(for: nowPlayingState.source)
        refreshSoon()
    }

    func cycleRepeat() {
        mediaCoordinator.cycleRepeat(for: nowPlayingState.source)
        refreshSoon()
    }

    func setDefaultSource(_ sourceKind: PlayerSourceKind) {
        defaultSource = PlayerModuleSettings.setDefaultSource(
            sourceKind,
            installedControllableSources: defaultSourceOptions
        )
    }

    func requestAutomationAccess() {
        guard let sourceKind = nowPlayingState.automationIssueSource ?? defaultSource else {
            return
        }

        requestAutomationAccess(for: sourceKind)
    }

    func openAutomationSettings() {
        for url in Self.automationSettingsURLs where NSWorkspace.shared.open(url) {
            return
        }

        let settingsBundleIDs = [
            "com.apple.SystemSettings",
            "com.apple.systempreferences",
        ]
        for bundleIdentifier in settingsBundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    private func refreshSoon(after delay: TimeInterval = 0.25) {
        let now = Date()
        let earliestDeadline = max(
            now.addingTimeInterval(delay),
            lastRefreshCompletedAt.addingTimeInterval(Self.minimumRefreshInterval)
        )

        if let pendingRefreshDeadline,
           pendingRefreshDeadline <= earliestDeadline {
            return
        }

        pendingRefreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.pendingRefreshWorkItem = nil
            self.pendingRefreshDeadline = nil
            self.refresh()
        }

        pendingRefreshWorkItem = workItem
        pendingRefreshDeadline = earliestDeadline
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, earliestDeadline.timeIntervalSince(now)),
            execute: workItem
        )
    }

    private func finishRefresh(with nextState: PlayerNowPlayingState) {
        defer {
            isRefreshing = false
            lastRefreshCompletedAt = Date()
            if needsRefreshAfterCurrentPass {
                needsRefreshAfterCurrentPass = false
                refreshSoon(after: Self.minimumRefreshInterval)
            }
        }

        processTrackSwitch(from: nowPlayingState, to: nextState)
        if nextState != nowPlayingState {
            nowPlayingState = nextState
        }
        requestArtworkLoadIfNeeded(for: nowPlayingState)
    }

    private func configureWorkspaceObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        let observedNames: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]

        for name in observedNames {
            let observer = notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let bundleIdentifier =
                    (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .bundleIdentifier

                Task { @MainActor [weak self, bundleIdentifier] in
                    guard let self,
                          let bundleIdentifier,
                          PlayerSourceKind.allCases.contains(where: { $0.bundleIdentifier == bundleIdentifier }) else {
                        return
                    }

                    self.refreshSoon(after: 0.1)
                }
            }
            workspaceObservers.append(observer)
        }
    }

    private func configureDistributedPlaybackObservers() {
        let notificationCenter = DistributedNotificationCenter.default()

        for name in Self.playbackNotificationNames {
            let observer = notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshSoon(after: 0.05)
                }
            }
            distributedObservers.append(observer)
        }
    }

    var canActivateCurrentSource: Bool {
        nowPlayingState.playbackStatus.isPlaying && nowPlayingState.source != nil
    }

    func trackSwitchNotification(for activity: IslandActivity) -> TrackSwitchNotification? {
        guard trackSwitchNotification?.activityID == activity.id else {
            return Self.debugTrackSwitchNotification(for: activity)
        }

        return trackSwitchNotification
    }

    private func syncSourceAvailability() {
        let installedSourceApps = PlayerSourceRegistry.installedDescriptors()
        if installedSourceApps != self.installedSourceApps {
            self.installedSourceApps = installedSourceApps
        }

        let defaultSourceOptions = PlayerSourceRegistry.installedControllableSources()
        if defaultSourceOptions != self.defaultSourceOptions {
            self.defaultSourceOptions = defaultSourceOptions
        }

        let resolvedDefaultSource = PlayerModuleSettings.reconcileDefaultSource(
            installedControllableSources: defaultSourceOptions
        )
        if resolvedDefaultSource != defaultSource {
            defaultSource = resolvedDefaultSource
        }
    }

    private static func debugTrackSwitchNotification(for activity: IslandActivity) -> TrackSwitchNotification? {
        guard activity.sourceID == "debug.player.trackswitch" else {
            return nil
        }

        let now = Date()
        return TrackSwitchNotification(
            activityID: activity.id,
            source: .music,
            track: PlayerTrackMetadata(
                title: "Debugging Fantastic Island",
                artist: "Fantastic Island",
                album: "UI Runtime Tools",
                duration: 326,
                elapsed: 92,
                artworkURL: nil
            ),
            artworkImage: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func joinedSourceNames(from names: [String]) -> String {
        names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    private func processTrackSwitch(from previousState: PlayerNowPlayingState, to nextState: PlayerNowPlayingState) {
        let previousIdentity = lastObservedTrackIdentity ?? TrackIdentity(state: previousState)
        guard let nextIdentity = TrackIdentity(state: nextState),
              let source = nextState.source,
              let track = nextState.track else {
            return
        }

        defer {
            lastObservedTrackIdentity = nextIdentity
        }

        guard let previousIdentity,
              previousIdentity != nextIdentity else {
            return
        }

        let timestamp = Date()
        let milliseconds = Int(timestamp.timeIntervalSince1970 * 1000)
        trackSwitchNotification = TrackSwitchNotification(
            activityID: "\(id).activity.track-switch.\(milliseconds)",
            source: source,
            track: track,
            artworkImage: nextState.artworkImage,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    private func requestAutomationAccess(for sourceKind: PlayerSourceKind) {
        guard !isResolvingAutomationAccess else {
            return
        }

        isResolvingAutomationAccess = true
        NSApplication.shared.activate(ignoringOtherApps: true)
        Task.detached(priority: .userInitiated) { [sourceKind] in
            _ = PlayerMediaCoordinator.determineAutomationPermission(
                for: sourceKind,
                askUserIfNeeded: true
            )

            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }

                self.isResolvingAutomationAccess = false
                self.refreshSoon(after: 0.1)
            }
        }
    }

    private func requestArtworkLoadIfNeeded(for state: PlayerNowPlayingState) {
        guard let identity = TrackIdentity(state: state),
              state.artworkImage == nil else {
            artworkLoadTask?.cancel()
            artworkLoadTask = nil
            artworkLoadIdentity = nil
            return
        }

        guard artworkLoadIdentity != identity else {
            return
        }

        artworkLoadTask?.cancel()
        artworkLoadIdentity = identity

        artworkLoadTask = Task { [weak self, state, identity] in
            guard let self else {
                return
            }

            defer {
                if self.artworkLoadIdentity == identity {
                    self.artworkLoadTask = nil
                    self.artworkLoadIdentity = nil
                }
            }

            guard let artworkImage = await self.mediaCoordinator.loadArtworkIfNeeded(for: state),
                  !Task.isCancelled,
                  self.artworkLoadIdentity == identity,
                  TrackIdentity(state: self.nowPlayingState) == identity else {
                return
            }

            self.nowPlayingState.artworkImage = artworkImage
        }
    }

    private func runPollingLoop() async {
        refresh()

        while !Task.isCancelled {
            let nextDelay = pollDelay(for: nowPlayingState)
            do {
                try await Task.sleep(for: nextDelay)
            } catch {
                return
            }
            refresh()
        }
    }

    private func pollDelay(for state: PlayerNowPlayingState) -> Duration {
        if !PlayerSourceRegistry.runningControllableSources().isEmpty {
            switch state.playbackStatus {
            case .playing:
                return PollCadence.playing
            case .paused, .stopped:
                return PollCadence.activeSourceApp
            }
        }

        switch state.playbackStatus {
        case .playing:
            return PollCadence.playing
        case .paused, .stopped:
            return PollCadence.idle
        }
    }
}
