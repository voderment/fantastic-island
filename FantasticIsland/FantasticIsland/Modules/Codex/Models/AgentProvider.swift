import Foundation

enum AgentHookFormat: String, Codable, CaseIterable {
    case codexNested
    case claudeStyle
    case cursorFlat
}

struct AgentHookEventSpec: Equatable, Codable {
    var name: String
    var timeout: Int
    var isAsync: Bool

    init(name: String, timeout: Int, isAsync: Bool = false) {
        self.name = name
        self.timeout = timeout
        self.isAsync = isAsync
    }
}

enum AgentProvider: String, Codable, CaseIterable, Identifiable {
    case codex
    case claudeCode
    case cursor
    case antigravity
    case conductor

    var id: String { rawValue }

    static var hookInstallationProviders: [AgentProvider] {
        [.codex, .claudeCode, .cursor, .antigravity]
    }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claudeCode:
            return "Claude Code"
        case .cursor:
            return "Cursor"
        case .antigravity:
            return "Antigravity"
        case .conductor:
            return "Conductor"
        }
    }

    var compactName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claudeCode:
            return "Claude"
        case .cursor:
            return "Cursor"
        case .antigravity:
            return "AG"
        case .conductor:
            return "Cond"
        }
    }

    var symbolName: String {
        switch self {
        case .codex:
            return "terminal"
        case .claudeCode:
            return "sparkles"
        case .cursor:
            return "cursorarrow"
        case .antigravity:
            return "scope"
        case .conductor:
            return "rectangle.3.group"
        }
    }

    var appBundleIdentifier: String {
        switch self {
        case .codex:
            return "com.openai.codex"
        case .claudeCode:
            return "com.anthropic.claudefordesktop"
        case .cursor:
            return "com.todesktop.230313mzl4w4u92"
        case .antigravity:
            return "com.google.antigravity-ide"
        case .conductor:
            return "com.conductor.app"
        }
    }

    var fallbackAppBundleIdentifiers: [String] {
        switch self {
        case .antigravity:
            return ["com.google.antigravity"]
        case .codex, .claudeCode, .cursor, .conductor:
            return []
        }
    }

    var urlScheme: String {
        switch self {
        case .codex:
            return "codex"
        case .claudeCode:
            return "claude"
        case .cursor:
            return "cursor"
        case .antigravity:
            return "antigravity-ide"
        case .conductor:
            return "conductor"
        }
    }

    var cliCommand: String {
        switch self {
        case .codex:
            return "codex"
        case .claudeCode:
            return "claude"
        case .cursor:
            return "cursor"
        case .antigravity:
            return "antigravity-ide"
        case .conductor:
            return "conductor"
        }
    }

    var configRelativePath: String {
        switch self {
        case .codex:
            return "hooks.json"
        case .claudeCode:
            return ".claude/settings.json"
        case .cursor:
            return ".cursor/hooks.json"
        case .antigravity:
            return ".antigravity/settings.json"
        case .conductor:
            return ""
        }
    }

    var hookFormat: AgentHookFormat {
        switch self {
        case .codex:
            return .codexNested
        case .claudeCode, .antigravity:
            return .claudeStyle
        case .cursor:
            return .cursorFlat
        case .conductor:
            return .codexNested
        }
    }

    var hookSource: String {
        switch self {
        case .codex:
            return "codex"
        case .claudeCode:
            return "claude"
        case .cursor:
            return "cursor"
        case .antigravity:
            return "antigravity"
        case .conductor:
            return "conductor"
        }
    }

    var hookEvents: [AgentHookEventSpec] {
        switch self {
        case .codex:
            return [
                .init(name: "SessionStart", timeout: 5),
                .init(name: "SessionEnd", timeout: 5, isAsync: true),
                .init(name: "UserPromptSubmit", timeout: 5),
                .init(name: "PreToolUse", timeout: 5),
                .init(name: "PostToolUse", timeout: 5),
                .init(name: "PermissionRequest", timeout: 45),
                .init(name: "Stop", timeout: 5),
            ]
        case .claudeCode, .antigravity:
            return [
                .init(name: "UserPromptSubmit", timeout: 5, isAsync: true),
                .init(name: "PreToolUse", timeout: 5),
                .init(name: "PostToolUse", timeout: 5, isAsync: true),
                .init(name: "PostToolUseFailure", timeout: 5, isAsync: true),
                .init(name: "PermissionRequest", timeout: 86_400),
                .init(name: "Stop", timeout: 5, isAsync: true),
                .init(name: "SubagentStart", timeout: 5, isAsync: true),
                .init(name: "SubagentStop", timeout: 5, isAsync: true),
                .init(name: "SessionStart", timeout: 5),
                .init(name: "SessionEnd", timeout: 5, isAsync: true),
                .init(name: "Notification", timeout: 86_400),
                .init(name: "PreCompact", timeout: 5, isAsync: true),
            ]
        case .cursor:
            return [
                .init(name: "beforeSubmitPrompt", timeout: 5),
                .init(name: "beforeShellExecution", timeout: 5),
                .init(name: "afterShellExecution", timeout: 5),
                .init(name: "beforeReadFile", timeout: 5),
                .init(name: "afterFileEdit", timeout: 5),
                .init(name: "beforeMCPExecution", timeout: 5),
                .init(name: "afterMCPExecution", timeout: 5),
                .init(name: "afterAgentThought", timeout: 5),
                .init(name: "afterAgentResponse", timeout: 5),
                .init(name: "stop", timeout: 5),
            ]
        case .conductor:
            return []
        }
    }

    var canLaunchWithPromptInTerminal: Bool {
        switch self {
        case .codex, .claudeCode:
            return true
        case .cursor, .antigravity, .conductor:
            return false
        }
    }

    var supportsDirectIslandReply: Bool {
        switch self {
        case .codex:
            return true
        case .claudeCode, .cursor, .antigravity, .conductor:
            return false
        }
    }

    var launchProfile: AgentLaunchProfile {
        AgentLaunchProfile(provider: self)
    }

    static func resolve(source: String?, terminalApp: String? = nil, bundleIdentifier: String? = nil) -> AgentProvider {
        let candidates = [source, terminalApp, bundleIdentifier]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        if candidates.contains(where: { $0.contains("conductor") || $0 == "com.conductor.app" }) {
            return .conductor
        }
        if candidates.contains(where: { $0.contains("antigravity") }) {
            return .antigravity
        }
        if candidates.contains(where: { $0.contains("cursor") || $0 == "com.todesktop.230313mzl4w4u92" }) {
            return .cursor
        }

        for candidate in candidates {
            if candidate.contains("claude") || candidate.contains("anthropic") {
                return .claudeCode
            }
            if candidate.contains("codex") || candidate == "com.openai.codex" {
                return .codex
            }
        }

        return .codex
    }
}

struct AgentLaunchProfile: Equatable, Codable {
    var provider: AgentProvider
    var bundleIdentifier: String
    var fallbackBundleIdentifiers: [String]
    var urlScheme: String
    var cliCommand: String
    var configRelativePath: String
    var hookFormat: AgentHookFormat
    var supportsPromptLaunch: Bool

    init(provider: AgentProvider) {
        self.provider = provider
        self.bundleIdentifier = provider.appBundleIdentifier
        self.fallbackBundleIdentifiers = provider.fallbackAppBundleIdentifiers
        self.urlScheme = provider.urlScheme
        self.cliCommand = provider.cliCommand
        self.configRelativePath = provider.configRelativePath
        self.hookFormat = provider.hookFormat
        self.supportsPromptLaunch = provider.canLaunchWithPromptInTerminal
    }
}

struct AgentNewSessionRequest: Equatable, Codable {
    var provider: AgentProvider
    var workingDirectory: String
    var initialPrompt: String

    init(provider: AgentProvider, workingDirectory: String, initialPrompt: String = "") {
        self.provider = provider
        self.workingDirectory = workingDirectory
        self.initialPrompt = initialPrompt
    }
}
