import Foundation

struct DiscoveredSession: Equatable {
    let id: String
    let cwd: String
    let title: String
    let transcriptPath: String
    let jumpTarget: CodexTerminalJumpTarget?
    let assistantSummary: String?
    let sessionSurface: CodexSessionSurface

    init(
        id: String,
        cwd: String,
        title: String,
        transcriptPath: String,
        jumpTarget: CodexTerminalJumpTarget? = nil,
        assistantSummary: String? = nil,
        sessionSurface: CodexSessionSurface = .unknown
    ) {
        self.id = id
        self.cwd = cwd
        self.title = title
        self.transcriptPath = transcriptPath
        self.jumpTarget = jumpTarget
        self.assistantSummary = assistantSummary
        self.sessionSurface = sessionSurface
    }
}

struct CodexSessionDiscovery {
    private let terminalDiscovery = CodexTerminalDiscovery()
    let rootURL: URL
    let maxFiles: Int
    let maxAge: TimeInterval

    init(
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions", isDirectory: true),
        maxFiles: Int = 80,
        maxAge: TimeInterval = 86_400 * 14
    ) {
        self.rootURL = rootURL
        self.maxFiles = maxFiles
        self.maxAge = maxAge
    }

    func discoverRecentSessions(now: Date = .now) -> [DiscoveredSession] {
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
                discoverSession(at: candidate.url)
            }
    }

    func discoverSession(at url: URL) -> DiscoveredSession? {
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

        return DiscoveredSession(
            id: sessionID,
            cwd: cwd,
            title: SessionSnapshot.title(for: cwd),
            transcriptPath: url.path,
            jumpTarget: insights.jumpTarget,
            assistantSummary: insights.assistantSummary,
            sessionSurface: sessionSurface.merged(with: insights.sessionSurface)
        )
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
