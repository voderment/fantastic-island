import AppKit
import Foundation

enum SessionPhase: String, Codable {
    case running
    case busy
    case waitingForApproval
    case waitingForAnswer
    case completed

    var displayName: String {
        switch self {
        case .running:
            return "Running"
        case .busy:
            return "Busy"
        case .waitingForApproval:
            return "Needs Approval"
        case .waitingForAnswer:
            return "Needs Answer"
        case .completed:
            return "Completed"
        }
    }

    var requiresAttention: Bool {
        switch self {
        case .waitingForApproval, .waitingForAnswer:
            return true
        case .running, .busy, .completed:
            return false
        }
    }
}

enum CodexIslandSurface: Equatable, Codable {
    case sessionList(actionableSessionID: String? = nil)

    var sessionID: String? {
        switch self {
        case let .sessionList(actionableSessionID):
            actionableSessionID
        }
    }

    var isNotificationCard: Bool {
        sessionID != nil
    }

    func matchesCurrentState(of session: SessionSnapshot?) -> Bool {
        guard sessionID != nil else {
            return true
        }

        guard let session else {
            return false
        }

        switch session.phase {
        case .waitingForApproval:
            return session.permissionRequest != nil
        case .waitingForAnswer:
            return session.questionPrompt != nil
        case .completed:
            return true
        case .running, .busy:
            return false
        }
    }

    static func notificationSurface(for event: CodexAgentEvent) -> CodexIslandSurface? {
        switch event {
        case let .permissionRequested(payload):
            return .sessionList(actionableSessionID: payload.sessionID)
        case let .questionAsked(payload):
            return .sessionList(actionableSessionID: payload.sessionID)
        case let .sessionCompleted(payload):
            return payload.isSessionEnd ? nil : .sessionList(actionableSessionID: payload.sessionID)
        default:
            return nil
        }
    }
}

enum CodexSessionSurface: String, Codable {
    case unknown
    case terminal
    case codexApp

    func merged(with other: CodexSessionSurface) -> CodexSessionSurface {
        if self == .codexApp || other == .codexApp {
            return .codexApp
        }

        if self == .terminal || other == .terminal {
            return .terminal
        }

        return .unknown
    }
}

struct SessionSourceFlags: OptionSet, Codable {
    let rawValue: Int

    static let rollout = SessionSourceFlags(rawValue: 1 << 0)
    static let hooks = SessionSourceFlags(rawValue: 1 << 1)
    static let appServer = SessionSourceFlags(rawValue: 1 << 2)
}

struct CodexPermissionRequest: Equatable, Codable {
    var title: String
    var summary: String
    var affectedPath: String
    var primaryActionTitle: String
    var secondaryActionTitle: String
    var alwaysActionTitle: String?
    var toolName: String?
    var toolUseID: String?
    var requiresTerminalApproval: Bool

    init(
        title: String,
        summary: String,
        affectedPath: String = "",
        primaryActionTitle: String = "Yes",
        secondaryActionTitle: String = "No",
        alwaysActionTitle: String? = nil,
        toolName: String? = nil,
        toolUseID: String? = nil,
        requiresTerminalApproval: Bool = false
    ) {
        self.title = title
        self.summary = summary
        self.affectedPath = affectedPath
        self.primaryActionTitle = primaryActionTitle
        self.secondaryActionTitle = secondaryActionTitle
        self.alwaysActionTitle = alwaysActionTitle
        self.toolName = toolName
        self.toolUseID = toolUseID
        self.requiresTerminalApproval = requiresTerminalApproval
    }
}

struct CodexQuestionOption: Equatable, Codable, Hashable {
    var label: String
    var description: String

    init(label: String, description: String = "") {
        self.label = label
        self.description = description
    }
}

struct CodexQuestionItem: Equatable, Codable {
    var id: String
    var header: String
    var question: String
    var options: [CodexQuestionOption]
    var allowsCustomAnswer: Bool
    var isSecret: Bool
    var multiSelect: Bool

    init(
        id: String,
        header: String,
        question: String,
        options: [CodexQuestionOption] = [],
        allowsCustomAnswer: Bool = false,
        isSecret: Bool = false,
        multiSelect: Bool = false
    ) {
        self.id = id
        self.header = header
        self.question = question
        self.options = options
        self.allowsCustomAnswer = allowsCustomAnswer
        self.isSecret = isSecret
        self.multiSelect = multiSelect
    }
}

struct CodexQuestionPrompt: Equatable, Codable {
    var title: String
    var options: [String]
    var questions: [CodexQuestionItem]

    init(title: String, options: [String] = [], questions: [CodexQuestionItem] = []) {
        self.title = title
        self.options = options
        self.questions = questions
    }
}

struct CodexQuestionResponse: Equatable, Codable {
    var rawAnswer: String?
    var answers: [String: [String]]

    init(rawAnswer: String? = nil, answers: [String: [String]] = [:]) {
        self.rawAnswer = rawAnswer
        self.answers = answers
    }

    init(answer: String) {
        self.rawAnswer = answer
        self.answers = [:]
    }

    var displaySummary: String {
        if let rawAnswer {
            let trimmed = rawAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        let fragments = answers
            .keys
            .sorted()
            .compactMap { key -> String? in
                guard let values = answers[key], !values.isEmpty else {
                    return nil
                }

                return "\(key): \(values.joined(separator: ", "))"
            }

        return fragments.joined(separator: " · ")
    }
}

enum CodexPendingRequestSource: String, Codable {
    case appServer
    case hook
}

enum CodexPendingRequestKind: String, Codable {
    case permission
    case question
}

struct CodexPendingRequestContext: Equatable, Codable {
    var requestID: String
    var source: CodexPendingRequestSource
    var kind: CodexPendingRequestKind
    var method: String?
    var itemID: String?
    var turnID: String?
    var threadID: String?
    var createdAt: Date

    init(
        requestID: String,
        source: CodexPendingRequestSource,
        kind: CodexPendingRequestKind,
        method: String? = nil,
        itemID: String? = nil,
        turnID: String? = nil,
        threadID: String? = nil,
        createdAt: Date = .now
    ) {
        self.requestID = requestID
        self.source = source
        self.kind = kind
        self.method = method
        self.itemID = itemID
        self.turnID = turnID
        self.threadID = threadID
        self.createdAt = createdAt
    }
}

enum CodexApprovalAction: String, Equatable, Codable {
    case deny
    case allowOnce
    case allowAlways

    var isApproved: Bool {
        self != .deny
    }
}

struct CodexTerminalJumpTarget: Identifiable, Codable, Hashable {
    var id: String
    var sessionID: String
    var transcriptPath: String?
    var terminalApp: String
    var workspaceName: String
    var paneTitle: String
    var workingDirectory: String?
    var bundleIdentifier: String?
    var processIdentifier: Int?
    var terminalSessionID: String?
    var terminalTTY: String?
    var windowIdentifier: String?
    var tabIdentifier: String?
    var paneIdentifier: String?
    var tmuxTarget: String?
    var tmuxSocketPath: String?
    var warpPaneUUID: String?

    init(
        sessionID: String,
        transcriptPath: String? = nil,
        terminalApp: String,
        workspaceName: String,
        paneTitle: String,
        workingDirectory: String? = nil,
        bundleIdentifier: String? = nil,
        processIdentifier: Int? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil,
        windowIdentifier: String? = nil,
        tabIdentifier: String? = nil,
        paneIdentifier: String? = nil,
        tmuxTarget: String? = nil,
        tmuxSocketPath: String? = nil,
        warpPaneUUID: String? = nil
    ) {
        self.sessionID = sessionID
        self.transcriptPath = transcriptPath
        self.terminalApp = terminalApp
        self.workspaceName = workspaceName
        self.paneTitle = paneTitle
        self.workingDirectory = workingDirectory
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.windowIdentifier = windowIdentifier
        self.tabIdentifier = tabIdentifier
        self.paneIdentifier = paneIdentifier
        self.tmuxTarget = tmuxTarget
        self.tmuxSocketPath = tmuxSocketPath
        self.warpPaneUUID = warpPaneUUID
        self.id = Self.makeIdentifier(
            sessionID: sessionID,
            transcriptPath: transcriptPath,
            terminalApp: terminalApp,
            workspaceName: workspaceName,
            paneTitle: paneTitle,
            workingDirectory: workingDirectory,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            terminalSessionID: terminalSessionID,
            terminalTTY: terminalTTY,
            windowIdentifier: windowIdentifier,
            tabIdentifier: tabIdentifier,
            paneIdentifier: paneIdentifier,
            tmuxTarget: tmuxTarget,
            warpPaneUUID: warpPaneUUID
        )
    }

    var displayLabel: String {
        let trimmed = terminalApp.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }

        return "Terminal"
    }

    var detailLabel: String? {
        var parts: [String] = []

        if let terminalTTY, !terminalTTY.isEmpty {
            parts.append(terminalTTY)
        }
        if let terminalSessionID, !terminalSessionID.isEmpty {
            parts.append(terminalSessionID)
        }
        if let tmuxTarget, !tmuxTarget.isEmpty {
            parts.append("tmux \(tmuxTarget)")
        }
        if let paneIdentifier, !paneIdentifier.isEmpty {
            parts.append("pane \(paneIdentifier)")
        }

        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: " · ")
    }

    var canActivate: Bool {
        if let tmuxTarget, !tmuxTarget.isEmpty {
            return true
        }

        return processIdentifier != nil
            || bundleIdentifier != nil
            || !terminalApp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canReply: Bool {
        if let tmuxTarget, !tmuxTarget.isEmpty {
            return true
        }

        return terminalApp.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ghostty"
    }

    func merged(with other: CodexTerminalJumpTarget) -> CodexTerminalJumpTarget {
        CodexTerminalJumpTarget(
            sessionID: sessionID,
            transcriptPath: other.transcriptPath ?? transcriptPath,
            terminalApp: other.terminalApp.isEmpty ? terminalApp : other.terminalApp,
            workspaceName: other.workspaceName.isEmpty ? workspaceName : other.workspaceName,
            paneTitle: other.paneTitle.isEmpty ? paneTitle : other.paneTitle,
            workingDirectory: other.workingDirectory ?? workingDirectory,
            bundleIdentifier: other.bundleIdentifier ?? bundleIdentifier,
            processIdentifier: other.processIdentifier ?? processIdentifier,
            terminalSessionID: other.terminalSessionID ?? terminalSessionID,
            terminalTTY: other.terminalTTY ?? terminalTTY,
            windowIdentifier: other.windowIdentifier ?? windowIdentifier,
            tabIdentifier: other.tabIdentifier ?? tabIdentifier,
            paneIdentifier: other.paneIdentifier ?? paneIdentifier,
            tmuxTarget: other.tmuxTarget ?? tmuxTarget,
            tmuxSocketPath: other.tmuxSocketPath ?? tmuxSocketPath,
            warpPaneUUID: other.warpPaneUUID ?? warpPaneUUID
        )
    }

    private static func makeIdentifier(
        sessionID: String,
        transcriptPath: String?,
        terminalApp: String,
        workspaceName: String,
        paneTitle: String,
        workingDirectory: String?,
        bundleIdentifier: String?,
        processIdentifier: Int?,
        terminalSessionID: String?,
        terminalTTY: String?,
        windowIdentifier: String?,
        tabIdentifier: String?,
        paneIdentifier: String?,
        tmuxTarget: String?,
        warpPaneUUID: String?
    ) -> String {
        let rawComponents: [String?] = [
            sessionID,
            transcriptPath,
            terminalApp,
            workspaceName,
            paneTitle,
            workingDirectory,
            bundleIdentifier,
            processIdentifier.map(String.init),
            terminalSessionID,
            terminalTTY,
            windowIdentifier,
            tabIdentifier,
            paneIdentifier,
            tmuxTarget,
            warpPaneUUID,
        ]

        let components = rawComponents.compactMap { value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return components.isEmpty ? sessionID : components.joined(separator: "|")
    }
}

struct CodexSessionTranscriptInsights: Equatable {
    var jumpTarget: CodexTerminalJumpTarget?
    var assistantSummary: String?
    var sessionSurface: CodexSessionSurface = .unknown

    mutating func merge(_ other: CodexSessionTranscriptInsights) {
        if let otherJumpTarget = other.jumpTarget {
            jumpTarget = jumpTarget.map { $0.merged(with: otherJumpTarget) } ?? otherJumpTarget
        }

        if let otherAssistantSummary = other.assistantSummary {
            assistantSummary = otherAssistantSummary
        }

        sessionSurface = sessionSurface.merged(with: other.sessionSurface)
    }
}

struct SessionSnapshot: Identifiable, Codable {
    static let liveSessionStalenessWindow: TimeInterval = 15 * 60
    static let recentVisibilityWindow: TimeInterval = 20 * 60
    private static let internalSupportMarkers = [
        "you are a helpful assistant. you will be presented with a user prompt, and your job is to provide a short title for a task",
        "generate a concise ui title (18-36 characters) for this task.",
        "return only the title. no quotes or trailing punctuation.",
        "you are an expert at upholding safety and compliance standards for codex ambient",
        "upholding safety and compliance standards for codex ambient",
    ]

    let id: String
    var cwd: String
    var title: String
    var transcriptPath: String?
    var phase: SessionPhase
    var lastEventAt: Date?
    var currentTool: String?
    var currentCommandPreview: String?
    var latestUserPrompt: String?
    var latestAssistantMessage: String?
    var completionMessageMarkdown: String?
    var assistantSummary: String?
    var jumpTarget: CodexTerminalJumpTarget?
    var permissionRequest: CodexPermissionRequest?
    var questionPrompt: CodexQuestionPrompt?
    var pendingRequestContext: CodexPendingRequestContext?
    var sessionSurface: CodexSessionSurface
    var sourceFlags: SessionSourceFlags
    var toolTransitionTimestamps: [Date]
    var isSessionEnded: Bool

    init(
        id: String,
        cwd: String,
        title: String,
        transcriptPath: String? = nil,
        phase: SessionPhase = .completed,
        lastEventAt: Date? = nil,
        currentTool: String? = nil,
        currentCommandPreview: String? = nil,
        latestUserPrompt: String? = nil,
        latestAssistantMessage: String? = nil,
        completionMessageMarkdown: String? = nil,
        assistantSummary: String? = nil,
        jumpTarget: CodexTerminalJumpTarget? = nil,
        permissionRequest: CodexPermissionRequest? = nil,
        questionPrompt: CodexQuestionPrompt? = nil,
        pendingRequestContext: CodexPendingRequestContext? = nil,
        sessionSurface: CodexSessionSurface = .unknown,
        sourceFlags: SessionSourceFlags = [],
        toolTransitionTimestamps: [Date] = [],
        isSessionEnded: Bool = false
    ) {
        self.id = id
        self.cwd = cwd
        self.title = title
        self.transcriptPath = transcriptPath
        self.phase = phase
        self.lastEventAt = lastEventAt
        self.currentTool = currentTool
        self.currentCommandPreview = currentCommandPreview
        self.latestUserPrompt = latestUserPrompt
        self.latestAssistantMessage = latestAssistantMessage
        self.completionMessageMarkdown = completionMessageMarkdown
        self.assistantSummary = assistantSummary
        self.jumpTarget = jumpTarget
        self.permissionRequest = permissionRequest
        self.questionPrompt = questionPrompt
        self.pendingRequestContext = pendingRequestContext
        self.sessionSurface = sessionSurface
        self.sourceFlags = sourceFlags
        self.toolTransitionTimestamps = toolTransitionTimestamps
        self.isSessionEnded = isSessionEnded
    }

    static func title(for cwd: String) -> String {
        let workspace = URL(fileURLWithPath: cwd).lastPathComponent
        return workspace.isEmpty ? "Codex" : "Codex · \(workspace)"
    }

    var canJumpBack: Bool {
        jumpTarget?.canActivate == true
    }

    var canSendText: Bool {
        phase == .completed && jumpTarget?.canReply == true
    }

    var canResolvePermission: Bool {
        phase == .waitingForApproval
            && permissionRequest != nil
            && pendingRequestContext?.kind == .permission
    }

    var canAnswerQuestion: Bool {
        phase == .waitingForAnswer
            && questionPrompt != nil
            && pendingRequestContext?.kind == .question
    }

    var islandActivityDate: Date {
        lastEventAt ?? .distantPast
    }

    var isInternalSupportSession: Bool {
        let candidates = [
            latestUserPrompt,
            currentCommandPreview,
            latestAssistantMessage,
            assistantSummary,
            title,
        ]

        return candidates
            .compactMap { $0 }
            .map(Self.normalizedInspectionText)
            .contains { normalized in
                Self.internalSupportMarkers.contains { normalized.contains($0) }
            }
    }

    func isLikelyLive(at now: Date = .now) -> Bool {
        if phase.requiresAttention {
            return true
        }

        guard phase == .running || phase == .busy else {
            return false
        }

        return now.timeIntervalSince(islandActivityDate) <= Self.liveSessionStalenessWindow
    }

    func isVisibleInIsland(at now: Date = .now) -> Bool {
        if phase.requiresAttention {
            return true
        }

        if phase == .running || phase == .busy {
            return isLikelyLive(at: now)
        }

        let age = now.timeIntervalSince(islandActivityDate)
        if age <= Self.recentVisibilityWindow {
            return true
        }

        return false
    }

    mutating func merge(_ insights: CodexSessionTranscriptInsights) {
        if let jumpTarget = insights.jumpTarget {
            self.jumpTarget = self.jumpTarget.map { $0.merged(with: jumpTarget) } ?? jumpTarget
        }

        if let assistantSummary = insights.assistantSummary {
            self.assistantSummary = assistantSummary
        }

        sessionSurface = sessionSurface.merged(with: insights.sessionSurface)
    }

    nonisolated private static func normalizedInspectionText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SessionStartedEvent: Equatable, Codable {
    var sessionID: String
    var cwd: String
    var title: String
    var summary: String
    var timestamp: Date
    var jumpTarget: CodexTerminalJumpTarget?
    var transcriptPath: String?
    var sessionSurface: CodexSessionSurface
}

struct SessionActivityUpdatedEvent: Equatable, Codable {
    var sessionID: String
    var summary: String
    var phase: SessionPhase
    var timestamp: Date
}

struct PermissionRequestedEvent: Equatable, Codable {
    var sessionID: String
    var request: CodexPermissionRequest
    var requestContext: CodexPendingRequestContext? = nil
    var timestamp: Date
}

struct QuestionAskedEvent: Equatable, Codable {
    var sessionID: String
    var prompt: CodexQuestionPrompt
    var requestContext: CodexPendingRequestContext? = nil
    var timestamp: Date
}

struct SessionCompletedEvent: Equatable, Codable {
    var sessionID: String
    var summary: String
    var timestamp: Date
    var isSessionEnd: Bool
}

struct JumpTargetUpdatedEvent: Equatable, Codable {
    var sessionID: String
    var jumpTarget: CodexTerminalJumpTarget
    var timestamp: Date
}

struct SessionMetadataUpdatedEvent: Equatable, Codable {
    var sessionID: String
    var title: String?
    var assistantSummary: String?
    var currentCommandPreview: String?
    var latestUserPrompt: String? = nil
    var latestAssistantMessage: String? = nil
    var completionMessageMarkdown: String? = nil
    var transcriptPath: String?
    var timestamp: Date
}

struct ActionableStateResolvedEvent: Equatable, Codable {
    var sessionID: String
    var summary: String
    var timestamp: Date
}

enum CodexAgentEvent: Equatable, Codable {
    case sessionStarted(SessionStartedEvent)
    case activityUpdated(SessionActivityUpdatedEvent)
    case permissionRequested(PermissionRequestedEvent)
    case questionAsked(QuestionAskedEvent)
    case sessionCompleted(SessionCompletedEvent)
    case jumpTargetUpdated(JumpTargetUpdatedEvent)
    case sessionMetadataUpdated(SessionMetadataUpdatedEvent)
    case actionableStateResolved(ActionableStateResolvedEvent)
}

struct FanActivityState {
    var activityScore = 0.0
    var isSpinning = false
    var rotationPeriod = 1.6
    var activeSessionCount = 0
    var inProgressSessionCount = 0
    var busySessionCount = 0
    var lastEventAt: Date?
}

struct CodexQuotaSnapshot: Equatable {
    enum SourceKind: Equatable {
        case preferred
        case fallback
    }

    var fiveHourRemainingPercent: Int?
    var weekRemainingPercent: Int?
    var fiveHourResetAt: Date?
    var weekResetAt: Date?
    var capturedAt: Date
    var sourceKind: SourceKind

    static func fromRolloutObject(_ object: [String: Any]) -> CodexQuotaSnapshot? {
        let timestamp = parseTimestamp(object["timestamp"] as? String) ?? .now
        let payload = object["payload"] as? [String: Any]
        let rateLimits =
            (payload?["rate_limits"] as? [String: Any])
            ?? (object["rate_limits"] as? [String: Any])
            ?? ((payload?["info"] as? [String: Any])?["rate_limits"] as? [String: Any])

        guard let rateLimits else {
            return nil
        }

        let sourceKind = preferredSourceKind(for: rateLimits["limit_id"])
        let fiveHour = parseWindow(rateLimits["primary"] as? [String: Any])
        let week = parseWindow(rateLimits["secondary"] as? [String: Any])
        guard fiveHour.remainingPercent != nil || week.remainingPercent != nil else {
            return nil
        }

        return CodexQuotaSnapshot(
            fiveHourRemainingPercent: fiveHour.remainingPercent,
            weekRemainingPercent: week.remainingPercent,
            fiveHourResetAt: fiveHour.resetAt,
            weekResetAt: week.resetAt,
            capturedAt: timestamp,
            sourceKind: sourceKind
        )
    }

    private static func preferredSourceKind(for value: Any?) -> SourceKind {
        guard let normalizedLimitID = normalizeLimitID(value) else {
            return .preferred
        }

        return normalizedLimitID == "codex" ? .preferred : .fallback
    }

    private static func normalizeLimitID(_ value: Any?) -> String? {
        guard let value else {
            return nil
        }

        let raw: String?
        switch value {
        case let value as String:
            raw = value
        case let value as NSNumber:
            raw = value.stringValue
        default:
            raw = nil
        }

        guard let raw else {
            return nil
        }

        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func parseWindow(_ dictionary: [String: Any]?) -> (remainingPercent: Int?, resetAt: Date?) {
        guard let dictionary else {
            return (nil, nil)
        }

        let remainingPercent: Int?
        if let value = dictionary["remaining_percent"] {
            remainingPercent = boundedPercentage(intValue(from: value))
        } else if let value = dictionary["pct_left"] {
            remainingPercent = boundedPercentage(intValue(from: value))
        } else if let value = dictionary["pct_remaining"] {
            remainingPercent = boundedPercentage(intValue(from: value))
        } else if let value = dictionary["used_percent"] {
            remainingPercent = boundedPercentage(intValue(from: value).map { 100 - $0 })
        } else {
            remainingPercent = nil
        }

        let resetAt =
            parseFlexibleDate(dictionary["resets_at"])
            ?? parseFlexibleDate(dictionary["reset_at"])
            ?? parseFlexibleDate(dictionary["resets_at_ms"])
            ?? parseFlexibleDate(dictionary["reset_at_ms"])

        return (remainingPercent, resetAt)
    }

    private static func boundedPercentage(_ value: Int?) -> Int? {
        guard let value else {
            return nil
        }

        return max(0, min(100, value))
    }
}

struct CodexMonitoringSnapshot {
    var sessions: [SessionSnapshot]
    var quotaSnapshot: CodexQuotaSnapshot?

    static let empty = CodexMonitoringSnapshot(sessions: [], quotaSnapshot: nil)
}

enum CodexProcessMonitor {
    static func isCodexRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == "com.openai.codex"
        }
    }
}
