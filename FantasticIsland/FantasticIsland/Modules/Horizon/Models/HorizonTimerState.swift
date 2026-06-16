import AppKit
import Combine
import Foundation

enum HorizonTimerMode: Equatable {
    case idle
    case running
    case paused
}

struct HorizonTimerSnapshot: Equatable {
    var mode: HorizonTimerMode
    var remainingSeconds: Int
    var presetMinutes: Int

    static let idle = HorizonTimerSnapshot(mode: .idle, remainingSeconds: 0, presetMinutes: 5)

    var displayText: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

@MainActor
final class HorizonTimerController: ObservableObject {
    @Published private(set) var snapshot = HorizonTimerSnapshot.idle

    private var tickTimer: Timer?
    private var endDate: Date?

    func start(minutes: Int) {
        let clamped = max(1, min(minutes, 180))
        endDate = Date().addingTimeInterval(TimeInterval(clamped * 60))
        snapshot = HorizonTimerSnapshot(
            mode: .running,
            remainingSeconds: clamped * 60,
            presetMinutes: clamped
        )
        startTicking()
    }

    func pause() {
        guard snapshot.mode == .running, let endDate else {
            return
        }

        snapshot = HorizonTimerSnapshot(
            mode: .paused,
            remainingSeconds: max(0, Int(endDate.timeIntervalSinceNow)),
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

        let remaining = max(0, Int(endDate.timeIntervalSinceNow))
        if remaining == 0 {
            reset()
            NSSound.beep()
            return
        }

        snapshot = HorizonTimerSnapshot(
            mode: .running,
            remainingSeconds: remaining,
            presetMinutes: snapshot.presetMinutes
        )
    }
}
