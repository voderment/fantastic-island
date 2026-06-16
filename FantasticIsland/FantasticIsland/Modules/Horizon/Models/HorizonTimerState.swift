import AppKit
import Combine
import Foundation

enum HorizonTimerMode: Equatable {
    case idle
    case running
    case paused
    case completed
}

struct HorizonTimerSnapshot: Equatable {
    var mode: HorizonTimerMode
    var remainingSeconds: Int
    var presetMinutes: Int

    static let idle = HorizonTimerSnapshot(mode: .idle, remainingSeconds: 0, presetMinutes: 5)

    var displayText: String {
        if mode == .completed {
            return "Done"
        }

        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var progressFraction: Double {
        guard presetMinutes > 0 else {
            return 0
        }

        let total = max(1, presetMinutes * 60)
        let elapsed = total - max(0, remainingSeconds)
        return min(1, max(0, Double(elapsed) / Double(total)))
    }
}

@MainActor
final class HorizonTimerController: ObservableObject {
    @Published private(set) var snapshot = HorizonTimerSnapshot.idle
    private(set) var completionDate: Date?
    var playsCompletionSound = true

    private var tickTimer: Timer?
    private var endDate: Date?

    func start(minutes: Int) {
        start(seconds: minutes * 60, presetMinutes: minutes)
    }

    func start(seconds: Int) {
        start(seconds: seconds, presetMinutes: max(1, Int(ceil(Double(seconds) / 60.0))))
    }

    private func start(seconds: Int, presetMinutes: Int) {
        let clampedSeconds = max(1, min(seconds, 10_800))
        let clampedPreset = max(1, min(presetMinutes, 180))
        completionDate = nil
        endDate = Date().addingTimeInterval(TimeInterval(clampedSeconds))
        snapshot = HorizonTimerSnapshot(
            mode: .running,
            remainingSeconds: clampedSeconds,
            presetMinutes: clampedPreset
        )
        startTicking()
    }

    func pause() {
        guard snapshot.mode == .running, let endDate else {
            return
        }

        snapshot = HorizonTimerSnapshot(
            mode: .paused,
            remainingSeconds: max(0, Int(ceil(endDate.timeIntervalSinceNow))),
            presetMinutes: snapshot.presetMinutes
        )
        self.endDate = nil
        stopTicking()
    }

    func resume() {
        guard snapshot.mode == .paused, snapshot.remainingSeconds > 0 else {
            return
        }

        endDate = Date().addingTimeInterval(TimeInterval(snapshot.remainingSeconds))
        snapshot = HorizonTimerSnapshot(
            mode: .running,
            remainingSeconds: snapshot.remainingSeconds,
            presetMinutes: snapshot.presetMinutes
        )
        startTicking()
    }

    func reset() {
        endDate = nil
        completionDate = nil
        snapshot = HorizonTimerSnapshot.idle
        stopTicking()
    }

    private func startTicking() {
        stopTicking()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        tickTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        guard let endDate else {
            reset()
            return
        }

        let remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        if remaining == 0 {
            completionDate = .now
            snapshot = HorizonTimerSnapshot(
                mode: .completed,
                remainingSeconds: 0,
                presetMinutes: snapshot.presetMinutes
            )
            self.endDate = nil
            stopTicking()
            if playsCompletionSound {
                NSSound.beep()
            }
            return
        }

        snapshot = HorizonTimerSnapshot(
            mode: .running,
            remainingSeconds: remaining,
            presetMinutes: snapshot.presetMinutes
        )
    }
}
