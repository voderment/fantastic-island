import Foundation

struct AgentProviderUsageCacheLoader {
    var usageDirectory: URL
    var fallbackURLsByProvider: [AgentProvider: [URL]]

    init(
        usageDirectory: URL = Self.defaultUsageDirectory,
        fallbackURLsByProvider: [AgentProvider: [URL]] = Self.defaultFallbackURLsByProvider
    ) {
        self.usageDirectory = usageDirectory
        self.fallbackURLsByProvider = fallbackURLsByProvider
    }

    static let defaultUsageDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Fantastic Island/Agent Usage", isDirectory: true)

    static let defaultFallbackURLsByProvider: [AgentProvider: [URL]] = [
        .claudeCode: [
            URL(fileURLWithPath: "/tmp/open-island-rl.json"),
            URL(fileURLWithPath: "/tmp/vibe-island-rl.json"),
        ],
        .cursor: [
            URL(fileURLWithPath: "/tmp/fantastic-island-cursor-rl.json"),
            URL(fileURLWithPath: "/tmp/cursor-rl.json"),
        ],
        .antigravity: [
            URL(fileURLWithPath: "/tmp/fantastic-island-antigravity-rl.json"),
            URL(fileURLWithPath: "/tmp/open-island-antigravity-rl.json"),
            URL(fileURLWithPath: "/tmp/antigravity-rl.json"),
        ],
    ]

    func loadUsage(for provider: AgentProvider) -> CodexQuotaSnapshot? {
        loadUsage(from: usageURLs(for: provider))
    }

    func loadUsageByProvider(for providers: [AgentProvider] = AgentProvider.allCases) -> [AgentProvider: CodexQuotaSnapshot] {
        providers.reduce(into: [:]) { result, provider in
            result[provider] = loadUsage(for: provider)
        }
    }

    func usageURLs(for provider: AgentProvider) -> [URL] {
        [Self.appOwnedUsageURL(for: provider, in: usageDirectory)] + (fallbackURLsByProvider[provider] ?? [])
    }

    static func appOwnedUsageURL(for provider: AgentProvider, in usageDirectory: URL = defaultUsageDirectory) -> URL {
        usageDirectory.appendingPathComponent(provider.rawValue).appendingPathExtension("json")
    }

    private func loadUsage(from urls: [URL]) -> CodexQuotaSnapshot? {
        let candidates = urls
            .compactMap { url -> (URL, Date)? in
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
                    ?? .distantPast
                return (url, modifiedAt)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.path > rhs.0.path
                }

                return lhs.1 > rhs.1
            }

        for (url, modifiedAt) in candidates {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let snapshot = Self.quotaSnapshot(from: object, capturedAt: modifiedAt) else {
                continue
            }

            return snapshot
        }

        return nil
    }

    static func quotaSnapshot(from object: [String: Any], capturedAt: Date = .now) -> CodexQuotaSnapshot? {
        let container = usageContainer(in: object)
        let fiveHour = usageWindow(
            for: ["five_hour", "fiveHour", "primary", "primary_limit", "five_hour_limit", "fiveHourLimit"],
            in: container
        ) ?? (nil, nil)
        let week = usageWindow(
            for: ["seven_day", "sevenDay", "weekly", "week", "secondary", "secondary_limit", "weekly_limit", "weekLimit"],
            in: container
        ) ?? (nil, nil)

        guard fiveHour.remainingPercent != nil || week.remainingPercent != nil else {
            return nil
        }

        return CodexQuotaSnapshot(
            fiveHourRemainingPercent: fiveHour.remainingPercent,
            weekRemainingPercent: week.remainingPercent,
            fiveHourResetAt: fiveHour.resetAt,
            weekResetAt: week.resetAt,
            capturedAt: capturedAt,
            sourceKind: .preferred
        )
    }

    private static func usageContainer(in object: [String: Any]) -> [String: Any] {
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

    private static func usageWindow(
        for keys: [String],
        in object: [String: Any]
    ) -> (remainingPercent: Int?, resetAt: Date?)? {
        for key in keys {
            if let window = object[key] as? [String: Any],
               let parsed = usageWindow(in: window) {
                return parsed
            }
        }

        return nil
    }

    private static func usageWindow(in window: [String: Any]) -> (remainingPercent: Int?, resetAt: Date?)? {
        let used = doubleValue(from: window["used_percentage"])
            ?? doubleValue(from: window["used_percent"])
            ?? doubleValue(from: window["utilization"])
        let remaining = doubleValue(from: window["remaining_percentage"])
            ?? doubleValue(from: window["remaining_percent"])
            ?? doubleValue(from: window["pct_left"])
            ?? doubleValue(from: window["pct_remaining"])
            ?? used.map { 100 - $0 }
        let boundedRemaining = remaining.map { max(0, min(100, Int($0.rounded()))) }
        let resetAt = parseFlexibleDate(window["resets_at"])
            ?? parseFlexibleDate(window["reset_at"])
            ?? parseFlexibleDate(window["resets_at_ms"])
            ?? parseFlexibleDate(window["reset_at_ms"])

        guard boundedRemaining != nil || resetAt != nil else {
            return nil
        }

        return (boundedRemaining, resetAt)
    }

    private static func doubleValue(from value: Any?) -> Double? {
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
}
