import SwiftUI

struct IslandHUDOverlayView: View {
    let overlay: IslandHUDOverlayState
    let onAdjust: ((Float) -> Void)?
    @State private var isDragging = false

    init(overlay: IslandHUDOverlayState, onAdjust: ((Float) -> Void)? = nil) {
        self.overlay = overlay
        self.onAdjust = onAdjust
    }

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

            levelBar(level: level)

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

    private func levelBar(level: Float) -> some View {
        GeometryReader { proxy in
            let clampedLevel = CGFloat(max(0, min(1, level)))
            let isAdjustable = onAdjust != nil
            let thumbSize: CGFloat = isDragging ? 10 : 7
            let trackHeight: CGFloat = isAdjustable ? 7 : 5

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(isAdjustable ? 0.18 : 0.14))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(Color.white.opacity(isAdjustable ? 0.88 : 0.82))
                    .frame(width: proxy.size.width * clampedLevel)
                    .frame(height: trackHeight)
                if isAdjustable {
                    Circle()
                        .fill(Color.white.opacity(0.96))
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                        .offset(x: max(0, min(proxy.size.width - thumbSize, (proxy.size.width * clampedLevel) - (thumbSize / 2))))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let onAdjust else { return }
                        isDragging = true
                        onAdjust(progress(for: value.location.x, width: proxy.size.width))
                    }
                    .onEnded { value in
                        guard let onAdjust else { return }
                        onAdjust(progress(for: value.location.x, width: proxy.size.width))
                        isDragging = false
                    }
            )
            .animation(.easeOut(duration: 0.12), value: isDragging)
        }
        .frame(width: 84, height: 10)
        .help(onAdjust == nil ? "" : "Drag to adjust")
    }

    private func progress(for locationX: CGFloat, width: CGFloat) -> Float {
        Float(max(0, min(1, locationX / max(1, width))))
    }
}
