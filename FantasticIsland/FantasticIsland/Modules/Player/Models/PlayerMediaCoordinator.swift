import AppKit
import Carbon
import Foundation

@MainActor
final class PlayerMediaCoordinator {
    private enum AppleEventError {
        static let noError: OSStatus = 0
        static let eventNotPermitted: OSStatus = -1743
        static let wouldRequireUserConsent: OSStatus = -1744
    }

    private enum TransportCommand {
        case previousTrack
        case togglePlayPause
        case nextTrack

        func perform(on source: ScriptSource) {
            switch self {
            case .previousTrack:
                source.previousTrack()
            case .togglePlayPause:
                source.togglePlayPause()
            case .nextTrack:
                source.nextTrack()
            }
        }
    }

    private struct PlayerSnapshot {
        var source: PlayerSourceKind
        var playbackStatus: PlayerPlaybackStatus
        var track: PlayerTrackMetadata?
        var shuffleMode: PlayerShuffleMode
        var repeatMode: PlayerRepeatMode
        var artworkImage: NSImage?
    }

    private enum FetchResult {
        case snapshot(PlayerSnapshot)
        case automationIssue(PlayerAutomationIssue)
        case unavailable
    }

    private struct AppleScriptExecutionResult {
        let descriptor: NSAppleEventDescriptor?
        let error: NSDictionary?

        var errorCode: Int? {
            error?[NSAppleScript.errorNumber] as? Int
        }

        var stringValue: String? {
            guard let descriptor,
                  descriptor.descriptorType != typeNull else {
                return nil
            }

            let output = (descriptor.stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? nil : output
        }
    }

    private struct ScriptSource {
        let kind: PlayerSourceKind
        let fetchState: () -> FetchResult
        let previousTrack: () -> Void
        let togglePlayPause: () -> Void
        let nextTrack: () -> Void
        let seek: (TimeInterval) -> Void
        let toggleShuffle: () -> Void
        let cycleRepeat: () -> Void
    }

    private lazy var sources: [ScriptSource] = [
        makeMusicSource(),
        makeSpotifySource(),
    ]
    private var lastPreferredSourceKind: PlayerSourceKind?
    private var artworkCache: [String: NSImage] = [:]
    private var artworkCacheOrder: [String] = []
    private var musicArtworkURLCache: [String: URL] = [:]
    private let artworkCacheLimit = 8
    private let launchedCommandDelay: TimeInterval = 0.8
    private let immediateRefreshDelay: TimeInterval = 0.25
    private let launchedRefreshDelay: TimeInterval = 1.15

    func fetchCurrentState() -> PlayerNowPlayingState {
        autoreleasepool {
            let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            var pausedCandidate: PlayerSnapshot?
            var automationIssueCandidate: PlayerAutomationIssue?

            for source in prioritizedSources(frontmostBundleID: frontmostBundleID) {
                switch source.fetchState() {
                case let .snapshot(snapshot):
                    if snapshot.playbackStatus == .playing {
                        lastPreferredSourceKind = snapshot.source
                        return toState(snapshot)
                    }

                    if pausedCandidate == nil {
                        pausedCandidate = snapshot
                    }
                case let .automationIssue(issue):
                    if automationIssueCandidate == nil {
                        automationIssueCandidate = issue
                    }
                case .unavailable:
                    continue
                }
            }

            if let pausedCandidate {
                lastPreferredSourceKind = pausedCandidate.source
                return toState(pausedCandidate)
            }

            if let automationIssueCandidate {
                lastPreferredSourceKind = nil
                return .issueState(automationIssueCandidate)
            }

            lastPreferredSourceKind = nil
            return .empty
        }
    }

    func previousTrack(for sourceKind: PlayerSourceKind?) -> TimeInterval? {
        performTransportCommand(.previousTrack, for: sourceKind)
    }

    func togglePlayPause(for sourceKind: PlayerSourceKind?) -> TimeInterval? {
        performTransportCommand(.togglePlayPause, for: sourceKind)
    }

    func nextTrack(for sourceKind: PlayerSourceKind?) -> TimeInterval? {
        performTransportCommand(.nextTrack, for: sourceKind)
    }

    func seek(to elapsed: TimeInterval, for sourceKind: PlayerSourceKind?) {
        resolvedSource(for: sourceKind)?.seek(elapsed)
    }

    func toggleShuffle(for sourceKind: PlayerSourceKind?) {
        resolvedSource(for: sourceKind)?.toggleShuffle()
    }

    func cycleRepeat(for sourceKind: PlayerSourceKind?) {
        resolvedSource(for: sourceKind)?.cycleRepeat()
    }

    func loadArtworkIfNeeded(for state: PlayerNowPlayingState) async -> NSImage? {
        guard let source = state.source,
              let track = state.track,
              state.artworkImage == nil else {
            return nil
        }

        let cacheKey: String
        let remoteArtworkURL: URL?

        switch source {
        case .music:
            cacheKey = musicArtworkCacheKey(for: track)
            remoteArtworkURL = musicArtworkURLCache[cacheKey]
        case .spotify:
            cacheKey = spotifyArtworkCacheKey(for: track, artworkURL: track.artworkURL)
            remoteArtworkURL = track.artworkURL
        }

        if let cachedImage = cachedArtworkImage(for: cacheKey) {
            return cachedImage
        }

        let resolvedArtworkURL: URL?
        switch source {
        case .music:
            if let remoteArtworkURL {
                resolvedArtworkURL = remoteArtworkURL
            } else {
                resolvedArtworkURL = await Self.lookupMusicArtworkURL(for: track)
                if let resolvedArtworkURL {
                    musicArtworkURLCache[cacheKey] = resolvedArtworkURL
                }
            }
        case .spotify:
            resolvedArtworkURL = remoteArtworkURL
        }

        guard let resolvedArtworkURL,
              let image = await Self.loadArtworkImage(from: resolvedArtworkURL) else {
            return nil
        }

        storeArtwork(image, for: cacheKey)
        return image
    }

    nonisolated static func automationPermissionStatus(
        for sourceKind: PlayerSourceKind?,
        askUserIfNeeded: Bool
    ) -> OSStatus {
        guard let sourceKind,
              isApplicationRunning(bundleIdentifier: sourceKind.bundleIdentifier) else {
            return OSStatus(procNotFound)
        }

        let targetDescriptor = NSAppleEventDescriptor(bundleIdentifier: sourceKind.bundleIdentifier)
        return AEDeterminePermissionToAutomateTarget(
            targetDescriptor.aeDesc,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            askUserIfNeeded
        )
    }

    nonisolated static func determineAutomationPermission(
        for sourceKind: PlayerSourceKind?,
        askUserIfNeeded: Bool
    ) -> OSStatus {
        automationPermissionStatus(for: sourceKind, askUserIfNeeded: askUserIfNeeded)
    }

    @discardableResult
    func activateSourceApplication(for sourceKind: PlayerSourceKind?) -> Bool {
        guard let sourceKind else {
            return false
        }

        if let runningApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: sourceKind.bundleIdentifier)
            .first {
            return runningApplication.activate(options: [.activateAllWindows])
        }

        return Self.launchApplication(bundleIdentifier: sourceKind.bundleIdentifier)
    }

    private func resolvedSource(for sourceKind: PlayerSourceKind?) -> ScriptSource? {
        guard let sourceKind else {
            return nil
        }

        return sources.first { $0.kind == sourceKind }
    }

    private func resolvedTransportSource(for activeSourceKind: PlayerSourceKind?) -> ScriptSource? {
        if let activeSource = resolvedSource(for: activeSourceKind) {
            return activeSource
        }

        let installedControllableSources = PlayerSourceRegistry.installedControllableSources()
        guard let defaultSourceKind = PlayerModuleSettings.resolvedDefaultSource(
            installedControllableSources: installedControllableSources
        ) else {
            return nil
        }

        return resolvedSource(for: defaultSourceKind)
    }

    private func performTransportCommand(
        _ command: TransportCommand,
        for activeSourceKind: PlayerSourceKind?
    ) -> TimeInterval? {
        guard let targetSource = resolvedTransportSource(for: activeSourceKind) else {
            return nil
        }

        if Self.isApplicationRunning(bundleIdentifier: targetSource.kind.bundleIdentifier) {
            command.perform(on: targetSource)
            return immediateRefreshDelay
        }

        guard Self.launchApplication(bundleIdentifier: targetSource.kind.bundleIdentifier) else {
            return nil
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(launchedCommandDelay * 1000)))
            command.perform(on: targetSource)
        }
        return launchedRefreshDelay
    }

    private func toState(_ snapshot: PlayerSnapshot) -> PlayerNowPlayingState {
        PlayerNowPlayingState(
            source: snapshot.source,
            playbackStatus: snapshot.playbackStatus,
            track: snapshot.track,
            shuffleMode: snapshot.shuffleMode,
            repeatMode: snapshot.repeatMode,
            artworkImage: snapshot.artworkImage,
            automationIssue: nil
        )
    }

    private func prioritizedSources(frontmostBundleID: String?) -> [ScriptSource] {
        var ordered: [ScriptSource] = []

        if let frontmostBundleID,
           let frontmostSource = sources.first(where: { $0.kind.bundleIdentifier == frontmostBundleID }) {
            ordered.append(frontmostSource)
        }

        if let lastPreferredSourceKind,
           let preferredSource = sources.first(where: { $0.kind == lastPreferredSourceKind }),
           !ordered.contains(where: { $0.kind == preferredSource.kind }) {
            ordered.append(preferredSource)
        }

        for source in sources where !ordered.contains(where: { $0.kind == source.kind }) {
            ordered.append(source)
        }

        return ordered
    }

    private func makeMusicSource() -> ScriptSource {
        ScriptSource(
            kind: .music,
            fetchState: { [weak self] in
                self?.fetchMusicState() ?? .unavailable
            },
            previousTrack: {
                Self.runAppleScript([
                    #"tell application "Music" to previous track"#,
                ])
            },
            togglePlayPause: {
                Self.runAppleScript([
                    #"tell application "Music" to playpause"#,
                ])
            },
            nextTrack: {
                Self.runAppleScript([
                    #"tell application "Music" to next track"#,
                ])
            },
            seek: { elapsed in
                Self.runAppleScript([
                    #"tell application "Music" to set player position to \#(elapsed)"#,
                ])
            },
            toggleShuffle: {
                Self.runAppleScript([
                    #"tell application "Music""#,
                    #"if not running then return"#,
                    #"set shuffle enabled to not shuffle enabled"#,
                    #"end tell"#,
                ])
            },
            cycleRepeat: {
                Self.runAppleScript([
                    #"tell application "Music""#,
                    #"if not running then return"#,
                    #"set currentRepeat to song repeat as text"#,
                    #"if currentRepeat is "off" then"#,
                    #"set song repeat to all"#,
                    #"else if currentRepeat is "all" then"#,
                    #"set song repeat to one"#,
                    #"else"#,
                    #"set song repeat to off"#,
                    #"end if"#,
                    #"end tell"#,
                ])
            }
        )
    }

    private func makeSpotifySource() -> ScriptSource {
        ScriptSource(
            kind: .spotify,
            fetchState: { [weak self] in
                self?.fetchSpotifyState() ?? .unavailable
            },
            previousTrack: {
                Self.runAppleScript([
                    #"tell application "Spotify" to previous track"#,
                ])
            },
            togglePlayPause: {
                Self.runAppleScript([
                    #"tell application "Spotify" to playpause"#,
                ])
            },
            nextTrack: {
                Self.runAppleScript([
                    #"tell application "Spotify" to next track"#,
                ])
            },
            seek: { elapsed in
                Self.runAppleScript([
                    #"tell application "Spotify" to set player position to \#(elapsed)"#,
                ])
            },
            toggleShuffle: {},
            cycleRepeat: {}
        )
    }

    private func fetchMusicState() -> FetchResult {
        autoreleasepool {
            guard Self.isApplicationRunning(bundleIdentifier: PlayerSourceKind.music.bundleIdentifier) else {
                return .unavailable
            }

            if let permissionIssue = permissionIssue(for: .music) {
                return .automationIssue(permissionIssue)
            }

            let result = Self.runAppleScript([
                #"tell application "Music""#,
                #"set currentState to player state as text"#,
                #"if currentState is "stopped" then return "stopped""#,
                #"set currentTrack to current track"#,
                #"set trackName to name of currentTrack"#,
                #"set artistName to artist of currentTrack"#,
                #"set albumName to album of currentTrack"#,
                #"set durationSeconds to duration of currentTrack"#,
                #"set elapsedSeconds to player position"#,
                #"set shuffleEnabled to shuffle enabled"#,
                #"set repeatMode to song repeat as text"#,
                #"set AppleScript's text item delimiters to (ASCII character 31)"#,
                #"return {currentState, trackName, artistName, albumName, (durationSeconds as text), (elapsedSeconds as text), (shuffleEnabled as text), repeatMode} as text"#,
                #"end tell"#,
            ])

            guard let output = result.stringValue else {
                return .unavailable
            }

            if output == "stopped" {
                return .snapshot(PlayerSnapshot(
                    source: .music,
                    playbackStatus: .stopped,
                    track: nil,
                    shuffleMode: .unsupported,
                    repeatMode: .unsupported,
                    artworkImage: nil
                ))
            }

            let parts = output.components(separatedBy: "\u{1F}")
            guard parts.count >= 8 else {
                return .unavailable
            }

            let title = fallback(parts[1], default: "Unknown Track")
            let artist = fallback(parts[2], default: "Unknown Artist")
            let album = parts[3].nilIfEmpty
            let duration = Double(parts[4]) ?? 0
            let elapsed = Double(parts[5]) ?? 0

            let cacheKey = [
                "music",
                title,
                artist,
                album ?? "",
            ].joined(separator: "\u{1F}")

            let track = PlayerTrackMetadata(
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                elapsed: elapsed,
                artworkURL: musicArtworkURLCache[cacheKey]
            )

            return .snapshot(PlayerSnapshot(
                source: .music,
                playbackStatus: playbackStatus(for: parts[0]),
                track: track,
                shuffleMode: shuffleMode(for: parts[6]),
                repeatMode: repeatMode(for: parts[7]),
                artworkImage: cachedArtworkImage(for: cacheKey) ?? loadMusicArtworkFromAppleScript(cacheKey: cacheKey)
            ))
        }
    }

    private func fetchSpotifyState() -> FetchResult {
        autoreleasepool {
            guard Self.isApplicationRunning(bundleIdentifier: PlayerSourceKind.spotify.bundleIdentifier) else {
                return .unavailable
            }

            if let permissionIssue = permissionIssue(for: .spotify) {
                return .automationIssue(permissionIssue)
            }

            let result = Self.runAppleScript([
                #"tell application "Spotify""#,
                #"set currentState to player state as text"#,
                #"if currentState is "stopped" then return "stopped""#,
                #"set currentTrack to current track"#,
                #"set trackName to name of currentTrack"#,
                #"set artistName to artist of currentTrack"#,
                #"set albumName to album of currentTrack"#,
                #"set durationMs to duration of currentTrack"#,
                #"set elapsedSeconds to player position"#,
                #"set artworkURL to artwork url of currentTrack"#,
                #"set AppleScript's text item delimiters to (ASCII character 31)"#,
                #"return {currentState, trackName, artistName, albumName, (durationMs as text), (elapsedSeconds as text), artworkURL} as text"#,
                #"end tell"#,
            ])

            guard let output = result.stringValue else {
                return .unavailable
            }

            if output == "stopped" {
                return .snapshot(PlayerSnapshot(
                    source: .spotify,
                    playbackStatus: .stopped,
                    track: nil,
                    shuffleMode: .unsupported,
                    repeatMode: .unsupported,
                    artworkImage: nil
                ))
            }

            let parts = output.components(separatedBy: "\u{1F}")
            guard parts.count >= 7 else {
                return .unavailable
            }

            let artworkURL = URL(string: parts[6])
            let track = PlayerTrackMetadata(
                title: fallback(parts[1], default: "Unknown Track"),
                artist: fallback(parts[2], default: "Unknown Artist"),
                album: parts[3].nilIfEmpty,
                duration: (Double(parts[4]) ?? 0) / 1000,
                elapsed: Double(parts[5]) ?? 0,
                artworkURL: artworkURL
            )

            return .snapshot(PlayerSnapshot(
                source: .spotify,
                playbackStatus: playbackStatus(for: parts[0]),
                track: track,
                shuffleMode: .unsupported,
                repeatMode: .unsupported,
                artworkImage: cachedArtworkImage(for: spotifyArtworkCacheKey(for: track, artworkURL: artworkURL))
            ))
        }
    }

    private func permissionIssue(for source: PlayerSourceKind) -> PlayerAutomationIssue? {
        switch Self.automationPermissionStatus(for: source, askUserIfNeeded: false) {
        case AppleEventError.noError:
            return nil
        case OSStatus(procNotFound):
            return nil
        case AppleEventError.eventNotPermitted:
            return .permissionDenied(source: source)
        case AppleEventError.wouldRequireUserConsent:
            return .permissionRequired(source: source)
        default:
            return .permissionRequired(source: source)
        }
    }

    private func playbackStatus(for rawValue: String) -> PlayerPlaybackStatus {
        switch rawValue.lowercased() {
        case "playing":
            return .playing
        case "paused":
            return .paused
        default:
            return .stopped
        }
    }

    private func repeatMode(for rawValue: String) -> PlayerRepeatMode {
        switch rawValue.lowercased() {
        case "all":
            return .all
        case "one":
            return .one
        case "off":
            return .off
        default:
            return .unsupported
        }
    }

    private func shuffleMode(for rawValue: String) -> PlayerShuffleMode {
        switch rawValue.lowercased() {
        case "true":
            return .on
        case "false":
            return .off
        default:
            return .unsupported
        }
    }

    private func fallback(_ value: String, default defaultValue: String) -> String {
        value.nilIfEmpty ?? defaultValue
    }

    private func musicArtworkCacheKey(for track: PlayerTrackMetadata) -> String {
        [
            "music",
            track.title,
            track.artist,
            track.album ?? "",
        ].joined(separator: "\u{1F}")
    }

    private func spotifyArtworkCacheKey(for track: PlayerTrackMetadata, artworkURL: URL?) -> String {
        if let artworkURL {
            return "spotify:\(artworkURL.absoluteString)"
        }

        return [
            "spotify",
            track.title,
            track.artist,
            track.album ?? "",
        ].joined(separator: "\u{1F}")
    }

    private func cachedArtworkImage(for key: String) -> NSImage? {
        artworkCache[key]
    }

    private func storeArtwork(_ image: NSImage, for key: String) {
        artworkCache[key] = image
        artworkCacheOrder.removeAll { $0 == key }
        artworkCacheOrder.append(key)

        if artworkCacheOrder.count > artworkCacheLimit,
           let evictedKey = artworkCacheOrder.first {
            artworkCacheOrder.removeFirst()
            artworkCache.removeValue(forKey: evictedKey)
        }
    }

    private func loadMusicArtworkFromAppleScript(cacheKey: String) -> NSImage? {
        let result = Self.runAppleScriptDescriptor([
            #"tell application "Music""#,
            #"set currentTrack to current track"#,
            #"if (count of artworks of currentTrack) is 0 then return missing value"#,
            #"return data of artwork 1 of currentTrack"#,
            #"end tell"#,
        ])

        guard let descriptor = result.descriptor else {
            return nil
        }

        guard descriptor.descriptorType != typeNull else {
            return nil
        }

        let data = descriptor.data
        guard !data.isEmpty else {
            return nil
        }

        guard let image = NSImage(data: data) else {
            return nil
        }

        storeArtwork(image, for: cacheKey)
        return image
    }

    private static func loadArtworkImage(from url: URL) async -> NSImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.5

        guard let data = await fetchData(for: request) else {
            return nil
        }

        return await MainActor.run {
            NSImage(data: data)
        }
    }

    @discardableResult
    private static func runAppleScript(_ lines: [String]) -> AppleScriptExecutionResult {
        autoreleasepool {
            runAppleScriptDescriptor(lines)
        }
    }

    private static func runAppleScriptDescriptor(_ lines: [String]) -> AppleScriptExecutionResult {
        autoreleasepool {
            let source = lines.joined(separator: "\n")
            guard let script = NSAppleScript(source: source) else {
                return AppleScriptExecutionResult(descriptor: nil, error: nil)
            }

            var error: NSDictionary?
            let descriptor = script.executeAndReturnError(&error)
            return AppleScriptExecutionResult(descriptor: descriptor, error: error)
        }
    }

    private static func normalizedMetadataValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func lookupMusicArtworkURL(for track: PlayerTrackMetadata) async -> URL? {
        let term = [track.title, track.artist]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !term.isEmpty else {
            return nil
        }

        let country = Locale.current.region?.identifier ?? "US"
        let candidates = [country, "US"]

        for storefront in candidates {
            guard let url = searchEndpointURL(term: term, storefront: storefront),
                  let data = await fetchData(from: url, timeout: 0.8),
                  let response = try? JSONDecoder().decode(PlayerMusicArtworkSearchResponse.self, from: data),
                  let match = bestSearchArtworkResult(from: response.results, for: track),
                  let rawArtworkURL = match.artworkUrl100,
                  let artworkURL = highResolutionArtworkURL(from: rawArtworkURL) else {
                continue
            }

            return artworkURL
        }

        return nil
    }

    private static func searchEndpointURL(term: String, storefront: String) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "country", value: storefront),
        ]
        return components?.url
    }

    private static func fetchData(from url: URL, timeout: TimeInterval) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        return await fetchData(for: request)
    }

    private static func fetchData(for request: URLRequest) async -> Data? {
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        } catch {
            return nil
        }
    }

    private static func bestSearchArtworkResult(
        from results: [PlayerMusicArtworkSearchResult],
        for track: PlayerTrackMetadata
    ) -> PlayerMusicArtworkSearchResult? {
        if let exactAlbumMatch = results.first(where: { result in
            matchesSearchArtworkResult(result, to: track, requireAlbumMatch: true)
        }) {
            return exactAlbumMatch
        }

        return results.first(where: { result in
            matchesSearchArtworkResult(result, to: track, requireAlbumMatch: false)
        })
    }

    private static func matchesSearchArtworkResult(
        _ result: PlayerMusicArtworkSearchResult,
        to track: PlayerTrackMetadata,
        requireAlbumMatch: Bool
    ) -> Bool {
        let expectedTitle = normalizedMetadataValue(track.title)
        let expectedArtist = normalizedMetadataValue(track.artist)
        let expectedAlbum = normalizedMetadataValue(track.album)

        guard normalizedMetadataValue(result.trackName) == expectedTitle,
              normalizedMetadataValue(result.artistName) == expectedArtist else {
            return false
        }

        guard requireAlbumMatch,
              let expectedAlbum else {
            return true
        }

        return normalizedMetadataValue(result.collectionName) == expectedAlbum
    }

    private static func highResolutionArtworkURL(from rawValue: String) -> URL? {
        let upgraded = rawValue
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            .replacingOccurrences(of: "100x100-75", with: "600x600-75")
        return URL(string: upgraded)
    }

    nonisolated private static func isApplicationRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    nonisolated private static func launchApplication(bundleIdentifier: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", bundleIdentifier]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

private struct PlayerMusicArtworkSearchResult: Decodable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let artworkUrl100: String?
}

private struct PlayerMusicArtworkSearchResponse: Decodable {
    let results: [PlayerMusicArtworkSearchResult]
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
