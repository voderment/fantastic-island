import AppKit
import Foundation

@MainActor
final class PlayerMediaCoordinator {
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

    private struct ScriptSource {
        let kind: PlayerSourceKind
        let fetchState: () -> PlayerSnapshot?
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
    private let artworkCacheLimit = 8
    private let launchedCommandDelay: TimeInterval = 0.8
    private let immediateRefreshDelay: TimeInterval = 0.25
    private let launchedRefreshDelay: TimeInterval = 1.15

    func fetchCurrentState() -> PlayerNowPlayingState {
        autoreleasepool {
            let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            var pausedCandidate: PlayerSnapshot?

            for source in prioritizedSources(frontmostBundleID: frontmostBundleID) {
                guard let snapshot = source.fetchState() else {
                    continue
                }

                if snapshot.playbackStatus == .playing {
                    lastPreferredSourceKind = snapshot.source
                    return toState(snapshot)
                }

                if pausedCandidate == nil {
                    pausedCandidate = snapshot
                }
            }

            if let pausedCandidate {
                lastPreferredSourceKind = pausedCandidate.source
                return toState(pausedCandidate)
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

    @discardableResult
    func activateSourceApplication(for sourceKind: PlayerSourceKind?) -> Bool {
        guard let sourceKind else {
            return false
        }

        if let runningApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: sourceKind.bundleIdentifier)
            .first {
            return runningApplication.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
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
            artworkImage: snapshot.artworkImage
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
                self?.fetchMusicState()
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
                self?.fetchSpotifyState()
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

    private func fetchMusicState() -> PlayerSnapshot? {
        autoreleasepool {
            guard Self.isApplicationRunning(bundleIdentifier: PlayerSourceKind.music.bundleIdentifier) else {
                return nil
            }

            guard let output = Self.runAppleScript([
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
            ]) else {
                return nil
            }

            if output == "stopped" {
                return PlayerSnapshot(
                    source: .music,
                    playbackStatus: .stopped,
                    track: nil,
                    shuffleMode: .unsupported,
                    repeatMode: .unsupported,
                    artworkImage: nil
                )
            }

            let parts = output.components(separatedBy: "\u{1F}")
            guard parts.count >= 8 else {
                return nil
            }

            let track = PlayerTrackMetadata(
                title: fallback(parts[1], default: "Unknown Track"),
                artist: fallback(parts[2], default: "Unknown Artist"),
                album: parts[3].nilIfEmpty,
                duration: Double(parts[4]) ?? 0,
                elapsed: Double(parts[5]) ?? 0,
                artworkURL: nil
            )

            return PlayerSnapshot(
                source: .music,
                playbackStatus: playbackStatus(for: parts[0]),
                track: track,
                shuffleMode: shuffleMode(for: parts[6]),
                repeatMode: repeatMode(for: parts[7]),
                artworkImage: cachedArtwork(for: musicArtworkCacheKey(for: track)) {
                    loadMusicArtwork()
                }
            )
        }
    }

    private func fetchSpotifyState() -> PlayerSnapshot? {
        autoreleasepool {
            guard Self.isApplicationRunning(bundleIdentifier: PlayerSourceKind.spotify.bundleIdentifier) else {
                return nil
            }

            guard let output = Self.runAppleScript([
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
            ]) else {
                return nil
            }

            if output == "stopped" {
                return PlayerSnapshot(
                    source: .spotify,
                    playbackStatus: .stopped,
                    track: nil,
                    shuffleMode: .unsupported,
                    repeatMode: .unsupported,
                    artworkImage: nil
                )
            }

            let parts = output.components(separatedBy: "\u{1F}")
            guard parts.count >= 7 else {
                return nil
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

            return PlayerSnapshot(
                source: .spotify,
                playbackStatus: playbackStatus(for: parts[0]),
                track: track,
                shuffleMode: .unsupported,
                repeatMode: .unsupported,
                artworkImage: cachedArtwork(for: spotifyArtworkCacheKey(for: track, artworkURL: artworkURL)) {
                    loadArtwork(from: artworkURL)
                }
            )
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

    private func cachedArtwork(for key: String, loader: () -> NSImage?) -> NSImage? {
        if let cachedImage = artworkCache[key] {
            return cachedImage
        }

        guard let image = loader() else {
            return nil
        }

        artworkCache[key] = image
        artworkCacheOrder.removeAll { $0 == key }
        artworkCacheOrder.append(key)

        if artworkCacheOrder.count > artworkCacheLimit,
           let evictedKey = artworkCacheOrder.first {
            artworkCacheOrder.removeFirst()
            artworkCache.removeValue(forKey: evictedKey)
        }

        return image
    }

    private func loadMusicArtwork() -> NSImage? {
        guard let descriptor = Self.runAppleScriptDescriptor([
            #"tell application "Music""#,
            #"set currentTrack to current track"#,
            #"if (count of artworks of currentTrack) is 0 then return missing value"#,
            #"return data of artwork 1 of currentTrack"#,
            #"end tell"#,
        ]) else {
            return nil
        }

        guard descriptor.descriptorType != typeNull else {
            return nil
        }

        let data = descriptor.data
        guard !data.isEmpty else {
            return nil
        }

        return NSImage(data: data)
    }

    private func loadArtwork(from url: URL?) -> NSImage? {
        guard let url else {
            return nil
        }

        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else {
            return nil
        }

        return image
    }

    @discardableResult
    private static func runAppleScript(_ lines: [String]) -> String? {
        autoreleasepool {
            guard let descriptor = runAppleScriptDescriptor(lines) else {
                return nil
            }

            if descriptor.descriptorType == typeNull {
                return nil
            }

            let output = (descriptor.stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? nil : output
        }
    }

    private static func runAppleScriptDescriptor(_ lines: [String]) -> NSAppleEventDescriptor? {
        autoreleasepool {
            let source = lines.joined(separator: "\n")
            guard let script = NSAppleScript(source: source) else {
                return nil
            }

            var error: NSDictionary?
            let descriptor = script.executeAndReturnError(&error)
            if error != nil {
                return nil
            }
            return descriptor
        }
    }

    private static func isApplicationRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    private static func launchApplication(bundleIdentifier: String) -> Bool {
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

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
