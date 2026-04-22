import AppKit
import SwiftUI

private struct PreviewShellSurface<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))

            content
                .padding(20)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.08, blue: 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

#Preview("Shell Gallery") {
    ScrollView {
        VStack(alignment: .leading, spacing: 28) {
            PreviewShellSurface(title: "Closed") {
                IslandClosedHeaderView(state: IslandShellPreviewMocks.closedHeader)
                .frame(width: 360, height: 38)
            }

            PreviewShellSurface(title: "Expanded With Wind Drive") {
                VStack(alignment: .leading, spacing: CodexIslandChromeMetrics.moduleColumnSpacing) {
                    IslandExpandedNavigationView(state: IslandShellPreviewMocks.expandedTabs)

                    HStack(alignment: .top, spacing: CodexIslandChromeMetrics.moduleColumnSpacing) {
                        IslandWindDrivePanelView(state: IslandShellPreviewMocks.windDrivePanel)

                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .frame(width: 430, height: 220)
                    }
                }
                .padding(CodexIslandChromeMetrics.expandedContentHorizontalInset)
                .frame(width: 760, alignment: .topLeading)
            }

            PreviewShellSurface(title: "Expanded Without Wind Drive") {
                VStack(alignment: .leading, spacing: CodexIslandChromeMetrics.moduleColumnSpacing) {
                    IslandExpandedNavigationView(state: IslandShellPreviewMocks.playerOnlyTabs)

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 620, height: 180)
                }
                .padding(CodexIslandChromeMetrics.expandedContentHorizontalInset)
                .frame(width: 720, alignment: .topLeading)
            }

            PreviewShellSurface(title: "Peek Notification") {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 520, height: 112)
            }

            PreviewShellSurface(title: "Peek Actionable") {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 520, height: 180)
            }
        }
    }
    .frame(width: 980, height: 1200)
    .preferredColorScheme(.dark)
}
