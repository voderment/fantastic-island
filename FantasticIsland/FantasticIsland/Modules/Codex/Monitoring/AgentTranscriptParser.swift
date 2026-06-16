import Foundation

struct AgentTranscriptTurn: Identifiable, Equatable, Codable {
    enum Role: String, Codable {
        case user
        case assistant
        case tool
        case system
    }

    let id: String
    var role: Role
    var text: String
    var toolName: String?

    init(id: String = UUID().uuidString, role: Role, text: String, toolName: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.toolName = toolName
    }
}

struct AgentTranscriptParser {
    static let maxTurns = 48
    static let maxTurnCharacters = 4_000

    static func parseTurns(at path: String, provider: AgentProvider) -> [AgentTranscriptTurn] {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .utf8),
              !content.isEmpty else {
            return []
        }

        let lines = content.split(whereSeparator: \.isNewline).map(String.init)
        if let storedTurns = parseStoredHookLines(lines), !storedTurns.isEmpty {
            return Array(storedTurns.suffix(maxTurns))
        }

        let turns: [AgentTranscriptTurn]

        switch provider {
        case .codex:
            turns = parseCodexLines(lines)
        case .claudeCode, .antigravity, .conductor:
            turns = parseClaudeLikeLines(lines)
        case .cursor:
            turns = parseCursorLines(lines)
        }

        return Array(turns.suffix(maxTurns))
    }

    static func extractMetadata(at path: String, provider: AgentProvider) -> (sessionID: String?, cwd: String?, assistantSummary: String?) {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]),
              !data.isEmpty else {
            return (nil, nil, nil)
        }

        let sample = String(decoding: data.prefix(96 * 1024), as: UTF8.self)
        let lines = sample.split(whereSeparator: \.isNewline).prefix(80).map(String.init)

        if let metadata = extractStoredHookMetadata(lines) {
            return metadata
        }

        var sessionID: String?
        var cwd: String?
        var assistantSummary: String?

        for line in lines {
            guard let object = jsonObject(for: line) else { continue }

            if sessionID == nil {
                sessionID =
                    object["sessionId"] as? String
                    ?? object["sessionID"] as? String
                    ?? object["session_id"] as? String
                    ?? (object["payload"] as? [String: Any])?["id"] as? String
            }

            if cwd == nil {
                cwd =
                    object["cwd"] as? String
                    ?? object["workspacePath"] as? String
                    ?? (object["payload"] as? [String: Any])?["cwd"] as? String
            }

            if assistantSummary == nil {
                let turns = switch provider {
                case .codex:
                    parseCodexLines([line])
                case .claudeCode, .antigravity, .conductor:
                    parseClaudeLikeLines([line])
                case .cursor:
                    parseCursorLines([line])
                }
                assistantSummary = turns.last(where: { $0.role == .assistant })?.text
            }

            if sessionID != nil, cwd != nil, assistantSummary != nil {
                break
            }
        }

        return (sessionID, cwd, assistantSummary)
    }

    private static func extractStoredHookMetadata(_ lines: [String]) -> (sessionID: String?, cwd: String?, assistantSummary: String?)? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = lines.compactMap {
            try? decoder.decode(AgentStoredSessionRecord.self, from: Data($0.utf8))
        }
        guard !records.isEmpty else { return nil }

        let latest = records.last?.payload
        let assistantSummary = records.reversed().compactMap(\.payload.assistantSummary).first
        return (latest?.sessionID, latest?.cwd, assistantSummary)
    }

    private static func parseStoredHookLines(_ lines: [String]) -> [AgentTranscriptTurn]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var turns: [AgentTranscriptTurn] = []
        var decodedAnyRecord = false

        for line in lines {
            guard let record = try? decoder.decode(AgentStoredSessionRecord.self, from: Data(line.utf8)) else {
                continue
            }

            decodedAnyRecord = true
            let payload = record.payload
            switch payload.hookEventName {
            case .sessionStart:
                if let prompt = payload.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !prompt.isEmpty,
                   !isInternalSupportText(prompt) {
                    turns.append(AgentTranscriptTurn(
                        id: "\(payload.sessionID)-\(record.timestamp.timeIntervalSince1970)-start",
                        role: .user,
                        text: clip(prompt)
                    ))
                }
            case .userPromptSubmit:
                if let prompt = payload.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !prompt.isEmpty,
                   !isInternalSupportText(prompt) {
                    turns.append(AgentTranscriptTurn(
                        id: "\(payload.sessionID)-\(record.timestamp.timeIntervalSince1970)-prompt",
                        role: .user,
                        text: clip(prompt)
                    ))
                }
            case .preToolUse, .permissionRequest:
                let text = payload.toolInput?.command
                    ?? payload.toolInput?.description
                    ?? payload.prompt
                    ?? payload.toolName
                if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    turns.append(AgentTranscriptTurn(
                        id: "\(payload.sessionID)-\(record.timestamp.timeIntervalSince1970)-tool",
                        role: .tool,
                        text: clip(text),
                        toolName: payload.toolName
                    ))
                }
            case .postToolUse, .stop:
                if let summary = payload.assistantSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !summary.isEmpty {
                    turns.append(AgentTranscriptTurn(
                        id: "\(payload.sessionID)-\(record.timestamp.timeIntervalSince1970)-assistant",
                        role: .assistant,
                        text: clip(summary)
                    ))
                }
            }
        }

        return decodedAnyRecord ? turns : nil
    }

    private static func parseCodexLines(_ lines: [String]) -> [AgentTranscriptTurn] {
        var turns: [AgentTranscriptTurn] = []

        for line in lines {
            guard let object = jsonObject(for: line),
                  let type = object["type"] as? String else {
                continue
            }

            switch type {
            case "response_item":
                let payload = object["payload"] as? [String: Any] ?? [:]
                let role = (payload["role"] as? String)?.lowercased()
                if role == "user", let text = extractText(from: payload), !isInternalSupportText(text) {
                    turns.append(AgentTranscriptTurn(role: .user, text: clip(text)))
                } else if role == "assistant", let text = extractText(from: payload) {
                    turns.append(AgentTranscriptTurn(role: .assistant, text: clip(text)))
                }
            case "event_msg":
                let payload = object["payload"] as? [String: Any] ?? [:]
                switch payload["type"] as? String {
                case "user_message":
                    if let text = extractText(from: payload), !isInternalSupportText(text) {
                        turns.append(AgentTranscriptTurn(role: .user, text: clip(text)))
                    }
                case "agent_message":
                    if let text = extractText(from: payload) {
                        turns.append(AgentTranscriptTurn(role: .assistant, text: clip(text)))
                    }
                default:
                    break
                }
            default:
                break
            }
        }

        return turns
    }

    private static func parseClaudeLikeLines(_ lines: [String]) -> [AgentTranscriptTurn] {
        var turns: [AgentTranscriptTurn] = []

        for line in lines {
            guard let object = jsonObject(for: line) else { continue }

            if object["type"] as? String == "attachment" {
                continue
            }

            if let type = object["type"] as? String, type == "queue-operation" {
                continue
            }

            if let role = object["role"] as? String,
               let message = object["message"] as? [String: Any],
               let text = extractText(from: message),
               !text.isEmpty {
                switch role.lowercased() {
                case "user":
                    guard !isInternalSupportText(text) else { continue }
                    turns.append(AgentTranscriptTurn(role: .user, text: clip(text)))
                case "assistant":
                    turns.append(AgentTranscriptTurn(role: .assistant, text: clip(text)))
                default:
                    break
                }
                continue
            }

            if let type = object["type"] as? String {
                switch type {
                case "user":
                    if let message = object["message"] as? [String: Any],
                       let text = extractText(from: message),
                       !isInternalSupportText(text) {
                        turns.append(AgentTranscriptTurn(role: .user, text: clip(text)))
                    }
                case "assistant":
                    if let message = object["message"] as? [String: Any],
                       let text = extractText(from: message) {
                        turns.append(AgentTranscriptTurn(role: .assistant, text: clip(text)))
                    }
                case "tool_use", "tool_result":
                    let toolName = object["name"] as? String ?? object["tool_name"] as? String
                    let text = extractText(from: object) ?? object["summary"] as? String
                    if let text, !text.isEmpty {
                        turns.append(AgentTranscriptTurn(role: .tool, text: clip(text), toolName: toolName))
                    }
                default:
                    break
                }
            }
        }

        return turns
    }

    private static func parseCursorLines(_ lines: [String]) -> [AgentTranscriptTurn] {
        var turns: [AgentTranscriptTurn] = []

        for line in lines {
            guard let object = jsonObject(for: line),
                  let role = object["role"] as? String,
                  let message = object["message"] as? [String: Any],
                  let text = extractCursorMessageText(message),
                  !text.isEmpty else {
                continue
            }

            switch role.lowercased() {
            case "user":
                guard !isInternalSupportText(text) else { continue }
                turns.append(AgentTranscriptTurn(role: .user, text: clip(text)))
            case "assistant":
                turns.append(AgentTranscriptTurn(role: .assistant, text: clip(text)))
            default:
                break
            }
        }

        return turns
    }

    private static func extractCursorMessageText(_ message: [String: Any]) -> String? {
        guard let content = message["content"] else { return nil }

        if let text = content as? String {
            return sanitizeUserFacingText(text)
        }

        guard let parts = content as? [[String: Any]] else { return nil }

        let chunks = parts.compactMap { part -> String? in
            guard (part["type"] as? String) == "text",
                  let text = part["text"] as? String else {
                return nil
            }
            return text
        }

        let joined = chunks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : sanitizeUserFacingText(joined)
    }

    private static func extractText(from dictionary: [String: Any]) -> String? {
        if let text = dictionary["text"] as? String, !text.isEmpty {
            return sanitizeUserFacingText(text)
        }

        if let content = dictionary["content"] as? String, !content.isEmpty {
            return sanitizeUserFacingText(content)
        }

        if let content = dictionary["content"] as? [[String: Any]] {
            let chunks = content.compactMap { item -> String? in
                if let text = item["text"] as? String, !text.isEmpty {
                    return text
                }
                if let text = item["content"] as? String, !text.isEmpty {
                    return text
                }
                return nil
            }
            let joined = chunks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : sanitizeUserFacingText(joined)
        }

        if let message = dictionary["message"] as? [String: Any],
           let nested = extractText(from: message) {
            return nested
        }

        return nil
    }

    private static func sanitizeUserFacingText(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("<user_query>"), cleaned.contains("</user_query>") {
            cleaned = cleaned
                .replacingOccurrences(of: "<user_query>", with: "")
                .replacingOccurrences(of: "</user_query>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleaned.hasPrefix("<system_instruction>"), let range = cleaned.range(of: "</system_instruction>") {
            cleaned = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    private static func isInternalSupportText(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("you are a helpful assistant")
            || normalized.contains("generate a concise ui title")
            || normalized.contains("bootstrap fetch")
            || normalized.hasPrefix("respond directly to the user's prompt")
    }

    private static func clip(_ text: String) -> String {
        guard text.count > maxTurnCharacters else { return text }
        let end = text.index(text.startIndex, offsetBy: maxTurnCharacters)
        return String(text[..<end]) + "…"
    }
}
