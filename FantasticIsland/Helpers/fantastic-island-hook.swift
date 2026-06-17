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
