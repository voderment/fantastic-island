import Foundation

enum ClashConnectionMode: String, CaseIterable, Identifiable {
    case global
    case rule
    case direct

    var id: String { rawValue }

    var title: String {
        switch self {
        case .global:
            return "全局"
        case .rule:
            return "代理"
        case .direct:
            return "直连"
        }
    }
}

enum ClashLatencyTestState: Equatable {
    case idle
    case testing(group: String, proxy: String)
    case failed(group: String, proxy: String, message: String)

    var isTesting: Bool {
        if case .testing = self {
            return true
        }

        return false
    }

    var currentGroup: String? {
        switch self {
        case .idle:
            return nil
        case let .testing(group, _), let .failed(group, _, _):
            return group
        }
    }

    var displayText: String {
        switch self {
        case .idle:
            return "测速"
        case let .testing(group, proxy):
            return "测速中 · \(group) · \(proxy)"
        case let .failed(group, proxy, message):
            return "失败 · \(group) · \(proxy) · \(message)"
        }
    }
}

struct ClashControlState: Equatable {
    var captureMode: ClashManagedCaptureMode = .none
    var capturePhase: ClashManagedCapturePhase = .inactive
    var connectionMode: ClashConnectionMode = .rule
    var latencyTestState: ClashLatencyTestState = .idle

    var isCaptureActive: Bool {
        captureMode != .none && capturePhase == .active
    }
}
