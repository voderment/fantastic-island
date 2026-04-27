import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ClashModuleModel: ObservableObject, IslandModule {
    static let moduleID = "clash"
    private static let managedTunProbeHost = "speed.cloudflare.com"
    private static let managedTunProbeURL = "https://speed.cloudflare.com/__down?bytes=262144"

    let id = ClashModuleModel.moduleID
    let title = "Clash"
    let symbolName = "lock.shield"
    let iconAssetName: String? = "clashicon"

    @Published private(set) var environment = ClashRuntimeEnvironment(
        moduleMode: .managed,
        coreBinaryPath: nil,
        configFilePath: nil,
        configDirectoryPath: nil,
        apiBaseURL: ClashConfigSupport.builtInAPIBaseURL(),
        uiBaseURL: ClashConfigSupport.builtInUIBaseURL(),
        activeProfileName: nil,
        captureMode: .none,
        isTunAvailable: ClashManagedCaptureMode.isTunExposedInCurrentBuild,
        activeProviderCounts: .zero
    )
    @Published private(set) var status: ClashRuntimeStatus = .disconnected
    @Published private(set) var runtimePhase: ClashManagedRuntimePhase = .stopped
    @Published private(set) var version: ClashRuntimeVersion?
    @Published private(set) var runtimeConfig: ClashRuntimeConfig?
    @Published private(set) var proxyGroups: [ClashProxyGroupSummary] = []
    @Published private(set) var recentLogs: [String] = []
    @Published private(set) var trafficSnapshot = ClashTrafficSnapshot.zero
    @Published private(set) var controlState = ClashControlState(
        captureMode: ClashModuleSettings.managedCaptureMode,
        capturePhase: .inactive,
        connectionMode: ClashModuleSettings.managedConnectionMode,
        latencyTestState: .idle
    )
    @Published private(set) var builtInProfiles: [ClashBuiltInProfile] = []
    @Published private(set) var builtInProfileSyncStatus: ClashBuiltInProfileSyncStatus = .idle
    @Published private(set) var ruleEntries: [ClashRuleEntry] = []
    @Published private(set) var rulesLoadError: String?
    @Published private(set) var isLoadingRules = false
    @Published private(set) var connectionOverview = ClashConnectionOverview.empty
    @Published private(set) var connectionOverviewError: String?
    @Published private(set) var isLoadingConnectionOverview = false
    @Published private(set) var logEntries: [ClashLogEntry] = []
    @Published private(set) var logStreamError: String?
    @Published private(set) var isStreamingLogs = false
    @Published private(set) var proxyProviders: [ClashProviderSummary] = []
    @Published private(set) var ruleProviders: [ClashRuleProviderSummary] = []
    @Published private(set) var providerLoadError: String?
    @Published private(set) var isLoadingProviders = false

    private let systemProxyController = SystemProxyController()
    private let builtInRuntimeManager: ClashBuiltInRuntimeManager
    private let pollInterval: TimeInterval = 4
    private var pollTimer: Timer?
    private var logStreamTask: Task<Void, Never>?

    var collapsedSummaryItems: [CollapsedSummaryItem] {
        [
            CollapsedSummaryItem(
                id: "\(id).summary.traffic",
                moduleID: id,
                title: "Traffic",
                text: compactTrafficText,
                isEnabledByDefault: true
            ),
            CollapsedSummaryItem(
                id: "\(id).summary.status",
                moduleID: id,
                title: "Status",
                text: "CLASH \(status.shortText)",
                isEnabledByDefault: false
            ),
            CollapsedSummaryItem(
                id: "\(id).summary.mode",
                moduleID: id,
                title: "Mode",
                text: "MODE \(runtimeConfig?.mode.uppercased() ?? "--")",
                isEnabledByDefault: false
            ),
        ]
    }

    var taskActivityContribution = TaskActivityContribution()
    var preferredOpenedContentHeight: CGFloat {
        CodexIslandChromeMetrics.preferredTallModuleOpenedContentHeight
    }

    var statusDescription: String { status.title }
    var runtimeStatusHasError: Bool {
        if case .failed = status {
            return true
        }

        return false
    }
    var runtimeStatusDetailText: String? {
        switch moduleMode {
        case .attach:
            switch status {
            case .disconnected, .attached, .runningOwned:
                return nil
            case .launching:
                return nil
            case let .failed(message):
                return Self.conciseRuntimeStatusMessage(message)
            }
        case .managed:
            if case let .failed(message) = runtimePhase {
                return Self.conciseRuntimeStatusMessage(message)
            }
            if case let .failed(message) = controlState.capturePhase {
                return Self.conciseRuntimeStatusMessage(message)
            }

            switch runtimePhase {
            case .preparing:
                return NSLocalizedString("Preparing the active managed profile and regenerating Island's runtime config.", comment: "")
            case .launching:
                return NSLocalizedString("Starting Island's bundled Mihomo runtime and waiting for the local API.", comment: "")
            case .reloading:
                return NSLocalizedString("Restarting Island's managed Mihomo runtime so the selected capture mode and config changes take effect.", comment: "")
            case .stopping:
                return NSLocalizedString("Stopping Island's managed runtime and releasing active capture state.", comment: "")
            case .running:
                switch controlState.capturePhase {
                case .inactive:
                    return controlState.captureMode == .none
                        ? NSLocalizedString("Managed runtime is running without any system traffic capture.", comment: "")
                        : controlState.captureMode.summary
                case .applying:
                    return NSLocalizedString("Applying the selected managed capture mode.", comment: "")
                case .active:
                    return controlState.captureMode.summary
                case let .failed(message):
                    return Self.conciseRuntimeStatusMessage(message)
                }
            case .stopped:
                return nil
            case .failed:
                return nil
            }
        }
    }
    var runtimeVersionText: String { version?.version ?? "--" }
    var modeText: String { runtimeConfig?.mode.uppercased() ?? "--" }
    var moduleMode: ClashModuleMode { ClashModuleSettings.mode }
    var moduleModeTitle: String { moduleMode.title }
    var moduleModeSummaryText: String { moduleMode.subtitle }
    var managedRuntimePhaseTitle: String { runtimePhase.title }
    var managedCaptureModeTitle: String { controlState.captureMode.title }
    var managedCapturePhaseTitle: String { controlState.capturePhase.title }
    var managedSystemProxyEnabled: Bool { controlState.captureMode == .systemProxy }
    var managedDesiredRunning: Bool { ClashModuleSettings.managedDesiredRunning }
    var managedTunStack: ClashManagedTunStack { ClashModuleSettings.managedTunStack }
    var managedTunAutoRoute: Bool { ClashModuleSettings.managedTunAutoRoute }
    var managedTunStrictRoute: Bool { ClashModuleSettings.managedTunStrictRoute }
    var mixedPortText: String { portText(for: runtimeConfig?.mixedPort) }
    var socksPortText: String { portText(for: runtimeConfig?.socksPort) }
    var httpPortText: String { portText(for: runtimeConfig?.port) }
    var resolvedPortSnapshot: ClashPortSnapshot {
        if let runtimeConfig {
            return ClashPortSnapshot(
                httpPort: runtimeConfig.port > 0 ? runtimeConfig.port : nil,
                socksPort: runtimeConfig.socksPort > 0 ? runtimeConfig.socksPort : nil,
                mixedPort: runtimeConfig.mixedPort > 0 ? runtimeConfig.mixedPort : nil
            )
        }

        let overridePorts = ClashModuleSettings.managedPortOverrides
        if moduleMode == .managed, overridePorts.hasAnyPort {
            return overridePorts
        }

        return ClashConfigSupport.portSnapshot(fromConfigFileAt: environment.configFilePath)
    }
    var resolvedHTTPPortText: String { portText(for: resolvedPortSnapshot.httpPort) }
    var resolvedSocksPortText: String { portText(for: resolvedPortSnapshot.socksPort) }
    var resolvedMixedPortText: String { portText(for: resolvedPortSnapshot.mixedPort) }
    var currentConnectionModeText: String { controlState.connectionMode.title }
    var canStopOwnedRuntime: Bool {
        moduleMode == .managed && runtimePhase != .stopped && runtimePhase != .stopping
    }
    var canStartOwnedRuntime: Bool {
        moduleMode == .managed
            && environment.canLaunchOwnedRuntime
            && runtimePhase.canStart
    }
    var canReloadManagedRuntime: Bool {
        moduleMode == .managed && runtimePhase == .running
    }
    var proxyTestStatusText: String { controlState.latencyTestState.displayText }
    var isTrafficRateAvailable: Bool {
        switch status {
        case .attached, .runningOwned:
            return true
        case .disconnected, .launching, .failed:
            return false
        }
    }
    var uploadRateText: String { ClashConfigSupport.formatTrafficRate(trafficSnapshot.upBytesPerSecond) }
    var downloadRateText: String { ClashConfigSupport.formatTrafficRate(trafficSnapshot.downBytesPerSecond) }
    var connectionCountText: String { String(connectionOverview.activeConnectionCount) }
    var uploadTotalText: String { ClashConfigSupport.formatByteCount(connectionOverview.uploadTotalBytes) }
    var downloadTotalText: String { ClashConfigSupport.formatByteCount(connectionOverview.downloadTotalBytes) }
    var memoryUsageText: String { ClashConfigSupport.formatByteCount(connectionOverview.memoryBytes) }
    var compactTrafficText: String {
        switch status {
        case .attached, .runningOwned, .launching:
            return "↑ \(uploadRateText) ↓ \(downloadRateText)"
        case .disconnected, .failed:
            return "CLASH \(status.shortText)"
        }
    }

    var configuredAttachConfigFilePath: String {
        ClashModuleSettings.attachConfigFilePath
    }

    var configuredAttachAPIBaseURL: String {
        ClashModuleSettings.attachAPIBaseURL
    }

    var configuredAttachAPISecret: String {
        ClashModuleSettings.attachAPISecret
    }

    var activeBuiltInProfile: ClashBuiltInProfile? {
        builtInProfiles.first(where: { $0.isActive }) ?? builtInProfiles.first
    }

    var builtInProfileIDs: [String] {
        builtInProfiles.map(\.id)
    }

    var activeBuiltInProfileID: String {
        activeBuiltInProfile?.id ?? builtInProfiles.first?.id ?? ""
    }

    var activeBuiltInProfileName: String {
        activeBuiltInProfile?.displayName ?? NSLocalizedString("Not configured", comment: "")
    }

    var activeBuiltInProfileSourceLabelText: String {
        NSLocalizedString("Source", comment: "")
    }

    var activeBuiltInProfileSourceKindText: String {
        guard let profile = activeBuiltInProfile else {
            return NSLocalizedString("Not configured", comment: "")
        }

        if profile.isStarterProfile {
            return NSLocalizedString("Default local profile", comment: "")
        }

        switch profile.sourceKind {
        case .remoteSubscription:
            return NSLocalizedString("Remote subscription", comment: "")
        case .importedFile:
            return NSLocalizedString("Imported local YAML", comment: "")
        }
    }

    var activeBuiltInProfileSourceText: String {
        activeBuiltInProfile?.sourceSummaryText ?? NSLocalizedString("Not configured", comment: "")
    }

    var activeBuiltInProfileSnapshotPathText: String {
        guard let profile = activeBuiltInProfile else {
            return NSLocalizedString("Not configured", comment: "")
        }

        return Self.snapshotPath(for: profile)
    }

    var builtInProfileStatusText: String {
        guard let profile = activeBuiltInProfile else {
            return NSLocalizedString("Not configured", comment: "")
        }

        switch builtInProfileSyncStatus {
        case .updating:
            return NSLocalizedString("Updating", comment: "")
        case .failed:
            return NSLocalizedString("Error", comment: "")
        case .ready:
            return profile.sourceKind == .remoteSubscription
                ? NSLocalizedString("Synced", comment: "")
                : NSLocalizedString("Local File", comment: "")
        case .idle:
            return profile.sourceKind == .remoteSubscription
                ? NSLocalizedString("Configured", comment: "")
                : NSLocalizedString("Local File", comment: "")
        }
    }

    var builtInProfileStatusDetailText: String {
        guard let profile = activeBuiltInProfile else {
            return NSLocalizedString("Create or import a built-in profile first.", comment: "")
        }

        switch builtInProfileSyncStatus {
        case .updating:
            return NSLocalizedString(
                "Refreshing the built-in profile snapshot and regenerating Island's local runtime config.",
                comment: ""
            )
        case let .failed(message):
            return message
        case let .ready(date):
            if profile.sourceKind == .remoteSubscription, let date {
                return ClashConfigSupport.localizedFormat(
                    "Last updated %@. Island can now reload the built-in runtime from the synced local snapshot.",
                    Self.profileDateFormatter.string(from: date)
                )
            }

            if profile.isStarterProfile {
                return NSLocalizedString(
                    "This is Island's default local profile. Import a YAML file or add a subscription when you want to replace it.",
                    comment: ""
                )
            }

            return NSLocalizedString(
                "Island stores an internal snapshot of this profile and regenerates the runtime config automatically when needed.",
                comment: ""
            )
        case .idle:
            if profile.sourceKind == .remoteSubscription {
                return NSLocalizedString(
                    "Remote built-in profiles sync into Island's local library and accept http:// or https:// YAML subscriptions.",
                    comment: ""
                )
            }

            if profile.isStarterProfile {
                return NSLocalizedString(
                    "This is Island's default local profile. Import a YAML file or add a subscription when you want to replace it.",
                    comment: ""
                )
            }

            return NSLocalizedString(
                "Imported YAML profiles stay inside Island until you explicitly re-import the original file.",
                comment: ""
            )
        }
    }

    var activeBuiltInProfileSupportsUpdateOnActivate: Bool {
        activeBuiltInProfile?.sourceKind == .remoteSubscription
    }

    var activeBuiltInProfileUpdateOnActivate: Bool {
        activeBuiltInProfile?.updateOnActivate ?? false
    }

    var currentBuiltInProfileActionTitle: String {
        if builtInProfileSyncStatus.isUpdating {
            return NSLocalizedString("Updating...", comment: "")
        }

        guard let profile = activeBuiltInProfile, canRefreshActiveBuiltInProfile else {
            return NSLocalizedString("Update Profile", comment: "")
        }

        return profile.sourceKind == .remoteSubscription
            ? NSLocalizedString("Update Profile", comment: "")
            : NSLocalizedString("Reimport Profile", comment: "")
    }

    var canRefreshActiveBuiltInProfile: Bool {
        guard let profile = activeBuiltInProfile else {
            return false
        }

        return profile.sourceKind == .remoteSubscription || profile.supportsReimport
    }

    var canDeleteBuiltInProfiles: Bool {
        !builtInProfiles.isEmpty
    }

    var proxyProviderCountText: String {
        String(proxyProviders.count)
    }

    var ruleProviderCountText: String {
        String(ruleProviders.count)
    }

    var managedDiagnostics: ClashManagedDiagnosticSnapshot {
        ClashManagedDiagnosticSnapshot(
            runtimePhase: runtimePhase,
            captureMode: controlState.captureMode,
            capturePhase: controlState.capturePhase,
            activeProfileName: managedLastHealthyProfileName,
            proxyProviderCount: proxyProviders.count,
            ruleProviderCount: ruleProviders.count,
            lastFailureMessage: status.diagnosticText
        )
    }

    var managedLastHealthyProfileName: String? {
        guard let profileID = ClashModuleSettings.managedLastHealthyProfileID else {
            return nil
        }

        return builtInProfiles.first(where: { $0.id == profileID })?.displayName
    }

    init() {
        ClashModuleSettings.ensureModeInitialized()
        let builtInProfileStore = ClashBuiltInProfileStore()

        self.builtInRuntimeManager = ClashBuiltInRuntimeManager(
            profileStore: builtInProfileStore
        )
        self.builtInRuntimeManager.updateHandlers(
            logHandler: { [weak self] message in
                self?.appendLogs(message)
            },
            terminationHandler: { [weak self] exitStatus in
                self?.handleBuiltInRuntimeTermination(exitStatus)
            }
        )

        syncBuiltInState()
        refreshEnvironment()
        syncLegacyStatus()
        startPollingTimer()

        Task {
            await restoreBuiltInRuntimeIfNeeded()
            await refresh(showConnectionErrors: false)
        }
    }

    deinit {
        pollTimer?.invalidate()
        logStreamTask?.cancel()
    }

    func makeContentView(presentation: IslandModulePresentationContext) -> AnyView {
        AnyView(ClashModuleContentView(model: self))
    }

    func updateModuleMode(_ mode: ClashModuleMode) {
        guard ClashModuleSettings.mode != mode else {
            return
        }

        let previousMode = ClashModuleSettings.mode
        ClashModuleSettings.mode = mode
        refreshEnvironment()

        Task {
            if previousMode == .managed && mode == .attach {
                await disableManagedCaptureIfNeeded()
                setManagedRuntimePhase(.stopping)
                builtInRuntimeManager.stop()
                setManagedRuntimePhase(.stopped)
            } else if previousMode == .attach && mode == .managed, ClashModuleSettings.managedDesiredRunning {
                await restoreBuiltInRuntimeIfNeeded()
            }

            await refresh(showConnectionErrors: false)
        }
    }

    func updateConfiguredAttachConfigFilePath(_ path: String) {
        ClashModuleSettings.attachConfigFilePath = path
        refreshEnvironment()
    }

    func updateConfiguredAttachAPIBaseURL(_ value: String) {
        ClashModuleSettings.attachAPIBaseURL = value
        refreshEnvironment()
    }

    func updateConfiguredAttachAPISecret(_ value: String) {
        ClashModuleSettings.attachAPISecret = value
        refreshEnvironment()
    }

    func updateManagedCaptureMode(_ mode: ClashManagedCaptureMode) {
        let normalizedMode = ClashManagedCaptureMode.normalizedForCurrentBuild(mode)
        guard moduleMode == .managed, controlState.captureMode != normalizedMode else {
            return
        }

        let previousMode = controlState.captureMode
        controlState.captureMode = normalizedMode
        ClashModuleSettings.managedCaptureMode = normalizedMode
        refreshEnvironment()

        Task {
            await applyManagedCaptureModeChange(from: previousMode, to: normalizedMode)
        }
    }

    func updateManagedSystemProxyEnabled(_ enabled: Bool) {
        updateManagedCaptureMode(enabled ? .systemProxy : .none)
    }

    func updateManagedTunStack(_ stack: ClashManagedTunStack) {
        guard ClashModuleSettings.managedTunStack != stack else {
            return
        }

        ClashModuleSettings.managedTunStack = stack
        Task {
            await applyManagedTunOptionsChange()
        }
    }

    func updateManagedTunAutoRoute(_ enabled: Bool) {
        guard ClashModuleSettings.managedTunAutoRoute != enabled else {
            return
        }

        ClashModuleSettings.managedTunAutoRoute = enabled
        Task {
            await applyManagedTunOptionsChange()
        }
    }

    func updateManagedTunStrictRoute(_ enabled: Bool) {
        guard ClashModuleSettings.managedTunStrictRoute != enabled else {
            return
        }

        ClashModuleSettings.managedTunStrictRoute = enabled
        Task {
            await applyManagedTunOptionsChange()
        }
    }

    func refreshEnvironment() {
        environment = Self.discoverEnvironment(
            mode: moduleMode,
            builtInRuntimeManager: builtInRuntimeManager,
            activeBuiltInProfileName: activeBuiltInProfile?.displayName,
            captureMode: controlState.captureMode,
            providerCounts: ClashProviderCountSnapshot(
                proxyProviders: proxyProviders.count,
                ruleProviders: ruleProviders.count
            )
        )
    }

    func refreshAction() {
        Task {
            await refresh(showConnectionErrors: true)
            if moduleMode == .managed {
                await loadProviders()
            }
        }
    }

    func updateSystemProxyEnabled(_ enabled: Bool) {
        Task {
            await applyAttachSystemProxy(enabled)
        }
    }

    func updateConnectionMode(_ mode: ClashConnectionMode) {
        guard controlState.connectionMode != mode else {
            return
        }

        let previousMode = controlState.connectionMode
        controlState.connectionMode = mode
        Task {
            await setConnectionMode(mode, previousMode: previousMode, persistOnSuccess: true)
        }
    }

    func startOrAttach() {
        Task {
            await attachOrStart()
        }
    }

    func reloadConfig() {
        Task {
            await reloadCurrentConfig()
        }
    }

    func stopOwnedRuntime() {
        guard moduleMode == .managed else {
            return
        }

        ClashModuleSettings.managedDesiredRunning = false
        Task {
            await stopManagedRuntime()
        }
    }

    func openConfigDirectory() {
        guard let configDirectoryPath = environment.configDirectoryPath else {
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: configDirectoryPath, isDirectory: true))
    }

    func openConfigFile() {
        guard let configFilePath = environment.configFilePath else {
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: configFilePath))
    }

    func showAddSubscriptionPrompt() {
        guard moduleMode == .managed else {
            return
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Add Built-in Subscription", comment: "")
        alert.informativeText = NSLocalizedString(
            "Built-in profiles accept Clash or Mihomo YAML subscriptions over http:// or https://.",
            comment: ""
        )
        alert.addButton(withTitle: NSLocalizedString("Add Profile", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        let nameField = NSTextField(string: "")
        nameField.placeholderString = NSLocalizedString("Optional display name", comment: "")
        let urlField = NSTextField(string: "")
        urlField.placeholderString = "http://example.com/clash.yaml"

        let stackView = NSStackView(views: [nameField, urlField])
        stackView.orientation = .vertical
        stackView.spacing = 10
        stackView.alignment = .leading
        nameField.frame.size.width = 320
        urlField.frame.size.width = 320
        alert.accessoryView = stackView

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        addBuiltInSubscription(
            named: nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            urlString: urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func addBuiltInSubscription(named preferredName: String?, urlString: String) {
        guard moduleMode == .managed else {
            return
        }

        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            handleFailure(NSLocalizedString("Built-in subscriptions must use http:// or https://.", comment: ""))
            return
        }

        let trimmedName = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines)

        builtInProfileSyncStatus = .updating
        Task {
            do {
                try await builtInRuntimeManager.addRemoteProfile(
                    named: (trimmedName?.isEmpty == false) ? trimmedName : nil,
                    urlString: trimmedURL
                )
                syncBuiltInState()
                ClashModuleSettings.managedDesiredRunning = true
                try await applyBuiltInRuntimeConfiguration(reloadRuntimeIfPossible: true, updateActiveProfileIfNeeded: false)
            } catch {
                syncBuiltInState()
                handleFailure(error.localizedDescription)
            }
        }
    }

    func importBuiltInProfile() {
        guard moduleMode == .managed else {
            return
        }

        let panel = NSOpenPanel()
        panel.title = NSLocalizedString("Import Built-in YAML Profile", comment: "")
        panel.prompt = NSLocalizedString("Import", comment: "")
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "yaml"), UTType(filenameExtension: "yml"), .plainText].compactMap { $0 }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        builtInProfileSyncStatus = .updating
        do {
            try builtInRuntimeManager.importProfile(from: url)
            syncBuiltInState()
            ClashModuleSettings.managedDesiredRunning = true
            Task {
                do {
                    try await applyBuiltInRuntimeConfiguration(reloadRuntimeIfPossible: true, updateActiveProfileIfNeeded: false)
                } catch {
                    syncBuiltInState()
                    handleFailure(error.localizedDescription)
                }
            }
        } catch {
            syncBuiltInState()
            handleFailure(error.localizedDescription)
        }
    }

    func updateCurrentBuiltInProfile() {
        guard moduleMode == .managed, canRefreshActiveBuiltInProfile else {
            return
        }

        builtInProfileSyncStatus = .updating
        Task {
            do {
                try await builtInRuntimeManager.refreshActiveProfile()
                syncBuiltInState()
                ClashModuleSettings.managedDesiredRunning = true
                try await applyBuiltInRuntimeConfiguration(reloadRuntimeIfPossible: true, updateActiveProfileIfNeeded: false)
            } catch {
                syncBuiltInState()
                handleFailure(error.localizedDescription)
            }
        }
    }

    func selectBuiltInProfile(id: String) {
        guard !id.isEmpty, id != activeBuiltInProfileID else {
            return
        }

        builtInProfileSyncStatus = .updating
        Task {
            do {
                try builtInRuntimeManager.activateProfile(id: id)
                syncBuiltInState()
                ClashModuleSettings.managedDesiredRunning = true
                try await applyBuiltInRuntimeConfiguration(reloadRuntimeIfPossible: true, updateActiveProfileIfNeeded: true)
            } catch {
                syncBuiltInState()
                handleFailure(error.localizedDescription)
            }
        }
    }

    func updateActiveBuiltInProfileUpdateOnActivate(_ enabled: Bool) {
        guard let activeBuiltInProfile, activeBuiltInProfile.sourceKind == .remoteSubscription else {
            return
        }

        do {
            try builtInRuntimeManager.setUpdateOnActivate(enabled, forProfileID: activeBuiltInProfile.id)
            syncBuiltInState()
        } catch {
            handleFailure(error.localizedDescription)
        }
    }

    func loadRules() {
        Task {
            await refreshRules()
        }
    }

    func refreshConnectionsOverview() {
        Task {
            await loadConnectionOverview()
        }
    }

    func refreshProviders() {
        Task {
            await loadProviders()
        }
    }

    func updateProxyProvider(named name: String) {
        Task {
            await triggerProxyProviderUpdate(named: name)
        }
    }

    func healthcheckProxyProvider(named name: String) {
        Task {
            await triggerProxyProviderHealthcheck(named: name)
        }
    }

    func updateRuleProvider(named name: String) {
        Task {
            await triggerRuleProviderUpdate(named: name)
        }
    }

    func startLogStreaming() {
        logStreamTask?.cancel()
        logEntries = []
        logStreamError = nil
        isStreamingLogs = true

        logStreamTask = Task { [weak self] in
            await self?.streamLogs()
        }
    }

    func stopLogStreaming() {
        logStreamTask?.cancel()
        logStreamTask = nil
        isStreamingLogs = false
    }

    func applyManagedPorts(httpPort: Int?, socksPort: Int?, mixedPort: Int?) {
        guard moduleMode == .managed else {
            return
        }

        Task {
            await updateManagedPorts(httpPort: httpPort, socksPort: socksPort, mixedPort: mixedPort)
        }
    }

    func builtInProfileName(for id: String) -> String {
        builtInProfiles.first(where: { $0.id == id })?.displayName ?? id
    }

    func showRenameBuiltInProfilePrompt(id: String) {
        guard moduleMode == .managed,
              let profile = builtInProfiles.first(where: { $0.id == id }) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Rename Profile", comment: "")
        alert.informativeText = NSLocalizedString(
            "Choose the display name that should appear in Island's built-in profile list.",
            comment: ""
        )
        alert.addButton(withTitle: NSLocalizedString("Save", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        let nameField = NSTextField(string: profile.displayName)
        nameField.placeholderString = NSLocalizedString("Profile name", comment: "")
        nameField.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = nameField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try builtInRuntimeManager.renameProfile(
                id: id,
                named: nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            syncBuiltInState()
        } catch {
            handleFailure(error.localizedDescription)
        }
    }

    func confirmDeleteBuiltInProfile(id: String) {
        guard moduleMode == .managed,
              let profile = builtInProfiles.first(where: { $0.id == id }) else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Delete Profile?", comment: "")
        alert.informativeText = String.localizedStringWithFormat(
            NSLocalizedString(
                "Delete \"%@\" from Island's built-in profile library? If it is active, Island will switch to another profile automatically.",
                comment: ""
            ),
            profile.displayName
        )
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try builtInRuntimeManager.deleteProfile(id: id)
            syncBuiltInState()
            Task {
                do {
                    ClashModuleSettings.managedDesiredRunning = true
                    try await applyBuiltInRuntimeConfiguration(
                        reloadRuntimeIfPossible: true,
                        updateActiveProfileIfNeeded: false
                    )
                } catch {
                    syncBuiltInState()
                    handleFailure(error.localizedDescription)
                }
            }
        } catch {
            handleFailure(error.localizedDescription)
        }
    }

    func selectProxy(_ proxyName: String, in groupName: String) {
        Task {
            await updateProxySelection(proxyName: proxyName, in: groupName)
        }
    }

    func testLatency(in groupName: String) {
        Task {
            guard let group = proxyGroups.first(where: { $0.name == groupName }) else {
                return
            }
            await testAllProxyLatencies(in: group)
        }
    }

    private var currentSystemProxyPort: Int? {
        resolvedPortSnapshot.mixedPort ?? resolvedPortSnapshot.httpPort ?? resolvedPortSnapshot.socksPort
    }

    private func applyAttachSystemProxy(_ enabled: Bool) async {
        do {
            try await setSystemProxyEnabled(enabled)
            controlState.captureMode = enabled ? .systemProxy : .none
            controlState.capturePhase = enabled ? .active : .inactive
            refreshEnvironment()
        } catch {
            controlState.captureMode = enabled ? .none : .systemProxy
            controlState.capturePhase = .failed(error.localizedDescription)
            handleFailure(error.localizedDescription)
        }
    }

    private func setSystemProxyEnabled(_ enabled: Bool) async throws {
        if enabled, currentSystemProxyPort == nil {
            throw ClashModuleError.invalidManagedProxyPort
        }

        try await systemProxyController.setEnabled(enabled, port: enabled ? currentSystemProxyPort : nil)
    }

    private func setConnectionMode(
        _ mode: ClashConnectionMode,
        previousMode: ClashConnectionMode,
        persistOnSuccess: Bool
    ) async {
        do {
            let body = try JSONSerialization.data(withJSONObject: ["mode": mode.rawValue])
            let _: EmptyAPIResponse = try await request(path: "/configs", method: "PATCH", body: body)
            controlState.connectionMode = mode
            if moduleMode == .managed, persistOnSuccess {
                ClashModuleSettings.managedConnectionMode = mode
            }
            await refresh(showConnectionErrors: true)
        } catch {
            controlState.connectionMode = previousMode
            handleFailure(ClashConfigSupport.localizedFormat("Mode switch failed: %@", error.localizedDescription))
        }
    }

    private func testAllProxyLatencies(in group: ClashProxyGroupSummary) async {
        let candidates = group.options
            .map(\.name)
            .filter(ClashConfigSupport.supportsLatencyTesting(for:))
        guard !candidates.isEmpty else {
            controlState.latencyTestState = .failed(
                group: group.name,
                proxy: group.current,
                message: NSLocalizedString("No latency-testable node is available right now.", comment: "")
            )
            return
        }

        if controlState.latencyTestState.isTesting {
            return
        }

        var lastFailure: (proxy: String, message: String)?
        for proxyName in candidates {
            do {
                let delay = try await testProxyLatency(of: proxyName, in: group.name)
                updateMeasuredLatency(delay, for: proxyName, in: group.name)
            } catch {
                lastFailure = (proxyName, error.localizedDescription)
            }
        }

        if let lastFailure {
            controlState.latencyTestState = .failed(group: group.name, proxy: lastFailure.proxy, message: lastFailure.message)
        } else {
            controlState.latencyTestState = .idle
        }

        await refresh(showConnectionErrors: true)
    }

    private func testProxyLatency(of proxyName: String, in groupName: String) async throws -> Int? {
        let trimmedProxyName = proxyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProxyName.isEmpty, trimmedProxyName != "--" else {
            controlState.latencyTestState = .failed(
                group: groupName,
                proxy: proxyName,
                message: NSLocalizedString("No latency-testable node is available right now.", comment: "")
            )
            return nil
        }

        if case let .testing(currentGroup, currentProxy) = controlState.latencyTestState,
           currentGroup == groupName,
           currentProxy == trimmedProxyName {
            return nil
        }

        controlState.latencyTestState = .testing(group: groupName, proxy: trimmedProxyName)

        let delay = try await requestProxyLatency(for: trimmedProxyName)
        controlState.latencyTestState = .idle
        return delay
    }

    private func startPollingTimer() {
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh(showConnectionErrors: false)
            }
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func attachOrStart() async {
        refreshEnvironment()

        if moduleMode == .attach {
            if await isAPIReachable() {
                status = .attached
                await refresh(showConnectionErrors: true)
                return
            }

            handleFailure(
                ClashConfigSupport.localizedFormat(
                    "Attach mode only connects to an already running API at %@.",
                    environment.apiBaseURLText
                )
            )
            return
        }

        ClashModuleSettings.managedDesiredRunning = true
        setManagedRuntimePhase(.launching)

        do {
            try await builtInRuntimeManager.start()
            refreshEnvironment()
        } catch {
            syncBuiltInState()
            handleFailure(error.localizedDescription)
            return
        }

        guard await waitForAPIReachable() else {
            handleFailure(ClashModuleError.managedRuntimeAPIUnavailable.localizedDescription)
            return
        }

        do {
            try await postManagedRuntimeStart(showConnectionErrors: true)
        } catch {
            handleFailure(error.localizedDescription)
        }
    }

    private func refresh(showConnectionErrors: Bool) async {
        refreshEnvironment()

        guard await isAPIReachable() else {
            version = nil
            runtimeConfig = nil
            trafficSnapshot = .zero
            proxyGroups = []

            if moduleMode == .managed {
                if builtInRuntimeManager.isRunning {
                    setManagedRuntimePhase(.launching)
                } else {
                    let shouldPreserveManagedState = !showConnectionErrors && shouldPreserveSilentManagedRefreshState()
                    if !shouldPreserveManagedState {
                        setManagedRuntimePhase(.stopped)
                    }
                    if showConnectionErrors {
                        handleFailure(
                            ClashConfigSupport.localizedFormat("API not reachable at %@.", environment.apiBaseURLText)
                        )
                    }
                }
            } else if showConnectionErrors {
                handleFailure(
                    ClashConfigSupport.localizedFormat("API not reachable at %@.", environment.apiBaseURLText)
                )
            } else if case .failed = status {
                // Preserve the last explicit attach-mode error until a user action clears it.
            } else {
                status = .disconnected
            }

            return
        }

        do {
            version = try await request(path: "/version", method: "GET", body: nil)
            runtimeConfig = try await request(path: "/configs", method: "GET", body: nil)
            trafficSnapshot = (try? await requestTrafficSnapshot()) ?? .zero
            if let runtimeMode = runtimeConfig?.mode, let connectionMode = ClashConnectionMode(rawValue: runtimeMode) {
                controlState.connectionMode = connectionMode
                if moduleMode == .managed {
                    ClashModuleSettings.managedConnectionMode = connectionMode
                }
            }

            let systemProxyEnabled = await systemProxyController.isEnabled(expectedPort: currentSystemProxyPort)
            proxyGroups = try await requestProxyGroups()

            if moduleMode == .managed {
                if builtInRuntimeManager.isRunning {
                    setManagedRuntimePhase(.running)
                } else {
                    setManagedRuntimePhase(.failed(NSLocalizedString("Managed API is reachable, but Island's bundled runtime is not the active owner of that controller port.", comment: "")))
                }

                syncManagedCaptureState(systemProxyEnabled: systemProxyEnabled)
                ClashModuleSettings.managedLastHealthyProfileID = activeBuiltInProfile?.id
                if proxyProviders.isEmpty && ruleProviders.isEmpty {
                    await loadProviders()
                }
            } else {
                controlState.captureMode = systemProxyEnabled ? .systemProxy : .none
                controlState.capturePhase = systemProxyEnabled ? .active : .inactive
                status = .attached
            }

            refreshEnvironment()
        } catch {
            if showConnectionErrors {
                handleFailure(error.localizedDescription)
            }
        }
    }

    private func reloadCurrentConfig() async {
        guard let configFilePath = environment.configFilePath else {
            handleFailure(NSLocalizedString("No config file available to reload.", comment: ""))
            return
        }

        if moduleMode == .managed {
            do {
                setManagedRuntimePhase(.preparing)
                try await builtInRuntimeManager.prepareRuntimeConfiguration(updateActiveProfileIfNeeded: false)
                syncBuiltInState()
                if controlState.captureMode == .tun {
                    await restartManagedRuntime(showConnectionErrors: true)
                    return
                }
            } catch {
                syncBuiltInState()
                handleFailure(error.localizedDescription)
                return
            }
        }

        do {
            let body = try JSONSerialization.data(withJSONObject: ["path": configFilePath])
            let _: EmptyAPIResponse = try await request(path: "/configs", method: "PUT", body: body)
            if moduleMode == .managed {
                setManagedRuntimePhase(.running)
            }
            await refresh(showConnectionErrors: true)
        } catch {
            handleFailure(ClashConfigSupport.localizedFormat("Reload failed: %@", error.localizedDescription))
        }
    }

    private func updateProxySelection(proxyName: String, in groupName: String) async {
        do {
            let body = try JSONSerialization.data(withJSONObject: ["name": proxyName])
            let encodedGroup = ClashConfigSupport.encodePathComponent(groupName)
            let _: EmptyAPIResponse = try await request(path: "/proxies/\(encodedGroup)", method: "PUT", body: body)
            await refresh(showConnectionErrors: true)
        } catch {
            handleFailure(ClashConfigSupport.localizedFormat("Switch failed: %@", error.localizedDescription))
        }
    }

    private func refreshRules() async {
        isLoadingRules = true
        rulesLoadError = nil
        defer { isLoadingRules = false }

        do {
            ruleEntries = try await requestRuleEntries()
        } catch {
            ruleEntries = []
            rulesLoadError = error.localizedDescription
        }
    }

    private func loadConnectionOverview() async {
        isLoadingConnectionOverview = true
        connectionOverviewError = nil
        defer { isLoadingConnectionOverview = false }

        do {
            connectionOverview = try await requestConnectionOverview()
        } catch {
            connectionOverview = .empty
            connectionOverviewError = error.localizedDescription
        }
    }

    private func loadProviders() async {
        guard moduleMode == .managed else {
            return
        }

        isLoadingProviders = true
        providerLoadError = nil
        defer { isLoadingProviders = false }

        do {
            proxyProviders = try await requestProxyProviders()
            ruleProviders = try await requestRuleProviders()
            refreshEnvironment()
        } catch {
            providerLoadError = error.localizedDescription
        }
    }

    private func triggerProxyProviderUpdate(named name: String) async {
        do {
            let encodedName = ClashConfigSupport.encodePathComponent(name)
            let _: EmptyAPIResponse = try await request(path: "/providers/proxies/\(encodedName)", method: "PUT", body: nil)
            await loadProviders()
        } catch {
            providerLoadError = error.localizedDescription
        }
    }

    private func triggerProxyProviderHealthcheck(named name: String) async {
        do {
            let encodedName = ClashConfigSupport.encodePathComponent(name)
            let _: EmptyAPIResponse = try await request(path: "/providers/proxies/\(encodedName)/healthcheck", method: "GET", body: nil)
            await loadProviders()
        } catch {
            providerLoadError = error.localizedDescription
        }
    }

    private func triggerRuleProviderUpdate(named name: String) async {
        do {
            let encodedName = ClashConfigSupport.encodePathComponent(name)
            let _: EmptyAPIResponse = try await request(path: "/providers/rules/\(encodedName)", method: "PUT", body: nil)
            await loadProviders()
        } catch {
            providerLoadError = error.localizedDescription
        }
    }

    private func streamLogs() async {
        defer {
            isStreamingLogs = false
        }

        do {
            let request = makeAPIRequest(path: "/logs", method: "GET", timeoutInterval: 0)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                throw ClashModuleError.httpStatus(httpResponse.statusCode)
            }

            for try await line in bytes.lines {
                if Task.isCancelled {
                    return
                }

                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLine.isEmpty else {
                    continue
                }

                let logEntry = Self.logEntry(from: trimmedLine)
                logEntries.append(logEntry)
                if logEntries.count > 400 {
                    logEntries.removeFirst(logEntries.count - 400)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            logStreamError = error.localizedDescription
        }
    }

    private func updateManagedPorts(httpPort: Int?, socksPort: Int?, mixedPort: Int?) async {
        guard moduleMode == .managed else {
            return
        }

        ClashModuleSettings.setManagedPortOverrides(httpPort: httpPort, socksPort: socksPort, mixedPort: mixedPort)

        do {
            setManagedRuntimePhase(.preparing)
            try await builtInRuntimeManager.prepareRuntimeConfiguration(updateActiveProfileIfNeeded: false)
            syncBuiltInState()

            if builtInRuntimeManager.isRunning {
                if controlState.captureMode == .tun {
                    await restartManagedRuntime(showConnectionErrors: true)
                } else if await isAPIReachable() {
                    await reloadCurrentConfig()
                } else {
                    await attachOrStart()
                }
            } else {
                setManagedRuntimePhase(.stopped)
                objectWillChange.send()
            }
        } catch {
            handleFailure(error.localizedDescription)
        }
    }

    private func request<T: Decodable>(path: String, method: String, body: Data?) async throws -> T {
        let request = makeAPIRequest(path: path, method: method, body: body, timeoutInterval: 6)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode), httpResponse.statusCode != 204 {
            throw ClashModuleError.httpStatus(httpResponse.statusCode)
        }

        if T.self == EmptyAPIResponse.self {
            return EmptyAPIResponse() as! T
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func requestJSONObject(path: String, method: String = "GET", body: Data? = nil) async throws -> [String: Any] {
        let request = makeAPIRequest(path: path, method: method, body: body, timeoutInterval: 6)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode), httpResponse.statusCode != 204 {
            throw ClashModuleError.httpStatus(httpResponse.statusCode)
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClashModuleError.invalidResponse
        }

        return object
    }

    private func requestRuleEntries() async throws -> [ClashRuleEntry] {
        let root = try await requestJSONObject(path: "/rules")
        guard let rules = root["rules"] as? [[String: Any]] else {
            throw ClashModuleError.invalidResponse
        }

        return rules.enumerated().map { index, rawRule in
            let type = (rawRule["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload = (rawRule["payload"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = (rawRule["proxy"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (rawRule["adapter"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (rawRule["action"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = (rawRule["provider"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (rawRule["payloadType"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            let normalizedType = (type?.isEmpty == false ? type! : NSLocalizedString("Unknown", comment: ""))
            let normalizedPayload = (payload?.isEmpty == false ? payload! : NSLocalizedString("No payload", comment: ""))
            let normalizedTarget = (target?.isEmpty == false ? target! : NSLocalizedString("No target", comment: ""))

            return ClashRuleEntry(
                id: "\(index)-\(normalizedType)-\(normalizedPayload)-\(normalizedTarget)",
                type: normalizedType,
                payload: normalizedPayload,
                target: normalizedTarget,
                source: source?.isEmpty == false ? source : nil
            )
        }
    }

    private func requestConnectionOverview() async throws -> ClashConnectionOverview {
        let root = try await requestJSONObject(path: "/connections")

        let rawConnections = root["connections"] as? [[String: Any]]
        let activeConnectionCount = rawConnections?.count
            ?? (root["connections"] as? [Any])?.count
            ?? (root["total"] as? Int)
            ?? 0

        return ClashConnectionOverview(
            activeConnectionCount: activeConnectionCount,
            uploadTotalBytes: Self.int64Value(for: "uploadTotal", in: root),
            downloadTotalBytes: Self.int64Value(for: "downloadTotal", in: root),
            memoryBytes: Self.int64Value(for: "memory", in: root)
        )
    }

    private func requestProxyLatency(for proxyName: String) async throws -> Int? {
        let encodedProxy = ClashConfigSupport.encodePathComponent(proxyName)
        let encodedURL = ClashConfigSupport.encodeQueryItem("https://www.gstatic.com/generate_204")
        let root = try await requestJSONObject(
            path: "/proxies/\(encodedProxy)/delay?url=\(encodedURL)&timeout=5000"
        )
        return root["delay"] as? Int
    }

    private func requestTrafficSnapshot() async throws -> ClashTrafficSnapshot {
        let request = makeAPIRequest(path: "/traffic", method: "GET", timeoutInterval: 3)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw ClashModuleError.httpStatus(httpResponse.statusCode)
        }

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            guard let data = trimmed.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let upBytesPerSecond = ClashConfigSupport.doubleValue(for: "up", in: object)
            let downBytesPerSecond = ClashConfigSupport.doubleValue(for: "down", in: object)
            return ClashTrafficSnapshot(
                upBytesPerSecond: upBytesPerSecond,
                downBytesPerSecond: downBytesPerSecond
            )
        }

        throw ClashModuleError.invalidResponse
    }

    private func makeAPIRequest(
        path: String,
        method: String,
        body: Data? = nil,
        timeoutInterval: TimeInterval
    ) -> URLRequest {
        ClashConfigSupport.makeAPIRequest(
            base: environment.apiBaseURL,
            path: path,
            method: method,
            body: body,
            timeoutInterval: timeoutInterval,
            authorizationSecret: resolvedAPIAuthorizationSecret
        )
    }

    private var resolvedAPIAuthorizationSecret: String? {
        guard moduleMode == .attach else {
            return nil
        }

        return ClashConfigSupport.resolvedAttachAPISecret(
            explicitSecret: ClashModuleSettings.attachAPISecret,
            configFilePath: environment.configFilePath
        )
    }

    private func requestProxyGroups() async throws -> [ClashProxyGroupSummary] {
        let root = try await requestJSONObject(path: "/proxies")
        guard let proxies = root["proxies"] as? [String: Any] else {
            throw ClashModuleError.invalidResponse
        }

        var groups: [ClashProxyGroupSummary] = []
        for key in orderedProxyGroupKeys(in: proxies) {
            guard let proxy = proxies[key] as? [String: Any],
                  let options = proxy["all"] as? [String],
                  !options.isEmpty,
                  let type = proxy["type"] as? String else {
                continue
            }

            let currentProxyName = proxy["now"] as? String ?? "--"
            let optionSummaries = options.map {
                ClashProxyOptionSummary(name: $0, delay: latestDelay(for: $0, in: proxies))
            }
            guard shouldIncludeProxyGroup(named: key) else {
                continue
            }
            groups.append(
                ClashProxyGroupSummary(
                    name: key,
                    type: type,
                    current: currentProxyName,
                    options: optionSummaries
                )
            )
        }

        return groups
    }

    private func requestProxyProviders() async throws -> [ClashProviderSummary] {
        let root = try await requestJSONObject(path: "/providers/proxies")
        guard let providers = root["providers"] as? [String: Any] else {
            return []
        }

        return providers.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.compactMap { key in
            guard let rawProvider = providers[key] as? [String: Any] else {
                return nil
            }

            let displayName = ((rawProvider["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? ((rawProvider["name"] as? String) ?? key)
                : key
            let proxies = rawProvider["proxies"] as? [Any]
            let nodeCount = proxies?.count
                ?? (rawProvider["proxyCount"] as? Int)
                ?? 0

            return ClashProviderSummary(
                name: displayName,
                type: (rawProvider["type"] as? String) ?? NSLocalizedString("Proxy Provider", comment: ""),
                vehicleType: rawProvider["vehicleType"] as? String,
                nodeCount: nodeCount,
                updatedAtText: Self.providerTimestampText(from: rawProvider["updatedAt"]),
                testURL: rawProvider["testUrl"] as? String
            )
        }
    }

    private func requestRuleProviders() async throws -> [ClashRuleProviderSummary] {
        let root = try await requestJSONObject(path: "/providers/rules")
        guard let providers = root["providers"] as? [String: Any] else {
            return []
        }

        return providers.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.compactMap { key in
            guard let rawProvider = providers[key] as? [String: Any] else {
                return nil
            }

            let displayName = ((rawProvider["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? ((rawProvider["name"] as? String) ?? key)
                : key
            let ruleCount = (rawProvider["ruleCount"] as? Int)
                ?? (rawProvider["rules"] as? [Any])?.count
                ?? 0

            return ClashRuleProviderSummary(
                name: displayName,
                type: (rawProvider["type"] as? String) ?? NSLocalizedString("Rule Provider", comment: ""),
                vehicleType: rawProvider["vehicleType"] as? String,
                ruleCount: ruleCount,
                updatedAtText: Self.providerTimestampText(from: rawProvider["updatedAt"]),
                behavior: rawProvider["behavior"] as? String
            )
        }
    }

    private func orderedProxyGroupKeys(in data: [String: Any]) -> [String] {
        let fallbackSortedKeys = data.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        let configuredOrder = ClashConfigSupport.proxyGroupOrder(fromConfigFileAt: environment.configFilePath)
        guard !configuredOrder.isEmpty else {
            return fallbackSortedKeys
        }

        let orderByName = Dictionary(uniqueKeysWithValues: configuredOrder.enumerated().map { ($1, $0) })
        return fallbackSortedKeys.sorted { lhs, rhs in
            let lhsIndex = orderByName[lhs]
            let rhsIndex = orderByName[rhs]

            switch (lhsIndex, rhsIndex) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
        }
    }

    private func shouldIncludeProxyGroup(named name: String) -> Bool {
        guard name.caseInsensitiveCompare("GLOBAL") == .orderedSame else {
            return true
        }

        return controlState.connectionMode == .global
    }

    private func latestDelay(for proxyName: String, in data: [String: Any]) -> Int? {
        guard let proxy = data[proxyName] as? [String: Any] else {
            return nil
        }

        let delayHistory = proxy["history"] as? [[String: Any]]
        return delayHistory?.compactMap { $0["delay"] as? Int }.last(where: { $0 > 0 })
    }

    private func updateMeasuredLatency(_ delay: Int?, for proxyName: String, in groupName: String) {
        proxyGroups = proxyGroups.map { group in
            guard group.name == groupName else {
                return group
            }

            let updatedOptions = group.options.map { option in
                guard option.name == proxyName else {
                    return option
                }

                return ClashProxyOptionSummary(name: option.name, delay: delay)
            }

            return ClashProxyGroupSummary(
                name: group.name,
                type: group.type,
                current: group.current,
                options: updatedOptions
            )
        }
    }

    private func isAPIReachable() async -> Bool {
        do {
            let _: ClashRuntimeVersion = try await request(path: "/version", method: "GET", body: nil)
            return true
        } catch {
            return false
        }
    }

    private func waitForAPIReachable() async -> Bool {
        for _ in 0..<20 {
            refreshEnvironment()
            if await isAPIReachable() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(500))
        }

        return false
    }

    private func restoreBuiltInRuntimeIfNeeded() async {
        guard moduleMode == .managed, ClashModuleSettings.managedDesiredRunning else {
            setManagedRuntimePhase(.stopped)
            syncManagedCaptureState(systemProxyEnabled: false)
            return
        }

        setManagedRuntimePhase(.launching)
        do {
            try await builtInRuntimeManager.start()
            refreshEnvironment()
            guard await waitForAPIReachable() else {
                handleFailure(ClashModuleError.managedRuntimeAPIUnavailable.localizedDescription)
                return
            }

            try await postManagedRuntimeStart(showConnectionErrors: false)
        } catch {
            syncBuiltInState()
            handleFailure(error.localizedDescription)
        }
    }

    private func applyBuiltInRuntimeConfiguration(
        reloadRuntimeIfPossible: Bool,
        updateActiveProfileIfNeeded: Bool
    ) async throws {
        setManagedRuntimePhase(.preparing)
        try await builtInRuntimeManager.prepareRuntimeConfiguration(updateActiveProfileIfNeeded: updateActiveProfileIfNeeded)
        syncBuiltInState()

        let apiReachable = await isAPIReachable()
        let requiresRestart = controlState.captureMode == .tun

        if reloadRuntimeIfPossible, apiReachable, builtInRuntimeManager.isRunning, !requiresRestart {
            await reloadCurrentConfig()
            return
        }

        if reloadRuntimeIfPossible,
           moduleMode == .managed,
           activeBuiltInProfile != nil {
            ClashModuleSettings.managedDesiredRunning = true
            if builtInRuntimeManager.isRunning {
                await restartManagedRuntime(showConnectionErrors: true)
            } else {
                await attachOrStart()
            }
        } else if !apiReachable && !builtInRuntimeManager.isRunning {
            setManagedRuntimePhase(.stopped)
        }
    }

    private func applyManagedCaptureModeChange(
        from previousMode: ClashManagedCaptureMode,
        to newMode: ClashManagedCaptureMode
    ) async {
        refreshEnvironment()

        do {
            setCapturePhase(.applying)
            try await builtInRuntimeManager.prepareRuntimeConfiguration(updateActiveProfileIfNeeded: false)
            syncBuiltInState()

            guard builtInRuntimeManager.isRunning else {
                syncManagedCaptureState(systemProxyEnabled: false)
                setManagedRuntimePhase(.stopped)
                return
            }

            if previousMode == .tun || newMode == .tun {
                do {
                    try await restartManagedRuntimeOrThrow(showConnectionErrors: true)
                } catch {
                    await rollbackManagedCaptureModeChange(
                        to: previousMode,
                        failureMessage: error.localizedDescription
                    )
                }
                return
            }

            if newMode == .systemProxy {
                try await setSystemProxyEnabled(true)
                setCapturePhase(.active)
            } else {
                try await setSystemProxyEnabled(false)
                setCapturePhase(.inactive)
            }

            await refresh(showConnectionErrors: true)
        } catch {
            controlState.captureMode = previousMode
            ClashModuleSettings.managedCaptureMode = previousMode
            setCapturePhase(.failed(error.localizedDescription))
            handleFailure(error.localizedDescription)
        }
    }

    private func applyManagedTunOptionsChange() async {
        guard moduleMode == .managed else {
            return
        }

        do {
            try await builtInRuntimeManager.prepareRuntimeConfiguration(updateActiveProfileIfNeeded: false)
            syncBuiltInState()

            if builtInRuntimeManager.isRunning, controlState.captureMode == .tun {
                await restartManagedRuntime(showConnectionErrors: true)
            } else {
                refreshEnvironment()
            }
        } catch {
            handleFailure(error.localizedDescription)
        }
    }

    private func restartManagedRuntime(showConnectionErrors: Bool) async {
        do {
            try await restartManagedRuntimeOrThrow(showConnectionErrors: showConnectionErrors)
        } catch {
            handleFailure(error.localizedDescription)
        }
    }

    private func restartManagedRuntimeOrThrow(showConnectionErrors: Bool) async throws {
        setManagedRuntimePhase(.reloading)
        await disableManagedCaptureIfNeeded()
        builtInRuntimeManager.stop()
        try await builtInRuntimeManager.start()
        refreshEnvironment()

        guard await waitForAPIReachable() else {
            throw ClashModuleError.managedRuntimeAPIUnavailable
        }

        try await postManagedRuntimeStart(showConnectionErrors: showConnectionErrors)
    }

    private func stopManagedRuntime() async {
        setManagedRuntimePhase(.stopping)
        await disableManagedCaptureIfNeeded()
        builtInRuntimeManager.stop()
        setManagedRuntimePhase(.stopped)
        status = .disconnected
        trafficSnapshot = .zero
        proxyGroups = []
    }

    private func postManagedRuntimeStart(showConnectionErrors: Bool) async throws {
        await refresh(showConnectionErrors: showConnectionErrors)
        await restoreManagedConnectionModeIfNeeded()

        setCapturePhase(.applying)
        try await applyCurrentManagedCaptureMode()
        await refresh(showConnectionErrors: showConnectionErrors)
    }

    private func applyCurrentManagedCaptureMode() async throws {
        switch controlState.captureMode {
        case .none:
            try await setSystemProxyEnabled(false)
            setCapturePhase(.inactive)
        case .systemProxy:
            try await setSystemProxyEnabled(true)
            setCapturePhase(.active)
        case .tun:
            try await verifyManagedTunCapture()
            setCapturePhase(.active)
        }
    }

    private func rollbackManagedCaptureModeChange(
        to previousMode: ClashManagedCaptureMode,
        failureMessage: String
    ) async {
        controlState.captureMode = previousMode
        ClashModuleSettings.managedCaptureMode = previousMode
        refreshEnvironment()

        do {
            try await builtInRuntimeManager.prepareRuntimeConfiguration(updateActiveProfileIfNeeded: false)
            syncBuiltInState()
            try await restartManagedRuntimeOrThrow(showConnectionErrors: false)
            appendLogs("Managed TUN verification failed. Restored \(previousMode.title). \(failureMessage)")
            await refresh(showConnectionErrors: false)
        } catch {
            setCapturePhase(.failed(failureMessage))
            handleFailure(error.localizedDescription)
        }
    }

    private func verifyManagedTunCapture() async throws {
        let probeProcess = try startManagedTunProbeProcess()
        defer {
            if probeProcess.isRunning {
                probeProcess.terminate()
            }
        }

        try await Task.sleep(nanoseconds: 500_000_000)

        for _ in 0..<6 {
            if try await managedTunCapturedProbeTraffic(host: Self.managedTunProbeHost) {
                return
            }

            try await Task.sleep(nanoseconds: 400_000_000)
        }

        throw ClashModuleError.managedTunCaptureUnavailable
    }

    private func startManagedTunProbeProcess() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "--noproxy", "*",
            "--silent",
            "--show-error",
            "--max-time", "6",
            Self.managedTunProbeURL,
            "--output", "/dev/null",
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        return process
    }

    private func managedTunCapturedProbeTraffic(host expectedHost: String) async throws -> Bool {
        let root = try await requestJSONObject(path: "/connections")
        guard let rawConnections = root["connections"] as? [[String: Any]] else {
            throw ClashModuleError.invalidResponse
        }

        let normalizedHost = expectedHost.lowercased()
        return rawConnections.contains { rawConnection in
            guard let metadata = rawConnection["metadata"] as? [String: Any],
                  let host = metadata["host"] as? String else {
                return false
            }

            return host.lowercased().contains(normalizedHost)
        }
    }

    private func disableManagedCaptureIfNeeded() async {
        guard moduleMode == .managed else {
            return
        }

        if controlState.captureMode == .systemProxy || controlState.capturePhase == .active {
            try? await setSystemProxyEnabled(false)
        }
        setCapturePhase(.inactive)
    }

    private func restoreManagedConnectionModeIfNeeded() async {
        guard moduleMode == .managed,
              let runtimeMode = runtimeConfig?.mode,
              let currentMode = ClashConnectionMode(rawValue: runtimeMode) else {
            return
        }

        let desiredMode = ClashModuleSettings.managedConnectionMode
        guard desiredMode != currentMode else {
            return
        }

        controlState.connectionMode = desiredMode
        await setConnectionMode(desiredMode, previousMode: currentMode, persistOnSuccess: false)
    }

    private func syncBuiltInState() {
        builtInProfiles = builtInRuntimeManager.profiles
        syncBuiltInProfileStatus()
        refreshEnvironment()
    }

    private func syncBuiltInProfileStatus() {
        guard let profile = activeBuiltInProfile else {
            builtInProfileSyncStatus = .idle
            return
        }

        if let error = profile.lastErrorMessage, !error.isEmpty {
            builtInProfileSyncStatus = .failed(error)
            return
        }

        if profile.lastUpdatedAt != nil || profile.sourceKind == .importedFile {
            builtInProfileSyncStatus = .ready(profile.lastUpdatedAt)
        } else {
            builtInProfileSyncStatus = .idle
        }
    }

    private func syncManagedCaptureState(systemProxyEnabled: Bool) {
        guard moduleMode == .managed else {
            return
        }

        switch controlState.captureMode {
        case .none:
            controlState.capturePhase = .inactive
        case .systemProxy:
            controlState.capturePhase = systemProxyEnabled ? .active : .inactive
        case .tun:
            controlState.capturePhase = builtInRuntimeManager.isRunning ? .active : .inactive
        }
        refreshEnvironment()
        syncLegacyStatus()
    }

    private func handleBuiltInRuntimeTermination(_ exitStatus: Int32) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            if self.controlState.captureMode == .systemProxy {
                try? await self.setSystemProxyEnabled(false)
            }
            self.controlState.capturePhase = .inactive

            if exitStatus == 0 {
                self.setManagedRuntimePhase(.stopped)
                if case .runningOwned = self.status {
                    self.status = .disconnected
                }
            } else {
                self.handleFailure(
                    ClashConfigSupport.localizedFormat("Core exited with status %d.", exitStatus)
                )
            }
        }
    }

    private func appendLogs(_ string: String) {
        for line in string.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            recentLogs.append(trimmed)
        }

        if recentLogs.count > 10 {
            recentLogs.removeFirst(recentLogs.count - 10)
        }
    }

    private func setManagedRuntimePhase(_ phase: ClashManagedRuntimePhase) {
        runtimePhase = phase
        syncLegacyStatus()
    }

    private func setCapturePhase(_ phase: ClashManagedCapturePhase) {
        controlState.capturePhase = phase
        syncLegacyStatus()
    }

    private func handleFailure(_ message: String) {
        if moduleMode == .managed {
            setManagedRuntimePhase(.failed(message))
        } else {
            status = .failed(message)
        }
    }

    private func shouldPreserveSilentManagedRefreshState() -> Bool {
        switch runtimePhase {
        case .preparing, .launching, .reloading, .failed:
            return true
        case .stopping:
            return false
        case .running:
            return builtInRuntimeManager.isRunning
        case .stopped:
            return false
        }
    }

    private func syncLegacyStatus() {
        guard moduleMode == .managed else {
            return
        }

        if case let .failed(message) = runtimePhase {
            status = .failed(message)
            return
        }

        if case let .failed(message) = controlState.capturePhase {
            status = .failed(message)
            return
        }

        if controlState.capturePhase == .applying {
            status = .launching
            return
        }

        switch runtimePhase {
        case .stopped:
            status = .disconnected
        case .preparing, .launching, .reloading, .stopping:
            status = .launching
        case .running:
            status = .runningOwned
        case .failed:
            break
        }
    }

    private func portText(for port: Int?) -> String {
        guard let port, port > 0 else {
            return "--"
        }

        return String(port)
    }

    private static func snapshotPath(for profile: ClashBuiltInProfile) -> String {
        ClashBuiltInPaths.profilesDirectoryURL()
            .appendingPathComponent(profile.snapshotRelativePath)
            .path
    }

    private static func logEntry(from rawLine: String) -> ClashLogEntry {
        let normalizedLine = rawLine.hasPrefix("data:")
            ? rawLine.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            : rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = normalizedLine.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let message = (object["payload"] as? String)
                ?? (object["message"] as? String)
                ?? normalizedLine
            let type = ((object["type"] as? String) ?? (object["level"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let level = ClashLogLevelFilter(rawValue: type.lowercased()) ?? inferredLogLevel(from: message)
            return ClashLogEntry(level: level, message: message, rawLine: normalizedLine)
        }

        return ClashLogEntry(level: inferredLogLevel(from: normalizedLine), message: normalizedLine, rawLine: normalizedLine)
    }

    private static func inferredLogLevel(from text: String) -> ClashLogLevelFilter {
        let uppercased = text.uppercased()
        if uppercased.contains("ERROR") {
            return .error
        }
        if uppercased.contains("WARN") {
            return .warning
        }
        if uppercased.contains("DEBUG") {
            return .debug
        }
        return .info
    }

    private static func int64Value(for key: String, in object: [String: Any]) -> Int64? {
        if let value = object[key] as? Int64 {
            return value
        }
        if let value = object[key] as? Int {
            return Int64(value)
        }
        if let value = object[key] as? Double {
            return Int64(value)
        }
        if let value = object[key] as? NSNumber {
            return value.int64Value
        }
        return nil
    }

    private static func conciseRuntimeStatusMessage(_ message: String) -> String {
        let condensed = message
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if condensed.localizedCaseInsensitiveContains("unexpected end of file")
            || condensed.localizedCaseInsensitiveContains("uncompress failed")
            || condensed.localizedCaseInsensitiveContains("gunzip") {
            return NSLocalizedString(
                "Bundled Mihomo archive is incomplete or corrupted. Rebuild the app to refresh bundled resources.",
                comment: ""
            )
        }

        if condensed.count > 180 {
            return String(condensed.prefix(177)) + "..."
        }

        return condensed
    }

    private static func providerTimestampText(from value: Any?) -> String? {
        guard let rawValue = value else {
            return nil
        }

        let date: Date?
        if let unixSeconds = rawValue as? TimeInterval {
            date = unixSeconds > 10_000_000_000
                ? Date(timeIntervalSince1970: unixSeconds / 1000)
                : Date(timeIntervalSince1970: unixSeconds)
        } else if let string = rawValue as? String {
            if let doubleValue = TimeInterval(string) {
                date = doubleValue > 10_000_000_000
                    ? Date(timeIntervalSince1970: doubleValue / 1000)
                    : Date(timeIntervalSince1970: doubleValue)
            } else {
                date = iso8601ProviderDateFormatter.date(from: string)
                    ?? iso8601ProviderDateFormatterWithoutFractionalSeconds.date(from: string)
            }
        } else {
            date = nil
        }

        guard let date else {
            return nil
        }

        return providerDateFormatter.string(from: date)
    }

    private static func discoverEnvironment(
        mode: ClashModuleMode,
        builtInRuntimeManager: ClashBuiltInRuntimeManager,
        activeBuiltInProfileName: String?,
        captureMode: ClashManagedCaptureMode,
        providerCounts: ClashProviderCountSnapshot
    ) -> ClashRuntimeEnvironment {
        switch mode {
        case .attach:
            let configuredAttachConfigFilePath = ClashConfigSupport.normalizedPath(ClashModuleSettings.attachConfigFilePath)
            let configuredAttachAPIBaseURL = ClashModuleSettings.attachAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let configFilePath = ClashConfigSupport.validFilePath(from: configuredAttachConfigFilePath) ?? discoverExistingConfigFilePath()
            let apiBaseURL = ClashConfigSupport.validURL(from: configuredAttachAPIBaseURL)
                ?? ClashConfigSupport.urlFromConfigFile(at: configFilePath)
                ?? ClashConfigSupport.defaultAPIBaseURL()

            return ClashRuntimeEnvironment(
                moduleMode: mode,
                coreBinaryPath: nil,
                configFilePath: configFilePath,
                configDirectoryPath: configFilePath.map(ClashConfigSupport.configDirectoryPath(for:)),
                apiBaseURL: apiBaseURL,
                uiBaseURL: nil,
                activeProfileName: nil,
                captureMode: .none,
                isTunAvailable: false,
                activeProviderCounts: .zero
            )
        case .managed:
            return ClashRuntimeEnvironment(
                moduleMode: mode,
                coreBinaryPath: builtInRuntimeManager.installedBinaryPath,
                configFilePath: builtInRuntimeManager.runtimeConfigFilePath,
                configDirectoryPath: builtInRuntimeManager.runtimeDirectoryPath,
                apiBaseURL: builtInRuntimeManager.apiBaseURL,
                uiBaseURL: builtInRuntimeManager.uiBaseURL,
                activeProfileName: activeBuiltInProfileName,
                captureMode: captureMode,
                isTunAvailable: ClashManagedCaptureMode.isTunExposedInCurrentBuild,
                activeProviderCounts: providerCounts
            )
        }
    }

    private static func discoverExistingConfigFilePath() -> String? {
        let fileManager = FileManager.default
        let homeURL = fileManager.homeDirectoryForCurrentUser
        let mihomoURL = homeURL.appendingPathComponent(".config/mihomo", isDirectory: true)
        let clashURL = homeURL.appendingPathComponent(".config/clash", isDirectory: true)

        if let mihomoProfile = latestYAMLFile(in: mihomoURL.appendingPathComponent("profiles", isDirectory: true)) {
            return mihomoProfile.path
        }

        if let clashProfile = latestYAMLFile(in: clashURL) {
            return clashProfile.path
        }

        if let mihomoConfig = latestYAMLFile(in: mihomoURL) {
            return mihomoConfig.path
        }

        return nil
    }

    private static func latestYAMLFile(in directoryURL: URL) -> URL? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        var candidates: [(url: URL, date: Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "yaml" else {
                continue
            }

            guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            let date = resourceValues.contentModificationDate ?? .distantPast
            candidates.append((url: url, date: date))
        }

        return candidates.sorted { lhs, rhs in
            lhs.date > rhs.date
        }.first?.url
    }

    private static let profileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let providerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let iso8601ProviderDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601ProviderDateFormatterWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
