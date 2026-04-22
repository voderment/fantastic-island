import AppKit
import Foundation

enum CodexTerminalTextSenderError: LocalizedError {
    case emptyText
    case unsupportedTarget
    case injectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "The text entry is empty."
        case .unsupportedTarget:
            return "Reply input is not available for this terminal session yet."
        case let .injectionFailed(message):
            return message
        }
    }
}

final class CodexTerminalTextSender {
    func send(_ text: String, to target: CodexTerminalJumpTarget, submit: Bool = true) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CodexTerminalTextSenderError.emptyText
        }

        if let tmuxTarget = target.tmuxTarget, !tmuxTarget.isEmpty {
            guard sendViaTmux(trimmed, tmuxTarget: tmuxTarget, socketPath: target.tmuxSocketPath, submit: submit) else {
                throw CodexTerminalTextSenderError.injectionFailed("Failed to send the reply through tmux.")
            }
            return
        }

        if target.terminalApp.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ghostty" {
            guard sendViaGhostty(trimmed, target: target, submit: submit) else {
                throw CodexTerminalTextSenderError.injectionFailed("Failed to send the reply through Ghostty.")
            }
            return
        }

        throw CodexTerminalTextSenderError.unsupportedTarget
    }

    private func sendViaTmux(_ text: String, tmuxTarget: String, socketPath: String?, submit: Bool) -> Bool {
        guard let tmuxPath = resolveTmuxPath() else {
            return false
        }

        var baseArguments: [String] = []
        if let socketPath, !socketPath.isEmpty {
            baseArguments += ["-S", socketPath]
        }

        guard runProcess(tmuxPath, arguments: baseArguments + ["send-keys", "-t", tmuxTarget, "-l", text]) else {
            return false
        }

        if submit {
            return runProcess(tmuxPath, arguments: baseArguments + ["send-keys", "-t", tmuxTarget, "Enter"])
        }

        return true
    }

    private func sendViaGhostty(_ text: String, target: CodexTerminalJumpTarget, submit: Bool) -> Bool {
        let sessionID = escape(target.terminalSessionID)
        let workingDirectory = escape(target.workingDirectory)
        let paneTitle = escape(target.paneTitle)
        let escapedText = escape(text)

        let enterScript = submit ? "send key \"enter\" to targetTerminal" : ""

        let script = """
        tell application "Ghostty"
            if not running then return "error"
            activate
            set targetTerminal to missing value
            if "\(sessionID)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (id of aTerminal as text) is "\(sessionID)" then
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat
                        if targetTerminal is not missing value then exit repeat
                    end repeat
                    if targetTerminal is not missing value then exit repeat
                end repeat
            end if
            if targetTerminal is missing value and "\(workingDirectory)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (working directory of aTerminal as text) is "\(workingDirectory)" then
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat
                        if targetTerminal is not missing value then exit repeat
                    end repeat
                    if targetTerminal is not missing value then exit repeat
                end repeat
            end if
            if targetTerminal is missing value and "\(paneTitle)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (name of aTerminal as text) contains "\(paneTitle)" then
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat
                        if targetTerminal is not missing value then exit repeat
                    end repeat
                    if targetTerminal is not missing value then exit repeat
                end repeat
            end if
            if targetTerminal is missing value then return "error"
            input text "\(escapedText)" to targetTerminal
            \(enterScript)
            return "ok"
        end tell
        """

        return runAppleScript(script)
    }

    private func resolveTmuxPath() -> String? {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private func runProcess(_ executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runAppleScript(_ script: String) -> Bool {
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            return false
        }
        let result = appleScript.executeAndReturnError(&error)
        return error == nil && result.stringValue == "ok"
    }

    private func escape(_ value: String?) -> String {
        guard let value else {
            return ""
        }

        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
