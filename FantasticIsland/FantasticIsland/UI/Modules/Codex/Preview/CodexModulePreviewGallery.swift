import SwiftUI

private struct CodexPreviewCard: View {
    let model: CodexPreviewCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: CodexExpandedMetrics.contentSpacing) {
            HStack {
                Text(model.title)
                    .font(.system(size: CodexExpandedMetrics.titleFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(model.subtitle)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Text(model.bodyText)
                .font(.system(size: CodexExpandedMetrics.summaryFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white.opacity(CodexExpandedMetrics.cardBackgroundOpacity), in: RoundedRectangle(cornerRadius: CodexExpandedMetrics.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CodexExpandedMetrics.cardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(CodexExpandedMetrics.cardBorderOpacity), lineWidth: 1)
        }
    }
}

#Preview("Codex Gallery") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            IslandPreviewContainer(title: "Expanded") {
                VStack(alignment: .leading, spacing: CodexExpandedMetrics.contentSpacing) {
                    HStack(spacing: CodexExpandedMetrics.globalInfoBadgeSpacing) {
                        Capsule().fill(Color.white.opacity(0.08)).frame(width: 140, height: 32)
                        Capsule().fill(Color.white.opacity(0.08)).frame(width: 140, height: 32)
                        Capsule().fill(Color.white.opacity(0.08)).frame(width: 100, height: 32)
                    }

                    VStack(spacing: CodexExpandedMetrics.sectionRowSpacing) {
                        ForEach(CodexPreviewMocks.expandedCards) { card in
                            CodexPreviewCard(model: card)
                        }
                    }
                }
                .frame(width: 560, alignment: .leading)
            }

            IslandPreviewContainer(title: "Peek") {
                CodexPreviewCard(model: CodexPreviewMocks.peekCard)
                    .frame(width: 520, alignment: .leading)
            }

            IslandPreviewContainer(title: "Empty") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(CodexPreviewMocks.emptyStateTitle)
                        .font(.system(size: CodexExpandedMetrics.titleFontSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(CodexPreviewMocks.emptyStateMessage)
                        .font(.system(size: CodexExpandedMetrics.summaryFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .frame(width: 560)
                .frame(minHeight: CodexExpandedMetrics.emptyStateMinimumHeight, alignment: .center)
                .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: CodexExpandedMetrics.cardCornerRadius, style: .continuous))
            }
        }
    }
    .frame(width: 860, height: 980)
    .background(Color(red: 0.06, green: 0.06, blue: 0.08))
    .preferredColorScheme(.dark)
}
