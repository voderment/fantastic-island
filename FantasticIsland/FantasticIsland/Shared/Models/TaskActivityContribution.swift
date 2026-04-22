import Foundation

struct TaskActivityContribution: Equatable {
    var activityScore: Double = 0
    var activeTaskCount: Int = 0
    var inProgressTaskCount: Int = 0
    var busyTaskCount: Int = 0
    var lastEventAt: Date?
    var supportsIdleSpin: Bool = false
}

struct AggregatedTaskActivity: Equatable {
    var activityScore: Double = 0
    var activeTaskCount: Int = 0
    var inProgressTaskCount: Int = 0
    var busyTaskCount: Int = 0
    var lastEventAt: Date?
    var supportsIdleSpin: Bool = false
}

enum TaskActivityAggregator {
    static func aggregate(_ contributions: [TaskActivityContribution]) -> AggregatedTaskActivity {
        AggregatedTaskActivity(
            activityScore: contributions.reduce(0) { $0 + $1.activityScore },
            activeTaskCount: contributions.reduce(0) { $0 + $1.activeTaskCount },
            inProgressTaskCount: contributions.reduce(0) { $0 + $1.inProgressTaskCount },
            busyTaskCount: contributions.reduce(0) { $0 + $1.busyTaskCount },
            lastEventAt: contributions.compactMap(\.lastEventAt).max(),
            supportsIdleSpin: contributions.contains { $0.supportsIdleSpin }
        )
    }
}
