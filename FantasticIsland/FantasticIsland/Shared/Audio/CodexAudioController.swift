import AppKit
import Foundation

@MainActor
final class CodexAudioController {
    private(set) var isMuted = true
    private var lastApprovalSoundAt = Date.distantPast
    private var lastCompletionSoundAt = Date.distantPast
    private var previousApprovalCount = 0
    private var previousCompletedCount = 0

    func primePlayback(approvalCount: Int, completedCount: Int) {
        previousApprovalCount = approvalCount
        previousCompletedCount = completedCount
    }

    func syncPlayback(approvalCount: Int, completedCount: Int) {
        guard !isMuted else {
            previousApprovalCount = approvalCount
            previousCompletedCount = completedCount
            return
        }

        if approvalCount > previousApprovalCount {
            playSystemSound(named: "Blow", throttle: &lastApprovalSoundAt)
        }

        if completedCount > previousCompletedCount {
            playSystemSound(named: "Glass", throttle: &lastCompletionSoundAt)
        }

        previousApprovalCount = approvalCount
        previousCompletedCount = completedCount
    }

    func stopAllPlayback() {}

    func setMuted(_ muted: Bool) {
        isMuted = muted
    }

    private func playSystemSound(named name: String, throttle: inout Date) {
        guard Date().timeIntervalSince(throttle) > 1.2 else {
            return
        }

        throttle = .now
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
