import Foundation

enum CodexHookEventName: String, Codable {
    case sessionStart = "SessionStart"
    case preToolUse = "PreToolUse"
    case permissionRequest = "PermissionRequest"
    case postToolUse = "PostToolUse"
    case userPromptSubmit = "UserPromptSubmit"
    case stop = "Stop"

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self.normalized(try container.decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func normalized(_ name: String) -> CodexHookEventName {
        switch name {
        case "SessionStart", "sessionStart":
            return .sessionStart
        case "SessionEnd", "sessionEnd", "Stop", "stop":
            return .stop
        case "UserPromptSubmit", "beforeSubmitPrompt", "userPromptSubmit", "userPromptSubmitted":
            return .userPromptSubmit
        case "PreToolUse", "beforeShellExecution", "beforeReadFile", "beforeMCPExecution", "BeforeTool", "preToolUse":
            return .preToolUse
        case "PostToolUse", "PostToolUseFailure", "afterShellExecution", "afterFileEdit", "afterMCPExecution", "afterAgentThought", "afterAgentResponse", "AfterTool", "postToolUse":
            return .postToolUse
        case "PermissionRequest", "permissionRequest", "Notification":
            return .permissionRequest
        default:
            return .postToolUse
        }
    }
}

enum CodexPermissionMode: String, Codable {
    case `default`
    case acceptEdits = "acceptEdits"
    case plan
    case dontAsk = "dontAsk"
    case bypassPermissions = "bypassPermissions"
}

struct CodexHookToolInput: Equatable, Codable {
    var command: String?
    var description: String?

    private enum CodingKeys: String, CodingKey {
        case command
        case description
    }

    init(command: String? = nil, description: String? = nil) {
        self.command = command
        self.description = description
    }

    init(from decoder: any Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            command = try container.decodeIfPresent(String.self, forKey: .command)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            return
        }

        let container = try decoder.singleValueContainer()
        command = try? container.decode(String.self)
        description = nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(description, forKey: .description)
    }
}

enum CodexHookJSONValue: Equatable, Codable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: CodexHookJSONValue])
    case array([CodexHookJSONValue])
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: CodexHookJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([CodexHookJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .boolean(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct CodexHookPayload: Codable {
    var cwd: String
    var hookEventName: CodexHookEventName
    var model: String?
    var permissionMode: CodexPermissionMode?
    var sessionID: String
    var terminalApp: String?
    var terminalSessionID: String?
    var terminalTTY: String?
    var terminalTitle: String?
    var terminalBundleIdentifier: String?
    var terminalProcessIdentifier: Int?
    var terminalWindowIdentifier: String?
    var terminalTabIdentifier: String?
    var terminalPaneIdentifier: String?
    var warpPaneUUID: String?
    var tmuxTarget: String?
    var tmuxSocketPath: String?
    var workspaceName: String?
    var workspaceIdentifier: String?
    var conductorPort: Int?
    var conductorURL: String?
    var transcriptPath: String?
    var source: String?
    var turnID: String?
    var toolName: String?
    var toolUseID: String?
    var toolInput: CodexHookToolInput?
    var toolResponse: CodexHookJSONValue?
    var prompt: String?
    var stopHookActive: Bool?
    var lastAssistantMessage: String?

    private enum CodingKeys: String, CodingKey {
        case cwd
        case hookEventName = "hook_event_name"
        case model
        case permissionMode = "permission_mode"
        case sessionID = "session_id"
        case terminalApp = "terminal_app"
        case terminalSessionID = "terminal_session_id"
        case terminalTTY = "terminal_tty"
        case terminalTitle = "terminal_title"
        case terminalBundleIdentifier = "terminal_bundle_identifier"
        case terminalProcessIdentifier = "terminal_process_identifier"
        case terminalWindowIdentifier = "terminal_window_identifier"
        case terminalTabIdentifier = "terminal_tab_identifier"
        case terminalPaneIdentifier = "terminal_pane_identifier"
        case warpPaneUUID = "warp_pane_uuid"
        case tmuxTarget = "tmux_target"
        case tmuxSocketPath = "tmux_socket_path"
        case workspaceName = "workspace_name"
        case workspaceIdentifier = "workspace_id"
        case conductorPort = "conductor_port"
        case conductorURL = "conductor_url"
        case transcriptPath = "transcript_path"
        case source
        case turnID = "turn_id"
        case toolName = "tool_name"
        case toolUseID = "tool_use_id"
        case toolInput = "tool_input"
        case toolResponse = "tool_response"
        case prompt
        case stopHookActive = "stop_hook_active"
        case lastAssistantMessage = "last_assistant_message"
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case event
        case eventName
        case hookEventName
        case sessionId
        case sessionID
        case projectPath
        case workspacePath
        case workspaceName
        case workspace
        case projectName
        case workspaceId
        case workspaceID
        case conductorWorkspaceName
        case conductorWorkspaceId
        case conductorWorkspaceID
        case conductorPort
        case conductorUrl
        case conductorURL
        case port
        case rootPath
        case command
        case description
        case input
        case message
        case response
        case summary
    }

    init(
        cwd: String,
        hookEventName: CodexHookEventName,
        model: String? = nil,
        permissionMode: CodexPermissionMode? = nil,
        sessionID: String,
        terminalApp: String? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil,
        terminalTitle: String? = nil,
        terminalBundleIdentifier: String? = nil,
        terminalProcessIdentifier: Int? = nil,
        terminalWindowIdentifier: String? = nil,
        terminalTabIdentifier: String? = nil,
        terminalPaneIdentifier: String? = nil,
        warpPaneUUID: String? = nil,
        tmuxTarget: String? = nil,
        tmuxSocketPath: String? = nil,
        workspaceName: String? = nil,
        workspaceIdentifier: String? = nil,
        conductorPort: Int? = nil,
        conductorURL: String? = nil,
        transcriptPath: String? = nil,
        source: String? = nil,
        turnID: String? = nil,
        toolName: String? = nil,
        toolUseID: String? = nil,
        toolInput: CodexHookToolInput? = nil,
        toolResponse: CodexHookJSONValue? = nil,
        prompt: String? = nil,
        stopHookActive: Bool? = nil,
        lastAssistantMessage: String? = nil
    ) {
        self.cwd = cwd
        self.hookEventName = hookEventName
        self.model = model
        self.permissionMode = permissionMode
        self.sessionID = sessionID
        self.terminalApp = terminalApp
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.terminalTitle = terminalTitle
        self.terminalBundleIdentifier = terminalBundleIdentifier
        self.terminalProcessIdentifier = terminalProcessIdentifier
        self.terminalWindowIdentifier = terminalWindowIdentifier
        self.terminalTabIdentifier = terminalTabIdentifier
        self.terminalPaneIdentifier = terminalPaneIdentifier
        self.warpPaneUUID = warpPaneUUID
        self.tmuxTarget = tmuxTarget
        self.tmuxSocketPath = tmuxSocketPath
        self.workspaceName = workspaceName
        self.workspaceIdentifier = workspaceIdentifier
        self.conductorPort = conductorPort
        self.conductorURL = conductorURL
        self.transcriptPath = transcriptPath
        self.source = source
        self.turnID = turnID
        self.toolName = toolName
        self.toolUseID = toolUseID
        self.toolInput = toolInput
        self.toolResponse = toolResponse
        self.prompt = prompt
        self.stopHookActive = stopHookActive
        self.lastAssistantMessage = lastAssistantMessage
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let alternate = try decoder.container(keyedBy: AlternateCodingKeys.self)

        hookEventName =
            (try? container.decode(CodexHookEventName.self, forKey: .hookEventName))
            ?? (try? alternate.decode(CodexHookEventName.self, forKey: .hookEventName))
            ?? (try? alternate.decode(CodexHookEventName.self, forKey: .eventName))
            ?? (try? alternate.decode(CodexHookEventName.self, forKey: .event))
            ?? .postToolUse
        cwd =
            (try? container.decode(String.self, forKey: .cwd))
            ?? (try? alternate.decode(String.self, forKey: .projectPath))
            ?? (try? alternate.decode(String.self, forKey: .workspacePath))
            ?? (try? alternate.decode(String.self, forKey: .rootPath))
            ?? FileManager.default.currentDirectoryPath
        model = try? container.decodeIfPresent(String.self, forKey: .model)
        permissionMode = try? container.decodeIfPresent(CodexPermissionMode.self, forKey: .permissionMode)
        source = try? container.decodeIfPresent(String.self, forKey: .source)
        sessionID =
            (try? container.decode(String.self, forKey: .sessionID))
            ?? (try? alternate.decode(String.self, forKey: .sessionId))
            ?? (try? alternate.decode(String.self, forKey: .sessionID))
            ?? "\(AgentProvider.resolve(source: source).rawValue):\(UUID().uuidString)"
        terminalApp = try? container.decodeIfPresent(String.self, forKey: .terminalApp)
        terminalSessionID = try? container.decodeIfPresent(String.self, forKey: .terminalSessionID)
        terminalTTY = try? container.decodeIfPresent(String.self, forKey: .terminalTTY)
        terminalTitle = try? container.decodeIfPresent(String.self, forKey: .terminalTitle)
        terminalBundleIdentifier = try? container.decodeIfPresent(String.self, forKey: .terminalBundleIdentifier)
        terminalProcessIdentifier = try? container.decodeIfPresent(Int.self, forKey: .terminalProcessIdentifier)
        terminalWindowIdentifier = try? container.decodeIfPresent(String.self, forKey: .terminalWindowIdentifier)
        terminalTabIdentifier = try? container.decodeIfPresent(String.self, forKey: .terminalTabIdentifier)
        terminalPaneIdentifier = try? container.decodeIfPresent(String.self, forKey: .terminalPaneIdentifier)
        warpPaneUUID = try? container.decodeIfPresent(String.self, forKey: .warpPaneUUID)
        tmuxTarget = try? container.decodeIfPresent(String.self, forKey: .tmuxTarget)
        tmuxSocketPath = try? container.decodeIfPresent(String.self, forKey: .tmuxSocketPath)
        workspaceName = Self.firstDecodedString(
            primary: container,
            primaryKeys: [.workspaceName],
            alternate: alternate,
            alternateKeys: [.workspaceName, .workspace, .projectName, .conductorWorkspaceName]
        )
        workspaceIdentifier = Self.firstDecodedString(
            primary: container,
            primaryKeys: [.workspaceIdentifier],
            alternate: alternate,
            alternateKeys: [.workspaceId, .workspaceID, .conductorWorkspaceId, .conductorWorkspaceID]
        )
        conductorPort = Self.firstDecodedInt(
            primary: container,
            primaryKeys: [.conductorPort],
            alternate: alternate,
            alternateKeys: [.conductorPort, .port]
        )
        conductorURL =
            (try? container.decodeIfPresent(String.self, forKey: .conductorURL))
            ?? (try? alternate.decodeIfPresent(String.self, forKey: .conductorUrl))
            ?? (try? alternate.decodeIfPresent(String.self, forKey: .conductorURL))
        transcriptPath = try? container.decodeIfPresent(String.self, forKey: .transcriptPath)
        turnID = try? container.decodeIfPresent(String.self, forKey: .turnID)
        toolName = try? container.decodeIfPresent(String.self, forKey: .toolName)
        toolUseID = try? container.decodeIfPresent(String.self, forKey: .toolUseID)
        toolInput =
            (try? container.decodeIfPresent(CodexHookToolInput.self, forKey: .toolInput))
            ?? Self.flatToolInput(from: alternate)
        toolResponse =
            (try? container.decodeIfPresent(CodexHookJSONValue.self, forKey: .toolResponse))
            ?? (try? alternate.decodeIfPresent(CodexHookJSONValue.self, forKey: .response))
        prompt =
            (try? container.decodeIfPresent(String.self, forKey: .prompt))
            ?? (try? alternate.decodeIfPresent(String.self, forKey: .message))
            ?? (try? alternate.decodeIfPresent(String.self, forKey: .input))
        stopHookActive = try? container.decodeIfPresent(Bool.self, forKey: .stopHookActive)
        lastAssistantMessage =
            (try? container.decodeIfPresent(String.self, forKey: .lastAssistantMessage))
            ?? (try? alternate.decodeIfPresent(String.self, forKey: .summary))
    }

    nonisolated var hasTerminalContext: Bool {
        terminalApp != nil
            || terminalSessionID != nil
            || terminalTTY != nil
            || terminalTitle != nil
            || terminalBundleIdentifier != nil
            || terminalProcessIdentifier != nil
            || terminalWindowIdentifier != nil
            || terminalTabIdentifier != nil
            || terminalPaneIdentifier != nil
            || warpPaneUUID != nil
            || tmuxTarget != nil
    }

    var assistantSummary: String? {
        clipped(lastAssistantMessage, limit: 160)
    }

    var agentProvider: AgentProvider {
        AgentProvider.resolve(
            source: source,
            terminalApp: terminalApp,
            bundleIdentifier: terminalBundleIdentifier
        )
    }

    nonisolated var sessionSurface: CodexSessionSurface {
        if let source = source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           source == "vscode" || source == "app-server" || source == "cursor" || source == "antigravity" || source == "conductor" {
            return .codexApp
        }

        if hasTerminalContext {
            return .terminal
        }

        return .unknown
    }

    var terminalJumpTarget: CodexTerminalJumpTarget? {
        if sessionSurface == .codexApp {
            return codexAppJumpTarget
        }

        guard hasTerminalContext else {
            return nil
        }

        let workspaceName = resolvedWorkspaceName
        let provider = agentProvider

        return CodexTerminalJumpTarget(
            sessionID: sessionID,
            transcriptPath: transcriptPath,
            terminalApp: terminalApp ?? "Terminal",
            workspaceName: workspaceName.isEmpty ? provider.displayName : workspaceName,
            paneTitle: terminalTitle ?? prompt ?? provider.displayName,
            workingDirectory: cwd,
            bundleIdentifier: terminalBundleIdentifier,
            processIdentifier: terminalProcessIdentifier,
            terminalSessionID: terminalSessionID,
            terminalTTY: terminalTTY,
            windowIdentifier: terminalWindowIdentifier,
            tabIdentifier: terminalTabIdentifier,
            paneIdentifier: terminalPaneIdentifier,
            tmuxTarget: tmuxTarget,
            tmuxSocketPath: tmuxSocketPath,
            warpPaneUUID: warpPaneUUID,
            workspaceIdentifier: workspaceIdentifier,
            conductorPort: conductorPort,
            conductorURL: conductorURL
        )
    }

    private var codexAppJumpTarget: CodexTerminalJumpTarget? {
        guard sessionSurface == .codexApp else {
            return nil
        }

        let workspaceName = resolvedWorkspaceName
        let provider = agentProvider
        return CodexTerminalJumpTarget(
            sessionID: sessionID,
            transcriptPath: transcriptPath,
            terminalApp: provider.displayName,
            workspaceName: workspaceName.isEmpty ? provider.displayName : workspaceName,
            paneTitle: prompt ?? provider.displayName,
            workingDirectory: cwd,
            bundleIdentifier: provider.appBundleIdentifier,
            workspaceIdentifier: workspaceIdentifier,
            conductorPort: conductorPort,
            conductorURL: conductorURL
        )
    }

    private var resolvedWorkspaceName: String {
        if let workspaceName = workspaceName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !workspaceName.isEmpty {
            return workspaceName
        }

        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    private static func flatToolInput(from container: KeyedDecodingContainer<AlternateCodingKeys>) -> CodexHookToolInput? {
        let command = try? container.decodeIfPresent(String.self, forKey: .command)
        let description = try? container.decodeIfPresent(String.self, forKey: .description)
        if command == nil && description == nil {
            return nil
        }

        return CodexHookToolInput(command: command ?? nil, description: description ?? nil)
    }

    private static func firstDecodedString(
        primary: KeyedDecodingContainer<CodingKeys>,
        primaryKeys: [CodingKeys],
        alternate: KeyedDecodingContainer<AlternateCodingKeys>,
        alternateKeys: [AlternateCodingKeys]
    ) -> String? {
        for key in primaryKeys {
            if let value = try? primary.decodeIfPresent(String.self, forKey: key),
               let trimmed = nonEmpty(value) {
                return trimmed
            }
        }

        for key in alternateKeys {
            if let value = try? alternate.decodeIfPresent(String.self, forKey: key),
               let trimmed = nonEmpty(value) {
                return trimmed
            }
        }

        return nil
    }

    private static func firstDecodedInt(
        primary: KeyedDecodingContainer<CodingKeys>,
        primaryKeys: [CodingKeys],
        alternate: KeyedDecodingContainer<AlternateCodingKeys>,
        alternateKeys: [AlternateCodingKeys]
    ) -> Int? {
        for key in primaryKeys {
            if let value = try? primary.decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            if let value = try? primary.decodeIfPresent(String.self, forKey: key),
               let integer = integerString(from: value) {
                return integer
            }
        }

        for key in alternateKeys {
            if let value = try? alternate.decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            if let value = try? alternate.decodeIfPresent(String.self, forKey: key),
               let integer = integerString(from: value) {
                return integer
            }
        }

        return nil
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func integerString(from value: String?) -> Int? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return Int(value)
    }
}

enum CodexHookDirective: Equatable, Codable {
    case permissionRequestAllow
    case permissionRequestDeny(reason: String)
    case preToolUseDeny(reason: String)

    private enum CodingKeys: String, CodingKey {
        case hookSpecificOutput
    }

    private enum HookSpecificOutputKeys: String, CodingKey {
        case hookEventName
        case decision
        case permissionDecision
        case permissionDecisionReason
    }

    private enum DecisionKeys: String, CodingKey {
        case behavior
        case message
    }

    private enum Behavior: String, Codable {
        case allow
        case deny
    }

    private enum PermissionDecision: String, Codable {
        case deny
    }

    nonisolated static func allow(for eventName: CodexHookEventName) -> CodexHookDirective? {
        switch eventName {
        case .permissionRequest:
            return .permissionRequestAllow
        case .preToolUse, .sessionStart, .postToolUse, .userPromptSubmit, .stop:
            return nil
        }
    }

    nonisolated static func deny(reason: String, for eventName: CodexHookEventName) -> CodexHookDirective {
        switch eventName {
        case .permissionRequest:
            return .permissionRequestDeny(reason: reason)
        case .preToolUse, .sessionStart, .postToolUse, .userPromptSubmit, .stop:
            return .preToolUseDeny(reason: reason)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let output = try container.nestedContainer(keyedBy: HookSpecificOutputKeys.self, forKey: .hookSpecificOutput)
        let hookEventName = try output.decode(CodexHookEventName.self, forKey: .hookEventName)

        switch hookEventName {
        case .permissionRequest:
            let decision = try output.nestedContainer(keyedBy: DecisionKeys.self, forKey: .decision)
            switch try decision.decode(Behavior.self, forKey: .behavior) {
            case .allow:
                self = .permissionRequestAllow
            case .deny:
                self = .permissionRequestDeny(reason: try decision.decodeIfPresent(String.self, forKey: .message) ?? "")
            }
        case .preToolUse:
            self = .preToolUseDeny(
                reason: try output.decodeIfPresent(String.self, forKey: .permissionDecisionReason) ?? ""
            )
        case .sessionStart, .postToolUse, .userPromptSubmit, .stop:
            self = .preToolUseDeny(reason: "")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var output = container.nestedContainer(keyedBy: HookSpecificOutputKeys.self, forKey: .hookSpecificOutput)

        switch self {
        case .permissionRequestAllow:
            try output.encode(CodexHookEventName.permissionRequest, forKey: .hookEventName)
            var decision = output.nestedContainer(keyedBy: DecisionKeys.self, forKey: .decision)
            try decision.encode(Behavior.allow, forKey: .behavior)
        case let .permissionRequestDeny(reason):
            try output.encode(CodexHookEventName.permissionRequest, forKey: .hookEventName)
            var decision = output.nestedContainer(keyedBy: DecisionKeys.self, forKey: .decision)
            try decision.encode(Behavior.deny, forKey: .behavior)
            try decision.encode(reason, forKey: .message)
        case let .preToolUseDeny(reason):
            try output.encode(CodexHookEventName.preToolUse, forKey: .hookEventName)
            try output.encode(PermissionDecision.deny, forKey: .permissionDecision)
            try output.encode(reason, forKey: .permissionDecisionReason)
        }
    }
}

enum HookInstallStatus: Equatable {
    case installed
    case notInstalled
    case error(String)

    var isInstalled: Bool {
        if case .installed = self {
            return true
        }

        return false
    }
}
