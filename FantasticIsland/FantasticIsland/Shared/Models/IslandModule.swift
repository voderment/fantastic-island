import SwiftUI

enum IslandActivityKind: Int, Equatable, Codable {
    case actionRequired
    case transientNotification
    case persistentPresence

    var sortPriority: Int {
        switch self {
        case .actionRequired:
            return 3
        case .transientNotification:
            return 2
        case .persistentPresence:
            return 1
        }
    }
}

enum IslandActivityAutoPresentationScope: String, Equatable, Codable {
    case selectedModuleOnly
    case global
    case manualOnly
}

struct IslandActivityPresentationPolicy: Equatable, Codable {
    var autoPresentationScope: IslandActivityAutoPresentationScope
    var autoDismissDelay: TimeInterval?
    var switchSelectedModuleOnAutoPresentation: Bool = true
    var promoteWhileExpanded: Bool = true

    static let manualOnly = IslandActivityPresentationPolicy(
        autoPresentationScope: .manualOnly,
        autoDismissDelay: nil,
        switchSelectedModuleOnAutoPresentation: false,
        promoteWhileExpanded: false
    )
}

struct IslandActivity: Identifiable, Equatable, Codable {
    let id: String
    let moduleID: String
    let sourceID: String
    let kind: IslandActivityKind
    let priority: Int
    let createdAt: Date
    let updatedAt: Date
    let presentationPolicy: IslandActivityPresentationPolicy
}

enum IslandModulePresentationContext: Equatable {
    case standard
    case activity(IslandActivity)
    case peek(IslandActivity)
}

enum IslandOpenReason: Equatable {
    case manualTap
    case shortcut
    case hover
    case notification(activityID: String)

    var notificationActivityID: String? {
        guard case let .notification(activityID) = self else {
            return nil
        }

        return activityID
    }

    var isNotification: Bool {
        notificationActivityID != nil
    }
}

@MainActor
protocol IslandModule: AnyObject {
    var id: String { get }
    var title: String { get }
    var symbolName: String { get }
    var iconAssetName: String? { get }
    var collapsedSummaryItems: [CollapsedSummaryItem] { get }
    var islandActivities: [IslandActivity] { get }
    var taskActivityContribution: TaskActivityContribution { get }
    var preferredOpenedContentHeight: CGFloat { get }
    var allowsInternalScrolling: Bool { get }

    func preferredOpenedContentHeight(for presentation: IslandModulePresentationContext) -> CGFloat
    func makeContentView(presentation: IslandModulePresentationContext) -> AnyView
}

extension IslandModule {
    var iconAssetName: String? { nil }
    var islandActivities: [IslandActivity] { [] }
    var allowsInternalScrolling: Bool { true }

    func preferredOpenedContentHeight(for presentation: IslandModulePresentationContext) -> CGFloat {
        preferredOpenedContentHeight
    }

    func makeContentView() -> AnyView {
        makeContentView(presentation: .standard)
    }
}

@MainActor
struct IslandModuleRegistry {
    let modules: [any IslandModule]

    func module(id: String) -> (any IslandModule)? {
        modules.first { $0.id == id }
    }
}
