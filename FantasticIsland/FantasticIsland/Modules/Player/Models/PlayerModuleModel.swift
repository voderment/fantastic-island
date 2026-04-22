import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class PlayerModuleModel: ObservableObject, IslandModule {
    static let moduleID = "player"
    private static let transientNotificationAutoDismissDelay: TimeInterval = 1.5
    private static let trackSwitchActivityPriority = 240
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
        static let paused: Duration = .seconds(5)
        static let stopped: Duration = .seconds(15)
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

    private let mediaCoordinator = PlayerMediaCoordinator()
    private var pollingTask: Task<Void, Never>?
    private var isRefreshing = false
    private var lastObservedTrackIdentity: TrackIdentity?

    init() {
        syncSourceAvailability()
        pollingTask = Task { [weak self] in
            await self?.runPollingLoop()
        }
    }

    deinit {
        pollingTask?.cancel()
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
        nowPlayingState.supportsTransportControls || defaultSource != nil
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

    func makeContentView(presentation: IslandModulePresentationContext) -> AnyView {
        AnyView(PlayerModuleContentView(model: self, presentation: presentation))
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

    func refresh() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }
        syncSourceAvailability()

        let nextState = mediaCoordinator.fetchCurrentState()
        processTrackSwitch(from: nowPlayingState, to: nextState)
        if nextState != nowPlayingState {
            nowPlayingState = nextState
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

    private func refreshSoon(after delay: TimeInterval = 0.25) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.refresh()
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
        switch state.playbackStatus {
        case .playing:
            return PollCadence.playing
        case .paused:
            return PollCadence.paused
        case .stopped:
            return PollCadence.stopped
        }
    }
}
