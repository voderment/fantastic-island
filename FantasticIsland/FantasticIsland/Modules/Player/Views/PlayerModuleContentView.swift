import AppKit
import SwiftUI

struct PlayerModuleRenderState {
    let presentation: IslandModulePresentationContext
    let nowPlayingState: PlayerNowPlayingState
    let trackSwitchNotification: PlayerModuleModel.TrackSwitchNotification?
    let supportsTransportControls: Bool
    let automationIssue: PlayerAutomationIssue?
    let canRequestAutomationAccess: Bool
    let isResolvingAutomationAccess: Bool
    let sourceOptions: [PlayerSourceKind]
    let selectedSource: PlayerSourceKind
    let selectPlaybackSource: (PlayerSourceKind) -> Void
    let openNowPlayingApp: () -> Void
    let previousTrack: () -> Void
    let togglePlayPause: () -> Void
    let nextTrack: () -> Void
    let seek: (Double) -> Void
    let toggleShuffle: () -> Void
    let cycleRepeat: () -> Void
    let requestAutomationAccess: () -> Void
    let openAutomationSettings: () -> Void
    let refresh: () -> Void
}

struct PlayerModuleLiveContentView: View {
    @ObservedObject var model: PlayerModuleModel
    let presentation: IslandModulePresentationContext

    var body: some View {
        PlayerModuleContentView(state: model.makeRenderState(for: presentation))
    }
}

struct PlayerModuleContentView: View {
    let state: PlayerModuleRenderState

    @State private var scrubProgress: Double?

    var body: some View {
        Group {
            switch state.presentation {
            case let .peek(activity):
                if let notification = state.trackSwitchNotification, notification.activityID == activity.id {
                    peekContent(notification: notification)
                } else {
                    EmptyView()
                }
            case .standard, .activity:
                standardContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var standardContent: some View {
        HStack(alignment: .center, spacing: PlayerExpandedMetrics.primaryColumnSpacing) {
            artworkView

            if showsAutomationIssue {
                VStack(alignment: .leading, spacing: 5) {
                    titleBlock
                    automationIssueActionRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    playerTitleRow
                    playerControlStrip
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private var playerTitleRow: some View {
        HStack(alignment: .center, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    PlayerAnimatedTitleText(
                        title: state.nowPlayingState.titleText,
                        lineLimit: 1
                    )
                    .layoutPriority(1)

                    if state.nowPlayingState.playbackStatus.isPlaying {
                        PlayerVisualizerView(isPlaying: true)
                    }
                }

                Text(state.nowPlayingState.artistText)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: state.openNowPlayingApp)
            .help("Open \(sourceBadgeText)")

            sourceMenu
        }
    }

    private var playerControlStrip: some View {
        HStack(alignment: .center, spacing: 7) {
            controlsRow
                .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 2) {
                PlayerProgressBar(
                    progress: displayedProgress,
                    isEnabled: state.nowPlayingState.supportsSeeking,
                    onChanged: { progress in
                        scrubProgress = progress
                    },
                    onEnded: { progress in
                        scrubProgress = nil
                        state.seek(progress)
                    }
                )
                .frame(height: 8)

                HStack(spacing: 0) {
                    Text(displayedElapsedText)
                    Spacer(minLength: 0)
                    Text(displayedRemainingText)
                }
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.46))
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(1)

            playbackModeControls
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func peekContent(notification: PlayerModuleModel.TrackSwitchNotification) -> some View {
        HStack(spacing: PlayerPeekMetrics.horizontalSpacing) {
            peekArtworkView(notification: notification)

            VStack(alignment: .leading, spacing: PlayerPeekMetrics.textSpacing) {
                Text(notification.track.title)
                    .font(.system(size: PlayerPeekMetrics.titleFontSize, weight: .bold))
                    .foregroundStyle(.white.opacity(PlayerPeekMetrics.titleOpacity))
                    .lineLimit(1)

                Text(notification.track.artist.isEmpty ? "Unknown Artist" : notification.track.artist)
                    .font(.system(size: PlayerPeekMetrics.artistFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(PlayerPeekMetrics.artistOpacity))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, PlayerPeekMetrics.contentHorizontalPadding)
        .padding(.vertical, PlayerPeekMetrics.contentVerticalPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: PlayerPeekMetrics.minimumHeight,
            alignment: .leading
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: state.openNowPlayingApp)
        .help("Open \(sourceBadgeText)")
    }

    private func peekArtworkView(notification: PlayerModuleModel.TrackSwitchNotification) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: PlayerPeekMetrics.artworkCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(PlayerPeekMetrics.artworkBackgroundStartOpacity),
                            Color.white.opacity(PlayerPeekMetrics.artworkBackgroundEndOpacity),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let artworkImage = notification.artworkImage {
                Image(nsImage: artworkImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: PlayerPeekMetrics.placeholderSymbolSize, weight: .medium))
                    .foregroundStyle(.white.opacity(PlayerPeekMetrics.placeholderOpacity))
            }
        }
        .clipShape(.rect(cornerRadius: PlayerPeekMetrics.artworkCornerRadius))
        .frame(width: PlayerPeekMetrics.artworkSize, height: PlayerPeekMetrics.artworkSize)
    }

    private var artworkView: some View {
        artworkBody
            .contentShape(RoundedRectangle(cornerRadius: PlayerExpandedMetrics.artworkCornerRadius, style: .continuous))
            .onTapGesture(perform: state.openNowPlayingApp)
            .help("Open \(sourceBadgeText)")
    }

    private var artworkBody: some View {
        artworkThumbnail
    }

    private var artworkThumbnail: some View {
        PlayerArtworkThumbnailView(
            artworkImage: state.nowPlayingState.artworkImage,
            artworkRevision: artworkRevision,
            trackIdentity: artworkTrackIdentity,
            hasTrack: state.nowPlayingState.track != nil,
            size: PlayerExpandedMetrics.artworkSize,
            cornerRadius: PlayerExpandedMetrics.artworkCornerRadius
        )
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if !showsAutomationIssue, state.nowPlayingState.playbackStatus.isPlaying {
                    PlayerVisualizerView(isPlaying: true)
                }

                Spacer(minLength: 0)

                sourceMenu
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                PlayerAnimatedTitleText(
                    title: state.nowPlayingState.titleText,
                    lineLimit: showsAutomationIssue ? 2 : 1
                )
                .layoutPriority(1)

                Spacer(minLength: 0)

                if !showsAutomationIssue {
                    playbackModeControls
                }
            }

            Text(state.nowPlayingState.artistText)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(showsAutomationIssue ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourceMenu: some View {
        Menu {
            ForEach(state.sourceOptions) { source in
                Button {
                    state.selectPlaybackSource(source)
                } label: {
                    HStack {
                        Text(source.displayName)
                        if source == state.selectedSource {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button("Refresh") {
                state.refresh()
            }
        } label: {
            HStack(spacing: 5) {
                if let sourceIconImage {
                    Image(nsImage: sourceIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 9, height: 9)
                        .clipShape(.rect(cornerRadius: 2))
                } else {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.48))
                }

                Text(sourceBadgeText)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.72)

                Image(systemName: "chevron.down")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .foregroundStyle(.white.opacity(0.64))
            .padding(.horizontal, 6)
            .frame(height: 18)
            .frame(width: 88, alignment: .trailing)
            .background(Color.white.opacity(0.045), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.7)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help("Now Playing follows the current media app")
    }

    private var automationIssueActionRow: some View {
        HStack(spacing: 10) {
            if state.canRequestAutomationAccess {
                issueActionButton(
                    title: state.isResolvingAutomationAccess ? "Requesting…" : "Grant Access",
                    action: state.requestAutomationAccess
                )
                .disabled(state.isResolvingAutomationAccess)
            }

            issueActionButton(title: "Open Settings", action: state.openAutomationSettings)
            issueActionButton(title: "Refresh", action: state.refresh)
        }
    }

    private var playbackModeControls: some View {
        HStack(spacing: 3) {
            modeButton(
                systemName: state.nowPlayingState.shuffleMode.symbolName,
                isActive: state.nowPlayingState.shuffleMode == .on,
                isEnabled: state.nowPlayingState.supportsShuffleControl,
                accessibilityLabel: state.nowPlayingState.shuffleMode == .on ? "Disable shuffle" : "Enable shuffle",
                action: state.toggleShuffle
            )

            modeButton(
                systemName: state.nowPlayingState.repeatMode.symbolName,
                isActive: state.nowPlayingState.repeatMode != .off && state.nowPlayingState.repeatMode != .unsupported,
                isEnabled: state.nowPlayingState.supportsRepeatControl,
                accessibilityLabel: repeatAccessibilityLabel,
                action: state.cycleRepeat
            )
        }
        .frame(height: 20)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: PlayerExpandedMetrics.progressSectionSpacing) {
            PlayerProgressBar(
                progress: displayedProgress,
                isEnabled: state.nowPlayingState.supportsSeeking,
                onChanged: { progress in
                    scrubProgress = progress
                },
                onEnded: { progress in
                    scrubProgress = nil
                    state.seek(progress)
                }
            )
            .frame(height: 8)

            HStack {
                Text(displayedElapsedText)
                Spacer(minLength: 0)
                Text(displayedRemainingText)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.66))
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 2) {
            controlButton(systemName: "backward.fill", iconSize: 13, frameWidth: 24, frameHeight: 22, action: state.previousTrack)
                .disabled(!state.supportsTransportControls)

            controlButton(
                systemName: state.nowPlayingState.playbackStatus.isPlaying ? "pause.fill" : "play.fill",
                iconSize: 16,
                frameWidth: 28,
                frameHeight: 24,
                action: state.togglePlayPause
            )
            .disabled(!state.supportsTransportControls)

            controlButton(systemName: "forward.fill", iconSize: 13, frameWidth: 24, frameHeight: 22, action: state.nextTrack)
                .disabled(!state.supportsTransportControls)
        }
        .opacity(state.supportsTransportControls ? 1 : PlayerExpandedMetrics.controlButtonOpacityDisabled)
    }

    private func controlButton(
        systemName: String,
        iconSize: CGFloat,
        frameWidth: CGFloat,
        frameHeight: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(.white.opacity(0.96))
                .frame(width: frameWidth, height: frameHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlayerTransportButtonStyle())
    }

    private func issueActionButton(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 12)
                .frame(height: 30)
        }
        .buttonStyle(PlayerIssueActionButtonStyle())
    }

    private func modeButton(
        systemName: String,
        isActive: Bool,
        isEnabled: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(modeButtonForegroundColor(isActive: isActive, isEnabled: isEnabled))
                .frame(width: 20, height: 20)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PlayerModeButtonStyle(isActive: isActive, isEnabled: isEnabled))
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private func modeButtonForegroundColor(
        isActive: Bool,
        isEnabled: Bool
    ) -> Color {
        guard isEnabled else {
            return .white.opacity(0.24)
        }

        if isActive {
            return .white.opacity(0.96)
        }

        return .white.opacity(0.58)
    }

    private var displayedProgress: Double {
        scrubProgress ?? state.nowPlayingState.progress
    }

    private var artworkRevision: Int? {
        state.nowPlayingState.artworkImage.map { ObjectIdentifier($0).hashValue }
    }

    private var artworkTrackIdentity: String? {
        guard let track = state.nowPlayingState.track else {
            return nil
        }

        return [
            state.nowPlayingState.source?.rawValue ?? "player",
            state.nowPlayingState.sourceBundleIdentifier ?? "",
            track.title,
            track.artist,
            track.album ?? "",
        ].joined(separator: "\u{1F}")
    }

    private var showsAutomationIssue: Bool {
        state.automationIssue != nil
    }

    private var sourceBadgeText: String {
        let label = state.nowPlayingState.sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label != "Player" else {
            return "Now Playing"
        }

        if label == PlayerSourceKind.nowPlaying.displayName {
            return "Now Playing"
        }

        return label
    }

    private var sourceIconImage: NSImage? {
        if let bundleIdentifier = state.nowPlayingState.sourceBundleIdentifier,
           !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let icon = PlayerSourceRegistry.appIcon(bundleIdentifier: bundleIdentifier) {
            return icon
        }

        return PlayerSourceRegistry.appIcon(for: state.selectedSource)
    }

    private var displayedElapsedText: String {
        timeText(for: displayedElapsed)
    }

    private var displayedRemainingText: String {
        "-\(timeText(for: displayedRemaining))"
    }

    private var displayedElapsed: TimeInterval {
        guard let track = state.nowPlayingState.track else {
            return 0
        }

        return track.duration * displayedProgress
    }

    private var displayedRemaining: TimeInterval {
        guard let track = state.nowPlayingState.track else {
            return 0
        }

        return max(track.duration - displayedElapsed, 0)
    }

    private var repeatAccessibilityLabel: String {
        switch state.nowPlayingState.repeatMode {
        case .off:
            return "Enable repeat all"
        case .all:
            return "Switch to repeat one"
        case .one:
            return "Disable repeat"
        case .unsupported:
            return "Repeat unavailable"
        }
    }

    private func timeText(for duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded(.down)), 0)
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes):\(String(format: "%02d", remainder))"
    }
}

private struct PlayerAnimatedTitleText: View {
    let title: String
    let lineLimit: Int

    var body: some View {
        Text(title)
            .font(.system(size: 14.5, weight: .bold))
            .foregroundStyle(.white.opacity(0.96))
            .lineLimit(lineLimit)
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.22), value: title)
    }
}

private struct PlayerArtworkThumbnailView: View {
    let artworkImage: NSImage?
    let artworkRevision: Int?
    let trackIdentity: String?
    let hasTrack: Bool
    let size: CGFloat
    let cornerRadius: CGFloat

    @State private var displayedArtworkImage: NSImage?
    @State private var displayedArtworkRevision: Int?
    @State private var displayedArtworkTrackIdentity: String?
    @State private var placeholderFallbackTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                }

            if let displayedArtworkImage {
                Image(nsImage: displayedArtworkImage)
                    .resizable()
                    .scaledToFill()
                    .id(displayedArtworkRevision)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
                    .transition(.opacity)
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .frame(width: size, height: size)
        .animation(.smooth(duration: 0.22), value: displayedArtworkRevision)
        .onAppear(perform: syncDisplayedArtwork)
        .onChange(of: artworkRevision) { _, _ in
            syncDisplayedArtwork()
        }
        .onChange(of: trackIdentity) { _, _ in
            syncDisplayedArtwork()
        }
        .onChange(of: hasTrack) { _, _ in
            syncDisplayedArtwork()
        }
        .onDisappear {
            placeholderFallbackTask?.cancel()
        }
    }

    private func syncDisplayedArtwork() {
        if let artworkImage {
            placeholderFallbackTask?.cancel()
            displayedArtworkImage = artworkImage
            displayedArtworkRevision = artworkRevision
            displayedArtworkTrackIdentity = trackIdentity
            return
        }

        if !hasTrack {
            placeholderFallbackTask?.cancel()
            displayedArtworkImage = nil
            displayedArtworkRevision = nil
            displayedArtworkTrackIdentity = nil
            return
        }

        if trackIdentity != displayedArtworkTrackIdentity {
            schedulePlaceholderFallback(for: trackIdentity)
        }
    }

    private func schedulePlaceholderFallback(for trackIdentity: String?) {
        placeholderFallbackTask?.cancel()
        placeholderFallbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled,
                  self.trackIdentity == trackIdentity,
                  self.artworkRevision == nil else {
                return
            }

            withAnimation(.smooth(duration: 0.18)) {
                displayedArtworkImage = nil
                displayedArtworkRevision = nil
                displayedArtworkTrackIdentity = trackIdentity
            }
        }
    }
}

private struct PlayerTransportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.001))
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.smooth(duration: 0.14), value: configuration.isPressed)
    }
}

private struct PlayerModeButtonStyle: ButtonStyle {
    let isActive: Bool
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        backgroundFill(isPressed: configuration.isPressed)
                    )
            )
            .shadow(color: shadowColor(isPressed: configuration.isPressed), radius: isActive ? 3 : 0, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.smooth(duration: 0.14), value: configuration.isPressed)
    }

    private func backgroundFill(isPressed: Bool) -> some ShapeStyle {
        if !isEnabled {
            return AnyShapeStyle(Color.white.opacity(0.015))
        }

        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isPressed ? 0.24 : 0.18),
                        Color.white.opacity(isPressed ? 0.16 : 0.10),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color.white.opacity(isPressed ? 0.12 : 0.08),
                    Color.white.opacity(isPressed ? 0.07 : 0.035),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func shadowColor(isPressed: Bool) -> Color {
        guard isEnabled else {
            return .clear
        }

        if isActive {
            return .black.opacity(isPressed ? 0.12 : 0.18)
        }

        return .clear
    }
}

private struct PlayerIssueActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(configuration.isPressed ? 0.22 : 0.10), lineWidth: 0.8)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.smooth(duration: 0.14), value: configuration.isPressed)
    }
}

private struct PlayerProgressBar: View {
    let progress: Double
    let isEnabled: Bool
    let onChanged: (Double) -> Void
    let onEnded: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let clampedProgress = min(max(progress, 0), 1)
            let fillWidth = geometry.size.width * clampedProgress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.13))
                    .frame(height: 5)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.62),
                                Color.white.opacity(0.48),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth, height: 5)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else {
                            return
                        }
                        onChanged(progress(for: value.location.x, width: geometry.size.width))
                    }
                    .onEnded { value in
                        guard isEnabled else {
                            return
                        }
                        onEnded(progress(for: value.location.x, width: geometry.size.width))
                    }
            )
            .opacity(isEnabled ? 1 : 0.5)
        }
    }

    private func progress(for locationX: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else {
            return 0
        }

        return min(max(locationX / width, 0), 1)
    }
}
