import Foundation
import Security

enum ClashModuleSettings {
    private static let modeKey = "clash.module.mode"
    static let builtInProfilesMigratedKey = "clash.module.builtin.profilesMigrated"
    private static let managedCoreBinaryPathKey = "clash.module.managed.coreBinaryPath"
    private static let managedConfigFilePathKey = "clash.module.managed.configFilePath"
    private static let managedSubscriptionURLKey = "clash.module.managed.subscriptionURL"
    private static let managedSubscriptionLastUpdatedAtKey = "clash.module.managed.subscriptionLastUpdatedAt"
    private static let attachConfigFilePathKey = "clash.module.attach.configFilePath"
    private static let attachAPIBaseURLKey = "clash.module.attach.apiBaseURL"
    private static let attachAPISecretAccount = "clash.module.attach.apiSecret"
    private static let builtInRuntimeWasRunningKey = "clash.module.builtin.runtimeWasRunning"
    private static let builtInSystemProxyEnabledKey = "clash.module.builtin.systemProxyEnabled"
    private static let managedHTTPPortKey = "clash.module.managed.port"
    private static let managedSocksPortKey = "clash.module.managed.socksPort"
    private static let managedMixedPortKey = "clash.module.managed.mixedPort"
    private static let managedDesiredRunningKey = "clash.module.managed.desiredRunning"
    private static let managedCaptureModeKey = "clash.module.managed.captureMode"
    private static let managedConnectionModeKey = "clash.module.managed.connectionMode"
    private static let managedTunStackKey = "clash.module.managed.tunStack"
    private static let managedTunStrictRouteKey = "clash.module.managed.tunStrictRoute"
    private static let managedTunAutoRouteKey = "clash.module.managed.tunAutoRoute"
    private static let managedLastHealthyProfileIDKey = "clash.module.managed.lastHealthyProfileID"

    static var mode: ClashModuleMode {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: modeKey),
               let mode = ClashModuleMode(rawValue: rawValue) {
                return mode
            }

            return inferredDefaultMode()
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
        }
    }

    static var managedDesiredRunning: Bool {
        get {
            if UserDefaults.standard.object(forKey: managedDesiredRunningKey) != nil {
                return UserDefaults.standard.bool(forKey: managedDesiredRunningKey)
            }

            return UserDefaults.standard.bool(forKey: builtInRuntimeWasRunningKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: managedDesiredRunningKey)
        }
    }

    static var managedCaptureMode: ClashManagedCaptureMode {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: managedCaptureModeKey),
               let mode = ClashManagedCaptureMode(rawValue: rawValue) {
                let normalized = ClashManagedCaptureMode.normalizedForCurrentBuild(mode)
                if normalized != mode {
                    UserDefaults.standard.set(normalized.rawValue, forKey: managedCaptureModeKey)
                }
                return normalized
            }

            if UserDefaults.standard.bool(forKey: builtInSystemProxyEnabledKey) {
                return .systemProxy
            }

            return .none
        }
        set {
            let normalized = ClashManagedCaptureMode.normalizedForCurrentBuild(newValue)
            UserDefaults.standard.set(normalized.rawValue, forKey: managedCaptureModeKey)
        }
    }

    static var managedConnectionMode: ClashConnectionMode {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: managedConnectionModeKey),
               let mode = ClashConnectionMode(rawValue: rawValue) {
                return mode
            }

            return .rule
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: managedConnectionModeKey)
        }
    }

    static var managedTunStack: ClashManagedTunStack {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: managedTunStackKey),
               let stack = ClashManagedTunStack(rawValue: rawValue) {
                return stack
            }

            return .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: managedTunStackKey)
        }
    }

    static var managedTunStrictRoute: Bool {
        get {
            if UserDefaults.standard.object(forKey: managedTunStrictRouteKey) != nil {
                return UserDefaults.standard.bool(forKey: managedTunStrictRouteKey)
            }

            return true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: managedTunStrictRouteKey)
        }
    }

    static var managedTunAutoRoute: Bool {
        get {
            if UserDefaults.standard.object(forKey: managedTunAutoRouteKey) != nil {
                return UserDefaults.standard.bool(forKey: managedTunAutoRouteKey)
            }

            return true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: managedTunAutoRouteKey)
        }
    }

    static var managedLastHealthyProfileID: String? {
        get {
            let value = UserDefaults.standard.string(forKey: managedLastHealthyProfileIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty == false) ? value : nil
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                UserDefaults.standard.set(trimmed, forKey: managedLastHealthyProfileIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: managedLastHealthyProfileIDKey)
            }
        }
    }

    static var builtInRuntimeWasRunning: Bool {
        get { managedDesiredRunning }
        set { managedDesiredRunning = newValue }
    }

    static var builtInSystemProxyEnabled: Bool {
        get { managedCaptureMode == .systemProxy }
        set {
            managedCaptureMode = newValue ? .systemProxy : .none
        }
    }

    static var managedPortOverrides: ClashPortSnapshot {
        ClashPortSnapshot(
            httpPort: integerValue(forKey: managedHTTPPortKey),
            socksPort: integerValue(forKey: managedSocksPortKey),
            mixedPort: integerValue(forKey: managedMixedPortKey)
        )
    }

    static var managedCoreBinaryPath: String {
        get { UserDefaults.standard.string(forKey: managedCoreBinaryPathKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: managedCoreBinaryPathKey) }
    }

    static var managedConfigFilePath: String {
        get { UserDefaults.standard.string(forKey: managedConfigFilePathKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: managedConfigFilePathKey) }
    }

    static var managedSubscriptionURL: String {
        get { UserDefaults.standard.string(forKey: managedSubscriptionURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: managedSubscriptionURLKey) }
    }

    static var managedSubscriptionLastUpdatedAt: Date? {
        get {
            guard let timestamp = UserDefaults.standard.object(forKey: managedSubscriptionLastUpdatedAtKey) as? Double else {
                return nil
            }

            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: managedSubscriptionLastUpdatedAtKey)
            } else {
                UserDefaults.standard.removeObject(forKey: managedSubscriptionLastUpdatedAtKey)
            }
        }
    }

    static var attachConfigFilePath: String {
        get { UserDefaults.standard.string(forKey: attachConfigFilePathKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: attachConfigFilePathKey) }
    }

    static var attachAPIBaseURL: String {
        get { UserDefaults.standard.string(forKey: attachAPIBaseURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: attachAPIBaseURLKey) }
    }

    static var attachAPISecret: String {
        get { KeychainSecretStore.load(account: attachAPISecretAccount) ?? "" }
        set {
            let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedValue.isEmpty {
                KeychainSecretStore.delete(account: attachAPISecretAccount)
            } else {
                KeychainSecretStore.save(trimmedValue, account: attachAPISecretAccount)
            }
        }
    }

    static func currentManagedTunOptions() -> ClashManagedTunOptions {
        ClashManagedTunOptions(
            stack: managedTunStack,
            autoRoute: managedTunAutoRoute,
            strictRoute: managedTunStrictRoute
        )
    }

    static func setManagedPortOverrides(httpPort: Int?, socksPort: Int?, mixedPort: Int?) {
        setIntegerValue(httpPort, forKey: managedHTTPPortKey)
        setIntegerValue(socksPort, forKey: managedSocksPortKey)
        setIntegerValue(mixedPort, forKey: managedMixedPortKey)
    }

    static func ensureModeInitialized() {
        migrateLegacyManagedStateIfNeeded()

        guard UserDefaults.standard.string(forKey: modeKey) == nil else {
            return
        }

        mode = inferredDefaultMode()
    }

    private static func migrateLegacyManagedStateIfNeeded() {
        if UserDefaults.standard.object(forKey: managedDesiredRunningKey) == nil,
           UserDefaults.standard.object(forKey: builtInRuntimeWasRunningKey) != nil {
            UserDefaults.standard.set(
                UserDefaults.standard.bool(forKey: builtInRuntimeWasRunningKey),
                forKey: managedDesiredRunningKey
            )
        }

        if UserDefaults.standard.object(forKey: managedCaptureModeKey) == nil,
           UserDefaults.standard.object(forKey: builtInSystemProxyEnabledKey) != nil {
            let legacyEnabled = UserDefaults.standard.bool(forKey: builtInSystemProxyEnabledKey)
            UserDefaults.standard.set(
                (legacyEnabled ? ClashManagedCaptureMode.systemProxy : .none).rawValue,
                forKey: managedCaptureModeKey
            )
        }

        UserDefaults.standard.removeObject(forKey: builtInRuntimeWasRunningKey)
        UserDefaults.standard.removeObject(forKey: builtInSystemProxyEnabledKey)
    }

    private static func inferredDefaultMode() -> ClashModuleMode {
        if hasLegacyManagedConfiguration {
            return .managed
        }

        if hasLegacyAttachConfiguration || UserDefaults.standard.persistentDomain(forName: "com.west2online.ClashXPro") != nil {
            return .attach
        }

        return .managed
    }

    private static var hasLegacyManagedConfiguration: Bool {
        !managedSubscriptionURL.isEmpty || !managedConfigFilePath.isEmpty || !managedCoreBinaryPath.isEmpty
    }

    private static var hasLegacyAttachConfiguration: Bool {
        !attachConfigFilePath.isEmpty || !attachAPIBaseURL.isEmpty
    }

    private static func integerValue(forKey key: String) -> Int? {
        guard let value = UserDefaults.standard.object(forKey: key) as? Int, value > 0 else {
            return nil
        }

        return value
    }

    private static func setIntegerValue(_ value: Int?, forKey key: String) {
        if let value, value > 0 {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

private enum KeychainSecretStore {
    private static let service = "FantasticIsland.ClashAttach"

    static func load(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let attributes = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
