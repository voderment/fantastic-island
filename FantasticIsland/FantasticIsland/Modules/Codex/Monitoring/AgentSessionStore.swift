import Foundation

struct AgentStoredSessionRecord: Codable {
    var schemaVersion: Int
    var timestamp: Date
    var provider: AgentProvider
    var payload: CodexHookPayload

    init(timestamp: Date = .now, payload: CodexHookPayload) {
        self.schemaVersion = 1
        self.timestamp = timestamp
        self.provider = payload.agentProvider
        self.payload = payload
    }
}

struct AgentStoredSession: Equatable {
    var id: String
    var provider: AgentProvider
    var cwd: String
    var title: String
    var transcriptPath: String
    var jumpTarget: CodexTerminalJumpTarget?
    var assistantSummary: String?
    var sessionSurface: CodexSessionSurface
    var modifiedAt: Date
}

struct AgentSessionStore {
    static let defaultRootURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Fantastic Island", isDirectory: true)
        .appendingPathComponent("Agent Sessions", isDirectory: true)

    let rootURL: URL
    let maxFiles: Int
    let maxAge: TimeInterval

    init(
        rootURL: URL = Self.defaultRootURL,
        maxFiles: Int = 160,
        maxAge: TimeInterval = 86_400 * 14
    ) {
        self.rootURL = rootURL
        self.maxFiles = maxFiles
        self.maxAge = maxAge
    }

    func append(_ payload: CodexHookPayload, timestamp: Date = .now) throws -> URL {
        let url = transcriptURL(provider: payload.agentProvider, sessionID: payload.sessionID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var data = try JSONEncoder.agentSessionStoreEncoder.encode(AgentStoredSessionRecord(timestamp: timestamp, payload: payload))
        data.append(UInt8(ascii: "\n"))

        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: url, options: .atomic)
        }

        return url
    }

    func discoverRecentSessions(now: Date = .now) -> [AgentStoredSession] {
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
            .compactMap { loadSession(at: $0.url, modifiedAt: $0.modifiedAt) }
    }

    func loadSession(at url: URL, modifiedAt: Date? = nil) -> AgentStoredSession? {
        guard let records = loadRecords(at: url), let latest = records.last else {
            return nil
        }

        let payload = latest.payload
        let provider = payload.agentProvider
        let title = SessionSnapshot.title(for: payload.cwd, provider: provider)
        let assistantSummary = records.reversed().compactMap(\.payload.assistantSummary).first
        let jumpTarget = records.reversed().compactMap(\.payload.terminalJumpTarget).first
        let surface = records.reduce(CodexSessionSurface.unknown) { partial, record in
            partial.merged(with: record.payload.sessionSurface)
        }

        return AgentStoredSession(
            id: payload.sessionID,
            provider: provider,
            cwd: payload.cwd,
            title: title,
            transcriptPath: url.path,
            jumpTarget: jumpTarget,
            assistantSummary: assistantSummary,
            sessionSurface: surface,
            modifiedAt: modifiedAt ?? latest.timestamp
        )
    }

    func loadRecords(at url: URL) -> [AgentStoredSessionRecord]? {
        guard FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8),
              !content.isEmpty else {
            return nil
        }

        let decoder = JSONDecoder.agentSessionStoreDecoder
        return content
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                try? decoder.decode(AgentStoredSessionRecord.self, from: Data(String(line).utf8))
            }
    }

    private func transcriptURL(provider: AgentProvider, sessionID: String) -> URL {
        rootURL
            .appendingPathComponent(provider.rawValue, isDirectory: true)
            .appendingPathComponent(safeFileName(sessionID))
            .appendingPathExtension("jsonl")
    }

    private func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return result.isEmpty ? UUID().uuidString : result
    }
}

private extension JSONEncoder {
    static var agentSessionStoreEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var agentSessionStoreDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
