import SwiftUI

struct IslandClosedHeaderView: View {
    let state: IslandShellClosedHeaderRenderState
    let notchExclusionWidth: CGFloat

    init(state: IslandShellClosedHeaderRenderState, notchExclusionWidth: CGFloat = 0) {
        self.state = state
        self.notchExclusionWidth = notchExclusionWidth
    }

    var body: some View {
        Group {
            if notchExclusionWidth > 0 {
                HStack(spacing: 0) {
                    HStack(spacing: 0) {
                        IslandFanIconView(animationState: state.fanAnimationState)
                    }
                    .padding(.horizontal, CodexIslandChromeMetrics.closedHorizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Color.clear
                        .frame(width: notchExclusionWidth)

                    Color.clear
                        .padding(.horizontal, CodexIslandChromeMetrics.closedHorizontalPadding)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(spacing: 0) {
                    IslandFanIconView(animationState: state.fanAnimationState)

                    Spacer(minLength: CodexIslandChromeMetrics.closedFanModuleSpacing)

                    HStack(spacing: CodexIslandChromeMetrics.closedModuleSpacing) {
                        ForEach(state.compactModules) { module in
                            compactModuleSummary(module)
                        }
                    }
                }
                .padding(.horizontal, CodexIslandChromeMetrics.closedHorizontalPadding)
            }
        }
    }

    @ViewBuilder
    private func compactModuleSummary(_ module: CompactModuleSummary) -> some View {
        HStack(spacing: module.contentSpacing) {
            compactModuleIcon(for: module)

            switch module.content {
            case let .singleLine(text):
                Text(text)
                    .font(.system(size: CodexIslandChromeMetrics.closedPrimaryFontSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            case let .clashTraffic(upload, download):
                compactClashTraffic(upload: upload, download: download)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(module.title) \(module.accessibilityText)")
    }

    @ViewBuilder
    private func compactModuleIcon(for module: CompactModuleSummary) -> some View {
        if let iconAssetName = module.iconAssetName {
            Image(iconAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: CodexIslandChromeMetrics.closedIconSize, height: CodexIslandChromeMetrics.closedIconSize)
        } else {
            Image(systemName: module.symbolName)
                .font(.system(size: CodexIslandChromeMetrics.closedIconSize - 2, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: CodexIslandChromeMetrics.closedIconSize, height: CodexIslandChromeMetrics.closedIconSize)
        }
    }

    private func compactClashTraffic(upload: String, download: String) -> some View {
        VStack(alignment: .leading, spacing: CodexIslandChromeMetrics.closedTrafficLineSpacing) {
            Text(upload)
                .font(.system(size: CodexIslandChromeMetrics.closedTrafficFontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.18, green: 0.82, blue: 0.29))
                .lineLimit(1)

            Text(download)
                .font(.system(size: CodexIslandChromeMetrics.closedTrafficFontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.02, green: 0.55, blue: 1.0))
                .lineLimit(1)
        }
        .frame(width: CodexIslandChromeMetrics.compactClashTrafficBlockWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
