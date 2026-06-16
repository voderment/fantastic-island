// Visualizer pattern adapted from TheBoredTeam/boring.notch MusicVisualizer (OSS)

import SwiftUI

struct PlayerVisualizerView: View {
    let isPlaying: Bool

    @State private var barHeights: [CGFloat] = [0.35, 0.55, 0.42, 0.68]
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(barHeights.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.95), Color.white.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: 16 * barHeights[index])
                    .animation(.easeOut(duration: 0.22), value: barHeights[index])
            }
        }
        .frame(height: 16, alignment: .bottom)
        .onAppear { updateAnimation() }
        .onChange(of: isPlaying) { _, _ in updateAnimation() }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
        }
    }

    private func updateAnimation() {
        animationTask?.cancel()

        guard isPlaying else {
            withAnimation(.easeOut(duration: 0.2)) {
                barHeights = [0.35, 0.35, 0.35, 0.35]
            }
            return
        }

        animationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(240))
                barHeights = (0 ..< 4).map { _ in CGFloat.random(in: 0.35 ... 1.0) }
            }
        }
    }
}
