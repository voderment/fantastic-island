import SwiftUI

enum IslandVisualLanguage {
    static let accent = Color(red: 0.29, green: 0.86, blue: 0.46)
    static let shellTop = Color.black
    static let shellBottom = Color.black
    static let closedShell = Color.black
    static let glassFill = Color.white.opacity(0.038)
    static let glassStroke = Color.white.opacity(0.08)
    static let glassHighlight = Color.white.opacity(0.035)

    static var shellGradient: LinearGradient {
        LinearGradient(
            colors: [Color.black, Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var shellStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var closedShellStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.08), Color.white.opacity(0.025)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func islandLabel(_ size: CGFloat = 11, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func islandTitle(_ size: CGFloat = 15, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func islandBody(_ size: CGFloat = 13, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

private struct IslandGlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Capsule(style: .continuous)
                    .fill(IslandVisualLanguage.glassFill)
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(IslandVisualLanguage.glassStroke, lineWidth: 0.75)
            }
    }
}

private struct IslandGlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.034))
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.075), lineWidth: 0.75)
            }
    }
}

extension View {
    func islandGlassCapsule() -> some View {
        modifier(IslandGlassCapsuleModifier())
    }

    func islandGlassPanel(cornerRadius: CGFloat = 14) -> some View {
        modifier(IslandGlassPanelModifier(cornerRadius: cornerRadius))
    }
}
