import Foundation

final class CodexMonitoringEngine {
    private let queue: DispatchQueue
    private let tokenUsageQueue: DispatchQueue
    private let discovery: CodexSessionDiscovery
    private let sessionStore: AgentSessionStore
    private let reducer: CodexSessionReducer
    private let tailer: CodexRolloutTailer
    private let tokenUsageScanner: CodexTokenUsageHistoryScanner
    private var latestTokenUsageHistory = CodexTokenUsageHistory.empty
    private var lastTokenUsageScanAt = Date.distantPast
    private var isTokenUsageScanInFlight = false
    private let tokenUsageScanInterval: TimeInterval = 60

    init(
        discovery: CodexSessionDiscovery = CodexSessionDiscovery(),
        sessionStore: AgentSessionStore = AgentSessionStore(),
        reducer: CodexSessionReducer = CodexSessionReducer(),
        tailer: CodexRolloutTailer = CodexRolloutTailer(),
        tokenUsageScanner: CodexTokenUsageHistoryScanner = CodexTokenUsageHistoryScanner(),
        queue: DispatchQueue = DispatchQueue(label: "fantastic-island.monitoring", qos: .utility),
        tokenUsageQueue: DispatchQueue = DispatchQueue(label: "fantastic-island.codex-token-usage", qos: .utility)
    ) {
        self.discovery = discovery
        self.sessionStore = sessionStore
        self.reducer = reducer
        self.tailer = tailer
        self.tokenUsageScanner = tokenUsageScanner
        self.queue = queue
        self.tokenUsageQueue = tokenUsageQueue
    }

    func poll(completion: @escaping (CodexMonitoringSnapshot) -> Void) {
        queue.async { [self] in
            let sessions = discovery.discoverRecentSessions()
            tailer.sync(with: sessions, reducer: reducer)
            publishSnapshot(completion)
            refreshTokenUsageHistoryIfNeeded(now: .now, completion: completion)
        }
    }

    func applyHookPayload(
        _ payload: CodexHookPayload,
        followedBy event: CodexAgentEvent? = nil,
        completion: @escaping (CodexMonitoringSnapshot) -> Void
    ) {
        let storedTranscriptURL = try? sessionStore.append(payload)
        queue.async { [self] in
            reducer.applyHookPayload(payload)

            if let transcriptPath = payload.transcriptPath ?? storedTranscriptURL?.path {
                let discovered = discovery.discoverSession(at: URL(fileURLWithPath: transcriptPath)) ?? DiscoveredSession(
                    id: payload.sessionID,
                    provider: payload.agentProvider,
                    cwd: payload.cwd,
                    title: SessionSnapshot.title(for: payload.cwd, provider: payload.agentProvider),
                    transcriptPath: transcriptPath,
                    jumpTarget: payload.terminalJumpTarget,
                    assistantSummary: payload.assistantSummary,
                    sessionSurface: payload.sessionSurface
                )
                let sessions = discovery.discoverRecentSessions() + [discovered]
                tailer.sync(with: sessions, reducer: reducer)
            }

            if let event {
                reducer.apply(event)
            }

            publishSnapshot(completion)
            refreshTokenUsageHistoryIfNeeded(now: .now, force: payload.transcriptPath != nil, completion: completion)
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
            quotaSnapshot: reducer.latestQuotaSnapshot,
            tokenUsageHistory: latestTokenUsageHistory
        )

        DispatchQueue.main.async {
            completion(snapshot)
        }
    }

    private func refreshTokenUsageHistoryIfNeeded(
        now: Date,
        force: Bool = false,
        completion: @escaping (CodexMonitoringSnapshot) -> Void
    ) {
        guard !isTokenUsageScanInFlight,
              force || now.timeIntervalSince(lastTokenUsageScanAt) >= tokenUsageScanInterval else {
            return
        }

        isTokenUsageScanInFlight = true
        lastTokenUsageScanAt = now
        tokenUsageQueue.async { [self] in
            let history = tokenUsageScanner.scan(now: now)
            queue.async { [self] in
                latestTokenUsageHistory = history
                isTokenUsageScanInFlight = false
                publishSnapshot(completion)
            }
        }
    }
}
