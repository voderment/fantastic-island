import Foundation

struct CodexTerminalDiscovery {
    private let readLimit: Int = 64 * 1024

    func inspectTranscript(at url: URL, sessionID: String, cwd: String) -> CodexSessionTranscriptInsights {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return .init()
        }

        defer { try? handle.close() }

        let data = (try? handle.read(upToCount: readLimit)) ?? Data()
        guard !data.isEmpty else {
            return .init()
        }

        let lines = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        return inspect(lines: lines, sessionID: sessionID, cwd: cwd, transcriptPath: url.path)
    }

    func inspect(line: String, sessionID: String, cwd: String, transcriptPath: String?) -> CodexSessionTranscriptInsights? {
        guard let object = jsonObject(for: line) else {
            return nil
        }

        return inspect(object: object, sessionID: sessionID, cwd: cwd, transcriptPath: transcriptPath)
    }

    func inspect(lines: [String], sessionID: String, cwd: String, transcriptPath: String?) -> CodexSessionTranscriptInsights {
        var merged = CodexSessionTranscriptInsights()

        for line in lines {
            guard let object = jsonObject(for: line) else {
                continue
            }

            merged.merge(inspect(object: object, sessionID: sessionID, cwd: cwd, transcriptPath: transcriptPath))
        }

        return merged
    }

    func inspect(object: [String: Any], sessionID: String, cwd: String, transcriptPath: String?) -> CodexSessionTranscriptInsights {
        let payload = object["payload"] as? [String: Any] ?? [:]
        let candidates = [payload, object].filter { !$0.isEmpty }
        var insights = CodexSessionTranscriptInsights()

        if let assistantSummary = assistantSummary(from: object, payload: payload) {
            insights.assistantSummary = assistantSummary
        }

        if let jumpTarget = jumpTarget(from: candidates, sessionID: sessionID, cwd: cwd, transcriptPath: transcriptPath) {
            insights.jumpTarget = jumpTarget
            insights.sessionSurface = jumpTarget.terminalApp == "Codex.app" ? .codexApp : .terminal
        }

        if insights.sessionSurface == .unknown {
            insights.sessionSurface = surface(from: payload).merged(with: surface(from: object))
        }

        return insights
    }

    private func jumpTarget(from candidates: [[String: Any]], sessionID: String, cwd: String, transcriptPath: String?) -> CodexTerminalJumpTarget? {
        let terminalApp =
            firstStringValue(in: candidates, keys: Self.terminalAppKeys)
            ?? firstStringValue(in: candidates, keys: Self.legacyAppKeys)
        let terminalSessionID =
            firstStringValue(in: candidates, keys: Self.terminalSessionKeys)
            ?? firstStringValue(in: candidates, keys: Self.legacySessionKeys)
        let terminalTTY =
            firstStringValue(in: candidates, keys: Self.terminalTTYKeys)
            ?? firstStringValue(in: candidates, keys: Self.legacyTTYKeys)
        let terminalTitle =
            firstStringValue(in: candidates, keys: Self.terminalTitleKeys)
            ?? firstStringValue(in: candidates, keys: Self.legacyTitleKeys)
        let bundleIdentifier =
            firstStringValue(in: candidates, keys: Self.bundleIdentifierKeys)
        let processIdentifier =
            firstIntValue(in: candidates, keys: Self.processIdentifierKeys)
        let windowIdentifier =
            firstStringValue(in: candidates, keys: Self.windowIdentifierKeys)
        let tabIdentifier =
            firstStringValue(in: candidates, keys: Self.tabIdentifierKeys)
        let paneIdentifier =
            firstStringValue(in: candidates, keys: Self.paneIdentifierKeys)
        let tmuxTarget =
            firstStringValue(in: candidates, keys: Self.tmuxTargetKeys)
        let tmuxSocketPath =
            firstStringValue(in: candidates, keys: Self.tmuxSocketKeys)
        let warpPaneUUID =
            firstStringValue(in: candidates, keys: Self.warpPaneKeys)
        let source =
            firstStringValue(in: candidates, keys: Self.sourceKeys)?.lowercased()

        let resolvedApp: String?
        if source == "vscode" || source == "app-server" {
            resolvedApp = "Codex.app"
        } else if let terminalApp, !terminalApp.isEmpty {
            resolvedApp = terminalApp
        } else {
            resolvedApp = nil
        }

        guard resolvedApp != nil
            || bundleIdentifier != nil
            || processIdentifier != nil
            || terminalSessionID != nil
            || terminalTTY != nil
            || tmuxTarget != nil
            || warpPaneUUID != nil else {
            return nil
        }

        let workspaceName = URL(fileURLWithPath: cwd).lastPathComponent

        return CodexTerminalJumpTarget(
            sessionID: sessionID,
            transcriptPath: transcriptPath,
            terminalApp: resolvedApp ?? "Terminal",
            workspaceName: workspaceName.isEmpty ? "Codex" : workspaceName,
            paneTitle: terminalTitle ?? "Codex",
            workingDirectory: cwd,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            terminalSessionID: terminalSessionID,
            terminalTTY: terminalTTY,
            windowIdentifier: windowIdentifier,
            tabIdentifier: tabIdentifier,
            paneIdentifier: paneIdentifier,
            tmuxTarget: tmuxTarget,
            tmuxSocketPath: tmuxSocketPath,
            warpPaneUUID: warpPaneUUID
        )
    }

    private func assistantSummary(from object: [String: Any], payload: [String: Any]) -> String? {
        let type = normalizedTypeValue(object["type"]) ?? normalizedTypeValue(payload["type"])
        let role = normalizedTypeValue(payload["role"]) ?? normalizedTypeValue(object["role"])
        let looksAssistantLike =
            role == "assistant"
            || type == "agent_message"
            || (type == "response_item" && role != "user")
            || (type == "message" && role != "user")

        guard looksAssistantLike else {
            return nil
        }

        return clipped(
            joinedText(from: payload["content"])
                ?? joinedText(from: payload["text"])
                ?? joinedText(from: payload["message"])
                ?? joinedText(from: payload["output"])
                ?? joinedText(from: payload["assistant_summary"])
                ?? joinedText(from: object["content"])
                ?? joinedText(from: object["text"])
                ?? joinedText(from: object["message"]),
            limit: 160
        )
    }

    private func surface(from dictionary: [String: Any]) -> CodexSessionSurface {
        let source = firstStringValue(in: [dictionary], keys: Self.sourceKeys)?.lowercased()
        let originator = firstStringValue(in: [dictionary], keys: Self.originatorKeys)?.lowercased()

        if originator?.contains("desktop") == true || source == "vscode" || source == "app-server" {
            return .codexApp
        }

        if source == "cli" || source == "codex-exec" || source == "codexexec" {
            return .terminal
        }

        return .unknown
    }

    private func normalizedTypeValue(_ value: Any?) -> String? {
        guard let value = stringValue(from: value) else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let terminalAppKeys: Set<String> = ["terminalapp"]
    private static let terminalSessionKeys: Set<String> = ["terminalsessionid"]
    private static let terminalTTYKeys: Set<String> = ["terminaltty"]
    private static let terminalTitleKeys: Set<String> = ["terminaltitle"]
    private static let bundleIdentifierKeys: Set<String> = ["terminalbundleidentifier", "bundleidentifier", "bundleid"]
    private static let processIdentifierKeys: Set<String> = ["terminalprocessidentifier", "processidentifier", "pid"]
    private static let windowIdentifierKeys: Set<String> = ["terminalwindowidentifier", "windowidentifier", "windowid"]
    private static let tabIdentifierKeys: Set<String> = ["terminaltabidentifier", "tabidentifier", "tabid"]
    private static let paneIdentifierKeys: Set<String> = ["terminalpaneidentifier", "paneidentifier", "paneid"]
    private static let tmuxTargetKeys: Set<String> = ["tmuxtarget"]
    private static let tmuxSocketKeys: Set<String> = ["tmuxsocketpath"]
    private static let warpPaneKeys: Set<String> = ["warppaneuuid"]
    private static let sourceKeys: Set<String> = ["source"]
    private static let originatorKeys: Set<String> = ["originator"]

    private static let legacyAppKeys: Set<String> = ["terminalapplicationname", "terminalappname", "terminalapplication"]
    private static let legacySessionKeys: Set<String> = ["terminalsessionidentifier"]
    private static let legacyTTYKeys: Set<String> = ["ttypath", "ttyname"]
    private static let legacyTitleKeys: Set<String> = ["terminalwindowtitle", "terminaldisplaytitle", "title"]
}

private func firstStringValue(in dictionaries: [[String: Any]], keys: Set<String>) -> String? {
    for dictionary in dictionaries {
        for (key, value) in dictionary where keys.contains(normalizedMonitoringKey(key)) {
            if let string = stringValue(from: value) {
                return string
            }
        }
    }

    return nil
}

private func firstIntValue(in dictionaries: [[String: Any]], keys: Set<String>) -> Int? {
    for dictionary in dictionaries {
        for (key, value) in dictionary where keys.contains(normalizedMonitoringKey(key)) {
            if let number = intValue(from: value) {
                return number
            }
        }
    }

    return nil
}
