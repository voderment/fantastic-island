import Foundation

struct CodexThread: Codable, Sendable {
    let id: String
    let cwd: String
    let name: String?
    let preview: String
    let modelProvider: String
    let createdAt: Int
    let updatedAt: Int
    let ephemeral: Bool
    let path: String?
    let status: CodexThreadStatus
    let source: CodexThreadSource?
    let turns: [CodexTurn]?
}

enum CodexThreadStatusType: String, Codable, Sendable {
    case notLoaded
    case idle
    case systemError
    case active
}

struct CodexThreadStatus: Codable, Sendable {
    let type: CodexThreadStatusType
    let activeFlags: [String]?

    var isWaitingOnApproval: Bool {
        activeFlags?.contains("waitingOnApproval") == true
    }

    var isWaitingOnUserInput: Bool {
        activeFlags?.contains("waitingOnUserInput") == true
    }
}

enum CodexThreadSource: String, Codable, Sendable {
    case cli
    case vscode
    case appServer
    case exec
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = CodexThreadSource(rawValue: value) ?? .unknown
            return
        }

        self = .unknown
    }
}

struct CodexTurn: Codable, Sendable {
    let id: String
    let status: CodexTurnStatus
}

enum CodexTurnStatus: String, Codable, Sendable {
    case completed
    case interrupted
    case failed
    case inProgress
}

enum CodexAppServerRequestID: Hashable, Sendable, Codable {
    case int(Int)
    case string(String)

    init?(jsonValue: Any?) {
        switch jsonValue {
        case let value as Int:
            self = .int(value)
        case let value as NSNumber:
            self = .int(value.intValue)
        case let value as String:
            self = .string(value)
        default:
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case let .int(value):
            return "int:\(value)"
        case let .string(value):
            return "string:\(value)"
        }
    }

    var jsonValue: Any {
        switch self {
        case let .int(value):
            return value
        case let .string(value):
            return value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        throw DecodingError.typeMismatch(
            CodexAppServerRequestID.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported request id type.")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .int(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        }
    }
}

struct CodexAppServerPermissionProfile: Codable, Sendable {
    let fileSystem: CodexAppServerFileSystemPermissions?
    let network: CodexAppServerNetworkPermissions?
}

struct CodexAppServerFileSystemPermissions: Codable, Sendable {
    let read: [String]?
    let write: [String]?
}

struct CodexAppServerNetworkPermissions: Codable, Sendable {
    let enabled: Bool?
}

struct CodexAppServerPermissionsRequestApprovalParams: Codable, Sendable {
    let itemId: String
    let permissions: CodexAppServerPermissionProfile
    let reason: String?
    let threadId: String
    let turnId: String
}

struct CodexAppServerCommandExecutionRequestApprovalParams: Codable, Sendable {
    let threadId: String
    let approvalId: String?
    let turnId: String
    let command: String?
    let cwd: String?
    let itemId: String
    let proposedExecpolicyAmendment: [String]?
    let reason: String?
}

struct CodexAppServerFileChangeRequestApprovalParams: Codable, Sendable {
    let grantRoot: String?
    let itemId: String
    let reason: String?
    let threadId: String
    let turnId: String
}

struct CodexAppServerToolRequestUserInputParams: Codable, Sendable {
    let itemId: String
    let questions: [Question]
    let threadId: String
    let turnId: String

    struct Question: Codable, Sendable {
        let header: String
        let id: String
        let isOther: Bool?
        let isSecret: Bool?
        let options: [Option]?
        let question: String
    }

    struct Option: Codable, Sendable {
        let description: String
        let label: String
    }
}

enum CodexAppServerNotification: Sendable {
    case threadStarted(thread: CodexThread)
    case threadStatusChanged(threadId: String, status: CodexThreadStatus)
    case threadClosed(threadId: String)
    case threadNameUpdated(threadId: String, name: String?)
    case turnStarted(threadId: String, turn: CodexTurn)
    case turnCompleted(threadId: String, turn: CodexTurn)
    case serverRequestResolved(threadId: String, requestID: CodexAppServerRequestID)
    case unknown(method: String)
}

enum CodexAppServerServerRequest: Sendable {
    case permissionsApproval(id: CodexAppServerRequestID, params: CodexAppServerPermissionsRequestApprovalParams)
    case commandExecutionApproval(id: CodexAppServerRequestID, params: CodexAppServerCommandExecutionRequestApprovalParams)
    case fileChangeApproval(id: CodexAppServerRequestID, params: CodexAppServerFileChangeRequestApprovalParams)
    case toolRequestUserInput(id: CodexAppServerRequestID, params: CodexAppServerToolRequestUserInputParams)
    case unknown(id: CodexAppServerRequestID, method: String)
}

enum CodexAppServerError: LocalizedError, Equatable {
    case notConnected
    case disconnected
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Codex app-server is not connected."
        case .disconnected:
            return "Codex app-server connection was lost."
        case let .rpcError(message):
            return "Codex app-server error: \(message)"
        }
    }
}

enum CodexAppServerDisconnectReason: Sendable, Equatable {
    case stdoutEOF
    case processTerminated(Int32)
    case initializeFailed(String)
    case stopped
}

@MainActor
final class CodexAppServerClient {
    private let codexPath: String
    private let transportFactory: (String) -> any CodexAppServerTransport
    private var transport: (any CodexAppServerTransport)?
    private var stdin: (any CodexAppServerWritableStream)?
    private var readBuffer = Data()
    private var pendingRequests: [String: CheckedContinuation<Data, any Error>] = [:]
    private var nextRequestID = 1
    private var isCleaningUp = false

    var onNotification: (@Sendable (CodexAppServerNotification) -> Void)?
    var onServerRequest: (@Sendable (CodexAppServerServerRequest) -> Void)?
    var onDisconnect: (@Sendable (CodexAppServerDisconnectReason) -> Void)?

    init(
        codexPath: String = "/Applications/Codex.app/Contents/Resources/codex",
        transportFactory: ((String) -> any CodexAppServerTransport)? = nil
    ) {
        self.codexPath = codexPath
        self.transportFactory = transportFactory ?? { CodexAppServerProcessTransport(codexPath: $0) }
    }

    var isRunning: Bool {
        transport?.isRunning == true
    }

    func start() async throws {
        guard !isRunning else {
            return
        }

        let transport = transportFactory(codexPath)
        self.transport = transport
        stdin = transport.stdin
        isCleaningUp = false

        transport.stdout.onData = { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                if data.isEmpty {
                    self.handleDisconnect(reason: .stdoutEOF, shouldTerminateTransport: false)
                } else {
                    self.handleIncomingData(data)
                }
            }
        }

        transport.onTerminate = { [weak self] status in
            Task { @MainActor [weak self] in
                self?.handleDisconnect(reason: .processTerminated(status), shouldTerminateTransport: false)
            }
        }

        do {
            try transport.run()
            _ = try await sendRequest(
                method: "initialize",
                params: InitializeParams(
                    clientInfo: InitializeParams.ClientInfo(
                        name: "CodexFan",
                        version: "1.0.0"
                    ),
                    enabledExperimentalMethods: true
                )
            )
        } catch {
            handleDisconnect(
                reason: .initializeFailed(error.localizedDescription),
                shouldTerminateTransport: true
            )
            throw error
        }
    }

    func stop() {
        handleDisconnect(reason: .stopped, shouldTerminateTransport: true, shouldNotify: false)
    }

    func listLoadedThreads() async throws -> [CodexThread] {
        struct Result: Decodable { let threads: [CodexThread] }
        let data = try await sendRequest(method: "thread/loaded/list", params: [:] as [String: String])
        return try JSONDecoder().decode(Result.self, from: data).threads
    }

    func sendServerRequestResolved(
        requestID: CodexAppServerRequestID,
        result: [String: Any]
    ) throws {
        guard let stdin else {
            throw CodexAppServerError.notConnected
        }

        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID.jsonValue,
            "result": result,
        ]
        var data = try JSONSerialization.data(withJSONObject: envelope)
        data.append(UInt8(ascii: "\n"))
        try stdin.write(data)
    }

    func sendServerRequestError(
        requestID: CodexAppServerRequestID,
        message: String,
        code: Int = -32000
    ) throws {
        guard let stdin else {
            throw CodexAppServerError.notConnected
        }

        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID.jsonValue,
            "error": [
                "code": code,
                "message": message,
            ],
        ]
        var data = try JSONSerialization.data(withJSONObject: envelope)
        data.append(UInt8(ascii: "\n"))
        try stdin.write(data)
    }

    private func sendRequest<P: Encodable>(method: String, params: P) async throws -> Data {
        guard let stdin else {
            throw CodexAppServerError.notConnected
        }

        let requestID = nextRequestID
        nextRequestID += 1
        let requestKey = Self.responseKey(for: .int(requestID))

        let paramsData = try JSONEncoder().encode(params)
        let paramsObject = try JSONSerialization.jsonObject(with: paramsData)
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method,
            "params": paramsObject,
        ]
        var data = try JSONSerialization.data(withJSONObject: envelope)
        data.append(UInt8(ascii: "\n"))

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestKey] = continuation

            do {
                try stdin.write(data)
            } catch {
                let pendingContinuation = pendingRequests.removeValue(forKey: requestKey)
                pendingContinuation?.resume(throwing: CodexAppServerError.disconnected)
            }
        }
    }

    private func handleIncomingData(_ data: Data) {
        readBuffer.append(data)

        while let newlineIndex = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = readBuffer.prefix(upTo: newlineIndex)
            readBuffer.removeSubrange(...newlineIndex)

            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                continue
            }

            if let method = object["method"] as? String {
                if let requestID = CodexAppServerRequestID(jsonValue: object["id"]) {
                    handleServerRequest(
                        id: requestID,
                        method: method,
                        params: object["params"]
                    )
                } else {
                    handleNotification(method: method, params: object["params"])
                }
                continue
            }

            if let requestID = CodexAppServerRequestID(jsonValue: object["id"]) {
                handleResponse(id: requestID, object: object)
            }
        }
    }

    private func handleResponse(id: CodexAppServerRequestID, object: [String: Any]) {
        let key = Self.responseKey(for: id)
        let continuation = pendingRequests.removeValue(forKey: key)

        guard let continuation else {
            return
        }

        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown error."
            continuation.resume(throwing: CodexAppServerError.rpcError(message))
            return
        }

        let result = object["result"] ?? [:]
        if let data = try? JSONSerialization.data(withJSONObject: result) {
            continuation.resume(returning: data)
        } else {
            continuation.resume(throwing: CodexAppServerError.rpcError("Invalid app-server response."))
        }
    }

    private func handleServerRequest(
        id: CodexAppServerRequestID,
        method: String,
        params: Any?
    ) {
        guard let data = try? JSONSerialization.data(withJSONObject: params ?? [:]) else {
            onServerRequest?(.unknown(id: id, method: method))
            return
        }

        let decoder = JSONDecoder()
        switch method {
        case "item/permissions/requestApproval":
            if let payload = try? decoder.decode(CodexAppServerPermissionsRequestApprovalParams.self, from: data) {
                onServerRequest?(.permissionsApproval(id: id, params: payload))
                return
            }
        case "item/commandExecution/requestApproval":
            if let payload = try? decoder.decode(CodexAppServerCommandExecutionRequestApprovalParams.self, from: data) {
                onServerRequest?(.commandExecutionApproval(id: id, params: payload))
                return
            }
        case "item/fileChange/requestApproval":
            if let payload = try? decoder.decode(CodexAppServerFileChangeRequestApprovalParams.self, from: data) {
                onServerRequest?(.fileChangeApproval(id: id, params: payload))
                return
            }
        case "item/tool/requestUserInput":
            if let payload = try? decoder.decode(CodexAppServerToolRequestUserInputParams.self, from: data) {
                onServerRequest?(.toolRequestUserInput(id: id, params: payload))
                return
            }
        default:
            break
        }

        onServerRequest?(.unknown(id: id, method: method))
    }

    private func handleNotification(method: String, params: Any?) {
        guard let data = try? JSONSerialization.data(withJSONObject: params ?? [:]) else {
            onNotification?(.unknown(method: method))
            return
        }

        let decoder = JSONDecoder()

        switch method {
        case "thread/started":
            if let payload = try? decoder.decode(ThreadStartedNotification.self, from: data) {
                onNotification?(.threadStarted(thread: payload.thread))
                return
            }
        case "thread/status/changed":
            if let payload = try? decoder.decode(ThreadStatusChangedNotification.self, from: data) {
                onNotification?(.threadStatusChanged(threadId: payload.threadId, status: payload.status))
                return
            }
        case "thread/closed":
            if let payload = try? decoder.decode(ThreadClosedNotification.self, from: data) {
                onNotification?(.threadClosed(threadId: payload.threadId))
                return
            }
        case "thread/name/updated":
            if let payload = try? decoder.decode(ThreadNameUpdatedNotification.self, from: data) {
                onNotification?(.threadNameUpdated(threadId: payload.threadId, name: payload.threadName))
                return
            }
        case "turn/started":
            if let payload = try? decoder.decode(TurnStartedNotification.self, from: data) {
                onNotification?(.turnStarted(threadId: payload.threadId, turn: payload.turn))
                return
            }
        case "turn/completed":
            if let payload = try? decoder.decode(TurnCompletedNotification.self, from: data) {
                onNotification?(.turnCompleted(threadId: payload.threadId, turn: payload.turn))
                return
            }
        case "serverRequest/resolved":
            if let payload = try? decoder.decode(ServerRequestResolvedNotification.self, from: data) {
                onNotification?(.serverRequestResolved(threadId: payload.threadId, requestID: payload.requestId))
                return
            }
        default:
            break
        }

        onNotification?(.unknown(method: method))
    }

    private func handleDisconnect(
        reason: CodexAppServerDisconnectReason,
        shouldTerminateTransport: Bool,
        shouldNotify: Bool = true
    ) {
        guard !isCleaningUp else {
            return
        }

        isCleaningUp = true

        transport?.stdout.onData = nil
        transport?.onTerminate = nil
        if shouldTerminateTransport {
            transport?.terminate()
        }
        transport?.close()
        transport = nil
        stdin = nil
        readBuffer.removeAll(keepingCapacity: false)

        let continuations = Array(pendingRequests.values)
        pendingRequests.removeAll()
        continuations.forEach { $0.resume(throwing: CodexAppServerError.disconnected) }

        if shouldNotify {
            onDisconnect?(reason)
        }
    }

    private static func responseKey(for id: CodexAppServerRequestID) -> String {
        id.rawValue
    }
}

protocol CodexAppServerWritableStream: AnyObject {
    func write(_ data: Data) throws
    func close()
}

protocol CodexAppServerReadableStream: AnyObject {
    var onData: (@Sendable (Data) -> Void)? { get set }
    func close()
}

protocol CodexAppServerTransport: AnyObject {
    var stdin: any CodexAppServerWritableStream { get }
    var stdout: any CodexAppServerReadableStream { get }
    var onTerminate: (@Sendable (Int32) -> Void)? { get set }
    var isRunning: Bool { get }
    func run() throws
    func terminate()
    func close()
}

private final class CodexAppServerProcessTransport: CodexAppServerTransport, @unchecked Sendable {
    let stdin: any CodexAppServerWritableStream
    let stdout: any CodexAppServerReadableStream

    var onTerminate: (@Sendable (Int32) -> Void)? {
        didSet {
            if let onTerminate {
                process.terminationHandler = { terminatedProcess in
                    onTerminate(terminatedProcess.terminationStatus)
                }
            } else {
                process.terminationHandler = nil
            }
        }
    }

    var isRunning: Bool {
        process.isRunning
    }

    private let process: Process

    init(codexPath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--listen", "stdio://"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        self.process = process
        stdin = CodexAppServerFileHandleWriter(fileHandle: stdinPipe.fileHandleForWriting)
        stdout = CodexAppServerFileHandleReader(fileHandle: stdoutPipe.fileHandleForReading)
    }

    func run() throws {
        try process.run()
    }

    func terminate() {
        guard process.isRunning else {
            return
        }

        process.terminate()
    }

    func close() {
        stdout.close()
        stdin.close()
        process.terminationHandler = nil
    }
}

private final class CodexAppServerFileHandleWriter: CodexAppServerWritableStream, @unchecked Sendable {
    private let fileHandle: FileHandle

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    func write(_ data: Data) throws {
        try fileHandle.write(contentsOf: data)
    }

    func close() {
        try? fileHandle.close()
    }
}

private final class CodexAppServerFileHandleReader: CodexAppServerReadableStream, @unchecked Sendable {
    var onData: (@Sendable (Data) -> Void)? {
        didSet {
            if let onData {
                fileHandle.readabilityHandler = { fileHandle in
                    onData(fileHandle.availableData)
                }
            } else {
                fileHandle.readabilityHandler = nil
            }
        }
    }

    private let fileHandle: FileHandle

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    func close() {
        fileHandle.readabilityHandler = nil
        try? fileHandle.close()
    }
}

private struct ThreadStartedNotification: Decodable { let thread: CodexThread }
private struct ThreadStatusChangedNotification: Decodable { let threadId: String; let status: CodexThreadStatus }
private struct ThreadClosedNotification: Decodable { let threadId: String }
private struct ThreadNameUpdatedNotification: Decodable { let threadId: String; let threadName: String? }
private struct TurnStartedNotification: Decodable { let threadId: String; let turn: CodexTurn }
private struct TurnCompletedNotification: Decodable { let threadId: String; let turn: CodexTurn }
private struct ServerRequestResolvedNotification: Decodable { let requestId: CodexAppServerRequestID; let threadId: String }
private struct InitializeParams: Encodable {
    struct ClientInfo: Encodable {
        let name: String
        let version: String
    }

    let clientInfo: ClientInfo
    let enabledExperimentalMethods: Bool?
}
