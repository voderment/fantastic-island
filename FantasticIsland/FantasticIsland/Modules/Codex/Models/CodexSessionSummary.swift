import Foundation

enum CodexIslandSessionPresence: Equatable {
    case running
    case active
    case inactive
}

struct CodexIslandSessionBuckets {
    var primary: [SessionSnapshot]
    var overflow: [SessionSnapshot]
}

enum CodexIslandSessionPresentation {
    private static let inactivityThreshold: TimeInterval = 20 * 60

    static func computeBuckets(
        from sessions: [SessionSnapshot],
        now: Date = .now
    ) -> CodexIslandSessionBuckets {
        let ranked = sessions.sorted { lhs, rhs in
            let lhsScore = displayPriority(for: lhs, now: now)
            let rhsScore = displayPriority(for: rhs, now: now)
            if lhsScore == rhsScore {
                if lhs.islandActivityDate == rhs.islandActivityDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }

                return lhs.islandActivityDate > rhs.islandActivityDate
            }

            return lhsScore > rhsScore
        }

        var primary: [SessionSnapshot] = []
        var claimedLiveAttachmentKeys: Set<String> = []

        for session in ranked where session.isVisibleInIsland(at: now) {
            if let key = liveAttachmentKey(for: session),
               !claimedLiveAttachmentKeys.insert(key).inserted {
                continue
            }
            primary.append(session)
        }

        let primaryIDs = Set(primary.map(\.id))
        let overflow = ranked.filter { !primaryIDs.contains($0.id) }
        return CodexIslandSessionBuckets(primary: primary, overflow: overflow)
    }

    static func presence(
        for session: SessionSnapshot,
        at now: Date = .now
    ) -> CodexIslandSessionPresence {
        if session.isLikelyLive(at: now) {
            return .running
        }

        if session.phase.requiresAttention {
            return .active
        }

        if now.timeIntervalSince(session.islandActivityDate) <= inactivityThreshold {
            return .active
        }

        return .inactive
    }

    static func ageBadge(
        for session: SessionSnapshot,
        now: Date = .now
    ) -> String {
        let age = max(0, Int(now.timeIntervalSince(session.islandActivityDate)))
        if age < 60 {
            return "<1m"
        }
        if age < 3_600 {
            return "\(max(1, age / 60))m"
        }
        if age < 86_400 {
            return "\(max(1, age / 3_600))h"
        }
        return "\(max(1, age / 86_400))d"
    }

    private static func displayPriority(for session: SessionSnapshot, now: Date) -> Int {
        var score = 0
        let presence = presence(for: session, at: now)

        if session.phase.requiresAttention {
            score += 12_000
        }

        if session.currentTool?.isEmpty == false {
            score += 6_000
        }

        if session.canJumpBack {
            score += 3_500
        }

        switch presence {
        case .running:
            score += 5_000
        case .active:
            score += 2_000
        case .inactive:
            score += 400
        }

        switch session.phase {
        case .running:
            score += 2_000
        case .busy:
            score += 1_700
        case .waitingForApproval:
            score += 1_500
        case .waitingForAnswer:
            score += 1_200
        case .completed:
            score += 600
        }

        let age = now.timeIntervalSince(session.islandActivityDate)
        switch age {
        case ..<120:
            score += 500
        case ..<900:
            score += 250
        case ..<3_600:
            score += 120
        case ..<21_600:
            score += 40
        default:
            break
        }

        return score
    }

    private static func liveAttachmentKey(for session: SessionSnapshot) -> String? {
        if let jumpTarget = session.jumpTarget {
            return jumpTarget.id
        }

        if let transcriptPath = session.transcriptPath {
            return transcriptPath
        }

        return nil
    }
}
