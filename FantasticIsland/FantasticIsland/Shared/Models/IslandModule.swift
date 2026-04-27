import SwiftUI
#if DEBUG
import OSLog
#endif

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

    var cacheKey: String {
        switch self {
        case .standard:
            return "standard"
        case let .activity(activity):
            return "activity::\(activity.id)"
        case let .peek(activity):
            return "peek::\(activity.id)"
        }
    }
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

enum IslandPresentationState: Equatable {
    case closed
    case peek(activityID: String)
    case expanded(moduleID: String, activityID: String?)

    var visualMode: IslandPresentationVisualMode {
        switch self {
        case .closed:
            return .closed
        case .peek:
            return .peek
        case .expanded:
            return .expanded
        }
    }
}

enum IslandPresentationVisualMode: Equatable {
    case closed
    case peek
    case expanded
}

enum IslandTransitionPhase: Equatable {
    case preparing
    case morphing
    case revealingContent
    case stable
}

struct IslandTransitionEnvelope: Equatable {
    let presentation: IslandPresentationState
    let lockedHeight: CGFloat
}

struct IslandTransitionPlan: Identifiable {
    let id: UUID
    let from: IslandPresentationState
    let to: IslandPresentationState
    let targetEnvelope: IslandTransitionEnvelope
    let lockedHeight: CGFloat
    let startedAt: Date
}

struct IslandModuleRenderSnapshot: Identifiable {
    let id: String
    let moduleID: String
    let presentation: IslandModulePresentationContext
    let preferredHeight: CGFloat
    let allowsInternalScrolling: Bool
    let view: AnyView
}

#if DEBUG
enum IslandTransitionDiagnostics {
    private static let transitionLogger = Logger(subsystem: "io.github.fantasticisland", category: "transition")
    private static let panelLogger = Logger(subsystem: "io.github.fantasticisland", category: "panel")
    private static let publishLogger = Logger(subsystem: "io.github.fantasticisland", category: "publish")
    private static let playerLogger = Logger(subsystem: "io.github.fantasticisland", category: "player")

    static func transition(_ message: String) {
        transitionLogger.debug("\(message, privacy: .public)")
    }

    static func panel(_ message: String) {
        panelLogger.debug("\(message, privacy: .public)")
    }

    static func publish(_ message: String) {
        publishLogger.debug("\(message, privacy: .public)")
    }

    static func player(_ message: String) {
        playerLogger.debug("\(message, privacy: .public)")
    }
}
#else
enum IslandTransitionDiagnostics {
    static func transition(_ message: String) {}
    static func panel(_ message: String) {}
    static func publish(_ message: String) {}
    static func player(_ message: String) {}
}
#endif

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
    func makeRenderSnapshot(presentation: IslandModulePresentationContext) -> IslandModuleRenderSnapshot
    func makeLiveContentView(presentation: IslandModulePresentationContext) -> AnyView
}

extension IslandModule {
    var iconAssetName: String? { nil }
    var islandActivities: [IslandActivity] { [] }
    var allowsInternalScrolling: Bool { true }

    func preferredOpenedContentHeight(for presentation: IslandModulePresentationContext) -> CGFloat {
        preferredOpenedContentHeight
    }

    func makeRenderSnapshot(presentation: IslandModulePresentationContext) -> IslandModuleRenderSnapshot {
        IslandModuleRenderSnapshot(
            id: "\(id)::\(presentation.cacheKey)",
            moduleID: id,
            presentation: presentation,
            preferredHeight: preferredOpenedContentHeight(for: presentation),
            allowsInternalScrolling: allowsInternalScrolling,
            view: makeLiveContentView(presentation: presentation)
        )
    }
}

@MainActor
struct IslandModuleRegistry {
    let modules: [any IslandModule]

    func module(id: String) -> (any IslandModule)? {
        modules.first { $0.id == id }
    }
}
