import Foundation

enum ClashModuleMode: String, CaseIterable, Identifiable {
    case attach
    case managed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attach:
            return NSLocalizedString("Detect Mode", comment: "")
        case .managed:
            return NSLocalizedString("Managed Mode", comment: "")
        }
    }

    var subtitle: String {
        switch self {
        case .attach:
            return NSLocalizedString(
                "Detection mode reads an existing Clash client through its local API and config path. Fantastic Island does not start or manage the runtime in this mode.",
                comment: ""
            )
        case .managed:
            return NSLocalizedString(
                "Managed mode keeps YAML profiles in Fantastic Island, syncs subscriptions, and starts the managed Mihomo runtime when assets are available.",
                comment: ""
            )
        }
    }
}

enum ClashManagedCaptureMode: String, CaseIterable, Codable, Identifiable {
    case none
    case systemProxy
    case tun

    var id: String { rawValue }

    static var isTunExposedInCurrentBuild: Bool { false }

    static var visibleCases: [ClashManagedCaptureMode] {
        if isTunExposedInCurrentBuild {
            return [.none, .systemProxy, .tun]
        }

        return [.none, .systemProxy]
    }

    static func normalizedForCurrentBuild(_ mode: ClashManagedCaptureMode) -> ClashManagedCaptureMode {
        guard isTunExposedInCurrentBuild || mode != .tun else {
            return .none
        }

        return mode
    }

    var title: String {
        switch self {
        case .none:
            return NSLocalizedString("No Capture", comment: "")
        case .systemProxy:
            return NSLocalizedString("System Proxy", comment: "")
        case .tun:
            return "TUN"
        }
    }

    var shortText: String {
        switch self {
        case .none:
            return "OFF"
        case .systemProxy:
            return "SYS"
        case .tun:
            return "TUN"
        }
    }

    var summary: String {
        switch self {
        case .none:
            return NSLocalizedString("Only keep the managed Mihomo runtime available. Fantastic Island does not capture system traffic.", comment: "")
        case .systemProxy:
            return NSLocalizedString("Route traffic through the local proxy ports using macOS networksetup.", comment: "")
        case .tun:
            return NSLocalizedString("Enable Mihomo's managed TUN stack so Fantastic Island captures traffic directly.", comment: "")
        }
    }
}

enum ClashManagedTunStack: String, CaseIterable, Codable, Identifiable {
    case system
    case gvisor
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return NSLocalizedString("System", comment: "")
        case .gvisor:
            return "gVisor"
        case .mixed:
            return NSLocalizedString("Mixed", comment: "")
        }
    }
}

struct ClashManagedTunOptions: Equatable {
    let stack: ClashManagedTunStack
    let autoRoute: Bool
    let strictRoute: Bool
}

enum ClashManagedRuntimePhase: Equatable {
    case stopped
    case preparing
    case launching
    case running
    case reloading
    case stopping
    case failed(String)

    var title: String {
        switch self {
        case .stopped:
            return NSLocalizedString("Stopped", comment: "")
        case .preparing:
            return NSLocalizedString("Preparing", comment: "")
        case .launching:
            return NSLocalizedString("Launching", comment: "")
        case .running:
            return NSLocalizedString("Running", comment: "")
        case .reloading:
            return NSLocalizedString("Reloading", comment: "")
        case .stopping:
            return NSLocalizedString("Stopping", comment: "")
        case .failed:
            return NSLocalizedString("Error", comment: "")
        }
    }

    var shortText: String {
        switch self {
        case .stopped:
            return "OFF"
        case .preparing, .launching, .reloading, .stopping:
            return "BOOT"
        case .running:
            return "ON"
        case .failed:
            return "ERR"
        }
    }

    var diagnosticText: String? {
        if case let .failed(message) = self {
            return message
        }

        return nil
    }

    var canStart: Bool {
        switch self {
        case .stopped, .failed:
            return true
        case .preparing, .launching, .running, .reloading, .stopping:
            return false
        }
    }
}

enum ClashManagedCapturePhase: Equatable {
    case inactive
    case applying
    case active
    case failed(String)

    var title: String {
        switch self {
        case .inactive:
            return NSLocalizedString("Inactive", comment: "")
        case .applying:
            return NSLocalizedString("Applying", comment: "")
        case .active:
            return NSLocalizedString("Active", comment: "")
        case .failed:
            return NSLocalizedString("Error", comment: "")
        }
    }

    var diagnosticText: String? {
        if case let .failed(message) = self {
            return message
        }

        return nil
    }
}

struct ClashProviderCountSnapshot: Equatable {
    let proxyProviders: Int
    let ruleProviders: Int

    static let zero = ClashProviderCountSnapshot(proxyProviders: 0, ruleProviders: 0)
}

struct ClashRuntimeEnvironment: Equatable {
    let moduleMode: ClashModuleMode
    let coreBinaryPath: String?
    let configFilePath: String?
    let configDirectoryPath: String?
    let apiBaseURL: URL
    let uiBaseURL: URL?
    let activeProfileName: String?
    let captureMode: ClashManagedCaptureMode
    let isTunAvailable: Bool
    let activeProviderCounts: ClashProviderCountSnapshot

    var apiBaseURLText: String { apiBaseURL.absoluteString }
    var coreDisplayPath: String { coreBinaryPath ?? NSLocalizedString("Not found", comment: "") }
    var configDisplayPath: String { configFilePath ?? NSLocalizedString("Not found", comment: "") }
    var uiBaseURLText: String { uiBaseURL?.absoluteString ?? NSLocalizedString("Not configured", comment: "") }
    var activeProfileDisplayText: String { activeProfileName ?? NSLocalizedString("Not configured", comment: "") }
    var canLaunchOwnedRuntime: Bool {
        moduleMode == .managed && coreBinaryPath != nil && configFilePath != nil && configDirectoryPath != nil
    }
}

enum ClashBuiltInProfileSyncStatus: Equatable {
    case idle
    case updating
    case ready(Date?)
    case failed(String)

    var isUpdating: Bool {
        if case .updating = self {
            return true
        }

        return false
    }
}

enum ClashBuiltInProfileSourceKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case remoteSubscription
    case importedFile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remoteSubscription:
            return NSLocalizedString("Subscription", comment: "")
        case .importedFile:
            return NSLocalizedString("Local YAML", comment: "")
        }
    }
}

struct ClashBuiltInProfile: Codable, Equatable, Hashable, Identifiable {
    let id: String
    var displayName: String
    var sourceKind: ClashBuiltInProfileSourceKind
    var sourceLocation: String
    var snapshotRelativePath: String
    var updateOnActivate: Bool
    var lastUpdatedAt: Date?
    var lastErrorMessage: String?
    var isActive: Bool
    var isStarterProfile: Bool

    var remoteSubscriptionURL: URL? {
        guard sourceKind == .remoteSubscription else {
            return nil
        }

        return URL(string: sourceLocation)
    }

    var importedFilePath: String? {
        guard sourceKind == .importedFile, !sourceLocation.isEmpty else {
            return nil
        }

        return sourceLocation
    }

    var sourceSummaryText: String {
        switch sourceKind {
        case .remoteSubscription:
            return remoteSubscriptionURL?.absoluteString ?? NSLocalizedString("Not configured", comment: "")
        case .importedFile:
            if isStarterProfile {
                return NSLocalizedString("Created inside Fantastic Island as the default local profile.", comment: "")
            }

            return importedFilePath ?? NSLocalizedString("Not configured", comment: "")
        }
    }

    var supportsManualUpdate: Bool {
        sourceKind == .remoteSubscription
    }

    var supportsReimport: Bool {
        sourceKind == .importedFile && importedFilePath != nil
    }
}

struct ClashBuiltInProfileLibrary: Codable, Equatable {
    var schemaVersion: Int = 1
    var profiles: [ClashBuiltInProfile] = []
}

enum ClashRuntimeStatus: Equatable {
    case disconnected
    case launching
    case attached
    case runningOwned
    case failed(String)

    var title: String {
        switch self {
        case .disconnected:
            return NSLocalizedString("Idle", comment: "")
        case .launching:
            return NSLocalizedString("Launching", comment: "")
        case .attached:
            return NSLocalizedString("Attached", comment: "")
        case .runningOwned:
            return NSLocalizedString("Running", comment: "")
        case .failed:
            return NSLocalizedString("Error", comment: "")
        }
    }

    var diagnosticText: String? {
        if case let .failed(message) = self {
            return message
        }

        return nil
    }

    var shortText: String {
        switch self {
        case .disconnected:
            return "OFF"
        case .launching:
            return "BOOT"
        case .attached, .runningOwned:
            return "ON"
        case .failed:
            return "ERR"
        }
    }
}

struct ClashRuntimeVersion: Decodable {
    let version: String
    let premium: Bool?
}

struct ClashRuntimeConfig: Decodable {
    let port: Int
    let socksPort: Int
    let mixedPort: Int
    let allowLan: Bool
    let mode: String
    let logLevel: String

    enum CodingKeys: String, CodingKey {
        case port
        case socksPort = "socks-port"
        case mixedPort = "mixed-port"
        case allowLan = "allow-lan"
        case mode
        case logLevel = "log-level"
    }
}

struct ClashPortSnapshot: Equatable {
    let httpPort: Int?
    let socksPort: Int?
    let mixedPort: Int?

    var hasAnyPort: Bool {
        httpPort != nil || socksPort != nil || mixedPort != nil
    }
}

struct ClashTrafficSnapshot: Equatable {
    let upKbps: Double
    let downKbps: Double

    static let zero = ClashTrafficSnapshot(upKbps: 0, downKbps: 0)
}

struct ClashProxyOptionSummary: Identifiable, Equatable {
    let name: String
    let delay: Int?

    var id: String { name }
}

struct ClashProxyGroupSummary: Identifiable, Equatable {
    let name: String
    let type: String
    let current: String
    let options: [ClashProxyOptionSummary]

    var id: String { name }

    var currentDelay: Int? {
        options.first(where: { $0.name == current })?.delay
    }
}

enum ClashLogLevelFilter: String, CaseIterable, Identifiable {
    case all
    case debug
    case info
    case warning
    case error

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return NSLocalizedString("All", comment: "")
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .warning:
            return NSLocalizedString("Warning", comment: "")
        case .error:
            return NSLocalizedString("Error", comment: "")
        }
    }
}

struct ClashLogEntry: Identifiable, Equatable {
    let id: UUID
    let level: ClashLogLevelFilter
    let message: String
    let rawLine: String

    init(id: UUID = UUID(), level: ClashLogLevelFilter, message: String, rawLine: String) {
        self.id = id
        self.level = level
        self.message = message
        self.rawLine = rawLine
    }
}

struct ClashRuleEntry: Identifiable, Equatable {
    let id: String
    let type: String
    let payload: String
    let target: String
    let source: String?
}

struct ClashConnectionOverview: Equatable {
    let activeConnectionCount: Int
    let uploadTotalBytes: Int64?
    let downloadTotalBytes: Int64?
    let memoryBytes: Int64?

    static let empty = ClashConnectionOverview(
        activeConnectionCount: 0,
        uploadTotalBytes: nil,
        downloadTotalBytes: nil,
        memoryBytes: nil
    )
}

struct ClashProviderSummary: Identifiable, Equatable {
    let name: String
    let type: String
    let vehicleType: String?
    let nodeCount: Int
    let updatedAtText: String?
    let testURL: String?

    var id: String { name }

    var detailText: String {
        var components: [String] = []
        components.append(type)
        if let vehicleType, !vehicleType.isEmpty {
            components.append(vehicleType)
        }
        if nodeCount > 0 {
            components.append(
                String.localizedStringWithFormat(
                    NSLocalizedString("%d nodes", comment: ""),
                    nodeCount
                )
            )
        }
        if let updatedAtText, !updatedAtText.isEmpty {
            components.append(updatedAtText)
        }
        if let testURL, !testURL.isEmpty {
            components.append(testURL)
        }
        return components.joined(separator: " · ")
    }
}

struct ClashRuleProviderSummary: Identifiable, Equatable {
    let name: String
    let type: String
    let vehicleType: String?
    let ruleCount: Int
    let updatedAtText: String?
    let behavior: String?

    var id: String { name }

    var detailText: String {
        var components: [String] = []
        components.append(type)
        if let vehicleType, !vehicleType.isEmpty {
            components.append(vehicleType)
        }
        if let behavior, !behavior.isEmpty {
            components.append(behavior)
        }
        if ruleCount > 0 {
            components.append(
                String.localizedStringWithFormat(
                    NSLocalizedString("%d rules", comment: ""),
                    ruleCount
                )
            )
        }
        if let updatedAtText, !updatedAtText.isEmpty {
            components.append(updatedAtText)
        }
        return components.joined(separator: " · ")
    }
}

struct ClashManagedDiagnosticSnapshot: Equatable {
    let runtimePhase: ClashManagedRuntimePhase
    let captureMode: ClashManagedCaptureMode
    let capturePhase: ClashManagedCapturePhase
    let activeProfileName: String?
    let proxyProviderCount: Int
    let ruleProviderCount: Int
    let lastFailureMessage: String?
}
