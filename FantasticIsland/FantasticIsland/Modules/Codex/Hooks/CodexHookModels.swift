import Foundation

enum CodexHookEventName: String, Codable {
    case sessionStart = "SessionStart"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case userPromptSubmit = "UserPromptSubmit"
    case stop = "Stop"
}

enum CodexPermissionMode: String, Codable {
    case `default`
    case acceptEdits = "acceptEdits"
    case plan
    case dontAsk = "dontAsk"
    case bypassPermissions = "bypassPermissions"
}

struct CodexHookToolInput: Equatable, Codable {
    var command: String
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
    var permissionMode: CodexPermissionMode
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

    var hasTerminalContext: Bool {
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

    var sessionSurface: CodexSessionSurface {
        if let source = source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           source == "vscode" || source == "app-server" {
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

        let workspaceName = URL(fileURLWithPath: cwd).lastPathComponent

        return CodexTerminalJumpTarget(
            sessionID: sessionID,
            transcriptPath: transcriptPath,
            terminalApp: terminalApp ?? "Terminal",
            workspaceName: workspaceName.isEmpty ? "Codex" : workspaceName,
            paneTitle: terminalTitle ?? prompt ?? "Codex",
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
            warpPaneUUID: warpPaneUUID
        )
    }

    private var codexAppJumpTarget: CodexTerminalJumpTarget? {
        guard sessionSurface == .codexApp else {
            return nil
        }

        let workspaceName = URL(fileURLWithPath: cwd).lastPathComponent
        return CodexTerminalJumpTarget(
            sessionID: sessionID,
            transcriptPath: transcriptPath,
            terminalApp: "Codex.app",
            workspaceName: workspaceName.isEmpty ? "Codex" : workspaceName,
            paneTitle: prompt ?? "Codex",
            workingDirectory: cwd,
            bundleIdentifier: "com.openai.codex"
        )
    }
}

enum CodexHookDirective: Equatable, Codable {
    case deny(reason: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case reason
    }

    private enum DirectiveType: String, Codable {
        case deny
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(DirectiveType.self, forKey: .type) {
        case .deny:
            self = .deny(reason: try container.decode(String.self, forKey: .reason))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .deny(reason):
            try container.encode(DirectiveType.deny, forKey: .type)
            try container.encode(reason, forKey: .reason)
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
