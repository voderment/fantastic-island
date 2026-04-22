import AVFoundation
import Foundation

@MainActor
final class CodexAudioController: NSObject, @preconcurrency AVAudioPlayerDelegate {
    private enum CueState {
        case idle
        case awaitingLoop
        case playingStopCue
    }

    private var startStopPlayer: AVAudioPlayer?
    private var fanLoopPlayer: AVAudioPlayer?
    private var cueState: CueState = .idle
    private var isFanLoopDesired = false
    private var isMuted = false

    override init() {
        super.init()
        configurePlayers()
    }

    func primePlayback(inProgressSessionCount: Int) {
        let shouldRunFanLoop = inProgressSessionCount > 0
        isFanLoopDesired = shouldRunFanLoop
        cueState = .idle

        if isMuted {
            stopPlayers()
            return
        }

        if shouldRunFanLoop {
            playFanLoop()
        } else {
            stopAllPlayback()
        }
    }

    func syncPlayback(inProgressSessionCount: Int) {
        let shouldRunFanLoop = inProgressSessionCount > 0
        if isMuted {
            isFanLoopDesired = shouldRunFanLoop
            stopPlayers()
            return
        }

        guard shouldRunFanLoop != isFanLoopDesired || (shouldRunFanLoop && !(fanLoopPlayer?.isPlaying ?? false) && cueState == .idle) else {
            return
        }

        isFanLoopDesired = shouldRunFanLoop

        if shouldRunFanLoop {
            playStartCueThenFanLoop()
        } else {
            stopFanLoopAndPlayStopCue()
        }
    }

    func stopAllPlayback() {
        isFanLoopDesired = false
        stopPlayers()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        if muted {
            stopPlayers()
        }
    }

    private func stopPlayers() {
        cueState = .idle
        startStopPlayer?.stop()
        startStopPlayer?.currentTime = 0
        fanLoopPlayer?.stop()
        fanLoopPlayer?.currentTime = 0
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === startStopPlayer else {
            return
        }

        switch cueState {
        case .awaitingLoop:
            cueState = .idle
            guard isFanLoopDesired else {
                return
            }
            playFanLoop()
        case .playingStopCue, .idle:
            cueState = .idle
        }
    }

    private func configurePlayers() {
        startStopPlayer = makePlayer(resource: "startandstop", fileExtension: "mp3")
        startStopPlayer?.delegate = self

        fanLoopPlayer = makePlayer(resource: "fanvoice", fileExtension: "aiff")
        fanLoopPlayer?.numberOfLoops = -1
    }

    private func playStartCueThenFanLoop() {
        fanLoopPlayer?.stop()
        fanLoopPlayer?.currentTime = 0

        guard let startStopPlayer else {
            cueState = .idle
            playFanLoop()
            return
        }

        cueState = .awaitingLoop
        startStopPlayer.stop()
        startStopPlayer.currentTime = 0
        if !startStopPlayer.play() {
            cueState = .idle
            playFanLoop()
        }
    }

    private func stopFanLoopAndPlayStopCue() {
        fanLoopPlayer?.stop()
        fanLoopPlayer?.currentTime = 0

        guard let startStopPlayer else {
            cueState = .idle
            return
        }

        cueState = .playingStopCue
        startStopPlayer.stop()
        startStopPlayer.currentTime = 0
        if !startStopPlayer.play() {
            cueState = .idle
        }
    }

    private func playFanLoop() {
        guard let fanLoopPlayer else {
            return
        }

        fanLoopPlayer.stop()
        fanLoopPlayer.currentTime = 0
        fanLoopPlayer.play()
    }

    private func makePlayer(resource: String, fileExtension: String) -> AVAudioPlayer? {
        guard let url =
            Bundle.main.url(forResource: resource, withExtension: fileExtension, subdirectory: "source/voice")
            ?? Bundle.main.url(forResource: resource, withExtension: fileExtension) else {
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            return player
        } catch {
            NSLog("Fantastic Island audio load failed for %@.%@: %@", resource, fileExtension, error.localizedDescription)
            return nil
        }
    }
}
