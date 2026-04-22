import AppKit
import Foundation

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

    static let empty = PlayerNowPlayingState(
        source: nil,
        playbackStatus: .stopped,
        track: nil,
        shuffleMode: .unsupported,
        repeatMode: .unsupported,
        artworkImage: nil
    )

    static func == (lhs: PlayerNowPlayingState, rhs: PlayerNowPlayingState) -> Bool {
        lhs.source == rhs.source
            && lhs.playbackStatus == rhs.playbackStatus
            && lhs.track == rhs.track
            && lhs.shuffleMode == rhs.shuffleMode
            && lhs.repeatMode == rhs.repeatMode
    }

    var sourceLabel: String {
        source?.displayName ?? "Player"
    }

    var titleText: String {
        track?.title ?? "Nothing Playing"
    }

    var artistText: String {
        track?.artist ?? "No active media source"
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
        source != nil
    }

    var supportsSeeking: Bool {
        source != nil && (track?.duration ?? 0) > 0
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

    private static func timeText(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded(.down)), 0)
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes):\(String(format: "%02d", remainder))"
    }
}
