import Foundation

@MainActor
final class CodexAppServerCoordinator {
    private enum PendingPayload {
        case permissions(CodexAppServerPermissionsRequestApprovalParams)
        case command(CodexAppServerCommandExecutionRequestApprovalParams)
        case fileChange(CodexAppServerFileChangeRequestApprovalParams)
        case question(CodexAppServerToolRequestUserInputParams)
    }

    private struct PendingRequest {
        var id: CodexAppServerRequestID
        var sessionID: String
        var kind: CodexPendingRequestKind
        var method: String
        var itemID: String?
        var turnID: String?
        var payload: PendingPayload
        var createdAt: Date
    }

    private var client: CodexAppServerClient?
    private var connectTask: Task<Void, Never>?
    private var knownThreads: [String: CodexThread] = [:]
    private var pendingRequestsByID: [String: PendingRequest] = [:]
    private var pendingRequestIDBySession: [String: String] = [:]
    private let codexPath: String

    var onEvent: ((CodexAgentEvent) -> Void)?
    var onStatusMessage: ((String) -> Void)?

    private(set) var isConnected = false

    init(codexPath: String = "/Applications/Codex.app/Contents/Resources/codex") {
        self.codexPath = codexPath
    }

    func ensureConnected() {
        guard !isConnected, connectTask == nil else {
            return
        }

        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            return
        }

        connectTask = Task { [weak self] in
            guard let self else {
                return
            }

            defer {
                self.connectTask = nil
            }

            do {
                let client = CodexAppServerClient(codexPath: codexPath)
                client.onNotification = { [weak self] notification in
                    Task { @MainActor [weak self] in
                        self?.handleNotification(notification)
                    }
                }
                client.onServerRequest = { [weak self] request in
                    Task { @MainActor [weak self] in
                        self?.handleServerRequest(request)
                    }
                }
                client.onDisconnect = { [weak self] reason in
                    Task { @MainActor [weak self] in
                        self?.handleClientDisconnect(reason)
                    }
                }
                try await client.start()

                guard !Task.isCancelled else {
                    client.stop()
                    return
                }

                self.client = client
                self.isConnected = true
                self.onStatusMessage?("Connected")
                await self.syncLoadedThreads()
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self.resetConnectionState(statusMessage: "Unavailable")
            }
        }
    }

    func disconnect() {
        connectTask?.cancel()
        client?.stop()
        resetConnectionState(statusMessage: "Disconnected")
    }

    func resolvePermission(
        requestContext: CodexPendingRequestContext,
        action: CodexApprovalAction
    ) async -> Bool {
        guard let pending = pendingRequestsByID[requestContext.requestID],
              pending.kind == .permission,
              let client else {
            return false
        }

        do {
            let payload = permissionResolutionPayload(for: pending, action: action)
            try client.sendServerRequestResolved(requestID: pending.id, result: payload)
            clearPendingRequest(requestID: requestContext.requestID)
            onEvent?(.actionableStateResolved(
                ActionableStateResolvedEvent(
                    sessionID: pending.sessionID,
                    summary: action.isApproved ? "Approval sent." : "Denied.",
                    timestamp: .now
                )
            ))
            return true
        } catch {
            onStatusMessage?("Connected · resolve failed")
            return false
        }
    }

    func resolveQuestion(
        requestContext: CodexPendingRequestContext,
        response: CodexQuestionResponse
    ) async -> Bool {
        guard let pending = pendingRequestsByID[requestContext.requestID],
              pending.kind == .question,
              case let .question(params) = pending.payload,
              let client else {
            return false
        }

        var answerMap: [String: Any] = [:]

        for (questionID, values) in response.answers where !values.isEmpty {
            answerMap[questionID] = ["answers": values]
        }

        if answerMap.isEmpty,
           let firstQuestionID = params.questions.first?.id,
           let rawAnswer = response.rawAnswer?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawAnswer.isEmpty {
            answerMap[firstQuestionID] = ["answers": [rawAnswer]]
        }

        guard !answerMap.isEmpty else {
            return false
        }

        do {
            try client.sendServerRequestResolved(
                requestID: pending.id,
                result: [
                    "answers": answerMap,
                ]
            )
            clearPendingRequest(requestID: requestContext.requestID)
            onEvent?(.actionableStateResolved(
                ActionableStateResolvedEvent(
                    sessionID: pending.sessionID,
                    summary: "Answer sent.",
                    timestamp: .now
                )
            ))
            return true
        } catch {
            onStatusMessage?("Connected · resolve failed")
            return false
        }
    }

    private func syncLoadedThreads() async {
        guard let client else {
            return
        }

        do {
            let threads = try await client.listLoadedThreads()
            for thread in threads where !thread.ephemeral {
                knownThreads[thread.id] = thread
                emitSessionStarted(from: thread)
            }
            if isConnected, !threads.isEmpty {
                onStatusMessage?("Connected · \(threads.count) threads")
            }
        } catch {
            if isConnected {
                onStatusMessage?("Connected")
            }
        }
    }

    private func handleClientDisconnect(_ reason: CodexAppServerDisconnectReason) {
        let statusMessage: String
        switch reason {
        case .initializeFailed:
            statusMessage = "Unavailable"
        case .stdoutEOF, .processTerminated, .stopped:
            statusMessage = "Disconnected"
        }

        resetConnectionState(statusMessage: statusMessage)
    }

    private func resetConnectionState(statusMessage: String?) {
        client = nil
        connectTask = nil
        knownThreads.removeAll()
        pendingRequestsByID.removeAll()
        pendingRequestIDBySession.removeAll()
        isConnected = false

        if let statusMessage {
            onStatusMessage?(statusMessage)
        }
    }

    private func handleServerRequest(_ request: CodexAppServerServerRequest) {
        switch request {
        case let .permissionsApproval(id, params):
            let summary = params.reason ?? permissionSummary(for: params.permissions)
            let affectedPath = params.permissions.fileSystem?.write?.first
                ?? params.permissions.fileSystem?.read?.first
                ?? ""

            let pending = PendingRequest(
                id: id,
                sessionID: params.threadId,
                kind: .permission,
                method: "item/permissions/requestApproval",
                itemID: params.itemId,
                turnID: params.turnId,
                payload: .permissions(params),
                createdAt: .now
            )
            registerPendingRequest(pending)
            onEvent?(.permissionRequested(
                PermissionRequestedEvent(
                    sessionID: params.threadId,
                    request: CodexPermissionRequest(
                        title: "Approval Required",
                        summary: clipped(summary, limit: 260) ?? "Codex requests additional permissions.",
                        affectedPath: affectedPath,
                        alwaysActionTitle: "Always"
                    ),
                    requestContext: requestContext(for: pending),
                    timestamp: .now
                )
            ))

        case let .commandExecutionApproval(id, params):
            let summary = params.command ?? params.reason ?? "Codex requests command approval."
            let pending = PendingRequest(
                id: id,
                sessionID: params.threadId,
                kind: .permission,
                method: "item/commandExecution/requestApproval",
                itemID: params.itemId,
                turnID: params.turnId,
                payload: .command(params),
                createdAt: .now
            )
            registerPendingRequest(pending)

            onEvent?(.sessionMetadataUpdated(
                SessionMetadataUpdatedEvent(
                    sessionID: params.threadId,
                    title: nil,
                    assistantSummary: nil,
                    currentCommandPreview: params.command,
                    latestUserPrompt: nil,
                    latestAssistantMessage: nil,
                    completionMessageMarkdown: nil,
                    transcriptPath: nil,
                    timestamp: .now
                )
            ))
            onEvent?(.permissionRequested(
                PermissionRequestedEvent(
                    sessionID: params.threadId,
                    request: CodexPermissionRequest(
                        title: "Approval Required",
                        summary: clipped(summary, limit: 260) ?? "Codex requests command approval.",
                        affectedPath: params.cwd ?? "",
                        alwaysActionTitle: "Always",
                        toolName: "exec_command"
                    ),
                    requestContext: requestContext(for: pending),
                    timestamp: .now
                )
            ))

        case let .fileChangeApproval(id, params):
            let summary = params.reason ?? "Codex wants to apply file changes."
            let pending = PendingRequest(
                id: id,
                sessionID: params.threadId,
                kind: .permission,
                method: "item/fileChange/requestApproval",
                itemID: params.itemId,
                turnID: params.turnId,
                payload: .fileChange(params),
                createdAt: .now
            )
            registerPendingRequest(pending)
            onEvent?(.permissionRequested(
                PermissionRequestedEvent(
                    sessionID: params.threadId,
                    request: CodexPermissionRequest(
                        title: "Approval Required",
                        summary: clipped(summary, limit: 260) ?? "Codex requests file change approval.",
                        affectedPath: params.grantRoot ?? "",
                        alwaysActionTitle: "Always",
                        toolName: "apply_patch"
                    ),
                    requestContext: requestContext(for: pending),
                    timestamp: .now
                )
            ))

        case let .toolRequestUserInput(id, params):
            let questionItems = params.questions.map { question in
                CodexQuestionItem(
                    id: question.id,
                    header: question.header,
                    question: question.question,
                    options: (question.options ?? []).map {
                        CodexQuestionOption(label: $0.label, description: $0.description)
                    },
                    allowsCustomAnswer: question.isOther ?? false,
                    isSecret: question.isSecret ?? false,
                    multiSelect: false
                )
            }
            let title = questionItems.first?.question ?? "Codex needs input."
            let options = questionItems.first?.options.map(\.label) ?? []

            let pending = PendingRequest(
                id: id,
                sessionID: params.threadId,
                kind: .question,
                method: "item/tool/requestUserInput",
                itemID: params.itemId,
                turnID: params.turnId,
                payload: .question(params),
                createdAt: .now
            )
            registerPendingRequest(pending)
            onEvent?(.questionAsked(
                QuestionAskedEvent(
                    sessionID: params.threadId,
                    prompt: CodexQuestionPrompt(
                        title: clipped(title, limit: 260) ?? "Codex needs input.",
                        options: options,
                        questions: questionItems
                    ),
                    requestContext: requestContext(for: pending),
                    timestamp: .now
                )
            ))

        case .unknown:
            break
        }
    }

    private func handleNotification(_ notification: CodexAppServerNotification) {
        switch notification {
        case let .threadStarted(thread):
            guard !thread.ephemeral else {
                return
            }
            knownThreads[thread.id] = thread
            emitSessionStarted(from: thread)

        case let .threadStatusChanged(threadID, status):
            if var thread = knownThreads[threadID] {
                thread = CodexThread(
                    id: thread.id,
                    cwd: thread.cwd,
                    name: thread.name,
                    preview: thread.preview,
                    modelProvider: thread.modelProvider,
                    createdAt: thread.createdAt,
                    updatedAt: thread.updatedAt,
                    ephemeral: thread.ephemeral,
                    path: thread.path,
                    status: status,
                    source: thread.source,
                    turns: thread.turns
                )
                knownThreads[threadID] = thread
            }

            switch status.type {
            case .active:
                if status.isWaitingOnApproval {
                    if pendingRequest(for: threadID, kind: .permission) == nil {
                        onEvent?(.permissionRequested(
                            PermissionRequestedEvent(
                                sessionID: threadID,
                                request: CodexPermissionRequest(
                                    title: "Approval Required",
                                    summary: "Codex is waiting for approval."
                                ),
                                requestContext: nil,
                                timestamp: .now
                            )
                        ))
                    }
                } else if status.isWaitingOnUserInput {
                    if pendingRequest(for: threadID, kind: .question) == nil {
                        onEvent?(.questionAsked(
                            QuestionAskedEvent(
                                sessionID: threadID,
                                prompt: CodexQuestionPrompt(title: "Codex is waiting for input."),
                                requestContext: nil,
                                timestamp: .now
                            )
                        ))
                    }
                } else {
                    onEvent?(.activityUpdated(
                        SessionActivityUpdatedEvent(
                            sessionID: threadID,
                            summary: "Codex is working…",
                            phase: .running,
                            timestamp: .now
                        )
                    ))
                }
            case .idle:
                onEvent?(.sessionCompleted(
                    SessionCompletedEvent(
                        sessionID: threadID,
                        summary: "Codex is idle.",
                        timestamp: .now,
                        isSessionEnd: false
                    )
                ))
            case .notLoaded, .systemError:
                break
            }

        case let .threadClosed(threadID):
            knownThreads[threadID] = nil
            clearPendingRequests(for: threadID)
            onEvent?(.sessionCompleted(
                SessionCompletedEvent(
                    sessionID: threadID,
                    summary: "Codex thread closed.",
                    timestamp: .now,
                    isSessionEnd: true
                )
            ))

        case let .threadNameUpdated(threadID, name):
            guard let name, !name.isEmpty else {
                return
            }
            onEvent?(.sessionMetadataUpdated(
                SessionMetadataUpdatedEvent(
                    sessionID: threadID,
                    title: name,
                    assistantSummary: nil,
                    currentCommandPreview: nil,
                    latestUserPrompt: nil,
                    latestAssistantMessage: nil,
                    completionMessageMarkdown: nil,
                    transcriptPath: nil,
                    timestamp: .now
                )
            ))

        case let .turnStarted(threadID, _):
            onEvent?(.activityUpdated(
                SessionActivityUpdatedEvent(
                    sessionID: threadID,
                    summary: "Codex is working…",
                    phase: .running,
                    timestamp: .now
                )
            ))

        case let .turnCompleted(threadID, turn):
            let summary: String
            switch turn.status {
            case .completed:
                summary = "Turn completed."
            case .interrupted:
                summary = "Turn interrupted."
            case .failed:
                summary = "Turn failed."
            case .inProgress:
                summary = "Turn in progress."
            }
            onEvent?(.sessionCompleted(
                SessionCompletedEvent(
                    sessionID: threadID,
                    summary: summary,
                    timestamp: .now,
                    isSessionEnd: false
                )
            ))

        case let .serverRequestResolved(threadID, requestID):
            if let pending = clearPendingRequest(requestID: requestID.rawValue) {
                onEvent?(.actionableStateResolved(
                    ActionableStateResolvedEvent(
                        sessionID: pending.sessionID,
                        summary: pending.kind == .permission ? "Approval resolved." : "Answer resolved.",
                        timestamp: .now
                    )
                ))
            } else {
                onEvent?(.actionableStateResolved(
                    ActionableStateResolvedEvent(
                        sessionID: threadID,
                        summary: "Action resolved.",
                        timestamp: .now
                    )
                ))
            }

        case .unknown:
            break
        }
    }

    private func pendingRequest(for sessionID: String, kind: CodexPendingRequestKind) -> PendingRequest? {
        guard let requestID = pendingRequestIDBySession[sessionID],
              let pending = pendingRequestsByID[requestID],
              pending.kind == kind else {
            return nil
        }
        return pending
    }

    private func permissionResolutionPayload(for pending: PendingRequest, action: CodexApprovalAction) -> [String: Any] {
        switch pending.payload {
        case let .permissions(params):
            let permissions: [String: Any]
            if action.isApproved {
                permissions = permissionProfilePayload(params.permissions)
            } else {
                permissions = [:]
            }
            return [
                "permissions": permissions,
                "scope": action == .allowAlways ? "session" : "turn",
            ]

        case .command:
            let decision: String
            switch action {
            case .deny:
                decision = "decline"
            case .allowOnce:
                decision = "accept"
            case .allowAlways:
                decision = "acceptForSession"
            }
            return ["decision": decision]

        case .fileChange:
            let decision: String
            switch action {
            case .deny:
                decision = "decline"
            case .allowOnce:
                decision = "accept"
            case .allowAlways:
                decision = "acceptForSession"
            }
            return ["decision": decision]

        case .question:
            return [:]
        }
    }

    private func permissionProfilePayload(_ profile: CodexAppServerPermissionProfile) -> [String: Any] {
        var payload: [String: Any] = [:]

        if let fileSystem = profile.fileSystem {
            var fileSystemPayload: [String: Any] = [:]
            if let read = fileSystem.read {
                fileSystemPayload["read"] = read
            }
            if let write = fileSystem.write {
                fileSystemPayload["write"] = write
            }
            if !fileSystemPayload.isEmpty {
                payload["fileSystem"] = fileSystemPayload
            }
        }

        if let network = profile.network,
           let enabled = network.enabled {
            payload["network"] = ["enabled": enabled]
        }

        return payload
    }

    private func permissionSummary(for profile: CodexAppServerPermissionProfile) -> String {
        var fragments: [String] = []

        if let writePaths = profile.fileSystem?.write, !writePaths.isEmpty {
            fragments.append("Write: \(writePaths.prefix(2).joined(separator: ", "))")
        }

        if let readPaths = profile.fileSystem?.read, !readPaths.isEmpty {
            fragments.append("Read: \(readPaths.prefix(2).joined(separator: ", "))")
        }

        if profile.network?.enabled == true {
            fragments.append("Network access")
        }

        if fragments.isEmpty {
            return "Codex requests additional permissions."
        }

        return fragments.joined(separator: " · ")
    }

    private func registerPendingRequest(_ pending: PendingRequest) {
        let requestID = pending.id.rawValue
        if let existingRequestID = pendingRequestIDBySession[pending.sessionID],
           existingRequestID != requestID {
            pendingRequestsByID.removeValue(forKey: existingRequestID)
        }
        pendingRequestsByID[requestID] = pending
        pendingRequestIDBySession[pending.sessionID] = requestID
    }

    @discardableResult
    private func clearPendingRequest(requestID: String) -> PendingRequest? {
        guard let pending = pendingRequestsByID.removeValue(forKey: requestID) else {
            return nil
        }

        if pendingRequestIDBySession[pending.sessionID] == requestID {
            pendingRequestIDBySession.removeValue(forKey: pending.sessionID)
        }
        return pending
    }

    private func clearPendingRequests(for sessionID: String) {
        guard let requestID = pendingRequestIDBySession.removeValue(forKey: sessionID) else {
            return
        }
        pendingRequestsByID.removeValue(forKey: requestID)
    }

    private func requestContext(for pending: PendingRequest) -> CodexPendingRequestContext {
        CodexPendingRequestContext(
            requestID: pending.id.rawValue,
            source: .appServer,
            kind: pending.kind,
            method: pending.method,
            itemID: pending.itemID,
            turnID: pending.turnID,
            threadID: pending.sessionID,
            createdAt: pending.createdAt
        )
    }

    private func emitSessionStarted(from thread: CodexThread) {
        let workspaceName = URL(fileURLWithPath: thread.cwd).lastPathComponent
        let title = thread.name ?? (workspaceName.isEmpty ? "Codex" : workspaceName)
        let summary = thread.preview.isEmpty ? "Codex session." : String(thread.preview.prefix(160))
        let jumpTarget = CodexTerminalJumpTarget(
            sessionID: thread.id,
            transcriptPath: thread.path,
            terminalApp: "Codex.app",
            workspaceName: workspaceName.isEmpty ? "Codex" : workspaceName,
            paneTitle: title,
            workingDirectory: thread.cwd,
            bundleIdentifier: "com.openai.codex"
        )

        onEvent?(.sessionStarted(
            SessionStartedEvent(
                sessionID: thread.id,
                cwd: thread.cwd,
                title: title,
                summary: summary,
                timestamp: .now,
                jumpTarget: jumpTarget,
                transcriptPath: thread.path,
                sessionSurface: .codexApp
            )
        ))
    }
}
