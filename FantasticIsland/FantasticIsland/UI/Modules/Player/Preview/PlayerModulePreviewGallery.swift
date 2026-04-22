import SwiftUI

private struct PlayerPreviewPanel: View {
    let model: PlayerPreviewPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: PlayerExpandedMetrics.outerSpacing) {
            HStack(alignment: .top, spacing: PlayerExpandedMetrics.primaryColumnSpacing) {
                VStack(alignment: .leading, spacing: PlayerExpandedMetrics.controlsSpacing + 4) {
                    VStack(alignment: .leading, spacing: PlayerExpandedMetrics.titleBlockSpacing) {
                        Text(model.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white.opacity(0.96))
                        Text(model.artist)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.56))
                    }

                    HStack(spacing: PlayerExpandedMetrics.controlsSpacing) {
                        Circle().fill(Color.white.opacity(0.12)).frame(width: 32, height: 32)
                        Circle().fill(Color.white.opacity(0.18)).frame(width: 36, height: 36)
                        Circle().fill(Color.white.opacity(0.12)).frame(width: 32, height: 32)
                    }
                    .opacity(model.isIdle ? PlayerExpandedMetrics.controlButtonOpacityDisabled : 1)
                }

                RoundedRectangle(cornerRadius: PlayerExpandedMetrics.artworkCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: PlayerExpandedMetrics.artworkSize, height: PlayerExpandedMetrics.artworkSize)
            }

            VStack(alignment: .leading, spacing: PlayerExpandedMetrics.progressSectionSpacing) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 12)
                HStack {
                    Text("00:42")
                    Spacer()
                    Text("-02:18")
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.66))
            }
        }
        .frame(width: 560, alignment: .leading)
    }
}

#Preview("Player Gallery") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            IslandPreviewContainer(title: "Expanded Playing") {
                PlayerPreviewPanel(model: PlayerPreviewMocks.playing)
            }

            IslandPreviewContainer(title: "Peek") {
                HStack(spacing: PlayerPeekMetrics.horizontalSpacing) {
                    RoundedRectangle(cornerRadius: PlayerPeekMetrics.artworkCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: PlayerPeekMetrics.artworkSize, height: PlayerPeekMetrics.artworkSize)

                    VStack(alignment: .leading, spacing: PlayerPeekMetrics.textSpacing) {
                        Text(PlayerPreviewMocks.peekTitle)
                            .font(.system(size: PlayerPeekMetrics.titleFontSize, weight: .bold))
                            .foregroundStyle(.white.opacity(PlayerPeekMetrics.titleOpacity))
                        Text(PlayerPreviewMocks.peekArtist)
                            .font(.system(size: PlayerPeekMetrics.artistFontSize, weight: .medium))
                            .foregroundStyle(.white.opacity(PlayerPeekMetrics.artistOpacity))
                    }
                }
                .frame(width: 520)
                .frame(minHeight: PlayerPeekMetrics.minimumHeight, alignment: .leading)
            }

            IslandPreviewContainer(title: "Expanded Idle") {
                PlayerPreviewPanel(model: PlayerPreviewMocks.idle)
            }
        }
    }
    .frame(width: 860, height: 940)
    .background(Color(red: 0.06, green: 0.06, blue: 0.08))
    .preferredColorScheme(.dark)
}
