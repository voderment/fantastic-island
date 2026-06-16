import Foundation

struct DiscoveredSession: Equatable {
    let id: String
    let provider: AgentProvider
    let cwd: String
    let title: String
    let transcriptPath: String
    let phaseHint: SessionPhase?
    let isSessionEndedHint: Bool?
    let currentCommandPreview: String?
    let latestUserPrompt: String?
    let latestAssistantMessage: String?
    let completionMessageMarkdown: String?
    let jumpTarget: CodexTerminalJumpTarget?
    let assistantSummary: String?
    let sessionSurface: CodexSessionSurface
    let modifiedAt: Date?

    init(
        id: String,
        provider: AgentProvider = .codex,
        cwd: String,
        title: String,
        transcriptPath: String,
        phaseHint: SessionPhase? = nil,
        isSessionEndedHint: Bool? = nil,
        currentCommandPreview: String? = nil,
        latestUserPrompt: String? = nil,
        latestAssistantMessage: String? = nil,
        completionMessageMarkdown: String? = nil,
        jumpTarget: CodexTerminalJumpTarget? = nil,
        assistantSummary: String? = nil,
        sessionSurface: CodexSessionSurface = .unknown,
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.provider = provider
        self.cwd = cwd
        self.title = title
        self.transcriptPath = transcriptPath
        self.phaseHint = phaseHint
        self.isSessionEndedHint = isSessionEndedHint
        self.currentCommandPreview = currentCommandPreview
        self.latestUserPrompt = latestUserPrompt
        self.latestAssistantMessage = latestAssistantMessage
        self.completionMessageMarkdown = completionMessageMarkdown
        self.jumpTarget = jumpTarget
        self.assistantSummary = assistantSummary
        self.sessionSurface = sessionSurface
        self.modifiedAt = modifiedAt
    }
}

private extension DiscoveredSession {
    func fillingGaps(from fallback: DiscoveredSession) -> DiscoveredSession {
        DiscoveredSession(
            id: id,
            provider: provider,
            cwd: cwd,
            title: title,
            transcriptPath: transcriptPath,
            phaseHint: phaseHint,
            isSessionEndedHint: isSessionEndedHint,
            currentCommandPreview: currentCommandPreview,
            latestUserPrompt: latestUserPrompt,
            latestAssistantMessage: latestAssistantMessage,
            completionMessageMarkdown: completionMessageMarkdown,
            jumpTarget: jumpTarget ?? fallback.jumpTarget,
            assistantSummary: assistantSummary ?? fallback.assistantSummary,
            sessionSurface: sessionSurface.merged(with: fallback.sessionSurface),
            modifiedAt: modifiedAt ?? fallback.modifiedAt
        )
    }
}

struct CodexSessionDiscovery {
    private let terminalDiscovery = CodexTerminalDiscovery()
    let rootURL: URL
    let claudeRootURL: URL
    let cursorRootURL: URL
    let sessionStore: AgentSessionStore
    let maxFiles: Int
    let maxAge: TimeInterval

    init(
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions", isDirectory: true),
        claudeRootURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true),
        cursorRootURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor/projects", isDirectory: true),
        sessionStore: AgentSessionStore = AgentSessionStore(),
        maxFiles: Int = 240,
        maxAge: TimeInterval = 86_400 * 14
    ) {
        self.rootURL = rootURL
        self.claudeRootURL = claudeRootURL
        self.cursorRootURL = cursorRootURL
        self.sessionStore = sessionStore
        self.maxFiles = maxFiles
        self.maxAge = maxAge
    }

    func discoverRecentSessions(now: Date = .now) -> [DiscoveredSession] {
        var merged: [String: DiscoveredSession] = [:]

        for session in discoverCodexSessions(now: now) + discoverClaudeSessions(now: now) + discoverCursorSessions(now: now) + discoverStoredSessions(now: now) {
            if let existing = merged[session.id] {
                merged[session.id] = preferSession(existing, session)
            } else {
                merged[session.id] = session
            }
        }

        return merged.values.sorted { lhs, rhs in
            let lhsDate = (try? FileManager.default.attributesOfItem(atPath: lhs.transcriptPath)[.modificationDate] as? Date) ?? .distantPast
            let rhsDate = (try? FileManager.default.attributesOfItem(atPath: rhs.transcriptPath)[.modificationDate] as? Date) ?? .distantPast
            return lhsDate > rhsDate
        }
    }

    func discoverCodexSessions(now: Date = .now) -> [DiscoveredSession] {
        guard FileManager.default.fileExists(atPath: rootURL.path),
              let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let cutoff = now.addingTimeInterval(-maxAge)
        var candidates: [(url: URL, modifiedAt: Date)] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasPrefix("rollout-"),
                  fileURL.pathExtension == "jsonl",
                  let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }

            let modifiedAt = values.contentModificationDate ?? .distantPast
            guard modifiedAt >= cutoff else {
                continue
            }

            candidates.append((fileURL, modifiedAt))
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.modifiedAt == rhs.modifiedAt {
                    return lhs.url.lastPathComponent > rhs.url.lastPathComponent
                }

                return lhs.modifiedAt > rhs.modifiedAt
            }
            .prefix(maxFiles)
            .compactMap { candidate in
                discoverSession(at: candidate.url, modifiedAt: candidate.modifiedAt)
            }
    }

    func discoverClaudeSessions(now: Date = .now) -> [DiscoveredSession] {
        discoverJSONLSessions(
            rootURL: claudeRootURL,
            provider: .claudeCode,
            now: now,
            shouldInclude: { url in
                !url.path.contains("/subagents/") && !url.lastPathComponent.hasPrefix("agent-")
            }
        )
    }

    func discoverStoredSessions(now: Date = .now) -> [DiscoveredSession] {
        sessionStore.discoverRecentSessions(now: now).map { stored in
            DiscoveredSession(
                id: stored.id,
                provider: stored.provider,
                cwd: stored.cwd,
                title: stored.title,
                transcriptPath: stored.transcriptPath,
                phaseHint: stored.phase,
                isSessionEndedHint: stored.isSessionEnded,
                currentCommandPreview: stored.currentCommandPreview,
                latestUserPrompt: stored.latestUserPrompt,
                latestAssistantMessage: stored.latestAssistantMessage,
                completionMessageMarkdown: stored.completionMessageMarkdown,
                jumpTarget: stored.jumpTarget,
                assistantSummary: stored.assistantSummary,
                sessionSurface: stored.sessionSurface,
                modifiedAt: stored.modifiedAt
            )
        }
    }

    func discoverCursorSessions(now: Date = .now) -> [DiscoveredSession] {
        discoverJSONLSessions(
            rootURL: cursorRootURL,
            provider: .cursor,
            now: now,
            shouldInclude: { url in
                url.path.contains("/agent-transcripts/")
                    && !url.path.contains("/subagents/")
                    && url.deletingPathExtension().lastPathComponent == url.deletingLastPathComponent().lastPathComponent
            }
        )
    }

    private func discoverJSONLSessions(
        rootURL: URL,
        provider: AgentProvider,
        now: Date,
        shouldInclude: (URL) -> Bool
    ) -> [DiscoveredSession] {
        guard FileManager.default.fileExists(atPath: rootURL.path),
              let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let cutoff = now.addingTimeInterval(-maxAge)
        var candidates: [(url: URL, modifiedAt: Date)] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  shouldInclude(fileURL),
                  let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }

            let modifiedAt = values.contentModificationDate ?? .distantPast
            guard modifiedAt >= cutoff else { continue }
            candidates.append((fileURL, modifiedAt))
        }

        return candidates
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(maxFiles)
            .compactMap { discoverProviderSession(at: $0.url, provider: provider, modifiedAt: $0.modifiedAt) }
    }

    private func discoverProviderSession(at url: URL, provider: AgentProvider, modifiedAt: Date?) -> DiscoveredSession? {
        let metadata = AgentTranscriptParser.extractMetadata(at: url.path, provider: provider)
        let sessionID = metadata.sessionID ?? url.deletingPathExtension().lastPathComponent
        let cwd = metadata.cwd ?? inferWorkspacePath(from: url, provider: provider) ?? FileManager.default.homeDirectoryForCurrentUser.path
        let turns = AgentTranscriptParser.parseTurns(at: url.path, provider: provider)
        let terminalDiscovery = CodexTerminalDiscovery()
        var insights = CodexSessionTranscriptInsights()

        if let sample = try? String(contentsOf: url, encoding: .utf8) {
            let lines = sample.split(whereSeparator: \.isNewline).prefix(120).map(String.init)
            insights = terminalDiscovery.inspect(lines: lines, sessionID: sessionID, cwd: cwd, transcriptPath: url.path)
        }

        return DiscoveredSession(
            id: sessionID,
            provider: provider,
            cwd: cwd,
            title: SessionSnapshot.title(for: cwd, provider: provider),
            transcriptPath: url.path,
            jumpTarget: insights.jumpTarget,
            assistantSummary: metadata.assistantSummary ?? turns.last(where: { $0.role == .assistant })?.text,
            sessionSurface: insights.sessionSurface,
            modifiedAt: modifiedAt
        )
    }

    private func inferWorkspacePath(from url: URL, provider: AgentProvider) -> String? {
        switch provider {
        case .claudeCode, .antigravity, .conductor:
            let projectDir = url.deletingLastPathComponent().lastPathComponent
            return decodeProjectDirectory(projectDir)
        case .cursor:
            let components = url.pathComponents
            guard let projectsIndex = components.firstIndex(of: "projects"),
                  projectsIndex + 1 < components.count else {
                return nil
            }
            return decodeProjectDirectory(components[projectsIndex + 1])
        case .codex:
            return nil
        }
    }

    private func decodeProjectDirectory(_ encoded: String) -> String? {
        var normalized = encoded
        if normalized.hasPrefix("-") {
            normalized = "/" + String(normalized.dropFirst())
        }
        let path = normalized.replacingOccurrences(of: "-", with: "/")
        if FileManager.default.fileExists(atPath: path) {
            return path
        }

        return resolveHyphenEncodedProjectPath(encoded)
    }

    private func resolveHyphenEncodedProjectPath(_ encoded: String) -> String? {
        guard encoded.hasPrefix("-") else {
            return nil
        }

        let parts = String(encoded.dropFirst()).split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty else {
            return nil
        }

        var index = 0
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        while index < parts.count {
            var resolved: (url: URL, nextIndex: Int)?

            for nextIndex in stride(from: parts.count, through: index + 1, by: -1) {
                let component = parts[index..<nextIndex].joined(separator: "-")
                guard !component.isEmpty else { continue }
                let candidate = current.appendingPathComponent(component, isDirectory: true)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    resolved = (candidate, nextIndex)
                    break
                }
            }

            guard let resolved else {
                return nil
            }

            current = resolved.url
            index = resolved.nextIndex
        }

        return current.path
    }

    private func preferSession(_ lhs: DiscoveredSession, _ rhs: DiscoveredSession) -> DiscoveredSession {
        let lhsIsStored = isStoredSession(lhs)
        let rhsIsStored = isStoredSession(rhs)
        if lhsIsStored != rhsIsStored {
            let native = lhsIsStored ? rhs : lhs
            let stored = lhsIsStored ? lhs : rhs
            return native.fillingGaps(from: stored)
        }

        if lhs.provider == .codex, rhs.provider != .codex {
            return lhs
        }
        if rhs.provider == .codex, lhs.provider != .codex {
            return rhs
        }
        return lhs
    }

    private func isStoredSession(_ session: DiscoveredSession) -> Bool {
        session.transcriptPath.hasPrefix(sessionStore.rootURL.path)
    }

    func discoverSession(at url: URL, modifiedAt: Date? = nil) -> DiscoveredSession? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }

        defer { try? handle.close() }

        let data = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        guard !data.isEmpty else {
            return nil
        }

        let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map { String($0) }
        var sessionID: String?
        var cwd: String?
        var insights = CodexSessionTranscriptInsights()
        var sessionSurface: CodexSessionSurface = .unknown

        for line in lines {
            guard let object = jsonObject(for: line),
                  let type = object["type"] as? String else {
                continue
            }

            if type == "session_meta" {
                let payload = object["payload"] as? [String: Any] ?? [:]
                sessionID = payload["id"] as? String
                cwd = payload["cwd"] as? String
                sessionSurface = sessionSurface.merged(with: surface(fromSessionMetaPayload: payload))
                if let sessionID, let cwd {
                    insights.merge(terminalDiscovery.inspect(object: object, sessionID: sessionID, cwd: cwd, transcriptPath: url.path))
                }
                continue
            }

            guard let sessionID, let cwd else {
                continue
            }

            insights.merge(terminalDiscovery.inspect(object: object, sessionID: sessionID, cwd: cwd, transcriptPath: url.path))
        }

        guard let sessionID, let cwd else {
            return nil
        }

        let turns = AgentTranscriptParser.parseTurns(at: url.path, provider: .codex)

        return DiscoveredSession(
            id: sessionID,
            provider: .codex,
            cwd: cwd,
            title: SessionSnapshot.title(for: cwd, provider: .codex),
            transcriptPath: url.path,
            jumpTarget: insights.jumpTarget,
            assistantSummary: insights.assistantSummary ?? turns.last(where: { $0.role == .assistant })?.text,
            sessionSurface: sessionSurface.merged(with: insights.sessionSurface),
            modifiedAt: modifiedAt ?? transcriptModificationDate(at: url)
        )
    }

    private func transcriptModificationDate(at url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil
    }

    private func surface(fromSessionMetaPayload payload: [String: Any]) -> CodexSessionSurface {
        let source = (payload["source"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let originator = (payload["originator"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if originator?.contains("desktop") == true || source == "vscode" || source == "app-server" {
            return .codexApp
        }

        if source == "cli" || source == "codex-exec" {
            return .terminal
        }

        return .unknown
    }
}
