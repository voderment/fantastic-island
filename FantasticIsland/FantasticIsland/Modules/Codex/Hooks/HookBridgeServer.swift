import Darwin
import Foundation

final class HookBridgeServer {
    var onPayload: ((CodexHookPayload) -> CodexHookDirective?)?

    private let queue = DispatchQueue(label: "fantastic-island.hook-bridge")
    private var acceptSource: DispatchSourceRead?
    private var listenFD: Int32 = -1
    private let socketURL = CodexHookManager.socketURL

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
        if let acceptSource {
            self.acceptSource = nil
            acceptSource.cancel()
        } else if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        _ = socketURL.path.withCString { unlink($0) }
    }

    private func acceptPendingConnections() {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    break
                }
                return
            }

            handleConnection(clientFD)
        }
    }

    private func handleConnection(_ clientFD: Int32) {
        defer { close(clientFD) }

        var payload = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(clientFD, &buffer, buffer.count)
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
            _ = encoded.withUnsafeBytes { bytes in
                write(clientFD, bytes.baseAddress, bytes.count)
            }
            _ = "\n".withCString { newlinePointer in
                write(clientFD, newlinePointer, 1)
            }
        }
    }
}
