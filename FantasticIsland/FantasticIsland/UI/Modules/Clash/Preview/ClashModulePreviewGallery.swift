import SwiftUI

private struct ClashPreviewCard: View {
    let model: ClashPreviewCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: ClashExpandedMetrics.sectionTitleSpacing) {
            Text(model.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
            Text(model.detail)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(16)
        .background(Color.white.opacity(ClashExpandedMetrics.cardBackgroundOpacity), in: RoundedRectangle(cornerRadius: ClashExpandedMetrics.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ClashExpandedMetrics.cardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(ClashExpandedMetrics.cardBorderOpacity), lineWidth: 1)
        }
    }
}

#Preview("Clash Gallery") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            IslandPreviewContainer(title: "Expanded") {
                VStack(alignment: .leading, spacing: ClashExpandedMetrics.outerSpacing) {
                    ClashPreviewCard(model: ClashPreviewMocks.expandedCards[0])
                    VStack(spacing: ClashExpandedMetrics.cardSpacing) {
                        ForEach(ClashPreviewMocks.expandedCards.dropFirst()) { card in
                            ClashPreviewCard(model: card)
                        }
                    }
                }
                .frame(width: 560, alignment: .leading)
            }

            IslandPreviewContainer(title: "Pinned Header") {
                ClashPreviewCard(model: ClashPreviewMocks.pinnedHeader)
                    .frame(width: 560, alignment: .leading)
            }

            IslandPreviewContainer(title: "Empty") {
                ClashPreviewCard(model: ClashPreviewMocks.emptyCard)
                    .frame(width: 560, alignment: .leading)
            }
        }
    }
    .frame(width: 860, height: 900)
    .background(Color(red: 0.06, green: 0.06, blue: 0.08))
    .preferredColorScheme(.dark)
}
