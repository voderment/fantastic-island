import SwiftUI

enum IslandCardMetrics {
    static let moduleCardCornerRadius: CGFloat = 16
    static let moduleCardFillColor = Color.white.opacity(0.045)
    static let moduleCardStrokeColor = Color.white.opacity(0.11)
}

private struct IslandModuleCardSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat
    var fillColor: Color
    var strokeColor: Color
    var strokeWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [fillColor.opacity(1.35), fillColor.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [strokeColor.opacity(1.2), strokeColor.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: strokeWidth
                    )
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
                    .padding(.horizontal, cornerRadius)
            }
    }
}

extension View {
    func islandModuleCardSurface(
        cornerRadius: CGFloat = IslandCardMetrics.moduleCardCornerRadius,
        fillColor: Color = IslandCardMetrics.moduleCardFillColor,
        strokeColor: Color = IslandCardMetrics.moduleCardStrokeColor,
        strokeWidth: CGFloat = 1
    ) -> some View {
        modifier(
            IslandModuleCardSurfaceModifier(
                cornerRadius: cornerRadius,
                fillColor: fillColor,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth
            )
        )
    }
}

struct IslandSwitch: View {
    enum Size {
        case medium

        var trackWidth: CGFloat {
            switch self {
            case .medium: 38
            }
        }

        var trackHeight: CGFloat {
            switch self {
            case .medium: 22
            }
        }

        var knobSize: CGFloat {
            switch self {
            case .medium: 16
            }
        }

        var knobInset: CGFloat {
            switch self {
            case .medium: 3
            }
        }
    }

    @Binding var isOn: Bool
    var size: Size = .medium

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? Color.accentColor : Color.white.opacity(0.14))
                    .frame(width: size.trackWidth, height: size.trackHeight)

                Circle()
                    .fill(.white.opacity(0.96))
                    .frame(width: size.knobSize, height: size.knobSize)
                    .padding(size.knobInset)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
