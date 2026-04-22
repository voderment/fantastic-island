import Foundation

final class CodexMonitoringEngine {
    private let queue: DispatchQueue
    private let discovery: CodexSessionDiscovery
    private let reducer: CodexSessionReducer
    private let tailer: CodexRolloutTailer

    init(
        discovery: CodexSessionDiscovery = CodexSessionDiscovery(),
        reducer: CodexSessionReducer = CodexSessionReducer(),
        tailer: CodexRolloutTailer = CodexRolloutTailer(),
        queue: DispatchQueue = DispatchQueue(label: "fantastic-island.monitoring", qos: .utility)
    ) {
        self.discovery = discovery
        self.reducer = reducer
        self.tailer = tailer
        self.queue = queue
    }

    func poll(completion: @escaping (CodexMonitoringSnapshot) -> Void) {
        queue.async { [self] in
            let sessions = discovery.discoverRecentSessions()
            tailer.sync(with: sessions, reducer: reducer)
            publishSnapshot(completion)
        }
    }

    func applyHookPayload(_ payload: CodexHookPayload, completion: @escaping (CodexMonitoringSnapshot) -> Void) {
        queue.async { [self] in
            reducer.applyHookPayload(payload)

            if let transcriptPath = payload.transcriptPath {
                let discovered = discovery.discoverSession(at: URL(fileURLWithPath: transcriptPath)) ?? DiscoveredSession(
                    id: payload.sessionID,
                    cwd: payload.cwd,
                    title: SessionSnapshot.title(for: payload.cwd),
                    transcriptPath: transcriptPath,
                    jumpTarget: payload.terminalJumpTarget,
                    assistantSummary: payload.assistantSummary,
                    sessionSurface: payload.sessionSurface
                )
                let sessions = discovery.discoverRecentSessions() + [discovered]
                tailer.sync(with: sessions, reducer: reducer)
            }

            publishSnapshot(completion)
        }
    }

    func applyEvent(_ event: CodexAgentEvent, completion: @escaping (CodexMonitoringSnapshot) -> Void) {
        queue.async { [self] in
            reducer.apply(event)
            publishSnapshot(completion)
        }
    }

    private func publishSnapshot(_ completion: @escaping (CodexMonitoringSnapshot) -> Void) {
        let snapshot = CodexMonitoringSnapshot(
            sessions: reducer.allSessions,
            quotaSnapshot: reducer.latestQuotaSnapshot
        )

        DispatchQueue.main.async {
            completion(snapshot)
        }
    }
}
