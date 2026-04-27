import AppKit
import SwiftUI

struct PlayerModuleRenderState {
    let presentation: IslandModulePresentationContext
    let nowPlayingState: PlayerNowPlayingState
    let trackSwitchNotification: PlayerModuleModel.TrackSwitchNotification?
    let supportsTransportControls: Bool
    let canActivateCurrentSource: Bool
    let automationIssue: PlayerAutomationIssue?
    let canRequestAutomationAccess: Bool
    let isResolvingAutomationAccess: Bool
    let sourceBadgeImage: NSImage?
    let previousTrack: () -> Void
    let togglePlayPause: () -> Void
    let nextTrack: () -> Void
    let seek: (Double) -> Void
    let toggleShuffle: () -> Void
    let cycleRepeat: () -> Void
    let requestAutomationAccess: () -> Void
    let openAutomationSettings: () -> Void
    let refresh: () -> Void
    let activateCurrentSource: () -> Void
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
        VStack(alignment: .leading, spacing: PlayerExpandedMetrics.outerSpacing) {
            HStack(alignment: .top, spacing: PlayerExpandedMetrics.primaryColumnSpacing) {
                VStack(alignment: .leading, spacing: PlayerExpandedMetrics.controlsSpacing + 4) {
                    titleBlock

                    if showsAutomationIssue {
                        automationIssueActionRow
                    } else {
                        controlsRow
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                artworkView
            }

            if !showsAutomationIssue {
                progressSection
            }
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
        Group {
            if state.canActivateCurrentSource {
                Button(action: state.activateCurrentSource) {
                    artworkBody
                }
                .buttonStyle(PlayerArtworkButtonStyle())
                .help("Open \(state.nowPlayingState.sourceLabel)")
            } else {
                artworkBody
            }
        }
    }

    private var artworkBody: some View {
        artworkThumbnail
            .overlay(alignment: .bottomLeading) {
                if let badgeImage = state.sourceBadgeImage {
                    PlayerSourceBadgeView(image: badgeImage)
                        .offset(x: -5, y: 5)
                }
            }
    }

    private var artworkThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PlayerExpandedMetrics.artworkCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.03),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    )

            if let artworkImage = state.nowPlayingState.artworkImage {
                Image(nsImage: artworkImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .clipShape(.rect(cornerRadius: PlayerExpandedMetrics.artworkCornerRadius))
        .frame(width: PlayerExpandedMetrics.artworkSize, height: PlayerExpandedMetrics.artworkSize)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: PlayerExpandedMetrics.titleBlockSpacing) {
            HStack(alignment: .center, spacing: 16) {
                Text(state.nowPlayingState.titleText)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(showsAutomationIssue ? 2 : 1)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                if !showsAutomationIssue {
                    playbackModeControls
                }
            }

            Text(state.nowPlayingState.artistText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(showsAutomationIssue ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        HStack(spacing: 8) {
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
        .frame(height: 24)
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
            .frame(height: 12)

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
        HStack(spacing: PlayerExpandedMetrics.controlsSpacing) {
            controlButton(systemName: "backward.fill", iconSize: 24, frameWidth: 42, frameHeight: 32, action: state.previousTrack)
                .disabled(!state.supportsTransportControls)

            controlButton(
                systemName: state.nowPlayingState.playbackStatus.isPlaying ? "pause.fill" : "play.fill",
                iconSize: 28,
                frameWidth: 36,
                frameHeight: 36,
                action: state.togglePlayPause
            )
            .disabled(!state.supportsTransportControls)

            controlButton(systemName: "forward.fill", iconSize: 24, frameWidth: 42, frameHeight: 32, action: state.nextTrack)
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(modeButtonForegroundColor(isActive: isActive, isEnabled: isEnabled))
                .frame(width: 30, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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

    private var showsAutomationIssue: Bool {
        state.automationIssue != nil
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

private struct PlayerArtworkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.smooth(duration: 0.14), value: configuration.isPressed)
    }
}

private struct PlayerSourceBadgeView: View {
    let image: NSImage
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 10

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
    }
}

private struct PlayerTransportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        backgroundFill(isPressed: configuration.isPressed)
                    )
            )
            .shadow(color: shadowColor(isPressed: configuration.isPressed), radius: isActive ? 10 : 4, x: 0, y: 3)
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
            return .black.opacity(isPressed ? 0.20 : 0.30)
        }

        return .black.opacity(isPressed ? 0.10 : 0.16)
    }
}

private struct PlayerIssueActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .fill(Color.white.opacity(0.22))
                    .frame(height: 8)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.98),
                                Color.white.opacity(0.82),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth, height: 8)
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
