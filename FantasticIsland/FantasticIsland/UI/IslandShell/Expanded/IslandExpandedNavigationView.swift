import SwiftUI

struct IslandExpandedNavigationView: View {
    let state: IslandShellExpandedNavigationRenderState

    var body: some View {
        HStack(spacing: CodexIslandChromeMetrics.moduleHeaderToolbarSpacing) {
            HStack(spacing: CodexIslandChromeMetrics.moduleTabSpacing) {
                ForEach(state.tabs) { tab in
                    Button(action: tab.action) {
                        HStack(spacing: tab.isSelected ? 7 : 0) {
                            tabIcon(tab)
                                .frame(width: 14, height: 14, alignment: .center)

                            if tab.isSelected {
                                Text(tab.title)
                                    .font(IslandVisualLanguage.islandBody(12, weight: .semibold))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            }

                            if tab.showsPendingBadge {
                                Circle()
                                    .fill(IslandVisualLanguage.accent)
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .foregroundStyle(tab.isSelected ? Color.black.opacity(0.9) : .white.opacity(0.74))
                        .padding(.horizontal, tab.isSelected ? CodexIslandChromeMetrics.moduleTabHorizontalPadding : 9)
                        .padding(.vertical, CodexIslandChromeMetrics.moduleTabVerticalPadding)
                        .background {
                            if tab.isSelected {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.94))
                                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                            } else {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            }
                        }
                        .frame(height: max(32, CodexIslandChromeMetrics.moduleNavigationRowHeight - 4))
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                    .accessibilityLabel(tab.title)
                    .animation(.easeOut(duration: 0.18), value: tab.isSelected)
                }
            }

            Spacer()

            Button(action: state.openSettings) {
                Image(systemName: "gear")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.07), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.75)
                    }
            }
            .buttonStyle(.plain)
            .help("Open settings")
        }
    }

    @ViewBuilder
    private func tabIcon(_ tab: IslandShellTabRenderState) -> some View {
        if let iconAssetName = tab.iconAssetName {
            Image(iconAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: tab.symbolName)
                .font(.system(size: 12, weight: .semibold))
        }
    }
}
