import Foundation

enum CodexCLIReplySenderError: LocalizedError {
    case emptyText
    case missingExecutable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "The reply is empty."
        case .missingExecutable:
            return "The agent CLI is not installed."
        case let .failed(message):
            return message
        }
    }
}

private final class CodexProcessContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var didResume = false
    private let continuation: CheckedContinuation<Int32, Error>

    init(continuation: CheckedContinuation<Int32, Error>) {
        self.continuation = continuation
    }

    nonisolated func resume(_ result: Result<Int32, Error>) {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume else {
            return
        }
        didResume = true

        switch result {
        case let .success(status):
            continuation.resume(returning: status)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}

final class CodexCLIReplySender {
    var isAvailable: Bool {
        resolveExecutable(for: .codex) != nil
    }

    func canSend(to session: SessionSnapshot) -> Bool {
        guard !session.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        guard session.canSendText else {
            return false
        }

        switch session.provider {
        case .codex:
            return resolveExecutable(for: .codex) != nil
        case .claudeCode, .cursor, .antigravity, .conductor:
            return false
        }
    }

    func send(_ text: String, to session: SessionSnapshot) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CodexCLIReplySenderError.emptyText
        }

        guard session.canSendText else {
            throw CodexCLIReplySenderError.failed("Open \(session.provider.displayName) to reply.")
        }

        switch session.provider {
        case .codex:
            try await sendCodex(trimmed, sessionID: session.id, cwd: session.cwd)
        case .claudeCode, .cursor, .antigravity, .conductor:
            throw CodexCLIReplySenderError.failed("Open \(session.provider.displayName) to reply.")
        }
    }

    private func sendCodex(_ text: String, sessionID: String, cwd: String) async throws {
        guard let executable = resolveExecutable(for: .codex) else {
            throw CodexCLIReplySenderError.missingExecutable
        }

        try await runProcess(
            executable: executable,
            arguments: ["exec", "resume", "--all", "--skip-git-repo-check", sessionID, "-"],
            cwd: cwd,
            stdinText: text
        )
    }

    private func runProcess(executable: String, arguments: [String], cwd: String, stdinText: String?) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if FileManager.default.fileExists(atPath: cwd) {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = stdinText == nil ? FileHandle.nullDevice : inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let terminationStatus = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            let box = CodexProcessContinuationBox(continuation: continuation)

            process.terminationHandler = { process in
                box.resume(.success(process.terminationStatus))
            }

            do {
                try process.run()
                if let stdinText {
                    try inputPipe.fileHandleForWriting.write(contentsOf: Data(stdinText.utf8))
                    try inputPipe.fileHandleForWriting.close()
                }
            } catch {
                process.terminationHandler = nil
                process.terminate()
                box.resume(.failure(error))
            }
        }

        guard terminationStatus == 0 else {
            let message = Self.processMessage(
                stdout: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                stderr: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                fallback: "The agent CLI could not resume this session."
            )
            throw CodexCLIReplySenderError.failed(message)
        }
    }

    private func resolveExecutable(for provider: AgentProvider) -> String? {
        switch provider {
        case .codex:
            return [
                "/Applications/Codex.app/Contents/Resources/codex",
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
            ].first { FileManager.default.isExecutableFile(atPath: $0) }
        case .claudeCode:
            return [
                "/Users/\(NSUserName())/.local/bin/claude",
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
            ].first { FileManager.default.isExecutableFile(atPath: $0) }
        case .cursor, .antigravity, .conductor:
            return nil
        }
    }

    private static func processMessage(stdout: Data, stderr: Data, fallback: String) -> String {
        let candidates = [stderr, stdout]
            .compactMap { String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return candidates.first ?? fallback
    }
}
