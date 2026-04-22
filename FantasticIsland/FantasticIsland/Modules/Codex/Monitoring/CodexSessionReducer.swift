import Foundation

final class CodexSessionReducer {
    private static let fallbackSessionCWD = FileManager.default.homeDirectoryForCurrentUser.path

    private(set) var sessions: [String: SessionSnapshot] = [:]
    private(set) var latestQuotaSnapshot: CodexQuotaSnapshot?
    private let terminalDiscovery = CodexTerminalDiscovery()

    private var unknownSessionCWD: String {
        Self.fallbackSessionCWD
    }

    var allSessions: [SessionSnapshot] {
        sessions.values.sorted {
            ($0.lastEventAt ?? .distantPast) > ($1.lastEventAt ?? .distantPast)
        }
    }

    func upsertDiscoveredSession(_ session: DiscoveredSession) {
        var snapshot = sessions[session.id] ?? SessionSnapshot(
            id: session.id,
            cwd: session.cwd,
            title: session.title,
            transcriptPath: session.transcriptPath
        )

        snapshot.cwd = session.cwd
        snapshot.title = session.title
        snapshot.transcriptPath = session.transcriptPath
        snapshot.sourceFlags.insert(.rollout)
        snapshot.sessionSurface = snapshot.sessionSurface.merged(with: session.sessionSurface)
        if let jumpTarget = session.jumpTarget {
            snapshot.jumpTarget = snapshot.jumpTarget.map { $0.merged(with: jumpTarget) } ?? jumpTarget
        }
        if let assistantSummary = session.assistantSummary {
            snapshot.assistantSummary = assistantSummary
        }
        sessions[session.id] = snapshot
    }

    func applyRolloutLine(_ line: String, for session: DiscoveredSession) {
        upsertDiscoveredSession(session)
        guard let object = jsonObject(for: line) else {
            return
        }

        if let quotaSnapshot = CodexQuotaSnapshot.fromRolloutObject(object) {
            applyQuotaSnapshot(quotaSnapshot)
        }

        let timestamp = parseTimestamp(object["timestamp"] as? String) ?? .now
        guard var snapshot = sessions[session.id] else {
            return
        }
        let previousPhase = snapshot.phase
        let previousLastEventAt = snapshot.lastEventAt

        snapshot.merge(terminalDiscovery.inspect(object: object, sessionID: snapshot.id, cwd: snapshot.cwd, transcriptPath: snapshot.transcriptPath))

        switch object["type"] as? String {
        case "event_msg":
            applyEventMessage(object["payload"] as? [String: Any] ?? [:], timestamp: timestamp, snapshot: &snapshot)
        case "response_item":
            applyResponseItem(object["payload"] as? [String: Any] ?? [:], timestamp: timestamp, snapshot: &snapshot)
        default:
            break
        }

        snapshot.toolTransitionTimestamps = snapshot.toolTransitionTimestamps.filter {
            timestamp.timeIntervalSince($0) <= 3
        }

        if previousPhase == .completed,
           (snapshot.phase == .running || snapshot.phase == .busy),
           let previousLastEventAt,
           timestamp <= previousLastEventAt {
            snapshot.phase = .completed
            snapshot.currentTool = nil
            snapshot.currentCommandPreview = nil
        }
        sessions[session.id] = snapshot
    }

    func applyQuotaSnapshot(_ snapshot: CodexQuotaSnapshot) {
        guard let latestQuotaSnapshot else {
            self.latestQuotaSnapshot = snapshot
            return
        }

        if snapshot.sourceKind == .preferred, latestQuotaSnapshot.sourceKind != .preferred {
            self.latestQuotaSnapshot = snapshot
            return
        }

        if snapshot.sourceKind != .preferred, latestQuotaSnapshot.sourceKind == .preferred {
            return
        }

        if snapshot.capturedAt >= latestQuotaSnapshot.capturedAt {
            self.latestQuotaSnapshot = snapshot
        }
    }

    func applyHookPayload(_ payload: CodexHookPayload) {
        let now = Date()
        let workspaceName = URL(fileURLWithPath: payload.cwd).lastPathComponent
        let title = workspaceName.isEmpty ? "Codex" : "Codex · \(workspaceName)"
        let jumpTarget = payload.terminalJumpTarget
        let startEvent = SessionStartedEvent(
            sessionID: payload.sessionID,
            cwd: payload.cwd,
            title: title,
            summary: payload.assistantSummary ?? payload.prompt ?? "Codex session.",
            timestamp: now,
            jumpTarget: jumpTarget,
            transcriptPath: payload.transcriptPath,
            sessionSurface: payload.sessionSurface
        )

        if sessions[payload.sessionID] == nil {
            apply(.sessionStarted(startEvent))
        } else if let jumpTarget {
            apply(.jumpTargetUpdated(JumpTargetUpdatedEvent(sessionID: payload.sessionID, jumpTarget: jumpTarget, timestamp: now)))
        }

        if payload.assistantSummary != nil || payload.prompt != nil || payload.transcriptPath != nil {
            apply(.sessionMetadataUpdated(
                SessionMetadataUpdatedEvent(
                    sessionID: payload.sessionID,
                    title: nil,
                    assistantSummary: payload.assistantSummary,
                    currentCommandPreview: clipped(payload.prompt, limit: 160),
                    latestUserPrompt: payload.prompt,
                    latestAssistantMessage: payload.assistantSummary,
                    completionMessageMarkdown: payload.assistantSummary,
                    transcriptPath: payload.transcriptPath,
                    timestamp: now
                )
            ))
        }

        switch payload.hookEventName {
        case .sessionStart:
            apply(.activityUpdated(
                SessionActivityUpdatedEvent(
                    sessionID: payload.sessionID,
                    summary: payload.assistantSummary ?? "Codex session started.",
                    phase: .running,
                    timestamp: now
                )
            ))
        case .userPromptSubmit:
            apply(.activityUpdated(
                SessionActivityUpdatedEvent(
                    sessionID: payload.sessionID,
                    summary: payload.prompt ?? "Prompt submitted.",
                    phase: .running,
                    timestamp: now
                )
            ))
        case .preToolUse:
            let toolName = payload.toolName ?? "Tool"
            let summary = payload.toolInput?.command ?? payload.prompt ?? "\(toolName) is running."
            apply(.activityUpdated(
                SessionActivityUpdatedEvent(
                    sessionID: payload.sessionID,
                    summary: summary,
                    phase: .busy,
                    timestamp: now
                )
            ))
        case .postToolUse:
            let summary = payload.assistantSummary ?? "\(payload.toolName ?? "Tool") completed."
            apply(.activityUpdated(
                SessionActivityUpdatedEvent(
                    sessionID: payload.sessionID,
                    summary: summary,
                    phase: .running,
                    timestamp: now
                )
            ))
        case .stop:
            apply(.sessionCompleted(
                SessionCompletedEvent(
                    sessionID: payload.sessionID,
                    summary: payload.assistantSummary ?? "Turn completed.",
                    timestamp: now,
                    isSessionEnd: false
                )
            ))
        }
    }

    func apply(_ event: CodexAgentEvent) {
        switch event {
        case let .sessionStarted(payload):
            var session = sessions[payload.sessionID] ?? SessionSnapshot(
                id: payload.sessionID,
                cwd: payload.cwd,
                title: payload.title,
                transcriptPath: payload.transcriptPath,
                phase: .completed
            )
            session.cwd = payload.cwd
            session.title = payload.title
            session.transcriptPath = payload.transcriptPath ?? session.transcriptPath
            session.sessionSurface = session.sessionSurface.merged(with: payload.sessionSurface)
            session.lastEventAt = payload.timestamp
            session.assistantSummary = clipped(payload.summary, limit: 160)
            session.phase = .running
            session.isSessionEnded = false
            session.pendingRequestContext = nil
            if let jumpTarget = payload.jumpTarget {
                session.jumpTarget = session.jumpTarget.map { $0.merged(with: jumpTarget) } ?? jumpTarget
            }
            sessions[payload.sessionID] = session

        case let .activityUpdated(payload):
            guard var session = sessions[payload.sessionID] else {
                return
            }
            if payload.phase == .running,
               session.phase == .completed,
               let lastEventAt = session.lastEventAt,
               payload.timestamp <= lastEventAt {
                return
            }
            let shouldClearAttentionForActivityUpdate =
                session.phase.requiresAttention
                && payload.phase == .running
                && session.pendingRequestContext?.source != .hook

            if shouldClearAttentionForActivityUpdate || !(payload.phase == .running && session.phase.requiresAttention) {
                session.phase = payload.phase
                if payload.phase != .waitingForApproval {
                    session.permissionRequest = nil
                }
                if payload.phase != .waitingForAnswer {
                    session.questionPrompt = nil
                }
                if payload.phase != .waitingForApproval && payload.phase != .waitingForAnswer {
                    session.pendingRequestContext = nil
                }
            }
            session.currentTool = payload.phase == .busy ? session.currentTool : nil
            session.assistantSummary = clipped(payload.summary, limit: 160) ?? session.assistantSummary
            session.lastEventAt = payload.timestamp
            sessions[payload.sessionID] = session

        case let .permissionRequested(payload):
            var session = sessions[payload.sessionID] ?? SessionSnapshot(
                id: payload.sessionID,
                cwd: unknownSessionCWD,
                title: SessionSnapshot.title(for: unknownSessionCWD),
                phase: .running
            )
            session.phase = .waitingForApproval
            session.permissionRequest = payload.request
            session.questionPrompt = nil
            session.pendingRequestContext = payload.requestContext
            session.assistantSummary = clipped(payload.request.summary, limit: 160)
            session.currentCommandPreview = clipped(payload.request.summary, limit: 160)
            session.lastEventAt = payload.timestamp
            sessions[payload.sessionID] = session

        case let .questionAsked(payload):
            var session = sessions[payload.sessionID] ?? SessionSnapshot(
                id: payload.sessionID,
                cwd: unknownSessionCWD,
                title: SessionSnapshot.title(for: unknownSessionCWD),
                phase: .running
            )
            session.phase = .waitingForAnswer
            session.questionPrompt = payload.prompt
            session.permissionRequest = nil
            session.pendingRequestContext = payload.requestContext
            session.assistantSummary = clipped(payload.prompt.title, limit: 160)
            session.lastEventAt = payload.timestamp
            sessions[payload.sessionID] = session

        case let .sessionCompleted(payload):
            guard var session = sessions[payload.sessionID] else {
                return
            }
            session.phase = .completed
            session.currentTool = nil
            session.currentCommandPreview = nil
            session.permissionRequest = nil
            session.questionPrompt = nil
            session.pendingRequestContext = nil
            session.assistantSummary = clipped(payload.summary, limit: 160) ?? session.assistantSummary
            session.lastEventAt = payload.timestamp
            session.isSessionEnded = payload.isSessionEnd
            sessions[payload.sessionID] = session

        case let .jumpTargetUpdated(payload):
            guard var session = sessions[payload.sessionID] else {
                return
            }
            session.jumpTarget = session.jumpTarget.map { $0.merged(with: payload.jumpTarget) } ?? payload.jumpTarget
            session.sessionSurface = session.sessionSurface.merged(with: payload.jumpTarget.terminalApp == "Codex.app" ? .codexApp : .terminal)
            session.lastEventAt = payload.timestamp
            sessions[payload.sessionID] = session

        case let .sessionMetadataUpdated(payload):
            guard var session = sessions[payload.sessionID] else {
                return
            }
            if let title = clipped(payload.title, limit: 120) {
                session.title = title
            }
            if let assistantSummary = payload.assistantSummary {
                session.assistantSummary = clipped(assistantSummary, limit: 160)
            }
            if let currentCommandPreview = payload.currentCommandPreview {
                session.currentCommandPreview = clipped(currentCommandPreview, limit: 160)
            }
            if let latestUserPrompt = payload.latestUserPrompt {
                session.latestUserPrompt = clipped(latestUserPrompt, limit: 320)
            }
            if let latestAssistantMessage = payload.latestAssistantMessage {
                session.latestAssistantMessage = clipped(latestAssistantMessage, limit: 640)
            }
            if let completionMessageMarkdown = payload.completionMessageMarkdown {
                session.completionMessageMarkdown = completionMessageMarkdown
            }
            session.transcriptPath = payload.transcriptPath ?? session.transcriptPath
            session.lastEventAt = payload.timestamp
            sessions[payload.sessionID] = session

        case let .actionableStateResolved(payload):
            guard var session = sessions[payload.sessionID] else {
                return
            }
            session.phase = .running
            session.permissionRequest = nil
            session.questionPrompt = nil
            session.pendingRequestContext = nil
            session.assistantSummary = clipped(payload.summary, limit: 160)
            session.lastEventAt = payload.timestamp
            sessions[payload.sessionID] = session
        }
    }

    private func applyEventMessage(_ payload: [String: Any], timestamp: Date, snapshot: inout SessionSnapshot) {
        let source = payload
        switch payload["type"] as? String {
        case "task_started", "user_message":
            if !snapshot.phase.requiresAttention {
                snapshot.phase = .running
                snapshot.currentTool = nil
                snapshot.permissionRequest = nil
                snapshot.questionPrompt = nil
                snapshot.pendingRequestContext = nil
            }
            if let text = joinedTextRaw(from: source["content"]) ?? joinedTextRaw(from: source["text"]) ?? joinedTextRaw(from: source["message"]) {
                snapshot.latestUserPrompt = clipped(text, limit: 320)
                snapshot.currentCommandPreview = clipped(text, limit: 160)
            }
            snapshot.lastEventAt = timestamp
        case "agent_message":
            if snapshot.phase != .completed, !snapshot.phase.requiresAttention {
                snapshot.phase = .running
            }
            if let text = joinedTextRaw(from: source["content"]) ?? joinedTextRaw(from: source["text"]) ?? joinedTextRaw(from: source["message"]) {
                snapshot.latestAssistantMessage = clipped(text, limit: 640)
                snapshot.completionMessageMarkdown = cappedMarkdownMessage(text)
                snapshot.assistantSummary = clipped(text, limit: 160)
            }
            snapshot.lastEventAt = timestamp
        case "task_complete", "turn_aborted":
            snapshot.phase = .completed
            snapshot.currentTool = nil
            snapshot.currentCommandPreview = nil
            snapshot.permissionRequest = nil
            snapshot.questionPrompt = nil
            snapshot.pendingRequestContext = nil
            snapshot.lastEventAt = timestamp
        default:
            break
        }
    }

    private func applyResponseItem(_ payload: [String: Any], timestamp: Date, snapshot: inout SessionSnapshot) {
        guard let itemType = payload["type"] as? String else {
            return
        }

        if itemType == "message",
           let role = payload["role"] as? String {
            switch role {
            case "user":
                if !snapshot.phase.requiresAttention {
                    snapshot.phase = .running
                    snapshot.currentTool = nil
                    snapshot.pendingRequestContext = nil
                }
                if let text = joinedTextRaw(from: payload["content"]) ?? joinedTextRaw(from: payload["text"]) ?? joinedTextRaw(from: payload["message"]) {
                    snapshot.latestUserPrompt = clipped(text, limit: 320)
                    snapshot.currentCommandPreview = clipped(text, limit: 160)
                }
                snapshot.lastEventAt = timestamp
            case "assistant":
                if snapshot.phase != .completed, !snapshot.phase.requiresAttention {
                    snapshot.phase = .running
                }
                if let text = joinedTextRaw(from: payload["content"]) ?? joinedTextRaw(from: payload["text"]) ?? joinedTextRaw(from: payload["message"]) {
                    snapshot.latestAssistantMessage = clipped(text, limit: 640)
                    snapshot.completionMessageMarkdown = cappedMarkdownMessage(text)
                    snapshot.assistantSummary = clipped(text, limit: 160)
                }
                snapshot.lastEventAt = timestamp
            default:
                break
            }
            return
        }

        guard itemType == "function_call" || itemType == "custom_tool_call",
              let toolName = payload["name"] as? String else {
            return
        }

        if toolName == "request_user_input" {
            snapshot.phase = .waitingForAnswer
            snapshot.currentTool = toolName
            snapshot.permissionRequest = nil
            snapshot.questionPrompt = requestUserInputPrompt(from: payload["arguments"] as? String)
                ?? snapshot.questionPrompt
                ?? CodexQuestionPrompt(title: "Codex is waiting for input.")
            snapshot.currentCommandPreview = clipped(
                snapshot.questionPrompt?.title ?? commandPreview(toolName: toolName, payload: payload),
                limit: 160
            )
            snapshot.assistantSummary = clipped(
                snapshot.questionPrompt?.title ?? snapshot.assistantSummary,
                limit: 160
            )
            snapshot.lastEventAt = timestamp
            snapshot.toolTransitionTimestamps.append(timestamp)
            return
        }

        if !snapshot.phase.requiresAttention {
            snapshot.phase = .busy
            snapshot.currentTool = toolName
            snapshot.currentCommandPreview = commandPreview(toolName: toolName, payload: payload)
        }
        if let assistantText = joinedTextRaw(from: payload["output"]) ?? joinedTextRaw(from: payload["content"]) ?? joinedTextRaw(from: payload["message"]) {
            snapshot.latestAssistantMessage = clipped(assistantText, limit: 640)
            snapshot.assistantSummary = clipped(assistantText, limit: 160)
        }
        snapshot.lastEventAt = timestamp
        snapshot.toolTransitionTimestamps.append(timestamp)
    }

    private func commandPreview(toolName: String, payload: [String: Any]) -> String? {
        guard let arguments = payload["arguments"] as? String,
              let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        switch toolName {
        case "exec_command":
            return clipped(object["cmd"] as? String)
        case "write_stdin":
            return clipped(object["chars"] as? String)
        default:
            return nil
        }
    }

    private func requestUserInputPrompt(from arguments: String?) -> CodexQuestionPrompt? {
        guard let arguments,
              let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawQuestions = object["questions"] as? [[String: Any]],
              !rawQuestions.isEmpty else {
            return nil
        }

        let questions = rawQuestions.compactMap { question -> CodexQuestionItem? in
            guard let id = question["id"] as? String,
                  let header = question["header"] as? String,
                  let prompt = question["question"] as? String else {
                return nil
            }

            let options = (question["options"] as? [[String: Any]] ?? []).compactMap { option -> CodexQuestionOption? in
                guard let label = option["label"] as? String else {
                    return nil
                }
                return CodexQuestionOption(
                    label: label,
                    description: option["description"] as? String ?? ""
                )
            }

            return CodexQuestionItem(
                id: id,
                header: header,
                question: prompt,
                options: options,
                allowsCustomAnswer: question["isOther"] as? Bool ?? false,
                isSecret: question["isSecret"] as? Bool ?? false,
                multiSelect: false
            )
        }

        guard !questions.isEmpty else {
            return nil
        }

        let title = clipped(questions.first?.question, limit: 260) ?? "Codex is waiting for input."
        let options = questions.first?.options.map(\.label) ?? []
        return CodexQuestionPrompt(title: title, options: options, questions: questions)
    }

    private func cappedMarkdownMessage(_ message: String, cap: Int = 8_000) -> String {
        guard message.count > cap else {
            return message
        }

        let endIndex = message.index(message.startIndex, offsetBy: cap)
        return "\(message[..<endIndex])…"
    }
}
