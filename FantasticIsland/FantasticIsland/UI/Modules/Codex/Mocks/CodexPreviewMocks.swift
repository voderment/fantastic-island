import Foundation

struct CodexPreviewCardModel: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let bodyText: String
}

enum CodexPreviewMocks {
    static let expandedCards: [CodexPreviewCardModel] = [
        CodexPreviewCardModel(
            id: "need-approval",
            title: "Need approval",
            subtitle: "LIVE 00:12",
            bodyText: "The CLI is waiting for a permission approval and should keep the primary action area visible."
        ),
        CodexPreviewCardModel(
            id: "session-completed",
            title: "Session completed",
            subtitle: "DONE",
            bodyText: "Completed rollout summary appears with a calmer chrome treatment."
        ),
    ]

    static let peekCard = CodexPreviewCardModel(
        id: "peek-completed",
        title: "Rollout finished",
        subtitle: "COMPLETED",
        bodyText: "Summarized notification content for the lightweight peek state."
    )

    static let emptyStateTitle = "No live conversations"
    static let emptyStateMessage = "Open Codex to populate live sessions here."
}
