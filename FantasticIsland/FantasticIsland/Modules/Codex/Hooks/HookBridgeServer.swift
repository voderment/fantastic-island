import Darwin
import Foundation

final class HookBridgeServer {
    var onPayload: ((CodexHookPayload) -> CodexHookDirective?)?

    private let queue = DispatchQueue(label: "fantastic-island.hook-bridge")
    private let workerQueue = DispatchQueue(label: "fantastic-island.hook-bridge.worker", attributes: .concurrent)
    private let connectionLock = NSLock()
    private var acceptSource: DispatchSourceRead?
    private var activeConnections: [ObjectIdentifier: ClientConnection] = [:]
    private var listenFD: Int32 = -1
    private let socketURL = CodexHookManager.socketURL
    private var isAcceptingConnections = false

    deinit {
        stop()
    }

    func start() throws {
        stop()

        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        _ = socketURL.path.withCString { unlink($0) }

        listenFD = socket(AF_UNIX, Int32(SOCK_STREAM), 0)
        guard listenFD >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let flags = fcntl(listenFD, F_GETFL, 0)
        _ = fcntl(listenFD, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        let pathBytes = Array(socketURL.path.utf8.prefix(maxLength - 1))
        for (index, byte) in pathBytes.enumerated() {
            withUnsafeMutablePointer(to: &addr.sun_path.0) {
                $0.withMemoryRebound(to: UInt8.self, capacity: maxLength) { pointer in
                    pointer[index] = byte
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count + 1)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFD, $0, addrLen)
            }
        }

        guard bindResult == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            stop()
            throw POSIXError(code)
        }

        guard listen(listenFD, 8) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            stop()
            throw POSIXError(code)
        }

        isAcceptingConnections = true
        acceptSource = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
        acceptSource?.setEventHandler { [weak self] in
            self?.acceptPendingConnections()
        }
        acceptSource?.setCancelHandler { [listenFD, socketURL] in
            if listenFD >= 0 {
                close(listenFD)
            }
            _ = socketURL.path.withCString { unlink($0) }
        }
        acceptSource?.resume()
    }

    func stop() {
        isAcceptingConnections = false
        if let acceptSource {
            self.acceptSource = nil
            listenFD = -1
            acceptSource.cancel()
        } else if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        cancelActiveConnections()
        _ = socketURL.path.withCString { unlink($0) }
    }

    private func acceptPendingConnections() {
        while true {
            let serverFD = listenFD
            guard serverFD >= 0 else {
                return
            }

            let clientFD = accept(serverFD, nil, nil)
            if clientFD < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    break
                }
                return
            }

            guard isAcceptingConnections else {
                close(clientFD)
                continue
            }

            let connection = ClientConnection(fileDescriptor: clientFD)
            registerConnection(connection)
            workerQueue.async { [weak self] in
                guard let self else {
                    connection.close()
                    return
                }
                self.handleConnection(connection)
            }
        }
    }

    private func handleConnection(_ connection: ClientConnection) {
        defer {
            unregisterConnection(connection)
            connection.close()
        }

        var payload = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                connection.read(into: rawBuffer.baseAddress, count: rawBuffer.count)
            }
            if count > 0 {
                payload.append(contentsOf: buffer.prefix(count))
                continue
            }

            break
        }

        guard !payload.isEmpty,
              let decoded = try? JSONDecoder().decode(CodexHookPayload.self, from: payload) else {
            return
        }

        let directive = onPayload?(decoded)
        if let directive,
           let encoded = try? JSONEncoder().encode(directive) {
            var response = encoded
            response.append(contentsOf: [0x0A])
            connection.write(response)
        }
    }

    private func registerConnection(_ connection: ClientConnection) {
        connectionLock.lock()
        activeConnections[ObjectIdentifier(connection)] = connection
        connectionLock.unlock()
    }

    private func unregisterConnection(_ connection: ClientConnection) {
        connectionLock.lock()
        activeConnections.removeValue(forKey: ObjectIdentifier(connection))
        connectionLock.unlock()
    }

    private func cancelActiveConnections() {
        connectionLock.lock()
        let connections = Array(activeConnections.values)
        connectionLock.unlock()

        for connection in connections {
            connection.cancel()
        }
    }

    private final class ClientConnection {
        private let lock = NSLock()
        private var fileDescriptor: Int32
        private var isCancelled = false

        init(fileDescriptor: Int32) {
            self.fileDescriptor = fileDescriptor
        }

        deinit {
            close()
        }

        func read(into buffer: UnsafeMutableRawPointer?, count: Int) -> Int {
            lock.lock()
            let fd = fileDescriptor
            let cancelled = isCancelled
            lock.unlock()

            guard fd >= 0, !cancelled else {
                return 0
            }

            return Darwin.read(fd, buffer, count)
        }

        func write(_ data: Data) {
            data.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else {
                    return
                }

                lock.lock()
                defer { lock.unlock() }

                guard fileDescriptor >= 0, !isCancelled else {
                    return
                }

                _ = Darwin.write(fileDescriptor, baseAddress, bytes.count)
            }
        }

        func cancel() {
            lock.lock()
            isCancelled = true
            if fileDescriptor >= 0 {
                _ = Darwin.shutdown(fileDescriptor, SHUT_RDWR)
            }
            lock.unlock()
        }

        func close() {
            lock.lock()
            let fd = fileDescriptor
            fileDescriptor = -1
            isCancelled = true
            lock.unlock()

            if fd >= 0 {
                Darwin.close(fd)
            }
        }
    }
}
