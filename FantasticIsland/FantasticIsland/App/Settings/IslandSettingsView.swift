import AppKit
import SwiftUI

struct IslandSettingsView: View {
    @ObservedObject var model: IslandAppModel

    @State private var selection: IslandSettingsDestination = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)

            detailPane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Color.black
                LinearGradient(
                    colors: [Color.white.opacity(0.025), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.dark)
        .environment(\.locale, model.resolvedLocale)
        .onAppear(perform: normalizeSelection)
        .onChange(of: model.enabledModuleIDs) { _, _ in
            normalizeSelection()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            sidebarHeader
            topLevelNavigation
            moduleNavigation
            Spacer(minLength: 0)
        }
        .padding(.top, 54)
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
        .frame(width: 240)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.02))
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fantastic Island")
                .font(.system(size: 27, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            Text("SETTINGS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var topLevelNavigation: some View {
        VStack(alignment: .leading, spacing: 6) {
            SidebarItemButton(
                title: "General",
                subtitle: "Startup and shortcuts",
                symbolName: "slider.horizontal.3",
                isSelected: selection == .general
            ) {
                selection = .general
            }

            SidebarItemButton(
                title: "About",
                subtitle: "Product and credits",
                symbolName: "info.circle",
                isSelected: selection == .about
            ) {
                selection = .about
            }

#if DEBUG
            SidebarItemButton(
                title: "Design Tokens",
                subtitle: "Runtime styling",
                symbolName: "dial.high",
                isSelected: false
            ) {
                model.openDesignTokenEditor()
            }
#endif
        }
    }

    private var moduleNavigation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Modules")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ForEach(model.modules, id: \.id) { module in
                SidebarItemButton(
                    title: module.title,
                    assetName: module.iconAssetName,
                    symbolName: module.iconAssetName == nil ? module.symbolName : nil,
                    isSelected: selection == .module(module.id)
                ) {
                    selection = .module(module.id)
                }
            }
        }
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                switch selection {
                case .general:
                    generalPage
                case .about:
                    IslandAboutPage()
                case let .module(moduleID):
                    modulePage(moduleID: moduleID)
                }
            }
            .padding(.top, 48)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageHeader(
                title: "General",
                caption: "Startup, shortcuts, and the small defaults that make the island stay out of the way."
            )

            SettingsCard(title: "Startup") {
                ToggleRow(
                    title: "Launch at Login",
                    detail: model.launchAtLoginStatusText,
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLoginEnabled($0) }
                    )
                )
            }

            SettingsCard(title: "Keyboard") {
                VStack(alignment: .leading, spacing: 12) {
                    ShortcutRow(
                        title: "Expand Island",
                        detail: "Open or close the island from anywhere.",
                        shortcut: model.expandShortcutDisplayText
                    )
                    ShortcutRow(
                        title: "Open Agents",
                        detail: "Jump straight to the Agents module.",
                        shortcut: model.agentsShortcutDisplayText
                    )
                    ShortcutRow(
                        title: "Previous Module",
                        detail: "Move left through enabled modules.",
                        shortcut: model.previousModuleShortcutDisplayText
                    )
                    ShortcutRow(
                        title: "Next Module",
                        detail: "Move right through enabled modules.",
                        shortcut: model.nextModuleShortcutDisplayText
                    )
                    ShortcutRow(
                        title: "Detached Island",
                        detail: "Turn the movable expanded surface on or off.",
                        shortcut: model.detachedModeShortcutDisplayText
                    )
                }
            }

            SettingsCard(title: "Display") {
                VStack(alignment: .leading, spacing: 12) {
                    ToggleRow(
                        title: "Hide in Fullscreen",
                        detail: "Hide the island while another app is fullscreen, like Alcove and Boring Notch.",
                        isOn: Binding(
                            get: { model.hideInFullscreen },
                            set: { model.setHideInFullscreen($0) }
                        )
                    )

                    ToggleRow(
                        title: "Detached Island",
                        detail: "Let the expanded island move like a small buddy window while collapsed state stays anchored to the notch.",
                        isOn: Binding(
                            get: { model.detachedModeEnabled },
                            set: { model.setDetachedModeEnabled($0) }
                        )
                    )
                }
            }

            SettingsCard(title: "Audio") {
                ToggleRow(
                    title: "Agent Notification Sounds",
                    detail: "Play short system sounds when approvals arrive or sessions complete.",
                    isOn: Binding(
                        get: { !model.isAudioMuted },
                        set: { model.setAgentSoundsEnabled($0) }
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func modulePage(moduleID: String) -> some View {
        if let module = model.moduleRegistry.module(id: moduleID) {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader(
                    title: module.title,
                    caption: modulePageCaption(for: module.id)
                )

                SettingsCard(title: "Availability") {
                    VStack(alignment: .leading, spacing: 12) {
                        ToggleRow(
                            title: "Enable Module",
                            detail: "Turning this off removes the module from the island while keeping its saved configuration.",
                            isOn: Binding(
                                get: { model.isModuleEnabled(module.id) },
                                set: { model.setModuleEnabled($0, for: module.id) }
                            )
                        )
                        .disabled(model.isModuleEnabled(module.id) && !model.canDisableModule(module.id))

                        if model.isModuleEnabled(module.id) && !model.canDisableModule(module.id) {
                            Text("At least one module must stay enabled.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.orange.opacity(0.88))
                        }
                    }
                }

                switch module.id {
                case CodexModuleModel.moduleID:
                    agentsModulePage
                case PlayerModuleModel.moduleID:
                    playerModulePage
                case HorizonModuleModel.moduleID:
                    horizonModulePage
                case TimerModuleModel.moduleID:
                    SettingsCard(title: "Timer") {
                        PlaceholderRow(
                            title: "Compact timer",
                            detail: "Timer controls live directly in the island for quick starts, pause, resume, and reset."
                        )
                    }
                case ShelfModuleModel.moduleID:
                    SettingsCard(title: "Shelf") {
                        PlaceholderRow(
                            title: "File drop shelf",
                            detail: "Drop files onto the island and keep compact open, reveal, share, and remove actions close by."
                        )
                    }
                case XPostModuleModel.moduleID:
                    postModulePage
                default:
                    SettingsCard(title: "Details") {
                        PlaceholderRow(
                            title: "No module-specific controls",
                            detail: "This module can add its own native settings later."
                        )
                    }
                }
            }
        } else {
            pageHeader(title: "Module", caption: "This module is no longer available.")
        }
    }

    private var agentsModulePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard(title: "Hooks") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionHeader(
                        title: "Agent Bridge",
                        detail: "Install native hook entries for Codex, Claude Code, Cursor, and Antigravity so sessions can appear in the island."
                    )

                    CodexStatusPanel(
                        title: "Hook Status",
                        detail: codexHooksStatusDetailText,
                        badgeText: model.agentsModule.hooksMenuStatusText,
                        badgeTint: hooksStatusTint
                    )

                    AdaptiveActionGroup {
                        ProminentActionButton(title: model.agentsModule.hooksActionTitle) {
                            model.agentsModule.installOrReinstallHooks()
                        }

                        SecondaryActionButton(title: "Open ~/.codex") {
                            model.agentsModule.openCodexDirectory()
                        }

                        SecondaryActionButton(title: "Repair Quota Bridge") {
                            model.agentsModule.installUsageBridges()
                        }

                        SecondaryActionButton(title: "SSH Setup") {
                            model.agentsModule.revealRemoteSSHSetupScript()
                        }

                        if model.agentsModule.hooksStatus.isInstalled {
                            SecondaryActionButton(title: "Uninstall", tint: Color.red.opacity(0.22)) {
                                model.agentsModule.uninstallHooks()
                            }
                        }
                    }
                }
            }

            SettingsCard(title: "Connection") {
                VStack(alignment: .leading, spacing: 14) {
                    CodexStatusPanel(
                        title: "Local Bridge",
                        detail: codexBridgeStatusDetailText,
                        badgeText: model.agentsModule.bridgeStatusText,
                        badgeTint: bridgeStatusTint
                    )

                    CodexStatusPanel(
                        title: "Codex App",
                        detail: codexAppServerStatusDetailText,
                        badgeText: localizedCodexAppServerStatusText,
                        badgeTint: appServerStatusTint
                    )

                    AdaptiveActionGroup {
                        SecondaryActionButton(title: "Refresh") {
                            model.agentsModule.refreshModuleStatus()
                        }
                    }

                    if let lastActionMessage = model.agentsModule.lastActionMessage,
                       !lastActionMessage.isEmpty {
                        Text(LocalizedStringKey(lastActionMessage))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.orange.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var playerModulePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard(title: "Playback Source") {
                SettingsControlRow(
                    title: "Default Source",
                    detail: "When no source is active, Player opens and controls this app."
                ) {
                    if model.playerModule.defaultSourceOptions.isEmpty {
                        settingsValueCapsule("No supported app found")
                            .opacity(0.6)
                    } else {
                        CapsuleMenuPicker(
                            selection: Binding(
                                get: { model.playerModule.defaultSourceSelection },
                                set: { model.playerModule.setDefaultSource($0) }
                            ),
                            options: model.playerModule.defaultSourceOptions,
                            title: \.displayName,
                            localizeLabel: false,
                            localizeMenuItems: false,
                            maxLabelWidth: 170
                        )
                    }
                }
            }

            SettingsCard(title: "Actions") {
                AdaptiveActionGroup {
                    SecondaryActionButton(title: "Refresh") {
                        model.playerModule.refresh()
                    }

                    SecondaryActionButton(title: "Toggle Play") {
                        model.playerModule.togglePlayPause()
                    }
                }
            }
        }
    }

    private var horizonModulePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard(title: "Native Access") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsControlRow(
                        title: "Calendar and Reminders",
                        detail: "Horizon uses native EventKit permissions for glanceable schedule and reminder cards."
                    ) {
                        StatusBadge(text: "Native", tint: Color(nsColor: .systemBlue))
                    }

                    SettingsControlRow(
                        title: "Weather",
                        detail: "Uses location once to fetch Open-Meteo forecast data."
                    ) {
                        StatusBadge(text: "Network", tint: Color(nsColor: .systemTeal))
                    }

                    SettingsControlRow(
                        title: "Battery, Timer, and Shelf",
                        detail: "Battery reads local power state. Shelf supports AirDrop/share, open, and reveal."
                    ) {
                        StatusBadge(text: "Local", tint: Color(nsColor: .systemGreen))
                    }
                }
            }
        }
    }

    private var postModulePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard(title: "X Account") {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsField(
                        title: "OAuth 2.0 Client ID",
                        prompt: "Client ID",
                        text: Binding(
                            get: { model.postModule.configuredClientID },
                            set: { model.postModule.updateConfiguredClientID($0) }
                        )
                    )

                    SettingsControlRow(
                        title: "Account",
                        detail: model.postModule.accountStatusText
                    ) {
                        StatusBadge(
                            text: model.postModule.isAuthenticated ? "Signed In" : "Setup",
                            tint: model.postModule.isAuthenticated ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange)
                        )
                    }

                    AdaptiveActionGroup {
                        if model.postModule.isAuthenticated {
                            SecondaryActionButton(title: "Disconnect", tint: Color.red.opacity(0.22)) {
                                model.postModule.disconnect()
                            }
                        } else {
                            ProminentActionButton(title: model.postModule.isSigningIn ? "Signing In..." : "Sign In") {
                                model.postModule.signIn()
                            }
                            .disabled(!model.postModule.canSignIn)
                        }
                    }
                }
            }
        }
    }

    private func pageHeader(title: String, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)

            if let caption {
                Text(LocalizedStringKey(caption))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingsValueCapsule(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.66))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: Capsule())
    }

    private var hooksStatusTint: Color {
        switch model.agentsModule.hooksStatus {
        case .installed:
            return Color(nsColor: .systemGreen)
        case .notInstalled:
            return Color(nsColor: .systemOrange)
        case .error:
            return Color(nsColor: .systemRed)
        }
    }

    private var bridgeStatusTint: Color {
        switch model.agentsModule.bridgeStatusText.lowercased() {
        case "ready":
            return Color(nsColor: .systemGreen)
        case "starting":
            return Color(nsColor: .systemOrange)
        default:
            return Color(nsColor: .systemRed)
        }
    }

    private var appServerStatusTint: Color {
        let status = model.agentsModule.appServerStatusText.lowercased()

        if status.hasPrefix("connected") {
            return Color(nsColor: .systemBlue)
        }

        switch status {
        case "disconnected":
            return .white.opacity(0.62)
        case "unavailable":
            return Color(nsColor: .systemRed)
        default:
            return Color(nsColor: .systemOrange)
        }
    }

    private var codexHooksStatusDetailText: String {
        switch model.agentsModule.hooksStatus {
        case .installed:
            return "Managed entries are present and Fantastic Island can receive lifecycle callbacks."
        case .notInstalled:
            return "No managed hooks were found yet. Install once to enable session and approval syncing."
        case .error:
            return "The current hook configuration could not be read cleanly. Reinstall to repair the managed entries."
        }
    }

    private var codexBridgeStatusDetailText: String {
        switch model.agentsModule.bridgeStatusText.lowercased() {
        case "ready":
            return "The local bridge is listening for agent hook events."
        case "starting":
            return "Bridge startup is still in progress."
        default:
            return "The bridge is unavailable, so CLI hook events will not reach Fantastic Island."
        }
    }

    private var codexAppServerStatusDetailText: String {
        let status = model.agentsModule.appServerStatusText.lowercased()

        if status.hasPrefix("connected") {
            return "Codex.app is connected and can stream live thread state into this module."
        }

        switch status {
        case "disconnected":
            return "Codex.app is not connected right now. Launch Codex to expose live threads and approval prompts."
        case "unavailable":
            return "Codex.app was detected, but its local app-server could not be reached."
        default:
            return "Connection state is changing. Refresh if this status lingers."
        }
    }

    private var localizedCodexAppServerStatusText: String {
        let status = model.agentsModule.appServerStatusText
        let prefix = "Connected · "
        let suffix = " threads"

        if status.hasPrefix(prefix), status.hasSuffix(suffix) {
            let countText = String(status.dropFirst(prefix.count).dropLast(suffix.count))
            if let count = Int(countText) {
                return String.localizedStringWithFormat(
                    NSLocalizedString("Connected · %d threads", comment: ""),
                    count
                )
            }
        }

        return NSLocalizedString(status, comment: "")
    }

    private func normalizeSelection() {
        if case let .module(moduleID) = selection, model.moduleRegistry.module(id: moduleID) == nil {
            selection = .general
        }
    }

    private func modulePageCaption(for moduleID: String) -> String? {
        switch moduleID {
        case CodexModuleModel.moduleID:
            return "Manage agent hooks, bridge health, and the local session surfaces that feed the island."
        case PlayerModuleModel.moduleID:
            return "Review the current media integration state and keep transport controls close at hand."
        case HorizonModuleModel.moduleID:
            return "Keep calendar, reminders, weather, and battery native and glanceable."
        case TimerModuleModel.moduleID:
            return "Run short timers without turning Horizon into a crowded dashboard."
        case ShelfModuleModel.moduleID:
            return "Drop files into a compact island shelf with quick open, reveal, share, and remove actions."
        case XPostModuleModel.moduleID:
            return "Draft and publish a compact text post without leaving the island."
        default:
            return nil
        }
    }
}

private enum IslandSettingsDestination: Hashable {
    case general
    case about
    case module(String)
}

private struct SidebarItemButton: View {
    let title: String
    var subtitle: String?
    var assetName: String?
    var symbolName: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.black.opacity(0.92) : .white.opacity(0.88))

                    if let subtitle {
                        Text(LocalizedStringKey(subtitle))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isSelected ? Color.black.opacity(0.62) : .white.opacity(0.46))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.94) : Color.white.opacity(0.04))
            )
            .overlay {
                if !isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.75)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.black.opacity(0.08) : Color.white.opacity(0.06))
                .frame(width: 30, height: 30)

            if let assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(isSelected ? Color.black.opacity(0.86) : .white.opacity(0.88))
            } else if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.86) : .white.opacity(0.88))
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.46))
                    .textCase(.uppercase)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .islandGlassPanel(cornerRadius: 12)
    }
}

private struct SettingsControlRow<Accessory: View>: View {
    let title: String
    let detail: String?
    let accessory: Accessory

    init(
        title: String,
        detail: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                if let detail {
                    Text(LocalizedStringKey(detail))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            accessory
                .fixedSize()
        }
    }
}

private struct ToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsControlRow(title: title, detail: detail) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
        }
    }
}

private struct PlaceholderRow: View {
    let title: String
    let detail: String

    var body: some View {
        SettingsControlRow(title: title, detail: detail) {
            Text("Later")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08), in: Capsule())
        }
    }
}

private struct ShortcutRow: View {
    let title: String
    let detail: String
    let shortcut: String

    var body: some View {
        SettingsControlRow(title: title, detail: detail) {
            Text(shortcut)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.86))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
        }
    }
}

private struct SettingsSectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            Text(LocalizedStringKey(detail))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    var isSecure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))

            Group {
                if isSecure {
                    SecureField(prompt, text: $text)
                } else {
                    TextField(prompt, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
    }
}

private struct CodexStatusPanel: View {
    let title: String
    let detail: String
    let badgeText: String
    let badgeTint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Text(LocalizedStringKey(detail))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            StatusBadge(text: badgeText, tint: badgeTint)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct SettingsInfoBlock: View {
    let title: String
    let value: String
    var monospaced = false
    var valueColor: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))
                .textCase(.uppercase)

            Text(verbatim: value)
                .font(.system(size: 12, weight: .medium, design: monospaced ? .monospaced : .default))
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AdaptiveActionGroup<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                content()
            }

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
    }
}

private struct ProminentActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct SecondaryActionButton: View {
    let title: String
    var tint: Color = Color.white.opacity(0.08)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct StatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.16), in: Capsule())
    }
}
