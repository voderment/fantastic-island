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
                    HStack(spacing: CodexIslandChromeMetrics.closedModuleSpacing) {
                        ForEach(state.compactModules.prefix(1)) { module in
                            compactModuleSummary(module)
                        }
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
                    .font(IslandVisualLanguage.islandLabel(CodexIslandChromeMetrics.closedPrimaryFontSize))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            case let .agentGrid(indicators, overflow):
                let count = indicators.count + overflow
                HStack(spacing: 5) {
                    if count > 0 {
                        CompactAgentGridView(indicators: indicators, overflow: overflow)
                    }
                    CompactAgentCountBadge(count: count)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
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

}

private struct CompactAgentCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(count > 0 ? .white.opacity(0.92) : .white.opacity(0.38))
            .lineLimit(1)
            .frame(minWidth: 16)
            .frame(height: 14)
            .padding(.horizontal, 1)
            .background(Color.white.opacity(count > 0 ? 0.10 : 0.045), in: Capsule())
            .accessibilityLabel(count == 1 ? "1 active session" : "\(count) active sessions")
    }
}

private struct CompactAgentGridView: View {
    let indicators: [CompactAgentIndicator]
    let overflow: Int

    private var cells: [CompactAgentGridCell] {
        var cells = indicators.map(CompactAgentGridCell.session)
        if overflow > 0 {
            cells.append(.overflow(overflow))
        }
        return cells
    }

    var body: some View {
        let rowSizes = CompactAgentGridMetrics.balancedRows(cells.count)
        let geometry = CompactAgentGridMetrics.cellGeometry(rowCount: rowSizes.count)
        let rows = splitIntoRows(cells, rowSizes: rowSizes)

        VStack(spacing: geometry.gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: geometry.gap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        CompactAgentGridTile(cell: cell, size: geometry.cell, radius: geometry.radius)
                    }
                }
            }
        }
        .fixedSize()
    }

    private func splitIntoRows(_ cells: [CompactAgentGridCell], rowSizes: [Int]) -> [[CompactAgentGridCell]] {
        var rows: [[CompactAgentGridCell]] = []
        var index = 0
        for size in rowSizes {
            let end = min(index + size, cells.count)
            rows.append(Array(cells[index..<end]))
            index = end
            if index >= cells.count { break }
        }
        return rows
    }
}

private enum CompactAgentGridCell {
    case session(CompactAgentIndicator)
    case overflow(Int)
}

private struct CompactAgentGridTile: View {
    let cell: CompactAgentGridCell
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        switch cell {
        case let .session(indicator):
            CompactAgentStateTile(
                color: indicator.provider.closedIndicatorColor,
                state: indicator.state,
                size: size,
                radius: radius
            )
        case let .overflow(count):
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.white.opacity(0.14))
                Text("+\(count)")
                    .font(.system(size: max(5, size * 0.55), weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(width: size, height: size)
        }
    }
}

private struct CompactAgentStateTile: View {
    let color: Color
    let state: CompactAgentIndicatorState
    let size: CGFloat
    let radius: CGFloat
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .opacity(opacity)
            .shadow(color: color.opacity(state == .running ? 0.24 : 0), radius: 3, y: 0)
            .onAppear {
                guard state == .waiting else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }

    private var opacity: Double {
        switch state {
        case .running:
            return 1
        case .waiting:
            return pulse ? 1 : 0.35
        case .idle:
            return 0.24
        }
    }
}

private extension AgentProvider {
    var closedIndicatorColor: Color {
        switch self {
        case .codex:
            return Color(red: 0.52, green: 0.72, blue: 1.0)
        case .claudeCode:
            return Color(red: 0.93, green: 0.56, blue: 0.34)
        case .cursor:
            return Color(red: 0.62, green: 0.66, blue: 1.0)
        case .antigravity:
            return Color(red: 0.44, green: 0.82, blue: 0.70)
        case .conductor:
            return Color(red: 0.86, green: 0.78, blue: 1.0)
        }
    }
}
