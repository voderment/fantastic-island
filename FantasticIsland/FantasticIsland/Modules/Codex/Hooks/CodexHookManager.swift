import Darwin
import Foundation

enum CodexHookManagerError: LocalizedError {
    case invalidHooksJSON
    case invalidConfigEncoding

    var errorDescription: String? {
        switch self {
        case .invalidHooksJSON:
            return "The existing Codex hooks file is not valid JSON."
        case .invalidConfigEncoding:
            return "The existing Codex config.toml is not valid UTF-8."
        }
    }
}

struct CodexHookManager {
    static let appSupportURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Fantastic Island", isDirectory: true)
    static let socketURL = appSupportURL.appendingPathComponent("hook-bridge.sock")
    static let helperURL = appSupportURL.appendingPathComponent("bin/fantastic-island-hook")

    private let codexDirectory: URL
    private let hooksURL: URL
    private let configURL: URL

    init(codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)) {
        self.codexDirectory = codexDirectory
        self.hooksURL = codexDirectory.appendingPathComponent("hooks.json")
        self.configURL = codexDirectory.appendingPathComponent("config.toml")
    }

    func status() throws -> HookInstallStatus {
        let command = hookCommand
        let featureEnabled = (try? String(contentsOf: configURL, encoding: .utf8).contains("codex_hooks = true")) ?? false
        let hooksInstalled = try hasManagedHooks(command: command)

        return featureEnabled && hooksInstalled ? .installed : .notInstalled
    }

    func install() throws {
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true, attributes: nil)
        try writeHelper()

        let configContents = try readConfigContents()
        let updatedConfig = enableCodexHooksFeature(in: configContents)
        try updatedConfig.write(to: configURL, atomically: true, encoding: .utf8)

        let data = FileManager.default.fileExists(atPath: hooksURL.path) ? try Data(contentsOf: hooksURL) : nil
        let updatedHooks = try installHooksJSON(existingData: data, hookCommand: hookCommand)
        if let updatedHooks {
            try updatedHooks.write(to: hooksURL, options: .atomic)
        }
    }

    func uninstall() throws {
        if FileManager.default.fileExists(atPath: configURL.path) {
            let configContents = try readConfigContents()
            let updatedConfig = disableCodexHooksFeatureIfPresent(in: configContents)
            try updatedConfig.write(to: configURL, atomically: true, encoding: .utf8)
        }

        guard FileManager.default.fileExists(atPath: hooksURL.path) else {
            return
        }

        let data = try Data(contentsOf: hooksURL)
        let updatedData = try uninstallHooksJSON(existingData: data, managedCommand: hookCommand)
        if let updatedData {
            try updatedData.write(to: hooksURL, options: .atomic)
        } else {
            try FileManager.default.removeItem(at: hooksURL)
        }
    }

    var hookCommand: String {
        shellQuote(Self.helperURL.path)
    }

    private static let managedEventNames = [
        "SessionStart",
        "PreToolUse",
        "PermissionRequest",
        "PostToolUse",
        "UserPromptSubmit",
        "Stop",
    ]

    private func hasManagedHooks(command: String) throws -> Bool {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else {
            return false
        }

        let data = try Data(contentsOf: hooksURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            throw CodexHookManagerError.invalidHooksJSON
        }

        for event in Self.managedEventNames {
            guard let groups = hooks[event] as? [[String: Any]] else {
                return false
            }

            let hasMatch = groups.contains { group in
                let hookEntries = group["hooks"] as? [[String: Any]] ?? []
                return hookEntries.contains { $0["command"] as? String == command }
            }
            if !hasMatch {
                return false
            }
        }

        return true
    }

    private func writeHelper() throws {
        let directory = Self.helperURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        try helperScript.write(to: Self.helperURL, atomically: true, encoding: .utf8)
        _ = Self.helperURL.path.withCString { chmod($0, 0o755) }
    }

    private func readConfigContents() throws -> String {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return ""
        }

        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            throw CodexHookManagerError.invalidConfigEncoding
        }

        return contents
    }

    private var helperScript: String {
        """
        #!/bin/sh
        SOCKET_PATH="$HOME/Library/Application Support/Fantastic Island/hook-bridge.sock"
        if [ ! -S "$SOCKET_PATH" ]; then
            exit 0
        fi
        /usr/bin/python3 -c 'import socket, sys; payload = sys.stdin.buffer.read(); sock = None
        try:
            if not payload:
                raise SystemExit(0)
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(40.0)
            sock.connect(sys.argv[1])
            sock.sendall(payload)
            sock.shutdown(socket.SHUT_WR)
            response = b""
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                response += chunk
            if response:
                sys.stdout.buffer.write(response)
        except Exception:
            pass
        finally:
            if sock is not None:
                try:
                    sock.close()
                except Exception:
                    pass' "$SOCKET_PATH" 2>/dev/null || exit 0
        """
    }

    private func installHooksJSON(existingData: Data?, hookCommand: String) throws -> Data? {
        var root = try loadRootObject(from: existingData)
        let existingHooks = root["hooks"] as? [String: Any] ?? [:]
        var hooksObject: [String: Any] = [:]

        for (eventName, value) in existingHooks {
            let groups = value as? [Any] ?? []
            let cleanedGroups = sanitizeForInstall(groups: groups, replacingCommand: hookCommand)
            if !cleanedGroups.isEmpty {
                hooksObject[eventName] = cleanedGroups
            }
        }

        let eventSpecs: [(name: String, matcher: String?)] = [
            ("SessionStart", "startup|resume"),
            ("PreToolUse", nil),
            ("PermissionRequest", nil),
            ("PostToolUse", nil),
            ("UserPromptSubmit", nil),
            ("Stop", nil),
        ]

        for spec in eventSpecs {
            let groups = hooksObject[spec.name] as? [Any] ?? []
            hooksObject[spec.name] = sanitizeForInstall(groups: groups, replacingCommand: hookCommand) + [managedGroup(matcher: spec.matcher, hookCommand: hookCommand)]
        }

        root["hooks"] = hooksObject
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private func uninstallHooksJSON(existingData: Data?, managedCommand: String) throws -> Data? {
        guard let existingData else {
            return nil
        }

        var root = try loadRootObject(from: existingData)
        var hooksObject = root["hooks"] as? [String: Any] ?? [:]

        for event in Self.managedEventNames {
            let groups = hooksObject[event] as? [Any] ?? []
            let cleaned = sanitize(groups: groups, managedCommand: managedCommand)
            if cleaned.isEmpty {
                hooksObject.removeValue(forKey: event)
            } else {
                hooksObject[event] = cleaned
            }
        }

        guard !hooksObject.isEmpty else {
            return nil
        }

        root["hooks"] = hooksObject
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data else {
            return [:]
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexHookManagerError.invalidHooksJSON
        }

        return object
    }

    private func sanitize(groups: [Any], managedCommand: String) -> [[String: Any]] {
        groups.compactMap { item in
            guard var group = item as? [String: Any] else {
                return nil
            }

            let hooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = hooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else {
                    return nil
                }
                return hook["command"] as? String == managedCommand ? nil : hook
            }

            guard !filteredHooks.isEmpty else {
                return nil
            }

            group["hooks"] = filteredHooks
            return group
        }
    }

    private func sanitizeForInstall(groups: [Any], replacingCommand: String) -> [[String: Any]] {
        groups.compactMap { item in
            guard var group = item as? [String: Any] else {
                return nil
            }

            let hooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = hooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else {
                    return nil
                }

                return hook["command"] as? String == replacingCommand ? nil : hook
            }

            guard !filteredHooks.isEmpty else {
                return nil
            }

            group["hooks"] = filteredHooks
            return group
        }
    }

    private func managedGroup(matcher: String?, hookCommand: String) -> [String: Any] {
        var group: [String: Any] = [
            "hooks": [[
                "type": "command",
                "command": hookCommand,
                "timeout": 45,
            ]]
        ]

        if let matcher {
            group["matcher"] = matcher
        }

        return group
    }

    private func enableCodexHooksFeature(in contents: String) -> String {
        var lines = contents.components(separatedBy: "\n")

        if let index = lineIndex(ofKey: "codex_hooks", inSection: "features", lines: lines) {
            lines[index] = "codex_hooks = true"
            return lines.joined(separator: "\n")
        }

        if let range = sectionRange(named: "features", lines: lines) {
            lines.insert("codex_hooks = true", at: range.upperBound)
            return lines.joined(separator: "\n")
        }

        if !lines.isEmpty, lines.last?.isEmpty == false {
            lines.append("")
        }
        lines.append("[features]")
        lines.append("codex_hooks = true")
        return lines.joined(separator: "\n")
    }

    private func disableCodexHooksFeatureIfPresent(in contents: String) -> String {
        var lines = contents.components(separatedBy: "\n")
        guard let index = lineIndex(ofKey: "codex_hooks", inSection: "features", lines: lines) else {
            return contents
        }

        lines.remove(at: index)
        return lines.joined(separator: "\n")
    }

    private func sectionRange(named section: String, lines: [String]) -> Range<Int>? {
        guard let headerIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[\(section)]" }) else {
            return nil
        }

        var endIndex = lines.count
        for index in (headerIndex + 1)..<lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                endIndex = index
                break
            }
        }

        return headerIndex..<endIndex
    }

    private func lineIndex(ofKey key: String, inSection section: String, lines: [String]) -> Int? {
        guard let range = sectionRange(named: section, lines: lines) else {
            return nil
        }

        for index in (range.lowerBound + 1)..<range.upperBound {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key) =") {
                return index
            }
        }

        return nil
    }

    private func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else {
            return "''"
        }

        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
