import Darwin
import Foundation

private struct ClashBuiltInInstalledAssetsState: Sendable {
    let mihomoVersion: String
    let mihomoAssetName: String
    let dashboardVersion: String
    let geoDataVersion: String
}

private struct ClashBuiltInAssetInstallPlan: Sendable {
    let expectedState: ClashBuiltInInstalledAssetsState
    let stateURL: URL
    let runtimeDirectoryURL: URL
    let installedBinaryURL: URL
    let uiDirectoryURL: URL
    let mihomoArchiveURL: URL
    let dashboardArchiveURL: URL
    let geoIPSourceURL: URL
    let geoSiteSourceURL: URL
}

@MainActor
final class ClashBuiltInRuntimeManager {
    static let bundledMihomoVersion = "v1.19.23"
    static let bundledDashboardVersion = "v1.245.0"
    static let bundledGeoDataVersion = "latest"
    nonisolated private static let ioQueue = DispatchQueue(
        label: "FantasticIsland.ClashBuiltInRuntimeManager.io",
        qos: .utility
    )

    private let fileManager: FileManager
    private let profileStore: ClashBuiltInProfileStore
    private var logHandler: @MainActor (String) -> Void
    private var terminationHandler: @MainActor (Int32) -> Void
    private var process: Process?
    private var bundledAssetInstallationTask: Task<[String], Error>?
    private var startTask: Task<Void, Error>?

    private(set) var library: ClashBuiltInProfileLibrary

    init(
        fileManager: FileManager = .default,
        profileStore: ClashBuiltInProfileStore,
        logHandler: @escaping @MainActor (String) -> Void = { _ in },
        terminationHandler: @escaping @MainActor (Int32) -> Void = { _ in }
    ) {
        self.fileManager = fileManager
        self.profileStore = profileStore
        self.logHandler = logHandler
        self.terminationHandler = terminationHandler
        self.library = (try? profileStore.performInitialMigrationIfNeeded())
            ?? (try? profileStore.loadOrBootstrapLibrary())
            ?? ClashBuiltInProfileLibrary()
    }

    func updateHandlers(
        logHandler: @escaping @MainActor (String) -> Void,
        terminationHandler: @escaping @MainActor (Int32) -> Void
    ) {
        self.logHandler = logHandler
        self.terminationHandler = terminationHandler
    }

    deinit {
        process?.terminationHandler = nil
        process?.terminate()
    }

    var profiles: [ClashBuiltInProfile] {
        library.profiles
    }

    var activeProfile: ClashBuiltInProfile? {
        library.profiles.first(where: { $0.isActive }) ?? library.profiles.first
    }

    var isRunning: Bool {
        process?.isRunning == true
    }

    var apiBaseURL: URL {
        ClashConfigSupport.urlFromConfigFile(at: runtimeConfigFilePath)
            ?? ClashConfigSupport.builtInAPIBaseURL()
    }

    var uiBaseURL: URL {
        apiBaseURL.appendingPathComponent("ui")
    }

    var runtimeConfigFilePath: String {
        ClashBuiltInPaths.runtimeConfigFileURL(fileManager: fileManager).path
    }

    var runtimeDirectoryPath: String {
        ClashBuiltInPaths.runtimeDirectoryURL(fileManager: fileManager).path
    }

    var installedBinaryPath: String? {
        let path = ClashBuiltInPaths.runtimeInstalledBinaryURL(fileManager: fileManager).path
        return fileManager.fileExists(atPath: path) ? path : nil
    }

    func reloadLibrary() {
        if let updatedLibrary = try? profileStore.loadOrBootstrapLibrary() {
            library = updatedLibrary
        }
    }

    func addRemoteProfile(named preferredName: String?, urlString: String) async throws {
        library = try await profileStore.addRemoteProfile(named: preferredName, urlString: urlString)
    }

    func importProfile(from url: URL, preferredName: String? = nil) throws {
        library = try profileStore.importProfile(from: url, preferredName: preferredName)
    }

    func activateProfile(id: String) throws {
        library = try profileStore.activateProfile(id: id)
    }

    func setUpdateOnActivate(_ enabled: Bool, forProfileID id: String) throws {
        library = try profileStore.setUpdateOnActivate(enabled, forProfileID: id)
    }

    func renameProfile(id: String, named preferredName: String) throws {
        library = try profileStore.renameProfile(id: id, named: preferredName)
    }

    func deleteProfile(id: String) throws {
        library = try profileStore.deleteProfile(id: id)
    }

    func refreshActiveProfile() async throws {
        guard let profile = activeProfile else {
            throw ClashModuleError.noBuiltInProfile
        }

        switch profile.sourceKind {
        case .remoteSubscription:
            library = try await profileStore.refreshRemoteProfile(id: profile.id)
        case .importedFile:
            library = try profileStore.reimportProfile(id: profile.id)
        }
    }

    func prepareRuntimeConfiguration(updateActiveProfileIfNeeded: Bool) async throws {
        try await installBundledAssetsIfNeeded()
        let profile = try await ensureActiveProfileReady(updateActiveProfileIfNeeded: updateActiveProfileIfNeeded)
        let snapshot = try profileStore.readSnapshot(for: profile)
        let currentPortSnapshot = ClashConfigSupport.portSnapshot(fromConfigFileAt: runtimeConfigFilePath)
        let resolvedPortOverrides = ClashConfigSupport.resolvedManagedPortOverrides(
            from: ClashModuleSettings.managedPortOverrides,
            preferredMixedPort: currentPortSnapshot.mixedPort ?? ClashConfigSupport.builtInDefaultMixedPort
        )
        let currentControllerPort = ClashConfigSupport.urlFromConfigFile(at: runtimeConfigFilePath)?.port
            ?? ClashConfigSupport.builtInDefaultControllerPort
        let reservedProxyPorts = Set([
            resolvedPortOverrides.httpPort,
            resolvedPortOverrides.socksPort,
            resolvedPortOverrides.mixedPort,
        ].compactMap { $0 })
        let controllerPort = ClashConfigSupport.availableManagedControllerPort(
            preferredPort: currentControllerPort,
            excluding: reservedProxyPorts
        )
        let dnsPort = ClashConfigSupport.availableManagedDNSPort(
            excluding: reservedProxyPorts.union([controllerPort])
        )
        let generatedConfig = try ClashConfigSupport.generatedBuiltInRuntimeConfig(
            from: snapshot,
            controllerPort: controllerPort,
            portOverrides: resolvedPortOverrides,
            dnsPort: dnsPort
        )
        let runtimeConfigURL = ClashBuiltInPaths.runtimeConfigFileURL(fileManager: fileManager)
        try await Self.writeRuntimeConfiguration(generatedConfig, to: runtimeConfigURL)
    }

    func start() async throws {
        if let startTask {
            return try await startTask.value
        }

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try await self.startRuntime()
        }
        startTask = task

        do {
            try await task.value
        } catch {
            startTask = nil
            throw error
        }

        startTask = nil
    }

    private func startRuntime() async throws {
        NSLog("[ClashManaged] start() requested. runtimeDir=%@", runtimeDirectoryPath)
        try await prepareRuntimeConfiguration(updateActiveProfileIfNeeded: true)
        guard !isRunning else {
            NSLog("[ClashManaged] start() skipped because runtime is already running.")
            return
        }

        guard let executablePath = installedBinaryPath else {
            NSLog("[ClashManaged] start() failed before launch: bundled binary missing.")
            throw ClashBuiltInRuntimeError.missingBundledBinary
        }

        await Self.terminateLingeringManagedProcesses(
            executablePath: executablePath,
            managedRuntimeDirectoryPath: runtimeDirectoryPath,
            excludingPID: process?.processIdentifier
        )

        let runtimeDirectoryURL = ClashBuiltInPaths.runtimeDirectoryURL(fileManager: fileManager)
        let configURL = ClashBuiltInPaths.runtimeConfigFileURL(fileManager: fileManager)

        let process = Process()
        let pipe = Pipe()
        let launchCommand = [
            "exec",
            Self.shellQuoted(executablePath),
            "-d",
            Self.shellQuoted(runtimeDirectoryURL.path),
            "-f",
            Self.shellQuoted(configURL.path),
        ].joined(separator: " ")

        // Launch through the system shell so the managed runtime can still be
        // executed after it is materialized into Application Support.
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", launchCommand]
        process.currentDirectoryURL = runtimeDirectoryURL
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let string = String(data: data, encoding: .utf8) else {
                return
            }

            Task { @MainActor [weak self] in
                self?.logHandler(string)
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.process = nil
                NSLog("[ClashManaged] runtime terminated with status %d.", terminatedProcess.terminationStatus)
                self.terminationHandler(terminatedProcess.terminationStatus)
            }
        }

        do {
            NSLog("[ClashManaged] launching managed runtime with shell command: %@", launchCommand)
            try process.run()
            self.process = process
            NSLog("[ClashManaged] managed runtime launch handed off to Process(pid=%d).", process.processIdentifier)
        } catch {
            NSLog("[ClashManaged] Process.run() failed: %@", error.localizedDescription)
            throw ClashBuiltInRuntimeError.launchFailed(error.localizedDescription)
        }
    }

    func stop() {
        let executablePath = installedBinaryPath
        let managedRuntimeDirectoryPath = runtimeDirectoryPath
        let trackedPID = process?.processIdentifier

        if let process {
            process.terminate()
            self.process = nil
        }

        guard let executablePath else {
            return
        }

        Task.detached(priority: .utility) {
            await Self.terminateLingeringManagedProcesses(
                executablePath: executablePath,
                managedRuntimeDirectoryPath: managedRuntimeDirectoryPath,
                excludingPID: trackedPID
            )
        }
    }

    private func ensureActiveProfileReady(updateActiveProfileIfNeeded: Bool) async throws -> ClashBuiltInProfile {
        guard var profile = activeProfile else {
            throw ClashModuleError.noBuiltInProfile
        }

        if updateActiveProfileIfNeeded, profile.sourceKind == .remoteSubscription, profile.updateOnActivate {
            do {
                library = try await profileStore.refreshRemoteProfile(id: profile.id)
                profile = activeProfile ?? profile
            } catch {
                if !profileStore.snapshotExists(for: profile) {
                    throw error
                }
            }
        }

        if !profileStore.snapshotExists(for: profile) {
            switch profile.sourceKind {
            case .remoteSubscription:
                library = try await profileStore.refreshRemoteProfile(id: profile.id)
            case .importedFile:
                guard profile.supportsReimport else {
                    throw ClashModuleError.missingProfileSnapshot
                }
                library = try profileStore.reimportProfile(id: profile.id)
            }
            profile = activeProfile ?? profile
        }

        return profile
    }

    private func installBundledAssetsIfNeeded() async throws {
        if let bundledAssetInstallationTask {
            _ = try await bundledAssetInstallationTask.value
            return
        }

        let plan = try makeBundledAssetInstallPlan()
        let task = Task<[String], Error> {
            try await Self.installBundledAssetsIfNeeded(using: plan)
        }
        bundledAssetInstallationTask = task

        do {
            let logMessages = try await task.value
            bundledAssetInstallationTask = nil
            logMessages.forEach { logHandler($0) }
        } catch {
            bundledAssetInstallationTask = nil
            throw error
        }
    }

    private func currentMihomoAssetName() -> String {
        if currentMachineArchitecture() == "x86_64" {
            return "mihomo-darwin-amd64-v1.19.23.gz"
        }
        return "mihomo-darwin-arm64-v1.19.23.gz"
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func bundledResourceURL(named name: String) -> URL? {
        let fileName = name as NSString
        let resourceName = fileName.deletingPathExtension
        let fileExtension = fileName.pathExtension.isEmpty ? nil : fileName.pathExtension
        return Bundle.main.url(forResource: resourceName, withExtension: fileExtension)
    }

    private func makeBundledAssetInstallPlan() throws -> ClashBuiltInAssetInstallPlan {
        let expectedState = ClashBuiltInInstalledAssetsState(
            mihomoVersion: Self.bundledMihomoVersion,
            mihomoAssetName: currentMihomoAssetName(),
            dashboardVersion: Self.bundledDashboardVersion,
            geoDataVersion: Self.bundledGeoDataVersion
        )

        guard let mihomoArchiveURL = bundledResourceURL(named: expectedState.mihomoAssetName) else {
            throw ClashBuiltInRuntimeError.missingBundledAsset(expectedState.mihomoAssetName)
        }
        guard let dashboardArchiveURL = bundledResourceURL(named: "compressed-dist.tgz") else {
            throw ClashBuiltInRuntimeError.missingBundledAsset("compressed-dist.tgz")
        }
        guard let geoIPSourceURL = bundledResourceURL(named: "geoip.metadb") else {
            throw ClashBuiltInRuntimeError.missingBundledAsset("geoip.metadb")
        }
        guard let geoSiteSourceURL = bundledResourceURL(named: "geosite.dat") else {
            throw ClashBuiltInRuntimeError.missingBundledAsset("geosite.dat")
        }

        return ClashBuiltInAssetInstallPlan(
            expectedState: expectedState,
            stateURL: ClashBuiltInPaths.installedAssetsStateURL(fileManager: fileManager),
            runtimeDirectoryURL: ClashBuiltInPaths.runtimeDirectoryURL(fileManager: fileManager),
            installedBinaryURL: ClashBuiltInPaths.runtimeInstalledBinaryURL(fileManager: fileManager),
            uiDirectoryURL: ClashBuiltInPaths.runtimeUIDirectoryURL(fileManager: fileManager),
            mihomoArchiveURL: mihomoArchiveURL,
            dashboardArchiveURL: dashboardArchiveURL,
            geoIPSourceURL: geoIPSourceURL,
            geoSiteSourceURL: geoSiteSourceURL
        )
    }

    nonisolated private static func writeRuntimeConfiguration(_ generatedConfig: String, to runtimeConfigURL: URL) async throws {
        try await runIO {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: runtimeConfigURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try generatedConfig.write(to: runtimeConfigURL, atomically: true, encoding: .utf8)
        }
    }

    nonisolated private static func installBundledAssetsIfNeeded(
        using plan: ClashBuiltInAssetInstallPlan
    ) async throws -> [String] {
        try await runIO {
            let fileManager = FileManager.default

            if let existingState = loadInstalledAssetsState(from: plan.stateURL),
               installedAssetsStateMatches(existingState, plan.expectedState),
               fileManager.fileExists(atPath: plan.installedBinaryURL.path),
               fileManager.fileExists(atPath: plan.uiDirectoryURL.path),
               fileManager.fileExists(atPath: plan.runtimeDirectoryURL.appendingPathComponent("geoip.metadb").path),
               fileManager.fileExists(atPath: plan.runtimeDirectoryURL.appendingPathComponent("geosite.dat").path) {
                return []
            }

            try fileManager.createDirectory(at: plan.runtimeDirectoryURL, withIntermediateDirectories: true, attributes: nil)

            var logMessages: [String] = []

            do {
                try installBundledMihomo(from: plan.mihomoArchiveURL, to: plan.installedBinaryURL)
                logMessages.append("Installed bundled Mihomo \(plan.expectedState.mihomoVersion)")
            } catch {
                throw ClashBuiltInRuntimeError.assetInstallStepFailed("Mihomo", error.localizedDescription)
            }

            do {
                try installBundledDashboard(from: plan.dashboardArchiveURL, to: plan.uiDirectoryURL)
                logMessages.append("Installed bundled metacubexd \(plan.expectedState.dashboardVersion)")
            } catch {
                throw ClashBuiltInRuntimeError.assetInstallStepFailed("Dashboard", error.localizedDescription)
            }

            do {
                try installBundledRuntimeFile(from: plan.geoIPSourceURL, to: plan.runtimeDirectoryURL.appendingPathComponent("geoip.metadb"))
                try installBundledRuntimeFile(from: plan.geoSiteSourceURL, to: plan.runtimeDirectoryURL.appendingPathComponent("geosite.dat"))
                logMessages.append("Installed bundled Clash geodata \(plan.expectedState.geoDataVersion)")
            } catch {
                throw ClashBuiltInRuntimeError.assetInstallStepFailed("Geodata", error.localizedDescription)
            }

            try saveInstalledAssetsState(plan.expectedState, to: plan.stateURL)
            return logMessages
        }
    }

    nonisolated private static func installBundledMihomo(from archiveURL: URL, to installedBinaryURL: URL) throws {
        let fileManager = FileManager.default
        let tempURL = installedBinaryURL.appendingPathExtension("tmp")
        try fileManager.createDirectory(at: installedBinaryURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try removeItemIfExists(at: tempURL)
        fileManager.createFile(atPath: tempURL.path, contents: nil)

        var shouldCleanupTemp = true
        let outputHandle = try FileHandle(forWritingTo: tempURL)
        defer {
            try? outputHandle.close()
            if shouldCleanupTemp {
                try? removeItemIfExists(at: tempURL)
            }
        }

        try runTool(
            executablePath: "/usr/bin/gunzip",
            arguments: ["-c", archiveURL.path],
            standardOutputHandle: outputHandle
        )

        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)
        try removeItemIfExists(at: installedBinaryURL)
        try fileManager.moveItem(at: tempURL, to: installedBinaryURL)
        shouldCleanupTemp = false
    }

    nonisolated private static func installBundledDashboard(from archiveURL: URL, to uiDirectoryURL: URL) throws {
        let fileManager = FileManager.default
        try removeItemIfExists(at: uiDirectoryURL)
        try fileManager.createDirectory(at: uiDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try runTool(executablePath: "/usr/bin/tar", arguments: ["-xzf", archiveURL.path, "-C", uiDirectoryURL.path])

        let indexURL = uiDirectoryURL.appendingPathComponent("index.html")
        guard fileManager.fileExists(atPath: indexURL.path) else {
            throw ClashBuiltInRuntimeError.invalidDashboardArchive
        }
    }

    nonisolated private static func installBundledRuntimeFile(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let tempURL = destinationURL.appendingPathExtension("tmp")

        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try removeItemIfExists(at: tempURL)
        try removeItemIfExists(at: destinationURL)

        var shouldCleanupTemp = true
        defer {
            if shouldCleanupTemp {
                try? removeItemIfExists(at: tempURL)
            }
        }

        try fileManager.copyItem(at: sourceURL, to: tempURL)
        try fileManager.moveItem(at: tempURL, to: destinationURL)
        shouldCleanupTemp = false
    }

    nonisolated private static func saveInstalledAssetsState(_ state: ClashBuiltInInstalledAssetsState, to url: URL) throws {
        let payload: [String: String] = [
            "mihomoVersion": state.mihomoVersion,
            "mihomoAssetName": state.mihomoAssetName,
            "dashboardVersion": state.dashboardVersion,
            "geoDataVersion": state.geoDataVersion,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    nonisolated private static func loadInstalledAssetsState(from url: URL) -> ClashBuiltInInstalledAssetsState? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mihomoVersion = object["mihomoVersion"] as? String,
              let mihomoAssetName = object["mihomoAssetName"] as? String,
              let dashboardVersion = object["dashboardVersion"] as? String,
              let geoDataVersion = object["geoDataVersion"] as? String else {
            return nil
        }

        return ClashBuiltInInstalledAssetsState(
            mihomoVersion: mihomoVersion,
            mihomoAssetName: mihomoAssetName,
            dashboardVersion: dashboardVersion,
            geoDataVersion: geoDataVersion
        )
    }

    nonisolated private static func installedAssetsStateMatches(
        _ lhs: ClashBuiltInInstalledAssetsState,
        _ rhs: ClashBuiltInInstalledAssetsState
    ) -> Bool {
        lhs.mihomoVersion == rhs.mihomoVersion
            && lhs.mihomoAssetName == rhs.mihomoAssetName
            && lhs.dashboardVersion == rhs.dashboardVersion
            && lhs.geoDataVersion == rhs.geoDataVersion
    }

    nonisolated private static func runTool(
        executablePath: String,
        arguments: [String],
        standardOutputHandle: FileHandle? = nil
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let errorPipe = Pipe()
        if let standardOutputHandle {
            process.standardOutput = standardOutputHandle
        } else {
            process.standardOutput = errorPipe
        }
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw ClashBuiltInRuntimeError.toolFailed(executablePath, error.localizedDescription)
        }

        process.waitUntilExit()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw ClashBuiltInRuntimeError.toolFailed(
                executablePath,
                errorOutput.isEmpty ? "exit \(process.terminationStatus)" : errorOutput
            )
        }
    }

    nonisolated private static func removeItemIfExists(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.removeItem(at: url)
    }

    nonisolated private static func runIO<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func terminateLingeringManagedProcesses(
        executablePath: String,
        managedRuntimeDirectoryPath: String,
        excludingPID: Int32?
    ) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let listedProcesses = Process()
                let outputPipe = Pipe()
                listedProcesses.executableURL = URL(fileURLWithPath: "/bin/ps")
                listedProcesses.arguments = ["-ax", "-o", "pid=,command="]
                listedProcesses.standardOutput = outputPipe
                listedProcesses.standardError = Pipe()

                do {
                    try listedProcesses.run()
                } catch {
                    continuation.resume()
                    return
                }

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                listedProcesses.waitUntilExit()

                guard listedProcesses.terminationStatus == 0,
                      let output = String(data: outputData, encoding: .utf8) else {
                    continuation.resume()
                    return
                }

                for line in output.split(whereSeparator: \.isNewline) {
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedLine.isEmpty else {
                        continue
                    }

                    let components = trimmedLine.split(maxSplits: 1, whereSeparator: \.isWhitespace)
                    guard components.count == 2,
                          let pid = Int32(components[0]),
                          pid != excludingPID else {
                        continue
                    }

                    let command = String(components[1])
                    guard command.contains(executablePath), command.contains(managedRuntimeDirectoryPath) else {
                        continue
                    }

                    kill(pid, SIGTERM)
                }

                continuation.resume()
            }
        }
    }
}

private enum ClashBuiltInRuntimeError: LocalizedError {
    case missingBundledAsset(String)
    case missingBundledBinary
    case invalidDashboardArchive
    case assetInstallStepFailed(String, String)
    case toolFailed(String, String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case let .missingBundledAsset(name):
            return ClashConfigSupport.localizedFormat("Bundled asset missing: %@", name)
        case .missingBundledBinary:
            return NSLocalizedString("Bundled Mihomo binary is not available.", comment: "")
        case .invalidDashboardArchive:
            return NSLocalizedString("Bundled dashboard assets are incomplete.", comment: "")
        case let .assetInstallStepFailed(step, message):
            return ClashConfigSupport.localizedFormat("%@ install failed: %@", step, message)
        case let .toolFailed(tool, message):
            return ClashConfigSupport.localizedFormat("%@ failed: %@", tool, message)
        case let .launchFailed(message):
            return ClashConfigSupport.localizedFormat("Launch failed: %@", message)
        }
    }
}

private func currentMachineArchitecture() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machine = systemInfo.machine
    return withUnsafeBytes(of: machine) { rawBuffer in
        let pointer = rawBuffer.baseAddress?.assumingMemoryBound(to: CChar.self)
        return pointer.map(String.init(cString:)) ?? "unknown"
    }
}
