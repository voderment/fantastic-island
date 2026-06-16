import SwiftUI

struct IslandExpandedNavigationView: View {
    let state: IslandShellExpandedNavigationRenderState

    var body: some View {
        HStack(spacing: CodexIslandChromeMetrics.moduleHeaderToolbarSpacing) {
            HStack(spacing: tabSpacing) {
                ForEach(state.tabs) { tab in
                    Button(action: tab.action) {
                        tabLabel(tab)
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

    private var usesCompactTabs: Bool {
        state.tabs.count > 3
    }

    private var tabSpacing: CGFloat {
        usesCompactTabs ? 4 : CodexIslandChromeMetrics.moduleTabSpacing
    }

    private func tabLabel(_ tab: IslandShellTabRenderState) -> some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: tab.isSelected && !usesCompactTabs ? 7 : 0) {
                tabIcon(tab)
                    .frame(width: 14, height: 14, alignment: .center)

                if tab.isSelected && !usesCompactTabs {
                    Text(tab.title)
                        .font(IslandVisualLanguage.islandBody(12, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .foregroundStyle(tab.isSelected ? Color.black.opacity(0.9) : .white.opacity(0.74))
            .frame(width: tabWidth(for: tab), height: 28)
            .background {
                tabBackground(tab)
            }

            if tab.showsPendingBadge {
                Circle()
                    .fill(IslandVisualLanguage.accent)
                    .frame(width: 7, height: 7)
                    .offset(x: 1.5, y: -1.5)
            }
        }
        .contentShape(Capsule(style: .continuous))
    }

    private func tabWidth(for tab: IslandShellTabRenderState) -> CGFloat? {
        usesCompactTabs ? 30 : nil
    }

    private func tabBackground(_ tab: IslandShellTabRenderState) -> some View {
        Capsule(style: .continuous)
            .fill(tabBackgroundColor(tab))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(tab.isSelected ? 0 : 0.09), lineWidth: 0.7)
            }
            .shadow(color: tab.isSelected ? .black.opacity(0.12) : .clear, radius: 6, y: 2)
    }

    private func tabBackgroundColor(_ tab: IslandShellTabRenderState) -> Color {
        tab.isSelected ? Color.white.opacity(0.94) : Color.white.opacity(0.055)
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
