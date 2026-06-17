import Darwin
import Foundation

enum CodexHookManagerError: LocalizedError {
    case invalidHooksJSON
    case invalidConfigEncoding
    case helperBuildFailed(String)
    case statusLineBridgeSkipped(String)

    var errorDescription: String? {
        switch self {
        case .invalidHooksJSON:
            return "The existing Codex hooks file is not valid JSON."
        case .invalidConfigEncoding:
            return "The existing Codex config.toml is not valid UTF-8."
        case let .helperBuildFailed(message):
            return "The Swift hook helper could not be built: \(message)"
        case let .statusLineBridgeSkipped(provider):
            return "\(provider) already has a custom status line. Fantastic Island left it unchanged."
        }
    }
}

enum AgentHookInstallState: String, Equatable {
    case installed
    case missing
    case invalidConfig
}

enum AgentUsageBridgeState: String, Equatable {
    case managed
    case missing
    case custom
    case invalidConfig
    case unsupported
}

struct AgentHookProviderDiagnostic: Identifiable, Equatable {
    var provider: AgentProvider
    var configPath: String
    var hookState: AgentHookInstallState
    var usageBridgeState: AgentUsageBridgeState
    var installedEventCount: Int
    var expectedEventCount: Int

    var id: AgentProvider { provider }

    var hooksInstalled: Bool {
        hookState == .installed
    }

    var isHealthy: Bool {
        hooksInstalled && (usageBridgeState == .managed || usageBridgeState == .unsupported)
    }

    var statusText: String {
        switch (hookState, usageBridgeState) {
        case (.installed, .managed), (.installed, .unsupported):
            return "Ready"
        case (.installed, .custom):
            return "Custom quota"
        case (.installed, .missing):
            return "Quota missing"
        case (.missing, _):
            return "Hooks missing"
        case (.invalidConfig, _), (_, .invalidConfig):
            return "Invalid config"
        }
    }
}

struct AgentHookDiagnosticsReport: Equatable {
    var helperInstalled: Bool
    var socketExists: Bool
    var codexFeatureEnabled: Bool
    var providers: [AgentHookProviderDiagnostic]

    static let empty = AgentHookDiagnosticsReport(
        helperInstalled: false,
        socketExists: false,
        codexFeatureEnabled: false,
        providers: []
    )

    var readyProviderCount: Int {
        providers.filter(\.isHealthy).count
    }

    var expectedProviderCount: Int {
        providers.count
    }

    var hasProblems: Bool {
        !helperInstalled
            || providers.contains { !$0.isHealthy }
            || !codexFeatureEnabled
    }

    var compactSummaryText: String {
        if expectedProviderCount == 0 {
            return "Hooks unavailable"
        }

        if !helperInstalled {
            return "Helper missing"
        }

        if !codexFeatureEnabled {
            return "Codex hooks off"
        }

        if readyProviderCount == expectedProviderCount, codexFeatureEnabled {
            return "Hooks ready"
        }

        return "\(readyProviderCount)/\(expectedProviderCount) ready"
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

    func diagnostics() -> AgentHookDiagnosticsReport {
        let configText = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let featureEnabled = configText.contains("codex_hooks = true") || configText.contains("hooks = true")
        let helperInstalled = FileManager.default.fileExists(atPath: Self.helperURL.path)
        let socketExists = FileManager.default.fileExists(atPath: Self.socketURL.path)

        let providerDiagnostics = AgentProvider.hookInstallationProviders.map { provider in
            diagnostic(for: provider)
        }

        return AgentHookDiagnosticsReport(
            helperInstalled: helperInstalled,
            socketExists: socketExists,
            codexFeatureEnabled: featureEnabled,
            providers: providerDiagnostics
        )
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

        try installUsageBridges()
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

        try uninstallUsageBridges()
    }

    var hookCommand: String {
        hookCommand(provider: .codex, eventName: nil)
    }

    func ensureHelperInstalled() throws {
        try writeHelper()
    }

    func installUsageBridges() throws {
        try writeHelper()
        for provider in Self.statusLineUsageBridgeProviders {
            do {
                try installStatusLineUsageBridge(for: provider)
            } catch CodexHookManagerError.statusLineBridgeSkipped {
                continue
            }
        }
    }

    func uninstallUsageBridges() throws {
        for provider in Self.statusLineUsageBridgeProviders {
            try uninstallStatusLineUsageBridge(for: provider)
        }
    }

    func writeRemoteSetupScript() throws -> URL {
        try writeHelper()
        let url = Self.appSupportURL.appendingPathComponent("remote-ssh-setup.sh")
        let script = """
        #!/bin/sh
        set -eu

        REMOTE="${1:-}"
        if [ -z "$REMOTE" ]; then
          echo "usage: remote-ssh-setup.sh user@host" >&2
          exit 64
        fi

        ssh "$REMOTE" 'mkdir -p "$HOME/.local/bin"'
        scp "\(Self.helperURL.path)" "$REMOTE:$HOME/.local/bin/fantastic-island-hook"
        ssh "$REMOTE" 'chmod 755 "$HOME/.local/bin/fantastic-island-hook"'

        cat <<'EOF'
        Remote helper copied.

        Add the remote command below to Codex, Claude Code, Cursor, or Antigravity hooks on that host:
          ~/.local/bin/fantastic-island-hook --source codex --event Stop

        For SSH sessions back to this Mac, forward the local bridge socket directory or run Fantastic Island on the remote Mac.
        EOF
        """

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: url, atomically: true, encoding: .utf8)
        _ = url.path.withCString { chmod($0, 0o755) }
        return url
    }

    static let statusLineUsageBridgeProviders: [AgentProvider] = [.claudeCode, .antigravity]

    private func diagnostic(for provider: AgentProvider) -> AgentHookProviderDiagnostic {
        let url = configURL(for: provider)
        let expectedEventCount = provider.hookEvents.count

        guard FileManager.default.fileExists(atPath: url.path) else {
            return AgentHookProviderDiagnostic(
                provider: provider,
                configPath: url.path,
                hookState: .missing,
                usageBridgeState: usageBridgeState(for: provider, root: nil, isInvalidConfig: false),
                installedEventCount: 0,
                expectedEventCount: expectedEventCount
            )
        }

        do {
            let data = try Data(contentsOf: url)
            let root = try loadRootObject(from: data)
            let hooks = root["hooks"] as? [String: Any] ?? [:]
            let installedEventCount = provider.hookEvents.reduce(0) { count, event in
                guard let groups = hooks[event.name] as? [Any],
                      containsManagedCommand(groups: groups, provider: provider) else {
                    return count
                }

                return count + 1
            }

            return AgentHookProviderDiagnostic(
                provider: provider,
                configPath: url.path,
                hookState: installedEventCount == expectedEventCount ? .installed : .missing,
                usageBridgeState: usageBridgeState(for: provider, root: root, isInvalidConfig: false),
                installedEventCount: installedEventCount,
                expectedEventCount: expectedEventCount
            )
        } catch {
            return AgentHookProviderDiagnostic(
                provider: provider,
                configPath: url.path,
                hookState: .invalidConfig,
                usageBridgeState: usageBridgeState(for: provider, root: nil, isInvalidConfig: true),
                installedEventCount: 0,
                expectedEventCount: expectedEventCount
            )
        }
    }

    private func usageBridgeState(
        for provider: AgentProvider,
        root: [String: Any]?,
        isInvalidConfig: Bool
    ) -> AgentUsageBridgeState {
        guard Self.statusLineUsageBridgeProviders.contains(provider) else {
            return .unsupported
        }

        if isInvalidConfig {
            return .invalidConfig
        }

        guard let root else {
            return .missing
        }

        guard let statusLine = root["statusLine"] else {
            return .missing
        }

        return statusLineUsageBridgeIsManaged(statusLine, provider: provider) ? .managed : .custom
    }

    private func hasManagedHooks(provider: AgentProvider) throws -> Bool {
        let url = configURL(for: provider)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexHookManagerError.invalidHooksJSON
        }

        guard let hooks = root["hooks"] as? [String: Any] else {
            return false
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

        func usageContainer(in object: [String: Any]) -> [String: Any] {
            if let rateLimits = object["rate_limits"] as? [String: Any] {
                return rateLimits
            }
            if let limits = object["limits"] as? [String: Any] {
                return limits
            }
            if let usage = object["usage"] as? [String: Any] {
                return usage
            }
            if let payload = object["payload"] as? [String: Any] {
                if let rateLimits = payload["rate_limits"] as? [String: Any] {
                    return rateLimits
                }
                if let usage = payload["usage"] as? [String: Any] {
                    return usage
                }
            }
            return object
        }

        func doubleValue(_ value: Any?) -> Double? {
            switch value {
            case let value as Double:
                return value
            case let value as Float:
                return Double(value)
            case let value as Int:
                return Double(value)
            case let value as NSNumber:
                return value.doubleValue
            case let value as String:
                return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
            default:
                return nil
            }
        }

        func remainingPercent(in window: [String: Any]?) -> Int? {
            guard let window else {
                return nil
            }
            let used = doubleValue(window["used_percentage"])
                ?? doubleValue(window["used_percent"])
                ?? doubleValue(window["utilization"])
            let remaining = doubleValue(window["remaining_percentage"])
                ?? doubleValue(window["remaining_percent"])
                ?? doubleValue(window["pct_left"])
                ?? doubleValue(window["pct_remaining"])
                ?? used.map { 100 - $0 }
            return remaining.map { max(0, min(100, Int($0.rounded()))) }
        }

        func usageWindow(for keys: [String], in object: [String: Any]) -> [String: Any]? {
            for key in keys {
                if let window = object[key] as? [String: Any] {
                    return window
                }
            }
            return nil
        }

        func providerLabel(_ source: String) -> String {
            switch source {
            case "claude", "claudeCode":
                return "Claude"
            case "antigravity":
                return "AG"
            case "cursor":
                return "Cursor"
            case "codex":
                return "Codex"
            default:
                return "Agents"
            }
        }

        func compactValue(_ value: Int?) -> String {
            guard let value else {
                return "--"
            }
            return String(value) + "%"
        }

        func statusLineText(provider: String, object: [String: Any]) -> String {
            let container = usageContainer(in: object)
            let fiveHour = remainingPercent(in: usageWindow(
                for: ["five_hour", "fiveHour", "primary", "primary_limit", "five_hour_limit", "fiveHourLimit"],
                in: container
            ))
            let week = remainingPercent(in: usageWindow(
                for: ["seven_day", "sevenDay", "weekly", "week", "secondary", "secondary_limit", "weekly_limit", "weekLimit"],
                in: container
            ))
            return providerLabel(provider) + " 5H " + compactValue(fiveHour) + " W " + compactValue(week)
        }

        func writeUsageCache(provider: String, data: Data) {
            let directory = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/Fantastic Island/Agent Usage", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(provider).appendingPathExtension("json")
            try? data.write(to: url, options: .atomic)
        }

        func firstString(in object: [String: Any], keys: [String]) -> String? {
            for key in keys {
                if let value = object[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }

            if let payload = object["payload"] as? [String: Any] {
                return firstString(in: payload, keys: keys)
            }

            return nil
        }

        func sessionStoreProvider(for object: [String: Any]) -> String {
            let bundleIdentifier = firstString(in: object, keys: ["terminal_bundle_identifier", "bundleIdentifier"])?.lowercased()
            let terminalApp = firstString(in: object, keys: ["terminal_app", "terminalApp"])?.lowercased()
            let source = firstString(in: object, keys: ["source"])?.lowercased()

            if bundleIdentifier == "com.conductor.app" || terminalApp == "conductor" {
                return "conductor"
            }

            switch source {
            case "claude", "claudecode", "claude_code":
                return "claudeCode"
            case "cursor":
                return "cursor"
            case "antigravity":
                return "antigravity"
            case "conductor":
                return "conductor"
            default:
                return "codex"
            }
        }

        func safeFileName(_ value: String) -> String {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
            let scalars = value.unicodeScalars.map { scalar -> Character in
                allowed.contains(scalar) ? Character(scalar) : "-"
            }
            let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
            return result.isEmpty ? UUID().uuidString : result
        }

        func writeSessionRecord(_ object: [String: Any]) {
            guard let sessionID = firstString(in: object, keys: ["session_id", "sessionId", "sessionID", "id"]) else {
                return
            }

            let provider = sessionStoreProvider(for: object)
            let directory = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/Fantastic Island/Agent Sessions", isDirectory: true)
                .appendingPathComponent(provider, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let record: [String: Any] = [
                "schemaVersion": 1,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "provider": provider,
                "payload": object,
            ]

            guard var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else {
                return
            }
            data.append(UInt8(ascii: "\n"))

            let url = directory.appendingPathComponent(safeFileName(sessionID)).appendingPathExtension("jsonl")
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
                _ = try? handle.close()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }

        var input = FileHandle.standardInput.readDataToEndOfFile()

        if let usageProvider = argumentValue(after: "--usage-provider") {
            guard !input.isEmpty else {
                exit(0)
            }

            if var object = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] {
                object["source"] = object["source"] ?? usageProvider
                if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
                    writeUsageCache(provider: usageProvider, data: data)
                } else {
                    writeUsageCache(provider: usageProvider, data: input)
                }
                print(statusLineText(provider: usageProvider, object: object))
            } else {
                writeUsageCache(provider: usageProvider, data: input)
            }
            exit(0)
        }

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
            writeSessionRecord(object)
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

    private func installStatusLineUsageBridge(for provider: AgentProvider) throws {
        let url = configURL(for: provider)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        let data = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        let updatedData = try installStatusLineUsageBridgeJSON(existingData: data, provider: provider)
        try updatedData.write(to: url, options: .atomic)
    }

    private func uninstallStatusLineUsageBridge(for provider: AgentProvider) throws {
        let url = configURL(for: provider)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        let data = try Data(contentsOf: url)
        let updatedData = try uninstallStatusLineUsageBridgeJSON(existingData: data)
        try updatedData.write(to: url, options: .atomic)
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

    func installStatusLineUsageBridgeJSON(existingData: Data?, provider: AgentProvider) throws -> Data {
        var root = try loadRootObject(from: existingData)

        if let existingStatusLine = root["statusLine"],
           !statusLineUsageBridgeIsManaged(existingStatusLine) {
            throw CodexHookManagerError.statusLineBridgeSkipped(provider.displayName)
        }

        root["statusLine"] = managedStatusLine(provider: provider)
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    func uninstallStatusLineUsageBridgeJSON(existingData: Data?) throws -> Data {
        var root = try loadRootObject(from: existingData)

        if let existingStatusLine = root["statusLine"],
           statusLineUsageBridgeIsManaged(existingStatusLine) {
            root.removeValue(forKey: "statusLine")
        }

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

    private func managedStatusLine(provider: AgentProvider) -> [String: Any] {
        [
            "type": "command",
            "command": usageBridgeCommand(provider: provider),
            "padding": 0,
        ]
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

    private func statusLineUsageBridgeIsManaged(_ value: Any, provider: AgentProvider? = nil) -> Bool {
        if let command = value as? String {
            return isManagedUsageBridgeCommand(command, provider: provider)
        }

        if let object = value as? [String: Any] {
            return isManagedUsageBridgeCommand(object["command"] as? String, provider: provider)
        }

        return false
    }

    private func isManagedUsageBridgeCommand(_ command: String?, provider: AgentProvider? = nil) -> Bool {
        guard isManagedCommand(command) else {
            return false
        }

        guard let command, command.contains("--usage-provider") else {
            return false
        }

        guard let provider else {
            return true
        }

        return command.contains("--usage-provider \(provider.hookSource)")
            || command.contains("--usage-provider '\(provider.hookSource)'")
            || command.contains("--usage-provider \"\(provider.hookSource)\"")
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

    private func usageBridgeCommand(provider: AgentProvider) -> String {
        [
            shellQuote(Self.helperURL.path),
            "--usage-provider",
            shellQuote(provider.hookSource),
        ].joined(separator: " ")
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
