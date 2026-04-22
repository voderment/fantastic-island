import AppKit
import SwiftUI

struct PlayerModuleContentView: View {
    @ObservedObject var model: PlayerModuleModel
    let presentation: IslandModulePresentationContext

    @State private var scrubProgress: Double?

    var body: some View {
        Group {
            switch presentation {
            case let .peek(activity):
                if let notification = model.trackSwitchNotification(for: activity) {
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
                    controlsRow
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                artworkView
            }

            progressSection
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
            if model.canActivateCurrentSource {
                Button(action: model.activateCurrentSource) {
                    artworkBody
                }
                .buttonStyle(PlayerArtworkButtonStyle())
                .help("Open \(model.nowPlayingState.sourceLabel)")
            } else {
                artworkBody
            }
        }
    }

    private var artworkBody: some View {
        artworkThumbnail
            .overlay(alignment: .bottomLeading) {
                if let badgeImage = sourceBadgeImage {
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

            if let artworkImage = model.nowPlayingState.artworkImage {
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
                Text(model.nowPlayingState.titleText)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                playbackModeControls
            }

            Text(model.nowPlayingState.artistText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
        }
    }

    private var playbackModeControls: some View {
        HStack(spacing: 8) {
            modeButton(
                systemName: model.nowPlayingState.shuffleMode.symbolName,
                isActive: model.nowPlayingState.shuffleMode == .on,
                isEnabled: model.nowPlayingState.supportsShuffleControl,
                accessibilityLabel: model.nowPlayingState.shuffleMode == .on ? "Disable shuffle" : "Enable shuffle",
                action: model.toggleShuffle
            )

            modeButton(
                systemName: model.nowPlayingState.repeatMode.symbolName,
                isActive: model.nowPlayingState.repeatMode != .off && model.nowPlayingState.repeatMode != .unsupported,
                isEnabled: model.nowPlayingState.supportsRepeatControl,
                accessibilityLabel: repeatAccessibilityLabel,
                action: model.cycleRepeat
            )
        }
        .frame(height: 24)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: PlayerExpandedMetrics.progressSectionSpacing) {
            PlayerProgressBar(
                progress: displayedProgress,
                isEnabled: model.nowPlayingState.supportsSeeking,
                onChanged: { progress in
                    scrubProgress = progress
                },
                onEnded: { progress in
                    scrubProgress = nil
                    model.seek(toProgress: progress)
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
            controlButton(systemName: "backward.fill", iconSize: 24, frameWidth: 42, frameHeight: 32, action: model.previousTrack)
                .disabled(!model.supportsTransportControls)

            controlButton(
                systemName: model.nowPlayingState.playbackStatus.isPlaying ? "pause.fill" : "play.fill",
                iconSize: 28,
                frameWidth: 36,
                frameHeight: 36,
                action: model.togglePlayPause
            )
            .disabled(!model.supportsTransportControls)

            controlButton(systemName: "forward.fill", iconSize: 24, frameWidth: 42, frameHeight: 32, action: model.nextTrack)
                .disabled(!model.supportsTransportControls)
        }
        .opacity(model.supportsTransportControls ? 1 : PlayerExpandedMetrics.controlButtonOpacityDisabled)
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
                .foregroundStyle(.white.opacity(isEnabled ? (isActive ? 0.96 : 0.54) : 0.24))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlayerModeButtonStyle(isActive: isActive))
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private var displayedProgress: Double {
        scrubProgress ?? model.nowPlayingState.progress
    }

    private var sourceBadgeImage: NSImage? {
        guard
            model.nowPlayingState.track != nil,
            let source = model.nowPlayingState.source
        else {
            return nil
        }

        return PlayerSourceRegistry.appIcon(for: source)
    }

    private var displayedElapsedText: String {
        timeText(for: displayedElapsed)
    }

    private var displayedRemainingText: String {
        "-\(timeText(for: displayedRemaining))"
    }

    private var displayedElapsed: TimeInterval {
        guard let track = model.nowPlayingState.track else {
            return 0
        }

        return track.duration * displayedProgress
    }

    private var displayedRemaining: TimeInterval {
        guard let track = model.nowPlayingState.track else {
            return 0
        }

        return max(track.duration - displayedElapsed, 0)
    }

    private var repeatAccessibilityLabel: String {
        switch model.nowPlayingState.repeatMode {
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        Color.white.opacity(
                            configuration.isPressed ? 0.16 : (isActive ? 0.1 : 0.001)
                        )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
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
