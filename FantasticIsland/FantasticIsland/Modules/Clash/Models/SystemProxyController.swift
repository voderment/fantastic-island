import Foundation

struct SystemProxyController {
    private let networkSetupPath = "/usr/sbin/networksetup"
    private let proxyHost = "127.0.0.1"

    func isEnabled(expectedPort: Int?) async -> Bool {
        do {
            let services = try await activeServices()
            for service in services {
                let output = try await run(arguments: ["-getwebproxy", service])
                let state = Self.parseProxyState(output)
                guard state.enabled, state.server == proxyHost else {
                    continue
                }

                if expectedPort == nil || state.port == expectedPort {
                    return true
                }
            }
        } catch {
            return false
        }

        return false
    }

    func setEnabled(_ enabled: Bool, port: Int?) async throws {
        if enabled, (port ?? 0) <= 0 {
            throw SystemProxyError.invalidPort
        }

        let services = try await activeServices()
        guard !services.isEmpty else {
            if enabled {
                throw SystemProxyError.noActiveServices
            }

            return
        }

        for service in services {
            if enabled {
                guard let port else {
                    throw SystemProxyError.invalidPort
                }

                _ = try await run(arguments: ["-setwebproxy", service, proxyHost, "\(port)"])
                _ = try await run(arguments: ["-setsecurewebproxy", service, proxyHost, "\(port)"])
                _ = try await run(arguments: ["-setsocksfirewallproxy", service, proxyHost, "\(port)"])
                _ = try await run(arguments: ["-setwebproxystate", service, "on"])
                _ = try await run(arguments: ["-setsecurewebproxystate", service, "on"])
                _ = try await run(arguments: ["-setsocksfirewallproxystate", service, "on"])
            } else {
                _ = try await run(arguments: ["-setwebproxystate", service, "off"])
                _ = try await run(arguments: ["-setsecurewebproxystate", service, "off"])
                _ = try await run(arguments: ["-setsocksfirewallproxystate", service, "off"])
            }
        }
    }

    private func activeServices() async throws -> [String] {
        let output = try await run(arguments: ["-listallnetworkservices"])
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") && !$0.lowercased().contains("network service") }
    }

    private func run(arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.networkSetupPath)
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: SystemProxyError.commandFailed(arguments: arguments, output: output, status: process.terminationStatus))
                    return
                }

                continuation.resume(returning: output)
            }
        }
    }

    private static func parseProxyState(_ output: String) -> ProxyState {
        var enabled = false
        var server: String?
        var port: Int?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = line.firstIndex(of: ":") else {
                continue
            }

            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case "enabled":
                enabled = value.lowercased().hasPrefix("yes")
            case "server":
                server = value
            case "port":
                port = Int(value)
            default:
                continue
            }
        }

        return ProxyState(enabled: enabled, server: server, port: port)
    }

    private struct ProxyState {
        let enabled: Bool
        let server: String?
        let port: Int?
    }
}

private enum SystemProxyError: LocalizedError {
    case invalidPort
    case noActiveServices
    case commandFailed(arguments: [String], output: String, status: Int32)

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "Invalid proxy port"
        case .noActiveServices:
            return "No active network services"
        case let .commandFailed(arguments, output, status):
            let command = arguments.joined(separator: " ")
            if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "networksetup failed (\(status)) for \(command)"
            }

            return "networksetup failed (\(status)) for \(command): \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}
