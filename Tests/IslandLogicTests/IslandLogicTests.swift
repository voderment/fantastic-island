import Foundation
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
    func testClashTrafficRateFormatterUsesBytesPerSecond() {
        XCTAssertEqual(ClashConfigSupport.formatTrafficRate(0), "0 B/s")
        XCTAssertEqual(ClashConfigSupport.formatTrafficRate(512), "512 B/s")
        XCTAssertEqual(ClashConfigSupport.formatTrafficRate(1024), "1 KB/s")
        XCTAssertEqual(ClashConfigSupport.formatTrafficRate(1536), "1.5 KB/s")
        XCTAssertEqual(ClashConfigSupport.formatTrafficRate(1024 * 1024), "1 MB/s")
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

    func testClashRequestBuilderAddsBearerAuthorization() throws {
        let request = ClashConfigSupport.makeAPIRequest(
            base: URL(string: "http://127.0.0.1:9090")!,
            path: "/version",
            method: "GET",
            body: nil,
            timeoutInterval: 6,
            authorizationSecret: "secret-value"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-value")
    }

    func testClashRequestBuilderOmitsAuthorizationWithoutSecret() throws {
        let request = ClashConfigSupport.makeAPIRequest(
            base: URL(string: "http://127.0.0.1:9090")!,
            path: "/version",
            method: "GET",
            body: nil,
            timeoutInterval: 6,
            authorizationSecret: nil
        )

        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testClashResolvedAttachSecretPrefersExplicitValueAndFallsBackToConfig() throws {
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent("clash-secret-\(UUID().uuidString).yaml")
        defer { try? FileManager.default.removeItem(at: configURL) }

        try """
        external-controller: 127.0.0.1:9090
        secret: "config-secret"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            ClashConfigSupport.resolvedAttachAPISecret(
                explicitSecret: nil,
                configFilePath: configURL.path
            ),
            "config-secret"
        )

        XCTAssertEqual(
            ClashConfigSupport.resolvedAttachAPISecret(
                explicitSecret: "manual-secret",
                configFilePath: configURL.path
            ),
            "manual-secret"
        )
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
}
