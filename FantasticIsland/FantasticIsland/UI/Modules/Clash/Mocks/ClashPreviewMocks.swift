import Foundation

struct ClashPreviewCardModel: Identifiable {
    let id: String
    let title: String
    let detail: String
}

enum ClashPreviewMocks {
    static let expandedCards: [ClashPreviewCardModel] = [
        ClashPreviewCardModel(id: "system-proxy", title: "System Proxy", detail: "↑ 128K  ↓ 2.1M  RULE"),
        ClashPreviewCardModel(id: "auto-group", title: "Proxy Group: Auto", detail: "Current: Tokyo-01   38 ms"),
        ClashPreviewCardModel(id: "streaming-group", title: "Proxy Group: Streaming", detail: "Current: US-03   126 ms"),
    ]

    static let pinnedHeader = ClashPreviewCardModel(
        id: "pinned-header",
        title: "Pinned Proxy Group Header",
        detail: "The expanded group header stays attached during scroll."
    )

    static let emptyCard = ClashPreviewCardModel(
        id: "empty",
        title: "No proxy groups",
        detail: "Use the managed runtime or connect an attach-mode Clash API to populate node groups."
    )
}
