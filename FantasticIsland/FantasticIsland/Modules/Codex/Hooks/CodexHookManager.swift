import Darwin
import Foundation

enum CodexHookManagerError: LocalizedError {
    case invalidHooksJSON
    case invalidConfigEncoding
    case helperBuildFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidHooksJSON:
            return "The existing Codex hooks file is not valid JSON."
        case .invalidConfigEncoding:
            return "The existing Codex config.toml is not valid UTF-8."
        case let .helperBuildFailed(message):
            return "The Swift hook helper could not be built: \(message)"
        }
    }
}

struct CodexHookManager {
    static let appSupportURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Fantastic Island", isDirectory: true)
    static let socketURL = appSupportURL.appendingPathComponent("hook-bridge.sock")
    static let helperURL = appSupportURL.appendingPathComponent("bin/fantastic-island-hook")

    private let codexDirectory: URL
    private let homeDirectory: URL
    private let hooksURL: URL
    private let configURL: URL

    init(
        codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.codexDirectory = codexDirectory
        self.homeDirectory = homeDirectory
        self.hooksURL = codexDirectory.appendingPathComponent("hooks.json")
        self.configURL = codexDirectory.appendingPathComponent("config.toml")
    }

    func status() throws -> HookInstallStatus {
        let configText = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let featureEnabled = configText.contains("codex_hooks = true") || configText.contains("hooks = true")
        let hooksInstalled = try AgentProvider.hookInstallationProviders.allSatisfy { provider in
            try hasManagedHooks(provider: provider)
        }

        return featureEnabled && hooksInstalled ? .installed : .notInstalled
    }

    func install() throws {
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true, attributes: nil)
        try writeHelper()

        let configContents = try readConfigContents()
        let updatedConfig = enableCodexHooksFeature(in: configContents)
        try updatedConfig.write(to: configURL, atomically: true, encoding: .utf8)

        for provider in AgentProvider.hookInstallationProviders {
            try installHooks(for: provider)
        }
    }

    func uninstall() throws {
        if FileManager.default.fileExists(atPath: configURL.path) {
            let configContents = try readConfigContents()
            let updatedConfig = disableCodexHooksFeatureIfPresent(in: configContents)
            try updatedConfig.write(to: configURL, atomically: true, encoding: .utf8)
        }

        for provider in AgentProvider.hookInstallationProviders {
            try uninstallHooks(for: provider)
        }
    }

    var hookCommand: String {
        hookCommand(provider: .codex, eventName: nil)
    }

    private func hasManagedHooks(provider: AgentProvider) throws -> Bool {
        let url = configURL(for: provider)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            throw CodexHookManagerError.invalidHooksJSON
        }

        for event in provider.hookEvents {
            guard let groups = hooks[event.name] as? [Any] else {
                return false
            }

            let hasMatch = containsManagedCommand(groups: groups, provider: provider)
            if !hasMatch {
                return false
            }
        }

        return true
    }

    private func writeHelper() throws {
        let directory = Self.helperURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        if let bundledHelperURL = Bundle.main.url(forResource: "fantastic-island-hook", withExtension: nil, subdirectory: "Helpers") {
            if FileManager.default.fileExists(atPath: Self.helperURL.path) {
                try FileManager.default.removeItem(at: Self.helperURL)
            }
            try FileManager.default.copyItem(at: bundledHelperURL, to: Self.helperURL)
        } else {
            try buildHelperFromEmbeddedSource()
        }

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

    private func buildHelperFromEmbeddedSource() throws {
        let sourceURL = Self.appSupportURL.appendingPathComponent("bin/fantastic-island-hook.swift")
        try helperSource.write(to: sourceURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        process.arguments = [sourceURL.path, "-O", "-o", Self.helperURL.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw CodexHookManagerError.helperBuildFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CodexHookManagerError.helperBuildFailed(message?.isEmpty == false ? message! : "swiftc exited with \(process.terminationStatus)")
        }
    }

    private var helperSource: String {
        """
        import Darwin
        import Foundation

        func argumentValue(after flag: String) -> String? {
            let arguments = CommandLine.arguments
            guard let index = arguments.firstIndex(of: flag),
                  arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }

        func firstEnvironmentValue(_ keys: [String]) -> String? {
            for key in keys {
                if let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty {
                    return value
                }
            }
            return nil
        }

        func setIfMissing(_ key: String, _ value: String?, in object: inout [String: Any]) {
            guard object[key] == nil, let value, !value.isEmpty else {
                return
            }
            object[key] = value
        }

        var input = FileHandle.standardInput.readDataToEndOfFile()
        guard !input.isEmpty else {
            exit(0)
        }

        if var object = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] {
            if object["source"] == nil, let source = argumentValue(after: "--source") {
                object["source"] = source
            }
            if object["hook_event_name"] == nil, let event = argumentValue(after: "--event") {
                object["hook_event_name"] = event
            }
            setIfMissing("workspace_name", firstEnvironmentValue([
                "CONDUCTOR_WORKSPACE_NAME",
                "CONDUCTOR_PROJECT_NAME",
                "CONDUCTOR_REPO_NAME",
                "WORKSPACE_NAME",
            ]), in: &object)
            setIfMissing("workspace_id", firstEnvironmentValue([
                "CONDUCTOR_WORKSPACE_ID",
                "CONDUCTOR_PROJECT_ID",
                "CONDUCTOR_WORKTREE_ID",
            ]), in: &object)
            setIfMissing("conductor_port", firstEnvironmentValue([
                "CONDUCTOR_PORT",
                "CONDUCTOR_APP_PORT",
                "CONDUCTOR_SERVER_PORT",
            ]), in: &object)
            setIfMissing("conductor_url", firstEnvironmentValue([
                "CONDUCTOR_URL",
                "CONDUCTOR_APP_URL",
                "CONDUCTOR_SERVER_URL",
            ]), in: &object)
            if object["source"] as? String == "codex",
               firstEnvironmentValue(["CONDUCTOR_WORKSPACE_NAME", "CONDUCTOR_PORT", "CONDUCTOR_URL"]) != nil {
                object["terminal_app"] = object["terminal_app"] ?? "Conductor"
                object["terminal_bundle_identifier"] = object["terminal_bundle_identifier"] ?? "com.conductor.app"
            }
            if let data = try? JSONSerialization.data(withJSONObject: object) {
                input = data
            }
        }

        let socketPath = NSHomeDirectory() + "/Library/Application Support/Fantastic Island/hook-bridge.sock"
        guard socketPath.withCString({ access($0, F_OK) }) == 0 else {
            exit(0)
        }

        let fd = socket(AF_UNIX, Int32(SOCK_STREAM), 0)
        guard fd >= 0 else {
            exit(0)
        }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        let pathBytes = Array(socketPath.utf8.prefix(maxLength - 1))
        for (index, byte) in pathBytes.enumerated() {
            withUnsafeMutablePointer(to: &address.sun_path.0) {
                $0.withMemoryRebound(to: UInt8.self, capacity: maxLength) { pointer in
                    pointer[index] = byte
                }
            }
        }

        let addressLength = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count + 1)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, addressLength)
            }
        }
        guard connected == 0 else {
            exit(0)
        }

        input.withUnsafeBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                _ = Darwin.write(fd, baseAddress, bytes.count)
            }
        }
        _ = shutdown(fd, SHUT_WR)

        var buffer = [UInt8](repeating: 0, count: 4096)
        var response = Data()
        while true {
            let count = buffer.withUnsafeMutableBufferPointer { pointer in
                Darwin.read(fd, pointer.baseAddress, pointer.count)
            }
            if count <= 0 {
                break
            }
            response.append(contentsOf: buffer.prefix(count))
        }

        if !response.isEmpty {
            FileHandle.standardOutput.write(response)
        }
        """
    }

    private func installHooks(for provider: AgentProvider) throws {
        let url = configURL(for: provider)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        let data = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        let updatedHooks = try installHooksJSON(existingData: data, provider: provider)
        try updatedHooks.write(to: url, options: .atomic)
    }

    private func uninstallHooks(for provider: AgentProvider) throws {
        let url = configURL(for: provider)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        let data = try Data(contentsOf: url)
        let updatedData = try uninstallHooksJSON(existingData: data, provider: provider)
        if let updatedData {
            try updatedData.write(to: url, options: .atomic)
        } else {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func installHooksJSON(existingData: Data?, provider: AgentProvider) throws -> Data {
        var root = try loadRootObject(from: existingData)
        let existingHooks = root["hooks"] as? [String: Any] ?? [:]
        var hooksObject: [String: Any] = [:]

        for (eventName, value) in existingHooks {
            let groups = value as? [Any] ?? []
            let cleanedGroups = sanitizeManagedHooks(groups: groups)
            if !cleanedGroups.isEmpty {
                hooksObject[eventName] = cleanedGroups
            }
        }

        for event in provider.hookEvents {
            let groups = hooksObject[event.name] as? [Any] ?? []
            hooksObject[event.name] = sanitizeManagedHooks(groups: groups) + [
                managedGroup(provider: provider, event: event)
            ]
        }

        root["hooks"] = hooksObject
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private func uninstallHooksJSON(existingData: Data?, provider: AgentProvider) throws -> Data? {
        guard let existingData else {
            return nil
        }

        var root = try loadRootObject(from: existingData)
        var hooksObject = root["hooks"] as? [String: Any] ?? [:]

        for event in provider.hookEvents {
            let groups = hooksObject[event.name] as? [Any] ?? []
            let cleaned = sanitizeManagedHooks(groups: groups)
            if cleaned.isEmpty {
                hooksObject.removeValue(forKey: event.name)
            } else {
                hooksObject[event.name] = cleaned
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

    private func sanitizeManagedHooks(groups: [Any]) -> [[String: Any]] {
        groups.compactMap { item in
            guard var group = item as? [String: Any] else {
                return nil
            }

            if isManagedCommand(group["command"] as? String) {
                return nil
            }

            let hooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = hooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else {
                    return nil
                }

                return isManagedCommand(hook["command"] as? String) ? nil : hook
            }

            if hooks.isEmpty {
                return group
            }

            guard !filteredHooks.isEmpty else {
                return nil
            }

            group["hooks"] = filteredHooks
            return group
        }
    }

    private func managedGroup(provider: AgentProvider, event: AgentHookEventSpec) -> [String: Any] {
        let command = hookCommand(provider: provider, eventName: event.name)

        switch provider.hookFormat {
        case .cursorFlat:
            return ["command": command]
        case .codexNested, .claudeStyle:
            var hook: [String: Any] = [
                "type": "command",
                "command": command,
                "timeout": event.timeout,
            ]
            if event.isAsync {
                hook["async"] = true
            }

            var group: [String: Any] = ["hooks": [hook]]
            if provider == .codex && event.name == "SessionStart" {
                group["matcher"] = "startup|resume"
            }
            return group
        }
    }

    private func containsManagedCommand(groups: [Any], provider: AgentProvider) -> Bool {
        groups.contains { item in
            guard let group = item as? [String: Any] else {
                return false
            }

            if managedCommandMatches(group["command"] as? String, provider: provider) {
                return true
            }

            let hooks = group["hooks"] as? [[String: Any]] ?? []
            return hooks.contains { hook in
                managedCommandMatches(hook["command"] as? String, provider: provider)
            }
        }
    }

    private func managedCommandMatches(_ command: String?, provider: AgentProvider) -> Bool {
        guard isManagedCommand(command) else {
            return false
        }

        return command?.contains("--source \(provider.hookSource)") == true
            || command?.contains("--source '\(provider.hookSource)'") == true
            || command?.contains("--source \"\(provider.hookSource)\"") == true
    }

    private func isManagedCommand(_ command: String?) -> Bool {
        guard let command else {
            return false
        }

        return command.contains(Self.helperURL.path)
            || command.contains("fantastic-island-hook")
    }

    private func hookCommand(provider: AgentProvider, eventName: String?) -> String {
        var parts = [
            shellQuote(Self.helperURL.path),
            "--source",
            shellQuote(provider.hookSource),
        ]
        if let eventName {
            parts.append("--event")
            parts.append(shellQuote(eventName))
        }
        return parts.joined(separator: " ")
    }

    private func configURL(for provider: AgentProvider) -> URL {
        if provider == .codex {
            return hooksURL
        }

        return homeDirectory.appendingPathComponent(provider.configRelativePath)
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
