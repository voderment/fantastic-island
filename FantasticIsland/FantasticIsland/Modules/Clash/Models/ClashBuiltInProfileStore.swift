import Foundation

enum ClashBuiltInPaths {
    static func rootDirectoryURL(fileManager: FileManager = .default) -> URL {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupportURL
            .appendingPathComponent("Fantastic Island", isDirectory: true)
            .appendingPathComponent("Clash", isDirectory: true)
    }

    static func legacyManagedConfigFileURL(fileManager: FileManager = .default) -> URL {
        rootDirectoryURL(fileManager: fileManager).appendingPathComponent("config.yaml")
    }

    static func profilesDirectoryURL(fileManager: FileManager = .default) -> URL {
        rootDirectoryURL(fileManager: fileManager).appendingPathComponent("Profiles", isDirectory: true)
    }

    static func profileManifestURL(fileManager: FileManager = .default) -> URL {
        profilesDirectoryURL(fileManager: fileManager).appendingPathComponent("manifest.json")
    }

    static func runtimeDirectoryURL(fileManager: FileManager = .default) -> URL {
        rootDirectoryURL(fileManager: fileManager).appendingPathComponent("Runtime", isDirectory: true)
    }

    static func runtimeConfigFileURL(fileManager: FileManager = .default) -> URL {
        runtimeDirectoryURL(fileManager: fileManager).appendingPathComponent("config.yaml")
    }

    static func runtimeBinaryDirectoryURL(fileManager: FileManager = .default) -> URL {
        runtimeDirectoryURL(fileManager: fileManager).appendingPathComponent("bin", isDirectory: true)
    }

    static func runtimeInstalledBinaryURL(fileManager: FileManager = .default) -> URL {
        runtimeBinaryDirectoryURL(fileManager: fileManager).appendingPathComponent("mihomo")
    }

    static func runtimeUIDirectoryURL(fileManager: FileManager = .default) -> URL {
        runtimeDirectoryURL(fileManager: fileManager)
            .appendingPathComponent(ClashConfigSupport.builtInUIRootDirectoryName, isDirectory: true)
            .appendingPathComponent(ClashConfigSupport.builtInUIName, isDirectory: true)
    }

    static func installedAssetsStateURL(fileManager: FileManager = .default) -> URL {
        runtimeDirectoryURL(fileManager: fileManager).appendingPathComponent("installed-assets.json")
    }
}

@MainActor
final class ClashBuiltInProfileStore {
    private let fileManager: FileManager
    private let defaults: UserDefaults

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.defaults = defaults
    }

    func loadLibrary() throws -> ClashBuiltInProfileLibrary {
        let manifestURL = ClashBuiltInPaths.profileManifestURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return ClashBuiltInProfileLibrary()
        }

        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return sanitizedLibrary(try decoder.decode(ClashBuiltInProfileLibrary.self, from: data))
    }

    func loadOrBootstrapLibrary() throws -> ClashBuiltInProfileLibrary {
        let manifestURL = ClashBuiltInPaths.profileManifestURL(fileManager: fileManager)
        let manifestExists = fileManager.fileExists(atPath: manifestURL.path)
        let library = sanitizedLibrary(try loadLibrary())
        guard !library.profiles.isEmpty else {
            guard !manifestExists else {
                return library
            }

            return try bootstrapLibraryFromLegacyStateIfAvailable()
        }

        return library
    }

    func performInitialMigrationIfNeeded() throws -> ClashBuiltInProfileLibrary {
        if defaults.bool(forKey: ClashModuleSettings.builtInProfilesMigratedKey) {
            return try loadOrBootstrapLibrary()
        }

        var library = try loadLibrary()
        if !library.profiles.isEmpty {
            defaults.set(true, forKey: ClashModuleSettings.builtInProfilesMigratedKey)
            return sanitizedLibrary(library)
        }

        let legacyConfigURL = legacyManagedConfigURL()
        let legacyConfigSnapshot = try normalizedLegacyConfigSnapshot(from: legacyConfigURL)
        var migratedProfiles: [ClashBuiltInProfile] = []

        if let legacySubscriptionURL = ClashConfigSupport.validLegacyRemoteProfileURL(from: ClashModuleSettings.managedSubscriptionURL) {
            var profile = makeProfile(
                id: UUID().uuidString.lowercased(),
                displayName: uniqueDisplayName(
                    preferredName: suggestedRemoteProfileName(for: legacySubscriptionURL),
                    existingProfiles: migratedProfiles
                ),
                sourceKind: .remoteSubscription,
                sourceLocation: legacySubscriptionURL.absoluteString,
                updateOnActivate: true,
                lastUpdatedAt: ClashModuleSettings.managedSubscriptionLastUpdatedAt,
                isActive: true,
                isStarterProfile: false
            )
            if let legacyConfigSnapshot {
                try writeSnapshot(legacyConfigSnapshot, for: profile)
                profile.lastErrorMessage = nil
            }
            migratedProfiles.append(profile)
        }

        if let legacyConfigSnapshot {
            var profile = makeProfile(
                id: UUID().uuidString.lowercased(),
                displayName: uniqueDisplayName(
                    preferredName: suggestedImportedProfileName(forPath: legacyConfigURL.path),
                    existingProfiles: migratedProfiles
                ),
                sourceKind: .importedFile,
                sourceLocation: legacyConfigURL.path,
                updateOnActivate: false,
                lastUpdatedAt: ClashModuleSettings.managedSubscriptionLastUpdatedAt ?? legacyConfigFileDate(at: legacyConfigURL),
                isActive: migratedProfiles.isEmpty,
                isStarterProfile: false
            )
            try writeSnapshot(legacyConfigSnapshot, for: profile)
            profile.lastErrorMessage = nil
            migratedProfiles.append(profile)
        }

        if migratedProfiles.isEmpty {
            library = try bootstrapLibraryFromLegacyStateIfAvailable()
        } else {
            library = ClashBuiltInProfileLibrary(schemaVersion: 1, profiles: migratedProfiles)
            try saveLibrary(library)
        }
        defaults.set(true, forKey: ClashModuleSettings.builtInProfilesMigratedKey)
        return library
    }

    func addRemoteProfile(
        named preferredName: String?,
        urlString: String,
        makeActive: Bool = true
    ) async throws -> ClashBuiltInProfileLibrary {
        guard let url = ClashConfigSupport.validRemoteProfileURL(from: urlString) else {
            throw ClashModuleError.insecureSubscriptionURL
        }

        var library = sanitizedLibrary(try loadLibrary())
        var profile = makeProfile(
            id: UUID().uuidString.lowercased(),
            displayName: uniqueDisplayName(
                preferredName: preferredName ?? suggestedRemoteProfileName(for: url),
                existingProfiles: library.profiles
            ),
            sourceKind: .remoteSubscription,
            sourceLocation: url.absoluteString,
            updateOnActivate: true,
            lastUpdatedAt: nil,
            isActive: makeActive,
            isStarterProfile: false
        )

        let rawConfig = try await ClashConfigSupport.fetchProfileText(from: url)
        let snapshot = try ClashConfigSupport.normalizedProfileSnapshot(from: rawConfig)
        try writeSnapshot(snapshot, for: profile)
        profile.lastUpdatedAt = Date()
        profile.lastErrorMessage = nil

        if makeActive {
            deactivateAllProfiles(in: &library)
        }
        library.profiles.append(profile)
        library = sanitizedLibrary(library)
        try saveLibrary(library)
        return library
    }

    func importProfile(from sourceURL: URL, preferredName: String? = nil, makeActive: Bool = true) throws -> ClashBuiltInProfileLibrary {
        let rawConfig = try String(contentsOf: sourceURL, encoding: .utf8)
        let snapshot = try ClashConfigSupport.normalizedProfileSnapshot(from: rawConfig)
        var library = sanitizedLibrary(try loadLibrary())
        var profile = makeProfile(
            id: UUID().uuidString.lowercased(),
            displayName: uniqueDisplayName(
                preferredName: preferredName ?? sourceURL.deletingPathExtension().lastPathComponent,
                existingProfiles: library.profiles
            ),
            sourceKind: .importedFile,
            sourceLocation: sourceURL.path,
            updateOnActivate: false,
            lastUpdatedAt: Date(),
            isActive: makeActive,
            isStarterProfile: false
        )

        try writeSnapshot(snapshot, for: profile)
        profile.lastErrorMessage = nil
        if makeActive {
            deactivateAllProfiles(in: &library)
        }
        library.profiles.append(profile)
        library = sanitizedLibrary(library)
        try saveLibrary(library)
        return library
    }

    func activateProfile(id: String) throws -> ClashBuiltInProfileLibrary {
        var library = try loadOrBootstrapLibrary()
        guard library.profiles.contains(where: { $0.id == id }) else {
            throw ClashModuleError.noBuiltInProfile
        }

        for index in library.profiles.indices {
            library.profiles[index].isActive = library.profiles[index].id == id
        }
        library = sanitizedLibrary(library)
        try saveLibrary(library)
        return library
    }

    func setUpdateOnActivate(_ enabled: Bool, forProfileID id: String) throws -> ClashBuiltInProfileLibrary {
        var library = try loadOrBootstrapLibrary()
        guard let index = library.profiles.firstIndex(where: { $0.id == id }) else {
            throw ClashModuleError.noBuiltInProfile
        }
        library.profiles[index].updateOnActivate = enabled
        try saveLibrary(library)
        return library
    }

    func renameProfile(id: String, named preferredName: String) throws -> ClashBuiltInProfileLibrary {
        var library = try loadOrBootstrapLibrary()
        guard let index = library.profiles.firstIndex(where: { $0.id == id }) else {
            throw ClashModuleError.noBuiltInProfile
        }

        let trimmedName = preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        library.profiles[index].displayName = uniqueDisplayName(
            preferredName: trimmedName.isEmpty ? normalizedDisplayName(for: library.profiles[index]) : trimmedName,
            existingProfiles: library.profiles.enumerated().compactMap { offset, profile in
                offset == index ? nil : profile
            }
        )
        try saveLibrary(library)
        return library
    }

    func deleteProfile(id: String) throws -> ClashBuiltInProfileLibrary {
        var library = try loadOrBootstrapLibrary()
        guard let index = library.profiles.firstIndex(where: { $0.id == id }) else {
            throw ClashModuleError.noBuiltInProfile
        }

        let removedProfile = library.profiles.remove(at: index)
        let profileDirectoryURL = snapshotURL(for: removedProfile).deletingLastPathComponent()
        if fileManager.fileExists(atPath: profileDirectoryURL.path) {
            try fileManager.removeItem(at: profileDirectoryURL)
        }

        if removedProfile.isActive, !library.profiles.isEmpty {
            library.profiles[0].isActive = true
        }

        library = sanitizedLibrary(library)
        try saveLibrary(library)
        return library
    }

    func refreshRemoteProfile(id: String) async throws -> ClashBuiltInProfileLibrary {
        var library = try loadOrBootstrapLibrary()
        guard let index = library.profiles.firstIndex(where: { $0.id == id }) else {
            throw ClashModuleError.noBuiltInProfile
        }

        guard let url = ClashConfigSupport.validRemoteProfileURL(from: library.profiles[index].sourceLocation) else {
            library.profiles[index].lastErrorMessage = ClashModuleError.insecureSubscriptionURL.localizedDescription
            try saveLibrary(library)
            throw ClashModuleError.insecureSubscriptionURL
        }

        do {
            let rawConfig = try await ClashConfigSupport.fetchProfileText(from: url)
            let snapshot = try ClashConfigSupport.normalizedProfileSnapshot(from: rawConfig)
            try writeSnapshot(snapshot, for: library.profiles[index])
            library.profiles[index].lastUpdatedAt = Date()
            library.profiles[index].lastErrorMessage = nil
            try saveLibrary(library)
            return library
        } catch {
            library.profiles[index].lastErrorMessage = error.localizedDescription
            try saveLibrary(library)
            throw error
        }
    }

    func reimportProfile(id: String) throws -> ClashBuiltInProfileLibrary {
        var library = try loadOrBootstrapLibrary()
        guard let index = library.profiles.firstIndex(where: { $0.id == id }) else {
            throw ClashModuleError.noBuiltInProfile
        }

        guard let sourcePath = library.profiles[index].importedFilePath,
              fileManager.fileExists(atPath: sourcePath) else {
            library.profiles[index].lastErrorMessage = ClashModuleError.importedFileUnavailable.localizedDescription
            try saveLibrary(library)
            throw ClashModuleError.importedFileUnavailable
        }

        do {
            let rawConfig = try String(contentsOfFile: sourcePath, encoding: .utf8)
            let snapshot = try ClashConfigSupport.normalizedProfileSnapshot(from: rawConfig)
            try writeSnapshot(snapshot, for: library.profiles[index])
            library.profiles[index].lastUpdatedAt = Date()
            library.profiles[index].lastErrorMessage = nil
            try saveLibrary(library)
            return library
        } catch {
            library.profiles[index].lastErrorMessage = error.localizedDescription
            try saveLibrary(library)
            throw error
        }
    }

    func snapshotExists(for profile: ClashBuiltInProfile) -> Bool {
        fileManager.fileExists(atPath: snapshotURL(for: profile).path)
    }

    func readSnapshot(for profile: ClashBuiltInProfile) throws -> String {
        let snapshotURL = snapshotURL(for: profile)
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            throw ClashModuleError.missingProfileSnapshot
        }

        return try String(contentsOf: snapshotURL, encoding: .utf8)
    }

    func snapshotURL(for profile: ClashBuiltInProfile) -> URL {
        ClashBuiltInPaths.rootDirectoryURL(fileManager: fileManager).appendingPathComponent(profile.snapshotRelativePath)
    }

    private func saveLibrary(_ library: ClashBuiltInProfileLibrary) throws {
        let sanitizedLibrary = sanitizedLibrary(library)
        let profilesDirectoryURL = ClashBuiltInPaths.profilesDirectoryURL(fileManager: fileManager)
        try fileManager.createDirectory(at: profilesDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sanitizedLibrary)

        let manifestURL = ClashBuiltInPaths.profileManifestURL(fileManager: fileManager)
        let tempURL = manifestURL.appendingPathExtension("tmp")
        try data.write(to: tempURL, options: .atomic)
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }
        try fileManager.moveItem(at: tempURL, to: manifestURL)
    }

    private func bootstrapLibraryFromLegacyStateIfAvailable(save: Bool = true) throws -> ClashBuiltInProfileLibrary {
        let legacyConfigURL = legacyManagedConfigURL()
        let library: ClashBuiltInProfileLibrary
        if let legacyConfigSnapshot = try normalizedLegacyConfigSnapshot(from: legacyConfigURL) {
            var profile = makeProfile(
                id: UUID().uuidString.lowercased(),
                displayName: suggestedImportedProfileName(forPath: legacyConfigURL.path),
                sourceKind: .importedFile,
                sourceLocation: legacyConfigURL.path,
                updateOnActivate: false,
                lastUpdatedAt: legacyConfigFileDate(at: legacyConfigURL) ?? Date(),
                isActive: true,
                isStarterProfile: false
            )
            try writeSnapshot(legacyConfigSnapshot, for: profile)
            profile.lastErrorMessage = nil
            library = ClashBuiltInProfileLibrary(schemaVersion: 1, profiles: [profile])
        } else {
            library = ClashBuiltInProfileLibrary()
        }

        if save {
            try saveLibrary(library)
        }
        return library
    }

    private func makeProfile(
        id: String,
        displayName: String,
        sourceKind: ClashBuiltInProfileSourceKind,
        sourceLocation: String,
        updateOnActivate: Bool,
        lastUpdatedAt: Date?,
        isActive: Bool,
        isStarterProfile: Bool
    ) -> ClashBuiltInProfile {
        ClashBuiltInProfile(
            id: id,
            displayName: displayName,
            sourceKind: sourceKind,
            sourceLocation: sourceLocation,
            snapshotRelativePath: "Profiles/\(id)/snapshot.yaml",
            updateOnActivate: updateOnActivate,
            lastUpdatedAt: lastUpdatedAt,
            lastErrorMessage: nil,
            isActive: isActive,
            isStarterProfile: isStarterProfile
        )
    }

    private func writeSnapshot(_ snapshot: String, for profile: ClashBuiltInProfile) throws {
        let snapshotURL = self.snapshotURL(for: profile)
        try fileManager.createDirectory(at: snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try snapshot.write(to: snapshotURL, atomically: true, encoding: .utf8)
    }

    private func deactivateAllProfiles(in library: inout ClashBuiltInProfileLibrary) {
        for index in library.profiles.indices {
            library.profiles[index].isActive = false
        }
    }

    private func sanitizedLibrary(_ library: ClashBuiltInProfileLibrary) -> ClashBuiltInProfileLibrary {
        var sanitized = library
        if sanitized.profiles.isEmpty {
            return sanitized
        }

        var normalizedProfiles: [ClashBuiltInProfile] = []
        normalizedProfiles.reserveCapacity(sanitized.profiles.count)
        for var profile in sanitized.profiles {
            profile.displayName = uniqueDisplayName(
                preferredName: normalizedDisplayName(for: profile),
                existingProfiles: normalizedProfiles
            )
            normalizedProfiles.append(profile)
        }
        sanitized.profiles = normalizedProfiles

        var foundActive = false
        for index in sanitized.profiles.indices {
            if sanitized.profiles[index].isActive {
                if foundActive {
                    sanitized.profiles[index].isActive = false
                } else {
                    foundActive = true
                }
            }
        }

        if !foundActive {
            sanitized.profiles[0].isActive = true
        }
        return sanitized
    }

    private func uniqueDisplayName(preferredName: String, existingProfiles: [ClashBuiltInProfile]) -> String {
        let baseName = preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? NSLocalizedString("Profile", comment: "")
            : preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingNames = Set(existingProfiles.map(\.displayName))
        guard existingNames.contains(baseName) else {
            return baseName
        }

        for index in 2...200 {
            let candidate = "\(baseName) \(index)"
            if !existingNames.contains(candidate) {
                return candidate
            }
        }

        return "\(baseName) \(UUID().uuidString.prefix(4))"
    }

    private func suggestedRemoteProfileName(for url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return host
        }
        return NSLocalizedString("Subscription Profile", comment: "")
    }

    private func suggestedImportedProfileName(forPath path: String?) -> String {
        guard let path, !path.isEmpty else {
            return NSLocalizedString("Local YAML", comment: "")
        }

        let baseName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        guard !baseName.isEmpty, baseName.lowercased() != "config" else {
            return NSLocalizedString("Local YAML", comment: "")
        }

        return baseName
    }

    private func normalizedDisplayName(for profile: ClashBuiltInProfile) -> String {
        let trimmedName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty, !legacyGeneratedDisplayNames.contains(trimmedName) {
            return trimmedName
        }

        if profile.isStarterProfile {
            return NSLocalizedString("Default Profile", comment: "")
        }

        switch profile.sourceKind {
        case .remoteSubscription:
            if let url = ClashConfigSupport.validRemoteProfileURL(from: profile.sourceLocation) {
                return suggestedRemoteProfileName(for: url)
            }
            return NSLocalizedString("Subscription Profile", comment: "")
        case .importedFile:
            return suggestedImportedProfileName(forPath: profile.importedFilePath)
        }
    }

    private var legacyGeneratedDisplayNames: Set<String> {
        [
            "Migrated Subscription",
            "已迁移订阅",
            "已遷移訂閱",
            "Migrated Local Profile",
            "已迁移本地配置",
            "已遷移本地設定檔",
            "Starter Profile",
            "起始配置",
            "起始設定檔",
        ]
    }

    private func legacyManagedConfigURL() -> URL {
        if let configuredPath = ClashConfigSupport.normalizedPath(ClashModuleSettings.managedConfigFilePath) {
            return URL(fileURLWithPath: configuredPath)
        }
        return ClashBuiltInPaths.legacyManagedConfigFileURL(fileManager: fileManager)
    }

    private func normalizedLegacyConfigSnapshot(from url: URL) throws -> String? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let rawConfig = try String(contentsOf: url, encoding: .utf8)
        let trimmed = rawConfig.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return try ClashConfigSupport.normalizedProfileSnapshot(from: rawConfig)
    }

    private func legacyConfigFileDate(at url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }
}
