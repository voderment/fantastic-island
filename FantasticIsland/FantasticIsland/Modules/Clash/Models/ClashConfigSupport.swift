import Darwin
import Foundation

enum ClashConfigSupport {
    static let builtInDefaultControllerPort = 9090
    static let builtInDefaultMixedPort = 7890
    static let builtInDefaultDNSPort = 8853
    static let builtInUIRootDirectoryName = "ui"
    static let builtInUIName = "metacubexd"

    static func defaultAPIBaseURL() -> URL {
        let defaults = UserDefaults.standard.persistentDomain(forName: "com.west2online.ClashXPro")
        let port = defaults?["apiPort"] as? Int ?? 9090
        return URL(string: "http://127.0.0.1:\(port)")!
    }

    static func builtInControllerAddress(port: Int = builtInDefaultControllerPort) -> String {
        "127.0.0.1:\(port)"
    }

    static func builtInAPIBaseURL(controllerPort: Int = builtInDefaultControllerPort) -> URL {
        URL(string: "http://\(builtInControllerAddress(port: controllerPort))")!
    }

    static func builtInUIBaseURL(controllerPort: Int = builtInDefaultControllerPort) -> URL {
        builtInAPIBaseURL(controllerPort: controllerPort).appendingPathComponent("ui")
    }

    static func normalizedPath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return NSString(string: trimmed).expandingTildeInPath
    }

    static func validExecutablePath(from path: String?) -> String? {
        guard let path else {
            return nil
        }

        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    static func validFilePath(from path: String?) -> String? {
        guard let path, FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        return path
    }

    static func validURL(from string: String) -> URL? {
        guard !string.isEmpty else {
            return nil
        }

        return URL(string: string)
    }

    static func normalizedSecret(_ secret: String?) -> String? {
        guard let secret = secret?.trimmingCharacters(in: .whitespacesAndNewlines),
              !secret.isEmpty else {
            return nil
        }

        return secret
    }

    static func resolvedAttachAPISecret(
        explicitSecret: String?,
        configFilePath: String?
    ) -> String? {
        normalizedSecret(explicitSecret) ?? controllerSecret(fromConfigFileAt: configFilePath)
    }

    static func validLegacyRemoteProfileURL(from string: String) -> URL? {
        guard let url = validURL(from: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return url
    }

    static func validRemoteProfileURL(from string: String) -> URL? {
        validLegacyRemoteProfileURL(from: string)
    }

    static func configDirectoryPath(for configFilePath: String) -> String {
        let configURL = URL(fileURLWithPath: configFilePath)
        if configURL.deletingLastPathComponent().lastPathComponent == "profiles" {
            return configURL.deletingLastPathComponent().deletingLastPathComponent().path
        }

        return configURL.deletingLastPathComponent().path
    }

    static func urlFromConfigFile(at path: String?) -> URL? {
        guard let path, let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        let pattern = #"external-controller:\s*['"]?([0-9a-zA-Z\.\-:]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(match.range(at: 1), in: raw) else {
            return nil
        }

        let controller = String(raw[range])
        if controller.hasPrefix("http://") || controller.hasPrefix("https://") {
            return URL(string: controller)
        }

        return URL(string: "http://\(controller)")
    }

    static func controllerSecret(fromConfigFileAt path: String?) -> String? {
        guard let path,
              let rawConfig = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        return topLevelStringValue(for: "secret", in: rawConfig)
    }

    static func makeAPIRequest(
        base: URL,
        path: String,
        method: String,
        body: Data?,
        timeoutInterval: TimeInterval,
        authorizationSecret: String?
    ) -> URLRequest {
        var request = URLRequest(url: makeURL(base: base, path: path))
        request.httpMethod = method
        request.timeoutInterval = timeoutInterval
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let authorizationSecret = normalizedSecret(authorizationSecret) {
            request.setValue("Bearer \(authorizationSecret)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func encodePathComponent(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func encodeQueryItem(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&?+")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func makeURL(base: URL, path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let url = URL(string: trimmed, relativeTo: base) {
            return url.absoluteURL
        }

        return base.appendingPathComponent(trimmed)
    }

    static func doubleValue(for key: String, in object: [String: Any]) -> Double {
        if let value = object[key] as? Double {
            return value
        }
        if let value = object[key] as? Int {
            return Double(value)
        }
        if let value = object[key] as? NSNumber {
            return value.doubleValue
        }
        return 0
    }

    static func fetchProfileText(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/yaml, text/yaml, text/plain, */*", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw ClashModuleError.httpStatus(httpResponse.statusCode)
        }

        let text = String(decoding: data, as: UTF8.self)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ClashModuleError.emptySubscription
        }

        return trimmedText
    }

    static func normalizedProfileSnapshot(from rawConfig: String) throws -> String {
        let trimmedConfig = rawConfig
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedConfig.isEmpty else {
            throw ClashModuleError.emptySubscription
        }

        let normalizedSource: String
        if looksLikeClashConfig(trimmedConfig) {
            normalizedSource = trimmedConfig
        } else if let decodedConfig = decodedBase64Subscription(from: trimmedConfig),
                  looksLikeClashConfig(decodedConfig) {
            normalizedSource = decodedConfig
        } else {
            throw ClashModuleError.unsupportedSubscriptionFormat
        }

        let normalizedSnapshot = normalizingQuotedNumericScalars(in: normalizedSource)
        return normalizedSnapshot.hasSuffix("\n") ? normalizedSnapshot : normalizedSnapshot + "\n"
    }

    static func generatedBuiltInRuntimeConfig(
        from snapshot: String,
        controllerPort: Int = builtInDefaultControllerPort,
        portOverrides: ClashPortSnapshot = ClashModuleSettings.managedPortOverrides,
        captureMode: ClashManagedCaptureMode = ClashModuleSettings.managedCaptureMode,
        tunOptions: ClashManagedTunOptions = ClashModuleSettings.currentManagedTunOptions(),
        dnsPort: Int = builtInDefaultDNSPort
    ) throws -> String {
        let normalizedSnapshot = try normalizedProfileSnapshot(from: snapshot)
        let strippedKeys: Set<String> = [
            "external-controller",
            "external-ui",
            "external-ui-name",
            "external-ui-url",
            "secret",
            "tun",
            "port",
            "socks-port",
            "mixed-port",
            "redir-port",
            "tproxy-port",
            "allow-lan",
            "bind-address",
        ]
        let sanitizedSnapshot = rewritingManagedDNSListen(
            in: strippingTopLevelKeys(strippedKeys, from: normalizedSnapshot),
            listenAddress: "127.0.0.1:\(dnsPort)",
            insertIfMissing: captureMode == .tun
        )

        var bootstrapLines: [String] = []
        bootstrapLines.append("mixed-port: \(portOverrides.mixedPort ?? builtInDefaultMixedPort)")
        if let httpPort = portOverrides.httpPort {
            bootstrapLines.append("port: \(httpPort)")
        }
        if let socksPort = portOverrides.socksPort {
            bootstrapLines.append("socks-port: \(socksPort)")
        }
        bootstrapLines.append("allow-lan: false")
        bootstrapLines.append("external-controller: \(builtInControllerAddress(port: controllerPort))")
        bootstrapLines.append("external-ui: \(builtInUIRootDirectoryName)")
        bootstrapLines.append("external-ui-name: \(builtInUIName)")
        if !hasTopLevelKey("mode", in: sanitizedSnapshot) {
            bootstrapLines.append("mode: rule")
        }
        if !hasTopLevelKey("log-level", in: sanitizedSnapshot) {
            bootstrapLines.append("log-level: info")
        }
        if captureMode == .tun, !hasTopLevelKey("dns", in: sanitizedSnapshot) {
            bootstrapLines.append(contentsOf: defaultManagedDNSSection(listenPort: dnsPort))
        }
        bootstrapLines.append(contentsOf: builtInTunSection(for: captureMode, options: tunOptions))

        let mergedConfig = bootstrapLines.joined(separator: "\n") + "\n\n" + sanitizedSnapshot
        return mergedConfig.hasSuffix("\n") ? mergedConfig : mergedConfig + "\n"
    }

    static func defaultStarterProfileSnapshot() -> String {
        """
        mixed-port: \(builtInDefaultMixedPort)
        mode: rule
        log-level: info

        dns:
          enable: true
          ipv6: false
          listen: 127.0.0.1:\(builtInDefaultDNSPort)
          enhanced-mode: fake-ip
          nameserver:
            - 223.5.5.5
            - 119.29.29.29

        proxies: []

        proxy-groups:
          - name: Proxy
            type: select
            proxies:
              - DIRECT

        rules:
          - MATCH,Proxy
        """
    }

    static func hasConfigFileContent(at path: String?) -> Bool {
        guard let path,
              let rawConfig = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }

        return !rawConfig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func proxyGroupOrder(fromConfigFileAt path: String?) -> [String] {
        guard let path,
              let rawConfig = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }

        return proxyGroupOrder(fromYAML: rawConfig)
    }

    static func portSnapshot(fromConfigFileAt path: String?) -> ClashPortSnapshot {
        guard let path,
              let rawConfig = try? String(contentsOfFile: path, encoding: .utf8) else {
            return ClashPortSnapshot(httpPort: nil, socksPort: nil, mixedPort: nil)
        }

        return ClashPortSnapshot(
            httpPort: topLevelIntegerValue(for: "port", in: rawConfig),
            socksPort: topLevelIntegerValue(for: "socks-port", in: rawConfig),
            mixedPort: topLevelIntegerValue(for: "mixed-port", in: rawConfig)
        )
    }

    static func formatTrafficRate(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var value = max(0, bytesPerSecond)
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        return "\(formatTrafficRateValue(value, unitIndex: unitIndex)) \(units[unitIndex])"
    }

    private static func formatTrafficRateValue(_ value: Double, unitIndex: Int) -> String {
        if unitIndex == 0 || value >= 100 {
            return "\(Int(value.rounded()))"
        }

        let precision = value >= 10 ? 1 : 2
        var formatted = String(format: "%.\(precision)f", value)
        while formatted.contains("."), formatted.last == "0" {
            formatted.removeLast()
        }
        if formatted.last == "." {
            formatted.removeLast()
        }
        return formatted
    }

    static func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: NSLocalizedString(key, comment: ""),
            locale: .current,
            arguments: arguments
        )
    }

    static func formatByteCount(_ value: Int64?) -> String {
        guard let value, value > 0 else {
            return "--"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: value)
    }

    static func supportsLatencyTesting(for proxyName: String) -> Bool {
        let normalizedName = proxyName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return !normalizedName.isEmpty
            && normalizedName != "--"
            && normalizedName != "DIRECT"
            && normalizedName != "REJECT"
            && normalizedName != "REJECT-DROP"
            && normalizedName != "PASS"
            && normalizedName != "COMPATIBLE"
    }

    static func availableManagedControllerPort(
        preferredPort: Int = builtInDefaultControllerPort,
        excluding reservedPorts: Set<Int> = []
    ) -> Int {
        availableTCPPort(preferredPort: preferredPort, excluding: reservedPorts)
    }

    static func resolvedManagedPortOverrides(
        from overrides: ClashPortSnapshot,
        preferredMixedPort: Int = builtInDefaultMixedPort
    ) -> ClashPortSnapshot {
        var reservedPorts = Set<Int>()

        let mixedPort = resolvedManagedPort(
            preferred: overrides.mixedPort ?? preferredMixedPort,
            reservedPorts: &reservedPorts
        )

        let httpPort = overrides.httpPort.map {
            resolvedManagedPort(preferred: $0, reservedPorts: &reservedPorts)
        }
        let socksPort = overrides.socksPort.map {
            resolvedManagedPort(preferred: $0, reservedPorts: &reservedPorts)
        }

        return ClashPortSnapshot(httpPort: httpPort, socksPort: socksPort, mixedPort: mixedPort)
    }

    static func availableManagedDNSPort(
        preferredPort: Int = builtInDefaultDNSPort,
        excluding reservedPorts: Set<Int> = []
    ) -> Int {
        availableLoopbackPort(preferredPort: preferredPort, requiresUDP: true, excluding: reservedPorts)
    }

    private static func strippingTopLevelKeys(_ keys: Set<String>, from rawConfig: String) -> String {
        let lines = rawConfig
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var keptLines: [String] = []
        var skippedTopLevelKey: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if skippedTopLevelKey == nil {
                    keptLines.append(line)
                }
                continue
            }

            let isTopLevelLine = leadingWhitespaceCount(in: line) == 0
            if isTopLevelLine {
                let key = trimmed
                    .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
                    .first
                    .map(String.init)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()

                if let key, keys.contains(key) {
                    skippedTopLevelKey = key
                    continue
                }

                skippedTopLevelKey = nil
                keptLines.append(line)
                continue
            }

            if skippedTopLevelKey == nil {
                keptLines.append(line)
            }
        }

        return keptLines.joined(separator: "\n")
    }

    private static func builtInTunSection(
        for captureMode: ClashManagedCaptureMode,
        options: ClashManagedTunOptions
    ) -> [String] {
        switch captureMode {
        case .none, .systemProxy:
            return [
                "tun:",
                "  enable: false",
            ]
        case .tun:
            return [
                "tun:",
                "  enable: true",
                "  stack: \(options.stack.rawValue)",
                "  auto-route: \(options.autoRoute ? "true" : "false")",
                "  auto-detect-interface: true",
                "  strict-route: \(options.strictRoute ? "true" : "false")",
                "  endpoint-independent-nat: true",
                "  device: utun",
                "  dns-hijack:",
                "    - any:53",
                "    - tcp://any:53",
            ]
        }
    }

    private static func defaultManagedDNSSection(listenPort: Int) -> [String] {
        [
            "dns:",
            "  enable: true",
            "  ipv6: false",
            "  listen: 127.0.0.1:\(listenPort)",
            "  enhanced-mode: fake-ip",
            "  default-nameserver:",
            "    - 223.5.5.5",
            "    - 119.29.29.29",
            "  nameserver:",
            "    - 223.5.5.5",
            "    - 119.29.29.29",
        ]
    }

    private static func rewritingManagedDNSListen(
        in rawConfig: String,
        listenAddress: String,
        insertIfMissing: Bool
    ) -> String {
        let lines = rawConfig
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var rewrittenLines: [String] = []
        var dnsIndent: Int?
        var didRewriteListen = false

        func flushDNSListenIfNeeded() {
            guard let dnsIndent, !didRewriteListen, insertIfMissing else {
                return
            }
            rewrittenLines.append(String(repeating: " ", count: dnsIndent + 2) + "listen: \(listenAddress)")
            didRewriteListen = true
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let indent = leadingWhitespaceCount(in: line)

            if let currentDNSIndent = dnsIndent,
               !trimmed.isEmpty,
               indent <= currentDNSIndent {
                flushDNSListenIfNeeded()
                dnsIndent = nil
            }

            if dnsIndent == nil {
                let lowercasedTrimmed = trimmed.lowercased()
                if !trimmed.isEmpty, indent == 0, lowercasedTrimmed.hasPrefix("dns:") {
                    dnsIndent = indent
                    didRewriteListen = false
                    rewrittenLines.append(line)
                    continue
                }
            } else if trimmed.lowercased().hasPrefix("listen:") {
                rewrittenLines.append(String(repeating: " ", count: indent) + "listen: \(listenAddress)")
                didRewriteListen = true
                continue
            }

            rewrittenLines.append(line)
        }

        flushDNSListenIfNeeded()
        return rewrittenLines.joined(separator: "\n")
    }

    private static func normalizingQuotedNumericScalars(in rawConfig: String) -> String {
        let numericScalarKeys: Set<String> = [
            "port",
            "socks-port",
            "mixed-port",
            "redir-port",
            "tproxy-port",
        ]

        return rawConfig
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let separatorIndex = trimmedLine.firstIndex(of: ":") else {
                    return String(line)
                }

                let key = trimmedLine[..<separatorIndex]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard numericScalarKeys.contains(key) else {
                    return String(line)
                }

                let valueStartIndex = trimmedLine.index(after: separatorIndex)
                let rawValue = trimmedLine[valueStartIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
                guard rawValue.count >= 2,
                      let firstCharacter = rawValue.first,
                      let lastCharacter = rawValue.last,
                      (firstCharacter == "'" && lastCharacter == "'")
                        || (firstCharacter == "\"" && lastCharacter == "\"") else {
                    return String(line)
                }

                let unquotedValue = rawValue.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !unquotedValue.isEmpty,
                      unquotedValue.allSatisfy(\.isNumber),
                      let keyRange = line.range(of: "\(key):", options: [.caseInsensitive, .regularExpression]) else {
                    return String(line)
                }

                let indentation = line[..<keyRange.lowerBound]
                return "\(indentation)\(key): \(unquotedValue)"
            }
            .joined(separator: "\n")
    }

    private static func proxyGroupOrder(fromYAML rawConfig: String) -> [String] {
        let normalizedConfig = rawConfig.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalizedConfig.components(separatedBy: "\n")
        var isInsideProxyGroupsSection = false
        var proxyGroupsIndent: Int?
        var currentGroupIndent: Int?
        var expectsNameOnNextLine = false
        var orderedNames: [String] = []
        var seenNames = Set<String>()

        for rawLine in lines {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if !isInsideProxyGroupsSection {
                guard trimmedLine.hasPrefix("proxy-groups:") else {
                    continue
                }

                isInsideProxyGroupsSection = true
                proxyGroupsIndent = leadingWhitespaceCount(in: line)
                currentGroupIndent = nil
                expectsNameOnNextLine = false
                continue
            }

            guard let proxyGroupsIndent else {
                break
            }

            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }

            let indent = leadingWhitespaceCount(in: line)
            if indent <= proxyGroupsIndent {
                break
            }

            if indent > proxyGroupsIndent, trimmedLine == "-" {
                currentGroupIndent = indent
                expectsNameOnNextLine = true
                continue
            }

            if indent > proxyGroupsIndent, let name = proxyGroupName(fromListItemLine: trimmedLine) {
                if seenNames.insert(name).inserted {
                    orderedNames.append(name)
                }
                currentGroupIndent = indent
                expectsNameOnNextLine = false
                continue
            }

            if expectsNameOnNextLine,
               let currentGroupIndent,
               indent > currentGroupIndent,
               let name = proxyGroupName(fromPropertyLine: trimmedLine) {
                if seenNames.insert(name).inserted {
                    orderedNames.append(name)
                }
                expectsNameOnNextLine = false
            }
        }

        return orderedNames
    }

    private static func proxyGroupName(fromListItemLine line: String) -> String? {
        guard line.hasPrefix("-") else {
            return nil
        }

        let content = line.dropFirst().trimmingCharacters(in: .whitespaces)
        if let name = proxyGroupName(fromPropertyLine: content) {
            return name
        }

        guard content.hasPrefix("{"), content.hasSuffix("}") else {
            return nil
        }

        let inlineContent = String(content.dropFirst().dropLast())
        for component in inlineContent.split(separator: ",") {
            if let name = proxyGroupName(fromPropertyLine: component.trimmingCharacters(in: .whitespaces)) {
                return name
            }
        }

        return nil
    }

    private static func proxyGroupName(fromPropertyLine line: String) -> String? {
        guard line.hasPrefix("name:") else {
            return nil
        }

        let value = line
            .dropFirst("name:".count)
            .trimmingCharacters(in: .whitespaces)
        return unquotedYAMLScalar(value)
    }

    private static func unquotedYAMLScalar(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let unquoted: String
        if trimmed.count >= 2,
           let first = trimmed.first,
           let last = trimmed.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            let result = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? nil : result
        } else {
            unquoted = trimmed
        }

        let hashIndex = unquoted.firstIndex(of: "#")
        let scalar = hashIndex.map { String(unquoted[..<$0]) } ?? unquoted
        let result = scalar.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func leadingWhitespaceCount(in line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    private static func decodedBase64Subscription(from encodedText: String) -> String? {
        let compactEncodedText = encodedText
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let data = Data(base64Encoded: compactEncodedText),
              let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }

        let trimmedDecoded = decoded
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDecoded.isEmpty ? nil : trimmedDecoded
    }

    private static func looksLikeClashConfig(_ rawConfig: String) -> Bool {
        [
            "proxies",
            "proxy-groups",
            "proxy-providers",
            "rules",
            "rule-providers",
        ].contains { hasTopLevelKey($0, in: rawConfig) }
    }

    private static func hasTopLevelKey(_ key: String, in rawConfig: String) -> Bool {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        guard let regularExpression = try? NSRegularExpression(pattern: #"(?m)^\#(escapedKey):"#) else {
            return false
        }

        let range = NSRange(rawConfig.startIndex..., in: rawConfig)
        return regularExpression.firstMatch(in: rawConfig, range: range) != nil
    }

    private static func topLevelIntegerValue(for key: String, in rawConfig: String) -> Int? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        guard let regularExpression = try? NSRegularExpression(pattern: #"(?m)^\#(escapedKey):\s*(\d+)\s*$"#),
              let match = regularExpression.firstMatch(in: rawConfig, range: NSRange(rawConfig.startIndex..., in: rawConfig)),
              let range = Range(match.range(at: 1), in: rawConfig) else {
            return nil
        }

        return Int(rawConfig[range])
    }

    private static func topLevelStringValue(for key: String, in rawConfig: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        guard let regularExpression = try? NSRegularExpression(pattern: #"(?m)^(\s*)\#(escapedKey):\s*(.+?)\s*$"#),
              let match = regularExpression.firstMatch(in: rawConfig, range: NSRange(rawConfig.startIndex..., in: rawConfig)),
              match.numberOfRanges >= 3,
              let indentRange = Range(match.range(at: 1), in: rawConfig),
              rawConfig[indentRange].isEmpty,
              let valueRange = Range(match.range(at: 2), in: rawConfig) else {
            return nil
        }

        return unquotedYAMLScalar(String(rawConfig[valueRange]))
    }

    private static func resolvedManagedPort(preferred: Int, reservedPorts: inout Set<Int>) -> Int {
        let port = availableTCPPort(preferredPort: preferred, excluding: reservedPorts)
        reservedPorts.insert(port)
        return port
    }

    private static func availableTCPPort(preferredPort: Int, excluding reservedPorts: Set<Int>) -> Int {
        availableLoopbackPort(preferredPort: preferredPort, requiresUDP: false, excluding: reservedPorts)
    }

    private static func availableLoopbackPort(
        preferredPort: Int,
        requiresUDP: Bool,
        excluding reservedPorts: Set<Int>
    ) -> Int {
        let lowerBound = max(1025, preferredPort)
        let candidates = Array(lowerBound...65535) + Array(1025..<lowerBound)
        for candidate in candidates {
            guard !reservedPorts.contains(candidate),
                  isPortAvailable(candidate, socketType: SOCK_STREAM) else {
                continue
            }
            if requiresUDP, !isPortAvailable(candidate, socketType: SOCK_DGRAM) {
                continue
            }
            return candidate
        }

        return preferredPort
    }

    private static func isPortAvailable(_ port: Int, socketType: Int32) -> Bool {
        let descriptor = socket(AF_INET, socketType, 0)
        guard descriptor >= 0 else {
            return false
        }
        defer { close(descriptor) }

        var reuseAddress: Int32 = 1
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride)) == 0
            }
        }
    }
}

struct EmptyAPIResponse: Decodable {}

enum ClashModuleError: LocalizedError {
    case httpStatus(Int)
    case invalidResponse
    case emptySubscription
    case unsupportedSubscriptionFormat
    case insecureSubscriptionURL
    case invalidManagedProxyPort
    case managedRuntimeAPIUnavailable
    case managedTunCaptureUnavailable
    case noBuiltInProfile
    case missingProfileSnapshot
    case importedFileUnavailable
    case lastBuiltInProfileDeletionDenied

    var errorDescription: String? {
        switch self {
        case let .httpStatus(code):
            return String(
                format: NSLocalizedString("HTTP %d", comment: ""),
                locale: .current,
                code
            )
        case .invalidResponse:
            return NSLocalizedString("Invalid API response", comment: "")
        case .emptySubscription:
            return NSLocalizedString("The subscription returned an empty response.", comment: "")
        case .unsupportedSubscriptionFormat:
            return NSLocalizedString(
                "The subscription must return a Clash or Mihomo YAML config. Convert non-YAML subscriptions upstream first.",
                comment: ""
            )
        case .insecureSubscriptionURL:
            return NSLocalizedString("Built-in subscriptions must use http:// or https://.", comment: "")
        case .invalidManagedProxyPort:
            return NSLocalizedString("No local Clash port is available for the selected managed capture mode.", comment: "")
        case .managedRuntimeAPIUnavailable:
            return NSLocalizedString("Core started but API did not become reachable.", comment: "")
        case .managedTunCaptureUnavailable:
            return NSLocalizedString(
                "Managed TUN started, but macOS traffic was not captured. Island's current TUN path is not usable on this machine yet.",
                comment: ""
            )
        case .noBuiltInProfile:
            return NSLocalizedString("Create or import a built-in profile first.", comment: "")
        case .missingProfileSnapshot:
            return NSLocalizedString("The selected built-in profile has no local snapshot yet.", comment: "")
        case .importedFileUnavailable:
            return NSLocalizedString("The original YAML file is no longer available for re-import.", comment: "")
        case .lastBuiltInProfileDeletionDenied:
            return NSLocalizedString("Keep at least one built-in profile in the library.", comment: "")
        }
    }
}
