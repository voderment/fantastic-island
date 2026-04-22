import Foundation

enum FanActivityModel {
    static func recompute(from sessions: [SessionSnapshot], now: Date = .now) -> FanActivityState {
        let inProgressSessions = sessions.filter {
            $0.isLikelyLive(at: now)
        }
        let activeSessions = sessions.filter {
            $0.isLikelyLive(at: now) || now.timeIntervalSince($0.lastEventAt ?? .distantPast) <= 12
        }
        let busySessions = activeSessions.filter { $0.phase == .busy }
        let recentUpdates = sessions.filter {
            now.timeIntervalSince($0.lastEventAt ?? .distantPast) <= 3
        }
        let recentToolTransitions = sessions.reduce(0) { partialResult, session in
            partialResult + session.toolTransitionTimestamps.filter { now.timeIntervalSince($0) <= 3 }.count
        }

        let score = 1.0 * Double(activeSessions.count)
            + 0.8 * Double(busySessions.count)
            + 0.3 * Double(recentUpdates.count)
            + 0.2 * Double(recentToolTransitions)

        return FanActivityState(
            activityScore: score,
            isSpinning: score > 0.05,
            rotationPeriod: rotationPeriod(for: score),
            activeSessionCount: activeSessions.count,
            inProgressSessionCount: inProgressSessions.count,
            busySessionCount: busySessions.count,
            lastEventAt: sessions.compactMap(\.lastEventAt).max()
        )
    }

    static func speedTier(hasActivitySource: Bool, inProgressTaskCount: Int) -> FanSpeedTier {
        FanSpeedTier.resolve(hasActivitySource: hasActivitySource, inProgressTaskCount: inProgressTaskCount)
    }

    static func rotationPeriod(for score: Double) -> Double {
        guard score > 0.05 else {
            return 1.6
        }

        return max(0.18, 1.6 - min(score, 6) * 0.22)
    }
}

enum FanSpeedTier: Equatable {
    case stopped
    case idle
    case single
    case double
    case group
    case overload

    var rotationPeriod: Double {
        switch self {
        case .stopped:
            return 1.6
        case .idle:
            return 4.8
        case .single:
            return 1.9
        case .double:
            return 1.34
        case .group:
            return 1.04
        case .overload:
            return 0.88
        }
    }

    var isSpinning: Bool {
        self != .stopped
    }

    static func resolve(hasActivitySource: Bool, inProgressTaskCount: Int) -> FanSpeedTier {
        guard inProgressTaskCount > 0 else {
            return hasActivitySource ? .idle : .stopped
        }

        switch inProgressTaskCount {
        case 1:
            return .single
        case 2:
            return .double
        case 3...4:
            return .group
        default:
            return .overload
        }
    }
}
