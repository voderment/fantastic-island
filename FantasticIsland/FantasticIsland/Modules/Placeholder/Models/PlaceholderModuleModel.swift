import Combine
import SwiftUI

@MainActor
final class PlaceholderModuleModel: ObservableObject, IslandModule {
    let id = "placeholder"
    let title = "blank"
    let symbolName = "square.dashed"

    var collapsedSummaryItems: [CollapsedSummaryItem] { [] }
    var taskActivityContribution = TaskActivityContribution()
    var preferredOpenedContentHeight: CGFloat { 196 }

    func makeLiveContentView(presentation: IslandModulePresentationContext) -> AnyView {
        AnyView(PlaceholderModuleContentView())
    }
}

private struct PlaceholderModuleContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reserved module slot")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Text("This tab is intentionally empty. The next module will plug into the island container without changing the shell.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.54))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .center)
        .padding(.horizontal, 20)
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }
}
