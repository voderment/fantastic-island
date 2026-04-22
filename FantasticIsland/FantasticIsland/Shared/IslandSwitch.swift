import SwiftUI

enum IslandCardMetrics {
    static let moduleCardCornerRadius: CGFloat = 14
    static let moduleCardFillColor = Color.white.opacity(0.05)
    static let moduleCardStrokeColor = Color.white.opacity(0.10)
}

private struct IslandModuleCardSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat
    var fillColor: Color
    var strokeColor: Color
    var strokeWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .background(fillColor, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: strokeWidth)
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
