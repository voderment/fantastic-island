import AppKit
import Foundation

enum AgentSessionLaunchError: LocalizedError {
    case missingWorkspace(String)
    case missingApplication(AgentProvider)
    case terminalLaunchFailed
    case workspaceLaunchFailed(AgentProvider)

    var errorDescription: String? {
        switch self {
        case let .missingWorkspace(path):
            return "The workspace folder could not be found: \(path)"
        case let .missingApplication(provider):
            return "\(provider.displayName) is not installed."
        case .terminalLaunchFailed:
            return "The session could not be started in Terminal."
        case let .workspaceLaunchFailed(provider):
            return "\(provider.displayName) could not open the selected workspace."
        }
    }
}

@MainActor
final class AgentSessionLauncher {
    func launch(_ request: AgentNewSessionRequest) throws {
        let workspaceURL = URL(fileURLWithPath: request.workingDirectory, isDirectory: true)
        guard FileManager.default.fileExists(atPath: workspaceURL.path) else {
            throw AgentSessionLaunchError.missingWorkspace(request.workingDirectory)
        }

        if request.provider.canLaunchWithPromptInTerminal {
            try launchTerminalBackedSession(request, workspaceURL: workspaceURL)
        } else {
            try launchWorkspaceBackedSession(request, workspaceURL: workspaceURL)
        }
    }

    private func launchTerminalBackedSession(_ request: AgentNewSessionRequest, workspaceURL: URL) throws {
        var command = "cd \(shellQuote(workspaceURL.path)) && \(shellQuote(resolveExecutable(for: request.provider)))"
        let prompt = request.initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            command += " \(shellQuote(prompt))"
        }

        let script = """
        tell application "Terminal"
            activate
            do script \(appleScriptString(command))
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else {
            throw AgentSessionLaunchError.terminalLaunchFailed
        }

        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if error != nil {
            throw AgentSessionLaunchError.terminalLaunchFailed
        }
    }

    private func launchWorkspaceBackedSession(_ request: AgentNewSessionRequest, workspaceURL: URL) throws {
        guard let applicationURL = applicationURL(for: request.provider) else {
            throw AgentSessionLaunchError.missingApplication(request.provider)
        }

        copyPromptIfNeeded(request.initialPrompt)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([workspaceURL], withApplicationAt: applicationURL, configuration: configuration) { _, error in
            if let error {
                NSLog("Fantastic Island failed to open %@ workspace: %@", request.provider.displayName, error.localizedDescription)
            }
        }
    }

    private func applicationURL(for provider: AgentProvider) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: provider.appBundleIdentifier) {
            return url
        }

        for bundleIdentifier in provider.fallbackAppBundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return url
            }
        }

        return nil
    }

    private func copyPromptIfNeeded(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
    }

    private func resolveExecutable(for provider: AgentProvider) -> String {
        let command = provider.cliCommand
        let candidates = [
            "/opt/homebrew/bin/\(command)",
            "/usr/local/bin/\(command)",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/\(command)",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.antigravity-ide/antigravity-ide/bin/\(command)",
        ]

        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return match
        }

        return command
    }

    private func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else {
            return "''"
        }

        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptString(_ string: String) -> String {
        "\"\(string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
