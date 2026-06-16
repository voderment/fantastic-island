import SwiftUI

struct IslandHUDOverlayView: View {
    let overlay: IslandHUDOverlayState

    var body: some View {
        switch overlay.kind {
        case let .volume(level, isMuted):
            HStack(spacing: 10) {
                Image(systemName: isMuted || level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.95), Color.white.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * CGFloat(isMuted ? 0 : level))
                    }
                }
                .frame(width: 84, height: 5)
                Text(isMuted ? "Mute" : "\(Int((level * 100).rounded()))%")
                    .font(IslandVisualLanguage.islandLabel(11))
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.12, green: 0.12, blue: 0.13), Color.black.opacity(0.92)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(IslandVisualLanguage.shellStrokeGradient, lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        }
    }
}
