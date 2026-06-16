import SwiftUI

struct IslandHUDOverlayView: View {
    let overlay: IslandHUDOverlayState

    var body: some View {
        switch overlay.kind {
        case let .volume(level, isMuted):
            hudContent(
                symbolName: isMuted || level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                level: isMuted ? 0 : level,
                valueText: isMuted ? "Mute" : "\(Int((level * 100).rounded()))%"
            )
        case let .brightness(level):
            hudContent(
                symbolName: level <= 0.08 ? "sun.min.fill" : "sun.max.fill",
                level: level,
                valueText: "\(Int((level * 100).rounded()))%"
            )
        }
    }

    private func hudContent(symbolName: String, level: Float, valueText: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(Color.white.opacity(0.82))
                        .frame(width: proxy.size.width * CGFloat(level))
                }
            }
            .frame(width: 84, height: 5)
            Text(valueText)
                .font(IslandVisualLanguage.islandLabel(11))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Capsule(style: .continuous)
                .fill(Color.black)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.26), radius: 10, y: 4)
    }
}
