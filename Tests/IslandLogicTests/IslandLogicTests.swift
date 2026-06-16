import Foundation
import Darwin
import XCTest
@testable import IslandLogic

actor EnvelopeQueue {
    private var buffer: [Data] = []
    private var waiters: [CheckedContinuation<Data, Never>] = []

    func push(_ data: Data) {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume(returning: data)
            return
        }

        buffer.append(data)
    }

    func next() async -> Data {
        if !buffer.isEmpty {
            return buffer.removeFirst()
        }

        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

final class DisconnectRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var reasons: [CodexAppServerDisconnectReason] = []

    func append(_ reason: CodexAppServerDisconnectReason) {
        lock.lock()
        reasons.append(reason)
        lock.unlock()
    }

    func snapshot() -> [CodexAppServerDisconnectReason] {
        lock.lock()
        defer { lock.unlock() }
        return reasons
    }
}

final class FakeWritableStream: CodexAppServerWritableStream, @unchecked Sendable {
    var onWrite: ((Data) throws -> Void)?

    func write(_ data: Data) throws {
        try onWrite?(data)
    }

    func close() {}
}

final class FakeReadableStream: CodexAppServerReadableStream, @unchecked Sendable {
    var onData: (@Sendable (Data) -> Void)?

    func send(_ data: Data) {
        onData?(data)
    }

    func close() {}
}

final class FakeTransport: CodexAppServerTransport, @unchecked Sendable {
    let stdin: any CodexAppServerWritableStream
    let stdout: any CodexAppServerReadableStream

    var onTerminate: (@Sendable (Int32) -> Void)?
    var isRunning = false
    var onRequest: (([String: Any]) -> Void)?

    private let writer = FakeWritableStream()
    private let reader = FakeReadableStream()
    private let queue = EnvelopeQueue()

    init() {
        stdin = writer
        stdout = reader

        writer.onWrite = { [weak self] data in
            guard let self else {
                return
            }

            Task {
                await self.queue.push(data)
            }

            let request = try Self.decodeJSONObject(from: data)
            self.onRequest?(request)
        }
    }

    func run() throws {
        isRunning = true
    }

    func terminate() {
        isRunning = false
        onTerminate?(SIGTERM)
    }

    func close() {
        reader.onData = nil
        onTerminate = nil
    }

    func sendEOF() {
        isRunning = false
        reader.send(Data())
    }

    func sendJSON(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(UInt8(ascii: "\n"))
        reader.send(data)
    }

    func nextMethod(_ method: String) async throws -> [String: Any] {
        while true {
            let envelope = try Self.decodeJSONObject(from: await queue.next())
            if envelope["method"] as? String == method {
                return envelope
            }
        }
    }

    private static func decodeJSONObject(from data: Data) throws -> [String: Any] {
        let payload = data.last == UInt8(ascii: "\n") ? Data(data.dropLast()) : data
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
    }
}

@MainActor
final class IslandLogicTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func testXPostValidatorBlocksURLs() {
        XCTAssertTrue(XPostTextValidator.validate("hello https://example.com").containsURL)
        XCTAssertTrue(XPostTextValidator.validate("hello http://example.com").containsURL)
        XCTAssertTrue(XPostTextValidator.validate("hello www.example.com").containsURL)
        XCTAssertFalse(XPostTextValidator.validate("hello example dot com").containsURL)
    }

    func testXPostValidatorRejectsEmptyText() {
        let validation = XPostTextValidator.validate(" \n\t ")
        XCTAssertTrue(validation.isEmpty)
        XCTAssertFalse(validation.isValid)
    }

    func testXPostValidatorRejectsOverLimitWeightedText() {
        let validation = XPostTextValidator.validate(String(repeating: "发", count: 141))
        XCTAssertEqual(validation.weightedLength, 282)
        XCTAssertTrue(validation.isOverLimit)
        XCTAssertFalse(validation.isValid)
    }

    func testAgentProviderMetadataIncludesRequiredNativeTargets() {
        XCTAssertEqual(AgentProvider.codex.launchProfile.bundleIdentifier, "com.openai.codex")
        XCTAssertEqual(AgentProvider.claudeCode.launchProfile.bundleIdentifier, "com.anthropic.claudefordesktop")
        XCTAssertEqual(AgentProvider.cursor.launchProfile.bundleIdentifier, "com.todesktop.230313mzl4w4u92")
        XCTAssertEqual(AgentProvider.antigravity.launchProfile.bundleIdentifier, "com.google.antigravity-ide")
        XCTAssertEqual(AgentProvider.antigravity.launchProfile.urlScheme, "antigravity-ide")
        XCTAssertEqual(AgentProvider.conductor.launchProfile.bundleIdentifier, "com.conductor.app")
        XCTAssertEqual(AgentProvider.conductor.launchProfile.urlScheme, "conductor")
        XCTAssertEqual(AgentProvider.codex.quotaShortName, "Cx")
        XCTAssertEqual(AgentProvider.claudeCode.quotaShortName, "Cl")
        XCTAssertEqual(AgentProvider.cursor.quotaShortName, "Cu")
        XCTAssertEqual(AgentProvider.antigravity.quotaShortName, "AG")
        XCTAssertEqual(AgentProvider.conductor.quotaShortName, "Co")
        XCTAssertEqual(AgentProvider.cursor.hookFormat, .cursorFlat)
        XCTAssertFalse(AgentProvider.hookInstallationProviders.contains(.conductor))
        XCTAssertTrue(AgentProvider.codex.supportsDirectIslandReply)
        XCTAssertFalse(AgentProvider.claudeCode.supportsDirectIslandReply)
        XCTAssertFalse(AgentProvider.cursor.supportsDirectIslandReply)
        XCTAssertFalse(AgentProvider.antigravity.supportsDirectIslandReply)
        XCTAssertFalse(AgentProvider.conductor.supportsDirectIslandReply)
    }

    func testAgentProviderResolutionUsesSourceAndBundleIdentifier() {
        XCTAssertEqual(AgentProvider.resolve(source: "claude"), .claudeCode)
        XCTAssertEqual(AgentProvider.resolve(source: "cursor"), .cursor)
        XCTAssertEqual(AgentProvider.resolve(source: "antigravity"), .antigravity)
        XCTAssertEqual(AgentProvider.resolve(source: "conductor"), .conductor)
        XCTAssertEqual(AgentProvider.resolve(source: nil, bundleIdentifier: "com.openai.codex"), .codex)
        XCTAssertEqual(AgentProvider.resolve(source: nil, bundleIdentifier: "com.conductor.app"), .conductor)
        XCTAssertEqual(AgentProvider.resolve(source: "codex", terminalApp: "Conductor", bundleIdentifier: "com.conductor.app"), .conductor)
    }

    func testAgentProviderUsageCacheLoaderReadsFiveHourAndWeeklyWindows() throws {
        let usageDirectory = temporaryDirectory()
        try FileManager.default.createDirectory(at: usageDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: usageDirectory) }

        try writeJSONObject(
            [
                "rate_limits": [
                    "primary": [
                        "remaining_percent": 83,
                        "reset_at": "2026-06-16T18:00:00Z",
                    ],
                    "secondary": [
                        "used_percent": 21,
                        "resets_at": 1_781_650_000,
                    ],
                ],
            ],
            to: AgentProviderUsageCacheLoader.appOwnedUsageURL(for: .claudeCode, in: usageDirectory)
        )
        try writeJSONObject(
            [
                "payload": [
                    "usage": [
                        "fiveHour": [
                            "used_percentage": "35",
                        ],
                        "weekly": [
                            "remaining_percentage": "44",
                        ],
                    ],
                ],
            ],
            to: AgentProviderUsageCacheLoader.appOwnedUsageURL(for: .antigravity, in: usageDirectory)
        )

        let loader = AgentProviderUsageCacheLoader(usageDirectory: usageDirectory, fallbackURLsByProvider: [:])
        let claude = try XCTUnwrap(loader.loadUsage(for: .claudeCode))
        XCTAssertEqual(claude.fiveHourRemainingPercent, 83)
        XCTAssertEqual(claude.weekRemainingPercent, 79)
        XCTAssertNotNil(claude.fiveHourResetAt)
        XCTAssertNotNil(claude.weekResetAt)

        let antigravity = try XCTUnwrap(loader.loadUsage(for: .antigravity))
        XCTAssertEqual(antigravity.fiveHourRemainingPercent, 65)
        XCTAssertEqual(antigravity.weekRemainingPercent, 44)
        XCTAssertNil(loader.loadUsage(for: .cursor))
    }

    func testAgentProviderUsageCacheLoaderCollectsAllProviderFiles() throws {
        let usageDirectory = temporaryDirectory()
        try FileManager.default.createDirectory(at: usageDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: usageDirectory) }

        for (provider, remaining) in [
            (AgentProvider.codex, 91),
            (.claudeCode, 82),
            (.cursor, 73),
            (.antigravity, 64),
            (.conductor, 55),
        ] {
            try writeJSONObject(
                [
                    "five_hour": ["remaining_percent": remaining],
                    "week": ["remaining_percent": remaining - 5],
                ],
                to: AgentProviderUsageCacheLoader.appOwnedUsageURL(for: provider, in: usageDirectory)
            )
        }

        let usageByProvider = AgentProviderUsageCacheLoader(
            usageDirectory: usageDirectory,
            fallbackURLsByProvider: [:]
        ).loadUsageByProvider()

        XCTAssertEqual(usageByProvider[.codex]?.fiveHourRemainingPercent, 91)
        XCTAssertEqual(usageByProvider[.claudeCode]?.weekRemainingPercent, 77)
        XCTAssertEqual(usageByProvider[.cursor]?.fiveHourRemainingPercent, 73)
        XCTAssertEqual(usageByProvider[.antigravity]?.weekRemainingPercent, 59)
        XCTAssertEqual(usageByProvider[.conductor]?.fiveHourRemainingPercent, 55)
    }

    func testStatusLineUsageBridgeInstallsAndUninstallsManagedCommandOnly() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = CodexHookManager(
            codexDirectory: root.appendingPathComponent(".codex", isDirectory: true),
            homeDirectory: root
        )

        let installedData = try manager.installStatusLineUsageBridgeJSON(existingData: nil, provider: .antigravity)
        let installed = try XCTUnwrap(try JSONSerialization.jsonObject(with: installedData) as? [String: Any])
        let statusLine = try XCTUnwrap(installed["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["type"] as? String, "command")
        XCTAssertTrue((statusLine["command"] as? String)?.contains("--usage-provider 'antigravity'") == true)

        let uninstalledData = try manager.uninstallStatusLineUsageBridgeJSON(existingData: installedData)
        let uninstalled = try XCTUnwrap(try JSONSerialization.jsonObject(with: uninstalledData) as? [String: Any])
        XCTAssertNil(uninstalled["statusLine"])

        let customData = try JSONSerialization.data(withJSONObject: [
            "statusLine": [
                "type": "command",
                "command": "custom-status-line",
            ],
        ])
        XCTAssertThrowsError(try manager.installStatusLineUsageBridgeJSON(existingData: customData, provider: .claudeCode)) { error in
            guard case CodexHookManagerError.statusLineBridgeSkipped = error else {
                XCTFail("Expected statusLineBridgeSkipped, got \(error)")
                return
            }
        }
    }

    func testHookStatusTreatsValidConfigWithoutHooksAsNotInstalled() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let codexDirectory = root.appendingPathComponent(".codex", isDirectory: true)
        let manager = CodexHookManager(codexDirectory: codexDirectory, homeDirectory: root)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)

        try "[features]\ncodex_hooks = true\n".write(
            to: codexDirectory.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )
        try writeJSONObject(["theme": "dark"], to: root.appendingPathComponent(".claude/settings.json"))

        XCTAssertNoThrow(try manager.status())
        XCTAssertEqual(try manager.status(), .notInstalled)
    }

    func testAgentsOverviewCapsDefaultListAndFocusesNotificationSession() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sessions = [
            makeSession(id: "approval", title: "Approval", phase: .waitingForApproval, at: now.addingTimeInterval(-300)),
            makeSession(id: "running-tool", title: "Running Tool", phase: .running, at: now.addingTimeInterval(-30), currentTool: "shell"),
            makeSession(id: "busy", title: "Busy", phase: .busy, at: now.addingTimeInterval(-40)),
            makeSession(id: "recent-a", title: "Recent A", phase: .completed, at: now.addingTimeInterval(-50)),
            makeSession(id: "recent-b", title: "Recent B", phase: .completed, at: now.addingTimeInterval(-60)),
        ]
        let buckets = CodexIslandSessionPresentation.computeBuckets(from: sessions, now: now)

        let compact = CodexIslandSessionPresentation.overviewSessions(
            from: buckets.primary,
            activeNotificationSession: nil,
            isNotificationMode: false,
            isShowingAllSessions: false
        )
        XCTAssertEqual(compact.count, CodexIslandSessionPresentation.compactOverviewSessionLimit)
        XCTAssertEqual(compact.map(\.id), Array(buckets.primary.prefix(3)).map(\.id))

        let focused = CodexIslandSessionPresentation.overviewSessions(
            from: buckets.primary,
            activeNotificationSession: sessions[0],
            isNotificationMode: true,
            isShowingAllSessions: false
        )
        XCTAssertEqual(focused.map(\.id), ["approval"])

        let expanded = CodexIslandSessionPresentation.overviewSessions(
            from: buckets.primary,
            activeNotificationSession: nil,
            isNotificationMode: false,
            isShowingAllSessions: true
        )
        XCTAssertEqual(expanded.count, buckets.primary.count)
    }

    func testSessionSnapshotCanSendTextFollowsDirectReplyCapability() {
        XCTAssertTrue(makeSession(id: "codex", provider: .codex, jumpTarget: replyCapableJumpTarget(sessionID: "codex")).canSendText)
        XCTAssertTrue(makeSession(id: "codex-no-target", provider: .codex).canSendText)
        XCTAssertFalse(makeSession(id: "codex-attention", provider: .codex, phase: .waitingForApproval).canSendText)
        XCTAssertFalse(makeSession(id: "claude", provider: .claudeCode, jumpTarget: replyCapableJumpTarget(sessionID: "claude")).canSendText)
        XCTAssertFalse(makeSession(id: "cursor", provider: .cursor, jumpTarget: replyCapableJumpTarget(sessionID: "cursor")).canSendText)
        XCTAssertFalse(makeSession(id: "antigravity", provider: .antigravity, jumpTarget: replyCapableJumpTarget(sessionID: "antigravity")).canSendText)
        XCTAssertFalse(makeSession(id: "conductor", provider: .conductor, jumpTarget: replyCapableJumpTarget(sessionID: "conductor")).canSendText)
    }

    func testInteractiveHookTimeoutsExceedIslandApprovalWait() {
        XCTAssertEqual(hookTimeout(for: "PreToolUse", provider: .codex), 45)
        XCTAssertEqual(hookTimeout(for: "PreToolUse", provider: .claudeCode), 45)
        XCTAssertEqual(hookTimeout(for: "PreToolUse", provider: .antigravity), 45)
        XCTAssertEqual(hookTimeout(for: "PermissionRequest", provider: .codex), 45)
    }

    func testAntigravityHookPayloadNormalizesClaudeStyleEventShape() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "Notification",
            "source": "antigravity",
            "session_id": "ag-session-1",
            "cwd": "/tmp/workspace",
            "prompt": "Need permission",
            "last_assistant_message": "I need to edit a file.",
        ])

        let payload = try JSONDecoder().decode(CodexHookPayload.self, from: data)
        XCTAssertEqual(payload.hookEventName, .permissionRequest)
        XCTAssertEqual(payload.agentProvider, .antigravity)
        XCTAssertEqual(payload.sessionID, "ag-session-1")
        XCTAssertEqual(payload.cwd, "/tmp/workspace")
        XCTAssertEqual(payload.assistantSummary, "I need to edit a file.")
    }

    func testCursorHookPayloadNormalizesFlatEventShape() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "event": "beforeShellExecution",
            "source": "cursor",
            "sessionId": "cursor-session-1",
            "workspacePath": "/tmp/workspace",
            "command": "npm test",
        ])

        let payload = try JSONDecoder().decode(CodexHookPayload.self, from: data)
        XCTAssertEqual(payload.hookEventName, .preToolUse)
        XCTAssertEqual(payload.agentProvider, .cursor)
        XCTAssertEqual(payload.sessionID, "cursor-session-1")
        XCTAssertEqual(payload.cwd, "/tmp/workspace")
        XCTAssertEqual(payload.toolInput?.command, "npm test")
    }

    func testSessionSnapshotTitleUsesProviderName() {
        XCTAssertEqual(
            SessionSnapshot.title(for: "/tmp/fantastic", provider: .claudeCode),
            "Claude Code · fantastic"
        )
    }

    func testAgentTranscriptParserReadsCursorConversation() throws {
        let fixture = """
        {"role":"user","message":{"content":[{"type":"text","text":"<user_query>hello island</user_query>"}]}}
        {"role":"assistant","message":{"content":[{"type":"text","text":"working on it"}]}}
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cursor-transcript-\(UUID().uuidString).jsonl")
        try fixture.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let turns = AgentTranscriptParser.parseTurns(at: url.path, provider: .cursor)
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns.first?.role, .user)
        XCTAssertEqual(turns.first?.text, "hello island")
        XCTAssertEqual(turns.last?.role, .assistant)
    }

    func testAgentTranscriptParserReadsClaudeConversation() throws {
        let fixture = """
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"ship it"}]},"sessionId":"abc","cwd":"/tmp/demo"}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"on it"}]},"sessionId":"abc","cwd":"/tmp/demo"}
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("claude-transcript-\(UUID().uuidString).jsonl")
        try fixture.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let turns = AgentTranscriptParser.parseTurns(at: url.path, provider: .claudeCode)
        XCTAssertEqual(turns.map(\.role), [.user, .assistant])
        XCTAssertEqual(turns.first?.text, "ship it")
    }

    func testAgentTranscriptParserReadsTailOfLargeTranscript() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("large-transcript-\(UUID().uuidString).jsonl")
        let filler = String(repeating: #"{"type":"attachment","content":"padding"}"# + "\n", count: 70_000)
        let tail = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"tail summary"}]}}"#
        try (filler + tail + "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let turns = AgentTranscriptParser.parseTurns(at: url.path, provider: .claudeCode)

        XCTAssertEqual(turns.last?.role, .assistant)
        XCTAssertEqual(turns.last?.text, "tail summary")
    }

    func testAgentTranscriptParserReadsTailWhenChunkStartsInsideMultibyteScalar() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("large-unicode-transcript-\(UUID().uuidString).jsonl")
        let maxReadBytes = 2 * 1024 * 1024
        let prefixByteCount = maxReadBytes + 2_000
        var prefix = Data()
        for _ in 0..<(prefixByteCount / 2) {
            prefix.append(contentsOf: [0xC3, 0xA9])
        }
        prefix.append(UInt8(ascii: "\n"))

        var expectedText = "tail summary"
        var tail = Data()
        repeat {
            let line = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"\#(expectedText)"}]}}"# + "\n"
            tail = Data(line.utf8)
            if tail.count % 2 != 0 {
                expectedText += "x"
            }
        } while tail.count % 2 != 0

        var data = prefix
        data.append(tail)
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let turns = AgentTranscriptParser.parseTurns(at: url.path, provider: .claudeCode)

        XCTAssertEqual(turns.last?.role, .assistant)
        XCTAssertEqual(turns.last?.text, expectedText)
    }

    func testAgentSessionStoreWritesHookTranscriptTurns() throws {
        let rootURL = temporaryDirectory().appendingPathComponent("store", isDirectory: true)
        let store = AgentSessionStore(rootURL: rootURL)
        let promptPayload = CodexHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .userPromptSubmit,
            sessionID: "ag-session-2",
            source: "antigravity",
            prompt: "Make the island useful"
        )
        let assistantPayload = CodexHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .stop,
            sessionID: "ag-session-2",
            source: "antigravity",
            lastAssistantMessage: "Done inside the island."
        )

        let url = try store.append(promptPayload, timestamp: Date(timeIntervalSince1970: 10))
        _ = try store.append(assistantPayload, timestamp: Date(timeIntervalSince1970: 11))

        let turns = AgentTranscriptParser.parseTurns(at: url.path, provider: .antigravity)
        XCTAssertEqual(turns.map(\.role), [.user, .assistant])
        XCTAssertEqual(turns.first?.text, "Make the island useful")
        XCTAssertEqual(turns.last?.text, "Done inside the island.")
    }

    func testDiscoveryFindsAntigravityFromSessionStore() throws {
        let rootURL = temporaryDirectory().appendingPathComponent("store", isDirectory: true)
        let store = AgentSessionStore(rootURL: rootURL)
        let payload = CodexHookPayload(
            cwd: "/tmp/ag-workspace",
            hookEventName: .postToolUse,
            sessionID: "ag-session-3",
            source: "antigravity",
            lastAssistantMessage: "Antigravity surfaced."
        )
        _ = try store.append(payload)

        let discovery = CodexSessionDiscovery(
            rootURL: temporaryDirectory().appendingPathComponent("codex", isDirectory: true),
            claudeRootURL: temporaryDirectory().appendingPathComponent("claude", isDirectory: true),
            cursorRootURL: temporaryDirectory().appendingPathComponent("cursor", isDirectory: true),
            sessionStore: store
        )
        let sessions = discovery.discoverRecentSessions()

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.provider, .antigravity)
        XCTAssertEqual(sessions.first?.id, "ag-session-3")
        XCTAssertEqual(sessions.first?.assistantSummary, "Antigravity surfaced.")
    }

    func testConductorHookPayloadPreservesWorkspaceMetadata() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "source": "codex",
            "terminal_app": "Conductor",
            "terminal_bundle_identifier": "com.conductor.app",
            "session_id": "conductor-session-1",
            "cwd": "/tmp/fantastic-island",
            "workspace_name": "belgrade",
            "workspace_id": "ws_123",
            "conductor_port": "3777",
            "conductor_url": "http://127.0.0.1:3777",
            "hook_event_name": "SessionStart",
        ])

        let payload = try JSONDecoder().decode(CodexHookPayload.self, from: data)
        XCTAssertEqual(payload.agentProvider, .conductor)
        XCTAssertEqual(payload.workspaceName, "belgrade")
        XCTAssertEqual(payload.workspaceIdentifier, "ws_123")
        XCTAssertEqual(payload.conductorPort, 3777)
        XCTAssertEqual(payload.terminalJumpTarget?.workspaceName, "belgrade")
        XCTAssertEqual(payload.terminalJumpTarget?.conductorPort, 3777)
        XCTAssertEqual(payload.terminalJumpTarget?.detailLabel, "ws_123 · :3777")
        XCTAssertEqual(try XCTUnwrap(payload.terminalJumpTarget).conductorRoutingURL?.absoluteString, "http://127.0.0.1:3777")
    }

    func testHookBridgeAcceptsPayloadAndReturnsDirective() throws {
        let socketURL = temporaryDirectory().appendingPathComponent("hook.sock")
        let server = HookBridgeServer(socketURL: socketURL)
        let payloadSeen = XCTestExpectation(description: "payload seen")
        server.onPayload = { payload in
            XCTAssertEqual(payload.sessionID, "bridge-session-1")
            XCTAssertEqual(payload.agentProvider, .claudeCode)
            payloadSeen.fulfill()
            return .permissionRequestAllow
        }

        try server.start()
        defer { server.stop() }

        let payload = try JSONSerialization.data(withJSONObject: [
            "source": "claude",
            "session_id": "bridge-session-1",
            "cwd": "/tmp/workspace",
            "hook_event_name": "PermissionRequest",
        ])
        let response = try Self.sendPayload(payload, to: socketURL)

        wait(for: [payloadSeen], timeout: 2)
        let directive = try JSONDecoder().decode(CodexHookDirective.self, from: response)
        XCTAssertEqual(directive, .permissionRequestAllow)
    }

    func testNativeTranscriptWinsOverHookStoreForSameSession() throws {
        let temp = temporaryDirectory()
        let codexRoot = temp.appendingPathComponent("codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)

        let codexURL = codexRoot.appendingPathComponent("rollout-native.jsonl")
        let nativeLine = #"{"type":"session_meta","payload":{"id":"same-session","cwd":"/tmp/native","source":"cli"}}"#
        try nativeLine.write(to: codexURL, atomically: true, encoding: .utf8)

        let store = AgentSessionStore(rootURL: temp.appendingPathComponent("store", isDirectory: true))
        let payload = CodexHookPayload(
            cwd: "/tmp/stored",
            hookEventName: .userPromptSubmit,
            sessionID: "same-session",
            source: "codex",
            prompt: "stored prompt"
        )
        _ = try store.append(payload)

        let discovery = CodexSessionDiscovery(
            rootURL: codexRoot,
            claudeRootURL: temp.appendingPathComponent("claude", isDirectory: true),
            cursorRootURL: temp.appendingPathComponent("cursor", isDirectory: true),
            sessionStore: store
        )
        let sessions = discovery.discoverRecentSessions()

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.provider, .codex)
        XCTAssertEqual(sessions.first?.cwd, "/tmp/native")
        XCTAssertEqual(URL(fileURLWithPath: sessions.first?.transcriptPath ?? "").standardizedFileURL.path, codexURL.standardizedFileURL.path)
    }

    func testDiscoveryFindsCodexRolloutTranscript() throws {
        let temp = temporaryDirectory()
        let workspace = temp.appendingPathComponent("codex-workspace", isDirectory: true)
        let codexRoot = temp.appendingPathComponent("codex/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)

        let transcript = codexRoot.appendingPathComponent("rollout-codex-session-1.jsonl")
        try writeJSONLines([
            [
                "type": "session_meta",
                "payload": [
                    "id": "codex-session-1",
                    "cwd": workspace.path,
                    "source": "cli",
                ],
            ],
            [
                "type": "response_item",
                "payload": [
                    "role": "assistant",
                    "content": [
                        ["type": "output_text", "text": "Codex surfaced from rollout."],
                    ],
                ],
            ],
        ], to: transcript)

        let discovery = CodexSessionDiscovery(
            rootURL: codexRoot,
            claudeRootURL: temp.appendingPathComponent("claude", isDirectory: true),
            cursorRootURL: temp.appendingPathComponent("cursor", isDirectory: true),
            sessionStore: AgentSessionStore(rootURL: temp.appendingPathComponent("store", isDirectory: true))
        )
        let sessions = discovery.discoverRecentSessions(now: Date().addingTimeInterval(5))

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, "codex-session-1")
        XCTAssertEqual(sessions.first?.provider, .codex)
        XCTAssertEqual(sessions.first?.cwd, workspace.path)
        XCTAssertEqual(sessions.first?.assistantSummary, "Codex surfaced from rollout.")
        XCTAssertEqual(sessions.first?.sessionSurface, .terminal)
        XCTAssertNotNil(sessions.first?.modifiedAt)
    }

    func testDiscoveryFindsClaudeProjectTranscript() throws {
        let temp = temporaryDirectory()
        let workspace = temp.appendingPathComponent("claude-workspace", isDirectory: true)
        let claudeRoot = temp.appendingPathComponent("claude/projects", isDirectory: true)
        let projectDir = claudeRoot.appendingPathComponent(encodedProjectDirectoryName(for: workspace), isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let transcript = projectDir.appendingPathComponent("claude-session-1.jsonl")
        try writeJSONLines([
            [
                "type": "user",
                "sessionId": "claude-session-1",
                "cwd": workspace.path,
                "message": [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "Review the island."],
                    ],
                ],
            ],
            [
                "type": "assistant",
                "sessionId": "claude-session-1",
                "cwd": workspace.path,
                "message": [
                    "role": "assistant",
                    "content": [
                        ["type": "text", "text": "Claude project transcript surfaced."],
                    ],
                ],
            ],
        ], to: transcript)

        let discovery = CodexSessionDiscovery(
            rootURL: temp.appendingPathComponent("codex", isDirectory: true),
            claudeRootURL: claudeRoot,
            cursorRootURL: temp.appendingPathComponent("cursor", isDirectory: true),
            sessionStore: AgentSessionStore(rootURL: temp.appendingPathComponent("store", isDirectory: true))
        )
        let sessions = discovery.discoverRecentSessions(now: Date().addingTimeInterval(5))

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, "claude-session-1")
        XCTAssertEqual(sessions.first?.provider, .claudeCode)
        XCTAssertEqual(sessions.first?.cwd, workspace.path)
        XCTAssertEqual(sessions.first?.assistantSummary, "Claude project transcript surfaced.")
    }

    func testDiscoveryInfersHyphenatedClaudeWorkspaceFromProjectDirectory() throws {
        let temp = temporaryDirectory()
        let workspace = temp.appendingPathComponent("fantastic-island", isDirectory: true)
        let claudeRoot = temp.appendingPathComponent("claude/projects", isDirectory: true)
        let projectDir = claudeRoot.appendingPathComponent(encodedProjectDirectoryName(for: workspace), isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let transcript = projectDir.appendingPathComponent("claude-fallback.jsonl")
        try writeJSONLines([
            [
                "type": "assistant",
                "message": [
                    "role": "assistant",
                    "content": [
                        ["type": "text", "text": "Inferred Claude workspace."],
                    ],
                ],
            ],
        ], to: transcript)

        let discovery = CodexSessionDiscovery(
            rootURL: temp.appendingPathComponent("codex", isDirectory: true),
            claudeRootURL: claudeRoot,
            cursorRootURL: temp.appendingPathComponent("cursor", isDirectory: true),
            sessionStore: AgentSessionStore(rootURL: temp.appendingPathComponent("store", isDirectory: true))
        )
        let sessions = discovery.discoverRecentSessions(now: Date().addingTimeInterval(5))

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, "claude-fallback")
        XCTAssertEqual(sessions.first?.cwd, workspace.path)
        XCTAssertEqual(sessions.first?.assistantSummary, "Inferred Claude workspace.")
    }

    func testDiscoveryFindsCursorAgentTranscript() throws {
        let temp = temporaryDirectory()
        let workspace = temp.appendingPathComponent("cursor-workspace", isDirectory: true)
        let cursorRoot = temp.appendingPathComponent("cursor/projects", isDirectory: true)
        let transcriptDir = cursorRoot
            .appendingPathComponent(encodedProjectDirectoryName(for: workspace), isDirectory: true)
            .appendingPathComponent("agent-transcripts/cursor-session-1", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)

        let transcript = transcriptDir.appendingPathComponent("cursor-session-1.jsonl")
        try writeJSONLines([
            [
                "role": "user",
                "sessionId": "cursor-session-1",
                "workspacePath": workspace.path,
                "message": [
                    "content": [
                        ["type": "text", "text": "<user_query>Polish the player.</user_query>"],
                    ],
                ],
            ],
            [
                "role": "assistant",
                "sessionId": "cursor-session-1",
                "workspacePath": workspace.path,
                "message": [
                    "content": [
                        ["type": "text", "text": "Cursor agent transcript surfaced."],
                    ],
                ],
            ],
        ], to: transcript)

        let discovery = CodexSessionDiscovery(
            rootURL: temp.appendingPathComponent("codex", isDirectory: true),
            claudeRootURL: temp.appendingPathComponent("claude", isDirectory: true),
            cursorRootURL: cursorRoot,
            sessionStore: AgentSessionStore(rootURL: temp.appendingPathComponent("store", isDirectory: true))
        )
        let sessions = discovery.discoverRecentSessions(now: Date().addingTimeInterval(5))

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, "cursor-session-1")
        XCTAssertEqual(sessions.first?.provider, .cursor)
        XCTAssertEqual(sessions.first?.cwd, workspace.path)
        XCTAssertEqual(sessions.first?.assistantSummary, "Cursor agent transcript surfaced.")
    }

    func testDiscoveryInfersHyphenatedCursorWorkspaceFromProjectDirectory() throws {
        let temp = temporaryDirectory()
        let workspace = temp.appendingPathComponent("cursor-fantastic-island", isDirectory: true)
        let cursorRoot = temp.appendingPathComponent("cursor/projects", isDirectory: true)
        let transcriptDir = cursorRoot
            .appendingPathComponent(encodedProjectDirectoryName(for: workspace), isDirectory: true)
            .appendingPathComponent("agent-transcripts/cursor-fallback", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)

        let transcript = transcriptDir.appendingPathComponent("cursor-fallback.jsonl")
        try writeJSONLines([
            [
                "role": "assistant",
                "message": [
                    "content": [
                        ["type": "text", "text": "Inferred Cursor workspace."],
                    ],
                ],
            ],
        ], to: transcript)

        let discovery = CodexSessionDiscovery(
            rootURL: temp.appendingPathComponent("codex", isDirectory: true),
            claudeRootURL: temp.appendingPathComponent("claude", isDirectory: true),
            cursorRootURL: cursorRoot,
            sessionStore: AgentSessionStore(rootURL: temp.appendingPathComponent("store", isDirectory: true))
        )
        let sessions = discovery.discoverRecentSessions(now: Date().addingTimeInterval(5))

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, "cursor-fallback")
        XCTAssertEqual(sessions.first?.cwd, workspace.path)
        XCTAssertEqual(sessions.first?.assistantSummary, "Inferred Cursor workspace.")
    }

    func testDiscoveryFindsConductorSessionStoreWithRoutingURL() throws {
        let temp = temporaryDirectory()
        let store = AgentSessionStore(rootURL: temp.appendingPathComponent("store", isDirectory: true))
        let payload = CodexHookPayload(
            cwd: "/tmp/conductor-workspace",
            hookEventName: .stop,
            sessionID: "conductor-session-2",
            terminalApp: "Conductor",
            terminalBundleIdentifier: "com.conductor.app",
            workspaceName: "belgrade",
            workspaceIdentifier: "ws_456",
            conductorPort: 3888,
            conductorURL: "http://127.0.0.1:3888",
            source: "codex",
            lastAssistantMessage: "Conductor session surfaced."
        )
        _ = try store.append(payload)

        let discovery = CodexSessionDiscovery(
            rootURL: temp.appendingPathComponent("codex", isDirectory: true),
            claudeRootURL: temp.appendingPathComponent("claude", isDirectory: true),
            cursorRootURL: temp.appendingPathComponent("cursor", isDirectory: true),
            sessionStore: store
        )
        let sessions = discovery.discoverRecentSessions(now: Date().addingTimeInterval(5))
        let jumpTarget = try XCTUnwrap(sessions.first?.jumpTarget)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, "conductor-session-2")
        XCTAssertEqual(sessions.first?.provider, .conductor)
        XCTAssertEqual(sessions.first?.assistantSummary, "Conductor session surfaced.")
        XCTAssertEqual(jumpTarget.workspaceName, "belgrade")
        XCTAssertEqual(jumpTarget.conductorRoutingURL?.absoluteString, "http://127.0.0.1:3888")
    }

    func testCodexClientHandlesSynchronousResponseDuringWrite() async throws {
        let transport = FakeTransport()
        transport.onRequest = { request in
            guard let method = request["method"] as? String else {
                return
            }

            switch method {
            case "initialize":
                try? transport.sendJSON([
                    "jsonrpc": "2.0",
                    "id": request["id"]!,
                    "result": [:],
                ])
            case "thread/loaded/list":
                try? transport.sendJSON([
                    "jsonrpc": "2.0",
                    "id": request["id"]!,
                    "result": ["threads": [Self.sampleThread]],
                ])
            default:
                break
            }
        }

        let client = CodexAppServerClient(codexPath: "/tmp/fake-codex") { _ in transport }
        try await client.start()

        let threads = try await client.listLoadedThreads()
        XCTAssertEqual(threads.map(\.id), ["thread-1"])
    }

    func testCodexClientRecoversAfterStdoutEOF() async throws {
        let transport1 = FakeTransport()
        transport1.onRequest = { request in
            guard request["method"] as? String == "initialize" else {
                return
            }

            try? transport1.sendJSON([
                "jsonrpc": "2.0",
                "id": request["id"]!,
                "result": [:],
            ])
        }

        let transport2 = FakeTransport()
        transport2.onRequest = { request in
            guard let method = request["method"] as? String else {
                return
            }

            switch method {
            case "initialize":
                try? transport2.sendJSON([
                    "jsonrpc": "2.0",
                    "id": request["id"]!,
                    "result": [:],
                ])
            case "thread/loaded/list":
                try? transport2.sendJSON([
                    "jsonrpc": "2.0",
                    "id": request["id"]!,
                    "result": ["threads": [Self.sampleThread]],
                ])
            default:
                break
            }
        }

        var transports = [transport1, transport2]
        let disconnectRecorder = DisconnectRecorder()
        let client = CodexAppServerClient(codexPath: "/tmp/fake-codex") { _ in
            transports.removeFirst()
        }
        client.onDisconnect = { disconnectRecorder.append($0) }

        try await client.start()

        let pendingRequest = Task {
            try await client.listLoadedThreads()
        }
        _ = try await transport1.nextMethod("thread/loaded/list")
        transport1.sendEOF()

        do {
            _ = try await pendingRequest.value
            XCTFail("Expected EOF to fail the pending request.")
        } catch {
            XCTAssertEqual(error as? CodexAppServerError, .disconnected)
        }

        XCTAssertEqual(disconnectRecorder.snapshot(), [.stdoutEOF])
        XCTAssertFalse(client.isRunning)

        try await client.start()
        let threads = try await client.listLoadedThreads()
        XCTAssertEqual(threads.map(\.id), ["thread-1"])
    }

    func testCodexClientCanReconnectAfterInitializeFailure() async throws {
        let transport1 = FakeTransport()
        transport1.onRequest = { request in
            guard request["method"] as? String == "initialize" else {
                return
            }

            transport1.sendEOF()
        }

        let transport2 = FakeTransport()
        transport2.onRequest = { request in
            guard request["method"] as? String == "initialize" else {
                return
            }

            try? transport2.sendJSON([
                "jsonrpc": "2.0",
                "id": request["id"]!,
                "result": [:],
            ])
        }

        var transports = [transport1, transport2]
        let disconnectRecorder = DisconnectRecorder()
        let client = CodexAppServerClient(codexPath: "/tmp/fake-codex") { _ in
            transports.removeFirst()
        }
        client.onDisconnect = { disconnectRecorder.append($0) }

        do {
            try await client.start()
            XCTFail("Expected initialize failure to throw.")
        } catch {
            XCTAssertFalse(client.isRunning)
        }

        XCTAssertEqual(disconnectRecorder.snapshot(), [.stdoutEOF])

        try await client.start()
        XCTAssertTrue(client.isRunning)
    }

    private static let sampleThread: [String: Any] = [
        "id": "thread-1",
        "cwd": "/tmp/workspace",
        "name": "Demo",
        "preview": "Preview",
        "modelProvider": "openai",
        "createdAt": 1,
        "updatedAt": 1,
        "ephemeral": false,
        "path": NSNull(),
        "status": [
            "type": "idle",
            "activeFlags": NSNull(),
        ],
        "source": "appServer",
        "turns": NSNull(),
    ]

    private func makeSession(
        id: String,
        provider: AgentProvider = .codex,
        title: String? = nil,
        phase: SessionPhase = .completed,
        at date: Date = Date(timeIntervalSince1970: 1_800_000_000),
        currentTool: String? = nil,
        jumpTarget: CodexTerminalJumpTarget? = nil
    ) -> SessionSnapshot {
        SessionSnapshot(
            id: id,
            provider: provider,
            cwd: "/tmp/\(id)",
            title: title ?? id,
            phase: phase,
            lastEventAt: date,
            currentTool: currentTool,
            jumpTarget: jumpTarget
        )
    }

    private func replyCapableJumpTarget(sessionID: String) -> CodexTerminalJumpTarget {
        CodexTerminalJumpTarget(
            sessionID: sessionID,
            terminalApp: "Ghostty",
            workspaceName: "workspace",
            paneTitle: "pane",
            terminalSessionID: "terminal-\(sessionID)"
        )
    }

    private func hookTimeout(for eventName: String, provider: AgentProvider) -> Int? {
        provider.hookEvents.first { $0.name == eventName }?.timeout
    }

    private func encodedProjectDirectoryName(for url: URL) -> String {
        url.path.replacingOccurrences(of: "/", with: "-")
    }

    private func writeJSONLines(_ objects: [[String: Any]], to url: URL) throws {
        let data = try objects.reduce(into: Data()) { partial, object in
            partial.append(try JSONSerialization.data(withJSONObject: object))
            partial.append(UInt8(ascii: "\n"))
        }
        try data.write(to: url, options: .atomic)
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: url, options: .atomic)
    }

    private static func sendPayload(_ payload: Data, to socketURL: URL) throws -> Data {
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM), 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        let pathBytes = Array(socketURL.path.utf8.prefix(maxLength - 1))
        for (index, byte) in pathBytes.enumerated() {
            withUnsafeMutablePointer(to: &address.sun_path.0) {
                $0.withMemoryRebound(to: UInt8.self, capacity: maxLength) { pointer in
                    pointer[index] = byte
                }
            }
        }

        let addressLength = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count + 1)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, addressLength)
            }
        }
        XCTAssertEqual(connected, 0)

        payload.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            let written = Darwin.write(fd, baseAddress, bytes.count)
            XCTAssertEqual(written, payload.count)
        }
        _ = shutdown(fd, SHUT_WR)

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBufferPointer { pointer in
                Darwin.read(fd, pointer.baseAddress, pointer.count)
            }
            if count <= 0 {
                break
            }
            response.append(contentsOf: buffer.prefix(count))
        }

        return response
    }
}
