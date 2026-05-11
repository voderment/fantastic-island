import AppKit
import Foundation

enum PlayerAutomationIssue: Equatable {
    case permissionDenied(source: PlayerSourceKind)
    case permissionRequired(source: PlayerSourceKind)

    var sourceKind: PlayerSourceKind {
        switch self {
        case let .permissionDenied(source), let .permissionRequired(source):
            return source
        }
    }

    var canRequestAccess: Bool {
        switch self {
        case .permissionRequired:
            return true
        case .permissionDenied:
            return false
        }
    }

    var titleText: String {
        "Automation Access Needed"
    }

    var detailText: String {
        switch self {
        case let .permissionDenied(source):
            return "Allow access to \(source.displayName) in Privacy & Security > Automation"
        case let .permissionRequired(source):
            return "Allow \(Self.hostApplicationName) to control \(source.displayName) when macOS asks"
        }
    }

    private static var hostApplicationName: String {
        if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.isEmpty {
            return displayName
        }

        if let bundleName = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String,
           !bundleName.isEmpty {
            return bundleName
        }

        return "Fantastic Island"
    }
}

enum PlayerPlaybackStatus: String, Equatable {
    case stopped
    case paused
    case playing

    var isPlaying: Bool { self == .playing }
}

enum PlayerRepeatMode: String, Equatable {
    case off
    case all
    case one
    case unsupported

    var symbolName: String {
        switch self {
        case .off, .all:
            return "repeat"
        case .one:
            return "repeat.1"
        case .unsupported:
            return "repeat"
        }
    }
}

enum PlayerShuffleMode: String, Equatable {
    case off
    case on
    case unsupported

    var symbolName: String {
        "shuffle"
    }
}

struct PlayerTrackMetadata: Equatable {
    var title: String
    var artist: String
    var album: String?
    var duration: TimeInterval
    var elapsed: TimeInterval
    var artworkURL: URL?
}

struct PlayerNowPlayingState: Equatable {
    var source: PlayerSourceKind?
    var playbackStatus: PlayerPlaybackStatus
    var track: PlayerTrackMetadata?
    var shuffleMode: PlayerShuffleMode
    var repeatMode: PlayerRepeatMode
    var artworkImage: NSImage?
    var automationIssue: PlayerAutomationIssue?

    static let empty = PlayerNowPlayingState(
        source: nil,
        playbackStatus: .stopped,
        track: nil,
        shuffleMode: .unsupported,
        repeatMode: .unsupported,
        artworkImage: nil,
        automationIssue: nil
    )

    static func issueState(_ issue: PlayerAutomationIssue) -> PlayerNowPlayingState {
        PlayerNowPlayingState(
            source: nil,
            playbackStatus: .stopped,
            track: nil,
            shuffleMode: .unsupported,
            repeatMode: .unsupported,
            artworkImage: nil,
            automationIssue: issue
        )
    }

    static func idleState(source: PlayerSourceKind) -> PlayerNowPlayingState {
        PlayerNowPlayingState(
            source: source,
            playbackStatus: .stopped,
            track: nil,
            shuffleMode: .unsupported,
            repeatMode: .unsupported,
            artworkImage: nil,
            automationIssue: nil
        )
    }

    static func == (lhs: PlayerNowPlayingState, rhs: PlayerNowPlayingState) -> Bool {
        lhs.source == rhs.source
            && lhs.playbackStatus == rhs.playbackStatus
            && lhs.track == rhs.track
            && lhs.shuffleMode == rhs.shuffleMode
            && lhs.repeatMode == rhs.repeatMode
            && lhs.automationIssue == rhs.automationIssue
            && lhs.artworkComparisonKey == rhs.artworkComparisonKey
    }

    var sourceLabel: String {
        source?.displayName ?? "Player"
    }

    var automationIssueSource: PlayerSourceKind? {
        automationIssue?.sourceKind
    }

    var titleText: String {
        track?.title ?? automationIssue?.titleText ?? "Nothing Playing"
    }

    var artistText: String {
        track?.artist ?? automationIssue?.detailText ?? "No active media source"
    }

    var durationText: String {
        Self.timeText(track?.duration ?? 0)
    }

    var elapsedText: String {
        Self.timeText(track?.elapsed ?? 0)
    }

    var remainingText: String {
        guard let track else {
            return "0:00"
        }

        return "-\(Self.timeText(max(track.duration - track.elapsed, 0)))"
    }

    var progress: Double {
        guard let track, track.duration > 0 else {
            return 0
        }

        return min(max(track.elapsed / track.duration, 0), 1)
    }

    var supportsTransportControls: Bool {
        automationIssue == nil && source != nil
    }

    var supportsSeeking: Bool {
        automationIssue == nil && source != nil && (track?.duration ?? 0) > 0
    }

    var supportsShuffleControl: Bool {
        shuffleMode != .unsupported && source == .music
    }

    var supportsRepeatControl: Bool {
        repeatMode != .unsupported && source == .music
    }

    var collapsedSummaryText: String {
        if playbackStatus == .playing, let track {
            return "PLAY \(track.title)"
        }

        return "PLAYER --"
    }

    private var artworkComparisonKey: String {
        let identity = trackIdentityForArtwork ?? "none"
        let presence = artworkImage == nil ? "missing" : "present"
        return "\(presence):\(identity)"
    }

    private var trackIdentityForArtwork: String? {
        if let artworkURL = track?.artworkURL?.absoluteString {
            return artworkURL
        }

        guard let track else {
            return source?.rawValue
        }

        return [
            source?.rawValue ?? "player",
            track.title,
            track.artist,
            track.album ?? "",
        ].joined(separator: "\u{1F}")
    }

    private static func timeText(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded(.down)), 0)
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes):\(String(format: "%02d", remainder))"
    }
}
