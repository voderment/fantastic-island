import AppKit
import Foundation

struct CodexTerminalAppDescriptor {
    let displayName: String
    let bundleIdentifier: String
    let aliases: [String]
}

enum CodexTerminalAppRegistry {
    private static let iconCache = NSCache<NSString, NSImage>()

    static let descriptors: [CodexTerminalAppDescriptor] = [
        .init(displayName: "iTerm", bundleIdentifier: "com.googlecode.iterm2", aliases: ["iterm", "iterm2"]),
        .init(displayName: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty", aliases: ["ghostty"]),
        .init(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal", aliases: ["terminal", "apple_terminal"]),
        .init(displayName: "Warp", bundleIdentifier: "dev.warp.Warp-Stable", aliases: ["warp", "warpterminal"]),
        .init(displayName: "WezTerm", bundleIdentifier: "com.github.wez.wezterm", aliases: ["wezterm"]),
        .init(displayName: "Codex", bundleIdentifier: "com.openai.codex", aliases: ["codex.app", "codex"]),
        .init(displayName: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92", aliases: ["cursor"]),
        .init(displayName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode", aliases: ["vscode", "code"]),
        .init(displayName: "Visual Studio Code - Insiders", bundleIdentifier: "com.microsoft.VSCodeInsiders", aliases: ["vscode-insiders", "code-insiders"]),
        .init(displayName: "Windsurf", bundleIdentifier: "com.exafunction.windsurf", aliases: ["windsurf"]),
        .init(displayName: "IntelliJ IDEA", bundleIdentifier: "com.jetbrains.intellij", aliases: ["intellij", "idea"]),
        .init(displayName: "WebStorm", bundleIdentifier: "com.jetbrains.WebStorm", aliases: ["webstorm"]),
        .init(displayName: "PyCharm", bundleIdentifier: "com.jetbrains.pycharm", aliases: ["pycharm"]),
        .init(displayName: "GoLand", bundleIdentifier: "com.jetbrains.goland", aliases: ["goland"]),
        .init(displayName: "CLion", bundleIdentifier: "com.jetbrains.CLion", aliases: ["clion"]),
    ]

    static func descriptor(for target: CodexTerminalJumpTarget) -> CodexTerminalAppDescriptor? {
        if let bundleIdentifier = normalizedBundleIdentifier(for: target),
           let descriptor = descriptors.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return descriptor
        }

        let preferredName = target.terminalApp.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !preferredName.isEmpty else {
            return nil
        }

        return descriptors.first { descriptor in
            descriptor.aliases.contains(preferredName) || descriptor.displayName.lowercased() == preferredName
        }
    }

    static func normalizedBundleIdentifier(for target: CodexTerminalJumpTarget) -> String? {
        if let bundleIdentifier = target.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }

        return descriptor(forTerminalAppName: target.terminalApp)?.bundleIdentifier
    }

    static func appIcon(for target: CodexTerminalJumpTarget, size: CGFloat = 64) -> NSImage? {
        let baseKey = (normalizedBundleIdentifier(for: target) ?? target.terminalApp).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseKey.isEmpty else {
            return nil
        }

        let dimension = max(1, Int(size.rounded()))
        let cacheKey = "\(baseKey)|\(dimension)"

        if let cachedIcon = iconCache.object(forKey: cacheKey as NSString) {
            return cachedIcon
        }

        guard let applicationURL = applicationURL(for: target) else {
            return nil
        }

        let sourceIcon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        let renderedIcon = (sourceIcon.copy() as? NSImage) ?? sourceIcon
        renderedIcon.size = NSSize(width: size, height: size)
        iconCache.setObject(renderedIcon, forKey: cacheKey as NSString)
        return renderedIcon
    }

    static func isCodexAppTarget(_ target: CodexTerminalJumpTarget) -> Bool {
        if normalizedBundleIdentifier(for: target) == "com.openai.codex" {
            return true
        }

        let appName = target.terminalApp.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appName == "codex" || appName == "codex.app"
    }

    static func deepLinkURL(for target: CodexTerminalJumpTarget) -> URL? {
        guard normalizedBundleIdentifier(for: target) == "com.openai.codex",
              UUID(uuidString: target.sessionID) != nil else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(target.sessionID)"
        return components.url
    }

    private static func applicationURL(for target: CodexTerminalJumpTarget) -> URL? {
        if let bundleIdentifier = normalizedBundleIdentifier(for: target),
           let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return applicationURL
        }

        if let descriptor = descriptor(for: target),
           let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: descriptor.bundleIdentifier) {
            return applicationURL
        }

        let trimmedName = target.terminalApp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return nil
        }

        if let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmedName) {
            return applicationURL
        }

        return NSWorkspace.shared.runningApplications.first { application in
            application.localizedName?.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }?.bundleURL
    }

    private static func descriptor(forTerminalAppName terminalApp: String) -> CodexTerminalAppDescriptor? {
        let preferredName = terminalApp.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !preferredName.isEmpty else {
            return nil
        }

        return descriptors.first { descriptor in
            descriptor.aliases.contains(preferredName) || descriptor.displayName.lowercased() == preferredName
        }
    }
}

enum CodexTerminalJumpServiceError: LocalizedError {
    case unavailable
    case launchFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "No terminal target could be resolved for this Codex session."
        case .launchFailed:
            return "The terminal application could not be activated."
        }
    }
}

final class CodexTerminalJumpService {
    func jump(to target: CodexTerminalJumpTarget) throws {
        if let tmuxTarget = target.tmuxTarget, !tmuxTarget.isEmpty, jumpToTmuxPane(target: tmuxTarget, socketPath: target.tmuxSocketPath) {
            if let descriptor = resolveTerminalApp(for: target), launchOrActivate(descriptor: descriptor, target: target) {
                return
            }
            return
        }

        if jumpToSpecializedTarget(target) {
            return
        }

        if let processIdentifier = target.processIdentifier,
           let runningApplication = NSWorkspace.shared.runningApplications.first(where: { Int($0.processIdentifier) == processIdentifier }) {
            _ = runningApplication.activate(options: [.activateAllWindows])
            return
        }

        if let bundleIdentifier = target.bundleIdentifier,
           let runningApplication = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            _ = runningApplication.activate(options: [.activateAllWindows])
            return
        }

        if let descriptor = resolveTerminalApp(for: target), launchOrActivate(descriptor: descriptor, target: target) {
            return
        }

        throw CodexTerminalJumpServiceError.unavailable
    }

    private func jumpToSpecializedTarget(_ target: CodexTerminalJumpTarget) -> Bool {
        let app = target.terminalApp.lowercased()

        if app == "codex.app" || app == "codex" || CodexTerminalAppRegistry.normalizedBundleIdentifier(for: target) == "com.openai.codex" {
            return jumpToCodexThread(target)
        }

        if app == "ghostty" {
            return runAppleScript(ghosttyJumpScript(target: target))
        }

        if app == "iterm" || app == "iterm2" {
            return runAppleScript(iTermJumpScript(target: target))
        }

        if app == "terminal" || app == "apple_terminal" {
            return runAppleScript(terminalJumpScript(target: target))
        }

        return false
    }

    private func resolveTerminalApp(for target: CodexTerminalJumpTarget) -> CodexTerminalAppDescriptor? {
        CodexTerminalAppRegistry.descriptor(for: target)
    }

    @discardableResult
    private func launchOrActivate(descriptor: CodexTerminalAppDescriptor, target: CodexTerminalJumpTarget) -> Bool {
        if let runningApplication = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == descriptor.bundleIdentifier }) {
            _ = runningApplication.activate(options: [.activateAllWindows])
            return true
        }

        if launchBundle(descriptor.bundleIdentifier) {
            return true
        }

        if !target.terminalApp.isEmpty {
            return launchApplication(target.terminalApp)
        }

        return false
    }

    private func jumpToCodexThread(_ target: CodexTerminalJumpTarget) -> Bool {
        if let deepLinkURL = CodexTerminalAppRegistry.deepLinkURL(for: target),
           NSWorkspace.shared.open(deepLinkURL) {
            return true
        }

        return launchBundle("com.openai.codex")
    }

    private func launchBundle(_ bundleIdentifier: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", bundleIdentifier]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func launchApplication(_ applicationName: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", applicationName]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func jumpToTmuxPane(target: String, socketPath: String?) -> Bool {
        guard let tmuxPath = resolveTmuxPath() else {
            return false
        }

        var arguments: [String] = []
        if let socketPath, !socketPath.isEmpty {
            arguments += ["-S", socketPath]
        }
        arguments += ["select-pane", "-t", target]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmuxPath)
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

    private func resolveTmuxPath() -> String? {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else {
            return false
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    private func escape(_ string: String?) -> String {
        guard let string else {
            return ""
        }

        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func ghosttyJumpScript(target: CodexTerminalJumpTarget) -> String {
        let sessionID = escape(target.terminalSessionID)
        let workingDirectory = escape(target.workingDirectory)
        let paneTitle = escape(target.paneTitle)

        return """
        tell application "Ghostty"
            if not running then return
            activate
            if "\(sessionID)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (id of aTerminal as text) is "\(sessionID)" then
                                set current tab of aWindow to aTab
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end if
            if "\(workingDirectory)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (working directory of aTerminal as text) is "\(workingDirectory)" then
                                set current tab of aWindow to aTab
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end if
            if "\(paneTitle)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (name of aTerminal as text) contains "\(paneTitle)" then
                                set current tab of aWindow to aTab
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end if
        end tell
        """
    }

    private func iTermJumpScript(target: CodexTerminalJumpTarget) -> String {
        let workingDirectory = escape(target.workingDirectory)
        let sessionID = escape(target.terminalSessionID)
        let tty = escape(target.terminalTTY)

        return """
        tell application "iTerm"
            activate
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if "\(sessionID)" is not "" and (id of aSession as text) is "\(sessionID)" then
                            select aTab
                            return
                        end if
                        if "\(tty)" is not "" and (tty of aSession as text) is "\(tty)" then
                            select aTab
                            return
                        end if
                        if "\(workingDirectory)" is not "" and (profile name of aSession as text) is not "" then
                            try
                                if (name of aSession as text) contains "\(workingDirectory)" then
                                    select aTab
                                    return
                                end if
                            end try
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
    }

    private func terminalJumpScript(target: CodexTerminalJumpTarget) -> String {
        let title = escape(target.paneTitle)
        return """
        tell application "Terminal"
            activate
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    try
                        if custom title of aTab contains "\(title)" then
                            set selected of aTab to true
                            return
                        end if
                    end try
                end repeat
            end repeat
        end tell
        """
    }
}
