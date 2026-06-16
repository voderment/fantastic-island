import Foundation

enum AgentActivityModel {
    static func recompute(from sessions: [SessionSnapshot], now: Date = .now) -> AgentActivityState {
        let inProgressSessions = sessions.filter {
            $0.isLikelyLive(at: now)
        }
        let activeSessions = sessions.filter {
            !$0.isSessionEnded && $0.isVisibleInIsland(at: now)
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

        return AgentActivityState(
            activityScore: score,
            activeSessionCount: activeSessions.count,
            inProgressSessionCount: inProgressSessions.count,
            busySessionCount: busySessions.count,
            lastEventAt: sessions.compactMap(\.lastEventAt).max()
        )
    }
}
