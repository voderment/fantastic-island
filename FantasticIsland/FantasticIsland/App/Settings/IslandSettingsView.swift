import AppKit
import SwiftUI

struct IslandSettingsView: View {
    @ObservedObject var model: IslandAppModel

    @State private var selection: IslandSettingsDestination = .general
    @State private var clashShowsSubscriptionForm = false
    @State private var clashPendingSubscriptionURL = ""
    @State private var clashPendingSubscriptionName = ""
    @State private var clashPresentedSheet: ClashSettingsSheet?
    @State private var clashManagedHTTPPort = ""
    @State private var clashManagedSocksPort = ""
    @State private var clashManagedMixedPort = ""

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
                    colors: [
                        Color.white.opacity(0.02),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.dark)
        .onAppear {
            normalizeSelection()
            syncClashManagedPortDrafts()
        }
        .onChange(of: model.enabledModuleIDs) { _, _ in
            normalizeSelection()
        }
        .onChange(of: model.clashModule.moduleMode) { _, _ in
            syncClashManagedPortDrafts()
        }
        .onChange(of: model.clashModule.resolvedPortSnapshot) { _, _ in
            syncClashManagedPortDrafts()
        }
        .environment(\.locale, model.resolvedLocale)
        .sheet(item: $clashPresentedSheet) { sheet in
            clashSheetView(for: sheet)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
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
                subtitle: "Startup, shortcut, language",
                symbolName: "slider.horizontal.3",
                isSelected: selection == .general
            ) {
                selection = .general
            }

            SidebarItemButton(
                title: "Wind Drive",
                subtitle: "Logo and sound",
                symbolName: "wind",
                isSelected: selection == .windDrive
            ) {
                selection = .windDrive
            }

            SidebarItemButton(
                title: "About",
                subtitle: "Product, version, credits",
                symbolName: "info.circle",
                isSelected: selection == .about
            ) {
                selection = .about
            }

#if DEBUG
            SidebarItemButton(
                title: "Design Tokens",
                subtitle: "Open the runtime token editor",
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
            Text("Module Configuration")
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
                case .windDrive:
                    windDrivePage
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
                caption: "Keep app-level behavior here. Nothing module-specific belongs on this page."
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

            SettingsCard(title: "Keyboard Shortcut") {
                ShortcutRow(
                    title: "Expand Notch Area",
                    detail: "Expands the notch surface from anywhere.",
                    shortcut: model.expandShortcutDisplayText
                )
            }

            SettingsCard(title: "Interface Language") {
                SettingsControlRow(
                    title: "Interface Language",
                    detail: "Supports following system language, English, Simplified Chinese, and Traditional Chinese."
                ) {
                    CapsuleMenuPicker(
                        selection: Binding(
                            get: { model.interfaceLanguage },
                            set: { model.setInterfaceLanguage($0) }
                        ),
                        options: IslandInterfaceLanguage.allCases,
                        title: \.title
                    )
                }
            }
        }
    }

    private var windDrivePage: some View {
        let iconTileSize: CGFloat = 74
        let iconGridSpacing: CGFloat = 12
        let previewSide = iconTileSize * 2 + iconGridSpacing
        let previewIconSize: CGFloat = 68
        let iconGridColumns = Array(
            repeating: GridItem(.fixed(iconTileSize), spacing: iconGridSpacing),
            count: 4
        )

        return VStack(alignment: .leading, spacing: 22) {
            pageHeader(
                title: "Wind Drive",
                caption: "Own the fan center mark here. The settings window itself stays static."
            )

            SettingsCard(title: "Expanded Notch Area") {
                ToggleRow(
                    title: "Show Wind Drive Panel",
                    detail: "Hides only the large Wind Drive panel while expanded. The collapsed fan icon stays visible.",
                    isOn: Binding(
                        get: { model.showsExpandedWindDrivePanel },
                        set: { model.setShowsExpandedWindDrivePanel($0) }
                    )
                )
            }

            SettingsCard(title: "Sound Effects") {
                ToggleRow(
                    title: "Enable Sound Effects",
                    detail: "Play fan start and stop cues based on activity.",
                    isOn: Binding(
                        get: { !model.isAudioMuted },
                        set: { enabled in
                            if enabled == model.isAudioMuted {
                                model.toggleAudioMuted()
                            }
                        }
                    )
                )
            }

            SettingsCard(title: "Drive Logo") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose a preset icon or upload a custom square image for the logo in the middle of the fan.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))

                    HStack(alignment: .top, spacing: iconGridSpacing) {
                        VStack(alignment: .leading, spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.white.opacity(0.05))

                                WindDriveMarkView(
                                    preset: model.windDriveLogoPreset,
                                    customImage: model.usesCustomWindDriveLogo ? model.windDriveCustomLogoImage : nil,
                                    size: previewIconSize,
                                    presetForegroundStyle: AnyShapeStyle(.white.opacity(0.96))
                                )
                            }
                            .frame(width: previewSide, height: previewSide)

                            VStack(alignment: .leading, spacing: 10) {
                                SecondaryActionButton(title: "Upload Square Image", fillsWidth: true) {
                                    model.selectCustomWindDriveLogo()
                                }

                                if model.usesCustomWindDriveLogo {
                                    SecondaryActionButton(title: "Use Preset Again", fillsWidth: true) {
                                        model.clearCustomWindDriveLogo()
                                    }
                                }
                            }
                        }
                        .frame(width: previewSide, alignment: .topLeading)

                        LazyVGrid(
                            columns: iconGridColumns,
                            alignment: .leading,
                            spacing: iconGridSpacing
                        ) {
                            ForEach(WindDriveLogoPreset.allCases) { preset in
                                WindDrivePresetIconButton(
                                    preset: preset,
                                    isSelected: !model.usesCustomWindDriveLogo && model.windDriveLogoPreset == preset
                                ) {
                                    model.setWindDriveLogoPreset(preset)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
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

                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ToggleRow(
                            title: "Enable Module",
                            detail: "Turning this off removes the module from the notch area, but keeps its saved configuration.",
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
                    codexFanModulePage
                case ClashModuleModel.moduleID:
                    clashModulePage
                case PlayerModuleModel.moduleID:
                    playerModulePage
                default:
                    SettingsCard(title: "Module Specific") {
                        PlaceholderRow(
                            title: "No module-specific controls yet",
                            detail: "This module can add its own configuration later."
                        )
                    }
                }
            }
        } else {
            pageHeader(title: "Module", caption: "This module is no longer available.")
        }
    }

    private var codexFanModulePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionHeader(
                        title: "Hooks",
                        detail: "Install the managed hook bundle in ~/.codex so Fantastic Island can mirror CLI sessions, approvals, and tool activity."
                    )

                    CodexStatusPanel(
                        title: "Current Status",
                        detail: codexHooksStatusDetailText,
                        badgeText: model.codexFanModule.hooksMenuStatusText,
                        badgeTint: hooksStatusTint
                    )

                    AdaptiveActionGroup {
                        ProminentActionButton(title: model.codexFanModule.hooksActionTitle) {
                            model.codexFanModule.installOrReinstallHooks()
                        }

                        SecondaryActionButton(title: "Open ~/.codex") {
                            model.codexFanModule.openCodexDirectory()
                        }

                        if model.codexFanModule.hooksStatus.isInstalled {
                            SecondaryActionButton(title: "Uninstall", tint: Color.red.opacity(0.22)) {
                                model.codexFanModule.uninstallHooks()
                            }
                        }
                    }
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        SettingsSectionHeader(
                            title: "Connection Health",
                            detail: "Bridge receives CLI hook payloads. App Server mirrors live Codex.app threads and approval requests."
                        )

                        Spacer(minLength: 0)

                        SecondaryActionButton(title: "Refresh Status") {
                            model.codexFanModule.refreshModuleStatus()
                        }
                    }

                    CodexStatusPanel(
                        title: "Bridge",
                        detail: codexBridgeStatusDetailText,
                        badgeText: model.codexFanModule.bridgeStatusText,
                        badgeTint: bridgeStatusTint
                    )

                    CodexStatusPanel(
                        title: "App Server",
                        detail: codexAppServerStatusDetailText,
                        badgeText: localizedCodexAppServerStatusText,
                        badgeTint: appServerStatusTint
                    )

                    if let lastActionMessage = model.codexFanModule.lastActionMessage,
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

    private var clashModulePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 18) {
                        Text("Connection Mode")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)

                        Spacer(minLength: 0)

                        CapsuleMenuPicker(
                            selection: Binding(
                                get: { model.clashModule.moduleMode },
                                set: { model.clashModule.updateModuleMode($0) }
                            ),
                            options: ClashModuleMode.allCases,
                            title: \.title,
                            localizeLabel: false,
                            localizeMenuItems: false,
                            maxLabelWidth: 118
                        )
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)

                    HStack(spacing: 20) {
                        CompactStatusLine(title: clashStatusLineTitle, value: model.clashModule.statusDescription)
                        CompactStatusLine(title: "API", value: model.clashModule.environment.apiBaseURLText)
                        CompactStatusLine(title: clashReferenceLineTitle, value: clashReferenceLineValue)
                        if model.clashModule.moduleMode == .managed {
                            CompactStatusLine(title: "Capture", value: model.clashModule.managedCaptureModeTitle)
                            CompactStatusLine(title: "Providers", value: "\(model.clashModule.proxyProviderCountText)/\(model.clashModule.ruleProviderCountText)")
                        }
                    }

                    if let runtimeStatusDetailText = model.clashModule.runtimeStatusDetailText {
                        SettingsInfoBlock(
                            title: "Runtime Details",
                            value: runtimeStatusDetailText,
                            monospaced: false,
                            valueColor: model.clashModule.runtimeStatusHasError
                                ? Color.red.opacity(0.9)
                                : Color.white.opacity(0.72)
                        )
                    }

                    Text(LocalizedStringKey(clashModeHintText))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionHeader(
                        title: clashConfigurationSectionTitle,
                        detail: clashConfigurationSectionDetail
                    )

                    if model.clashModule.moduleMode == .attach {
                        SettingsField(
                            title: "API Base URL",
                            prompt: "http://127.0.0.1:9090",
                            text: Binding(
                                get: { model.clashModule.configuredAttachAPIBaseURL },
                                set: { model.clashModule.updateConfiguredAttachAPIBaseURL($0) }
                            )
                        )

                        SettingsField(
                            title: "API Secret",
                            prompt: "Bearer secret",
                            text: Binding(
                                get: { model.clashModule.configuredAttachAPISecret },
                                set: { model.clashModule.updateConfiguredAttachAPISecret($0) }
                            ),
                            isSecure: true
                        )

                        SettingsField(
                            title: "Config File",
                            prompt: "~/.config/mihomo/config.yaml",
                            text: Binding(
                                get: { model.clashModule.configuredAttachConfigFilePath },
                                set: { model.clashModule.updateConfiguredAttachConfigFilePath($0) }
                            )
                        )

                        if let resolvedConfigFilePath = model.clashModule.environment.configFilePath {
                            SettingsInfoBlock(
                                title: "Resolved Config File",
                                value: resolvedConfigFilePath,
                                monospaced: true,
                                valueColor: .white.opacity(0.76)
                            )
                        } else {
                            Text("Leave Config File empty if you want Fantastic Island to try to discover a local Mihomo or Clash YAML file automatically.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        AdaptiveActionGroup {
                            SecondaryActionButton(title: "Add Subscription") {
                                openClashSubscriptionForm()
                            }

                            SecondaryActionButton(title: "Import YAML") {
                                model.clashModule.importBuiltInProfile()
                            }
                        }

                        if clashShowsSubscriptionForm {
                            BuiltInSubscriptionComposer(
                                urlText: $clashPendingSubscriptionURL,
                                nameText: $clashPendingSubscriptionName,
                                onCancel: closeClashSubscriptionForm,
                                onSubmit: submitClashSubscriptionForm
                            )
                        }

                        if model.clashModule.builtInProfiles.isEmpty {
                            SettingsEmptyState(
                                title: "No Profile Yet",
                                detail: "Add a subscription or import a YAML file first. Fantastic Island will use the profile you mark as current."
                            )
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(model.clashModule.builtInProfiles) { profile in
                                    BuiltInProfileRow(
                                        name: profile.displayName,
                                        detail: builtInProfileRowDetail(for: profile),
                                        sourceKind: profile.isStarterProfile
                                            ? NSLocalizedString("Default", comment: "")
                                            : profile.sourceKind.title,
                                        isActive: profile.isActive,
                                        primaryActionTitle: builtInProfilePrimaryActionTitle(for: profile),
                                        canDelete: model.clashModule.canDeleteBuiltInProfiles
                                    ) {
                                        handleBuiltInProfilePrimaryAction(profile)
                                    } onRename: {
                                        model.clashModule.showRenameBuiltInProfilePrompt(id: profile.id)
                                    } onDelete: {
                                        model.clashModule.confirmDeleteBuiltInProfile(id: profile.id)
                                    }
                                }
                            }

                            if model.clashModule.activeBuiltInProfileSupportsUpdateOnActivate {
                                ToggleRow(
                                    title: "Update on Activate",
                                    detail: "Refresh the remote YAML before Fantastic Island switches to this subscription.",
                                    isOn: Binding(
                                        get: { model.clashModule.activeBuiltInProfileUpdateOnActivate },
                                        set: { model.clashModule.updateActiveBuiltInProfileUpdateOnActivate($0) }
                                    )
                                )
                            }

                            Text(model.clashModule.builtInProfileStatusDetailText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(subscriptionStatusTint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if model.clashModule.moduleMode == .managed {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionHeader(
                            title: "Managed Runtime",
                            detail: "Start, stop, reload, and inspect Fantastic Island's managed Mihomo runtime directly from settings."
                        )

                        SettingsInfoBlock(
                            title: "Runtime Binary",
                            value: model.clashModule.environment.coreDisplayPath,
                            monospaced: true,
                            valueColor: .white.opacity(0.76)
                        )

                        SettingsInfoBlock(
                            title: "Dashboard",
                            value: model.clashModule.environment.uiBaseURLText,
                            monospaced: true,
                            valueColor: .white.opacity(0.76)
                        )

                        AdaptiveActionGroup {
                            ProminentActionButton(title: "Start Runtime") {
                                model.clashModule.startOrAttach()
                            }
                            .opacity(model.clashModule.canStartOwnedRuntime ? 1 : 0.6)
                            .disabled(!model.clashModule.canStartOwnedRuntime)

                            SecondaryActionButton(title: "Stop Runtime") {
                                model.clashModule.stopOwnedRuntime()
                            }
                            .opacity(model.clashModule.canStopOwnedRuntime ? 1 : 0.6)
                            .disabled(!model.clashModule.canStopOwnedRuntime)

                            SecondaryActionButton(title: "Reload Runtime") {
                                model.clashModule.reloadConfig()
                            }
                            .opacity(model.clashModule.canReloadManagedRuntime ? 1 : 0.6)
                            .disabled(!model.clashModule.canReloadManagedRuntime)
                        }

                        SettingsInfoBlock(
                            title: "Capture",
                            value: "\(model.clashModule.managedCaptureModeTitle) · \(model.clashModule.managedCapturePhaseTitle)",
                            monospaced: false,
                            valueColor: .white.opacity(0.76)
                        )

                        Text("Managed mode should be independently operable here: profile sync feeds the generated runtime config, capture mode controls how Fantastic Island takes over traffic, and runtime actions only affect Fantastic Island's own Mihomo instance.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionHeader(
                            title: "Capture",
                            detail: "Managed mode currently exposes system proxy capture only. TUN stays hidden until Fantastic Island's own path is production-ready."
                        )

                        ToggleRow(
                            title: "System Proxy",
                            detail: model.clashModule.runtimeStatusDetailText
                                ?? "Route traffic through Fantastic Island's local managed proxy ports using macOS networksetup.",
                            isOn: Binding(
                                get: { model.clashModule.managedSystemProxyEnabled },
                                set: { model.clashModule.updateManagedSystemProxyEnabled($0) }
                            )
                        )
                    }
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionHeader(
                        title: "Network Ports",
                        detail: clashNetworkPortsDetail
                    )

                    if model.clashModule.moduleMode == .managed {
                        portEditorCard
                    } else {
                        portReadOnlyCard
                    }
                }
            }

            if model.clashModule.moduleMode == .managed {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionHeader(
                            title: "Providers",
                            detail: "Refresh proxy and rule providers directly from Fantastic Island. No external dashboard is required for routine provider maintenance."
                        )

                        AdaptiveActionGroup {
                            SecondaryActionButton(title: "Refresh Providers") {
                                model.clashModule.refreshProviders()
                            }
                        }

                        if let providerLoadError = model.clashModule.providerLoadError, !providerLoadError.isEmpty {
                            SettingsEmptyState(
                                title: "Providers unavailable",
                                detail: providerLoadError
                            )
                        } else if model.clashModule.proxyProviders.isEmpty && model.clashModule.ruleProviders.isEmpty {
                            SettingsEmptyState(
                                title: "No providers exposed yet",
                                detail: "Fantastic Island will show provider controls here when the active Clash profile defines proxy-providers or rule-providers."
                            )
                        } else {
                            if !model.clashModule.proxyProviders.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    ActionGroupHeader(title: "Proxy Providers")

                                    ForEach(model.clashModule.proxyProviders) { provider in
                                        ProviderManagementRow(
                                            title: provider.name,
                                            detail: provider.detailText,
                                            primaryTitle: "Update",
                                            secondaryTitle: "Healthcheck"
                                        ) {
                                            model.clashModule.updateProxyProvider(named: provider.name)
                                        } onSecondaryAction: {
                                            model.clashModule.healthcheckProxyProvider(named: provider.name)
                                        }
                                    }
                                }
                            }

                            if !model.clashModule.ruleProviders.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    ActionGroupHeader(title: "Rule Providers")

                                    ForEach(model.clashModule.ruleProviders) { provider in
                                        ProviderManagementRow(
                                            title: provider.name,
                                            detail: provider.detailText,
                                            primaryTitle: "Update",
                                            secondaryTitle: nil
                                        ) {
                                            model.clashModule.updateRuleProvider(named: provider.name)
                                        } onSecondaryAction: {}
                                    }
                                }
                            }
                        }
                    }
                }

                SettingsCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionHeader(
                            title: "Diagnostics",
                            detail: "Keep the managed runtime, capture state, and provider inventory observable from Fantastic Island itself."
                        )

                        SettingsInfoBlock(
                            title: "Runtime Phase",
                            value: model.clashModule.managedDiagnostics.runtimePhase.title,
                            monospaced: false,
                            valueColor: .white.opacity(0.76)
                        )

                        SettingsInfoBlock(
                            title: "Capture State",
                            value: "\(model.clashModule.managedDiagnostics.captureMode.title) · \(model.clashModule.managedDiagnostics.capturePhase.title)",
                            monospaced: false,
                            valueColor: .white.opacity(0.76)
                        )

                        SettingsInfoBlock(
                            title: "Last Healthy Profile",
                            value: model.clashModule.managedDiagnostics.activeProfileName ?? NSLocalizedString("Not recorded", comment: ""),
                            monospaced: false,
                            valueColor: .white.opacity(0.76)
                        )

                        if let lastFailureMessage = model.clashModule.managedDiagnostics.lastFailureMessage, !lastFailureMessage.isEmpty {
                            SettingsInfoBlock(
                                title: "Last Failure",
                                value: lastFailureMessage,
                                monospaced: false,
                                valueColor: Color.red.opacity(0.9)
                            )
                        }
                    }
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionHeader(
                        title: "Advanced Capabilities",
                        detail: clashAdvancedCapabilitiesDetail
                    )

                    AdaptiveActionGroup {
                        SecondaryActionButton(title: "Logs") {
                            clashPresentedSheet = .logs
                        }

                        SecondaryActionButton(title: "Rules") {
                            clashPresentedSheet = .rules
                        }

                        SecondaryActionButton(title: "Connections") {
                            clashPresentedSheet = .connections
                        }
                    }

                    DividerLine()

                    AdaptiveActionGroup {
                        SecondaryActionButton(title: "Refresh") {
                            model.clashModule.refreshEnvironment()
                            model.clashModule.refreshAction()
                        }

                        SecondaryActionButton(title: "Open Config") {
                            model.clashModule.openConfigFile()
                        }

                        SecondaryActionButton(title: "Open Folder") {
                            model.clashModule.openConfigDirectory()
                        }
                    }
                }
            }
        }
    }

    private var playerModulePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard(title: "Playback Source") {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsControlRow(
                        title: "Default Source",
                        detail: "When no media source is active, player will open and control this app."
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
            }

            SettingsCard(title: "Actions") {
                HStack(spacing: 10) {
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

    private func pageHeader(title: String, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 30, weight: .bold))

            if let caption {
                Text(LocalizedStringKey(caption))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingsValueCapsule(_ text: String, localize: Bool = true) -> some View {
        Group {
            if localize {
                Text(LocalizedStringKey(text))
            } else {
                Text(verbatim: text)
            }
        }
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .foregroundStyle(.white.opacity(0.66))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    private var hooksStatusTint: Color {
        switch model.codexFanModule.hooksStatus {
        case .installed:
            return Color(nsColor: .systemGreen)
        case .notInstalled:
            return Color(nsColor: .systemOrange)
        case .error:
            return Color(nsColor: .systemRed)
        }
    }

    private var bridgeStatusTint: Color {
        switch model.codexFanModule.bridgeStatusText.lowercased() {
        case "ready":
            return Color(nsColor: .systemGreen)
        case "starting":
            return Color(nsColor: .systemOrange)
        default:
            return Color(nsColor: .systemRed)
        }
    }

    private var appServerStatusTint: Color {
        let status = model.codexFanModule.appServerStatusText.lowercased()

        if status.hasPrefix("connected") {
            return Color(nsColor: .systemBlue)
        }

        switch status {
        case "disconnected":
            return Color.white.opacity(0.62)
        case "unavailable":
            return Color(nsColor: .systemRed)
        default:
            return Color(nsColor: .systemOrange)
        }
    }

    private var subscriptionStatusTint: Color {
        switch model.clashModule.builtInProfileSyncStatus {
        case .idle:
            return .white.opacity(0.5)
        case .updating:
            return Color(nsColor: .systemOrange)
        case .ready:
            return Color(nsColor: .systemGreen)
        case .failed:
            return Color(nsColor: .systemRed)
        }
    }

    private var clashStatusLineTitle: String {
        model.clashModule.moduleMode == .attach ? "Connection" : "Runtime"
    }

    private var clashReferenceLineTitle: String {
        model.clashModule.moduleMode == .attach ? "Config" : "Profile"
    }

    private var clashReferenceLineValue: String {
        if model.clashModule.moduleMode == .attach {
            guard let configFilePath = model.clashModule.environment.configFilePath else {
                return NSLocalizedString("Not set", comment: "")
            }

            return URL(fileURLWithPath: configFilePath).lastPathComponent
        }

        return model.clashModule.activeBuiltInProfile?.displayName ?? NSLocalizedString("No profile", comment: "")
    }

    private var clashModeHintText: String {
        if model.clashModule.moduleMode == .attach {
            return "Detection mode never starts Fantastic Island's managed Mihomo workflow. Use it when you already have another Clash client running and only want Fantastic Island to inspect or control that client."
        }

        return "Managed mode uses Fantastic Island's profile library and managed Mihomo workflow. Use it when you want Fantastic Island to manage subscriptions and runtime behavior itself."
    }

    private var clashConfigurationSectionTitle: String {
        model.clashModule.moduleMode == .attach ? "Detection Settings" : "Managed Profiles"
    }

    private var clashConfigurationSectionDetail: String {
        if model.clashModule.moduleMode == .attach {
            return "Point Fantastic Island at the Clash API and optional config file from the client you already use. Fantastic Island only reads and controls that existing runtime."
        }

        return "Add, rename, delete, and switch the YAML profiles that Fantastic Island can run in managed mode."
    }

    private var clashNetworkPortsDetail: String {
        if model.clashModule.moduleMode == .attach {
            return "Fantastic Island only reads the current HTTP, Socks5, and mixed proxy ports from the Clash client you already use."
        }

        return "Managed mode keeps the proxy ports inside Fantastic Island's runtime config so you can align Mihomo with the rest of your network setup."
    }

    private var clashAdvancedCapabilitiesDetail: String {
        if model.clashModule.moduleMode == .attach {
            return "Inspect logs, rules, and connection overview from the detected client without leaving Fantastic Island."
        }

        return "Inspect runtime logs, current rules, and connection overview for Fantastic Island's managed Mihomo client. Provider refresh and diagnostics now stay in this settings page."
    }

    private func builtInProfileRowDetail(for profile: ClashBuiltInProfile) -> String {
        if profile.isStarterProfile {
            return NSLocalizedString("Created inside Fantastic Island as the default local profile.", comment: "")
        }

        switch profile.sourceKind {
        case .remoteSubscription:
            if let host = profile.remoteSubscriptionURL?.host, !host.isEmpty {
                return host
            }
            return profile.sourceSummaryText
        case .importedFile:
            if let path = profile.importedFilePath {
                return URL(fileURLWithPath: path).lastPathComponent
            }
            return profile.sourceSummaryText
        }
    }

    private var codexHooksStatusDetailText: String {
        switch model.codexFanModule.hooksStatus {
        case .installed:
            return "Managed entries are present and Fantastic Island can receive CLI lifecycle callbacks."
        case .notInstalled:
            return "No managed hooks were found yet. Install once to enable session and approval syncing."
        case .error:
            return "The current hook configuration could not be read cleanly. Reinstall to repair the managed entries."
        }
    }

    private var codexBridgeStatusDetailText: String {
        switch model.codexFanModule.bridgeStatusText.lowercased() {
        case "ready":
            return "The local bridge is listening for hook events from the Codex CLI."
        case "starting":
            return "Bridge startup is still in progress."
        default:
            return "The bridge is unavailable, so CLI hook events will not reach Fantastic Island."
        }
    }

    private var codexAppServerStatusDetailText: String {
        let status = model.codexFanModule.appServerStatusText.lowercased()

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
        let status = model.codexFanModule.appServerStatusText

        switch status {
        case "Connected":
            return NSLocalizedString("Connected", comment: "")
        case "Unavailable":
            return NSLocalizedString("Unavailable", comment: "")
        case "Disconnected":
            return NSLocalizedString("Disconnected", comment: "")
        case "Connected · resolve failed":
            return NSLocalizedString("Connected · resolve failed", comment: "")
        default:
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

            return status
        }
    }

    private func openClashSubscriptionForm() {
        clashPendingSubscriptionURL = ""
        clashPendingSubscriptionName = ""
        clashShowsSubscriptionForm = true
    }

    private func closeClashSubscriptionForm() {
        clashShowsSubscriptionForm = false
    }

    private func submitClashSubscriptionForm() {
        if clashPendingSubscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.clashModule.addBuiltInSubscription(
                named: clashPendingSubscriptionName,
                urlString: clashPendingSubscriptionURL
            )
            return
        }

        model.clashModule.addBuiltInSubscription(
            named: clashPendingSubscriptionName,
            urlString: clashPendingSubscriptionURL
        )
        closeClashSubscriptionForm()
    }

    private func builtInProfilePrimaryActionTitle(for profile: ClashBuiltInProfile) -> String? {
        if profile.isActive {
            return model.clashModule.canRefreshActiveBuiltInProfile
                ? model.clashModule.currentBuiltInProfileActionTitle
                : nil
        }

        return "Use"
    }

    private func handleBuiltInProfilePrimaryAction(_ profile: ClashBuiltInProfile) {
        if profile.isActive {
            model.clashModule.updateCurrentBuiltInProfile()
        } else {
            model.clashModule.selectBuiltInProfile(id: profile.id)
        }
    }

    private func normalizeSelection() {
        if case let .module(moduleID) = selection, model.moduleRegistry.module(id: moduleID) == nil {
            selection = .general
        }
    }

    private func syncClashManagedPortDrafts() {
        let ports = model.clashModule.resolvedPortSnapshot
        clashManagedHTTPPort = ports.httpPort.map(String.init) ?? ""
        clashManagedSocksPort = ports.socksPort.map(String.init) ?? ""
        clashManagedMixedPort = ports.mixedPort.map(String.init) ?? ""
    }

    private func validatedPortValue(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard let port = Int(trimmed), (1...65535).contains(port) else {
            return nil
        }
        return port
    }

    private func isValidPortDraft(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || validatedPortValue(from: trimmed) != nil
    }

    private var canApplyManagedPortDrafts: Bool {
        guard isValidPortDraft(clashManagedHTTPPort),
              isValidPortDraft(clashManagedSocksPort),
              isValidPortDraft(clashManagedMixedPort) else {
            return false
        }

        let snapshot = model.clashModule.resolvedPortSnapshot
        return validatedPortValue(from: clashManagedHTTPPort) != snapshot.httpPort
            || validatedPortValue(from: clashManagedSocksPort) != snapshot.socksPort
            || validatedPortValue(from: clashManagedMixedPort) != snapshot.mixedPort
    }

    @ViewBuilder
    private func clashSheetView(for sheet: ClashSettingsSheet) -> some View {
        switch sheet {
        case .logs:
            ClashLogsSheet(module: model.clashModule)
        case .rules:
            ClashRulesSheet(module: model.clashModule)
        case .connections:
            ClashConnectionsSheet(module: model.clashModule)
        }
    }

    private func modulePageCaption(for moduleID: String) -> String? {
        switch moduleID {
        case CodexModuleModel.moduleID:
            return "Manage Codex hooks, bridge health, and the local runtime actions that feed this module."
        case ClashModuleModel.moduleID:
            return "Switch between detection mode and managed mode, then focus on the settings and actions relevant to the mode you picked."
        case PlayerModuleModel.moduleID:
            return "Review the current media integration state and keep transport controls close at hand."
        default:
            return nil
        }
    }

    private var portReadOnlyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            portValueRow(
                title: "HTTP Proxy Port",
                value: model.clashModule.resolvedHTTPPortText
            )

            portValueRow(
                title: "Socks5 Proxy Port",
                value: model.clashModule.resolvedSocksPortText
            )

            portValueRow(
                title: "Mixed Proxy Port",
                value: model.clashModule.resolvedMixedPortText
            )

            Text("Detection mode does not rewrite ports. Change them in the Clash client you already run, then let Fantastic Island read the updated values.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var portEditorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsField(
                title: "HTTP Proxy Port",
                prompt: "7890",
                text: $clashManagedHTTPPort
            )

            SettingsField(
                title: "Socks5 Proxy Port",
                prompt: "7891",
                text: $clashManagedSocksPort
            )

            SettingsField(
                title: "Mixed Proxy Port",
                prompt: "7892",
                text: $clashManagedMixedPort
            )

            if !isValidPortDraft(clashManagedHTTPPort)
                || !isValidPortDraft(clashManagedSocksPort)
                || !isValidPortDraft(clashManagedMixedPort) {
                Text("Ports must be empty or use a value between 1 and 65535.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Leave a field empty if you want Fantastic Island to fall back to the generated runtime defaults for that port.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }

            AdaptiveActionGroup {
                ProminentActionButton(title: "Apply Ports") {
                    model.clashModule.applyManagedPorts(
                        httpPort: validatedPortValue(from: clashManagedHTTPPort),
                        socksPort: validatedPortValue(from: clashManagedSocksPort),
                        mixedPort: validatedPortValue(from: clashManagedMixedPort)
                    )
                }
                .opacity(canApplyManagedPortDrafts ? 1 : 0.6)
                .disabled(!canApplyManagedPortDrafts)

                SecondaryActionButton(title: "Reset") {
                    syncClashManagedPortDrafts()
                }
            }
        }
    }

    private func portValueRow(title: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            Text(verbatim: value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06), in: Capsule())
        }
    }
}

private enum IslandSettingsDestination: Hashable {
    case general
    case windDrive
    case about
    case module(String)
}

private enum ClashSettingsSheet: String, Identifiable {
    case logs
    case rules
    case connections

    var id: String { rawValue }
}

private struct SidebarItemButton: View {
    let title: String
    var subtitle: String? = nil
    var assetName: String? = nil
    var symbolName: String? = nil
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
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.94) : Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isSelected ? Color.black.opacity(0.08) : Color.white.opacity(0.06))
                .frame(width: 34, height: 34)

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
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
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
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingsControlRow(title: title, detail: detail) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .foregroundStyle(.primary)
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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }
}

private struct CompactStatusLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))
                .textCase(.uppercase)

            Text(verbatim: value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

private struct SettingsInfoBlock: View {
    let title: String
    let value: String
    var monospaced: Bool = false
    var valueColor: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))
                .textCase(.uppercase)

            if monospaced {
                Text(verbatim: value)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(valueColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(verbatim: value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(valueColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BuiltInProfileRow: View {
    let name: String
    let detail: String
    let sourceKind: String
    let isActive: Bool
    let primaryActionTitle: String?
    let canDelete: Bool
    let onPrimaryAction: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(verbatim: detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Text(verbatim: sourceKind)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08), in: Capsule())

                    if isActive {
                        StatusBadge(text: "Current", tint: Color(nsColor: .systemGreen))
                    }
                }
            }

            AdaptiveActionGroup {
                if let primaryActionTitle {
                    SecondaryActionButton(title: primaryActionTitle) {
                        onPrimaryAction()
                    }
                }

                SecondaryActionButton(title: "Rename") {
                    onRename()
                }

                SecondaryActionButton(
                    title: "Delete",
                    tint: canDelete ? Color.red.opacity(0.18) : Color.white.opacity(0.06)
                ) {
                    onDelete()
                }
                .disabled(!canDelete)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.08) : Color.white.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isActive ? Color.white.opacity(0.09) : Color.white.opacity(0.05), lineWidth: 1)
        }
    }
}

private struct ProviderManagementRow: View {
    let title: String
    let detail: String
    let primaryTitle: String
    let secondaryTitle: String?
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Text(verbatim: detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
                    .fixedSize(horizontal: false, vertical: true)
            }

            AdaptiveActionGroup {
                SecondaryActionButton(title: primaryTitle) {
                    onPrimaryAction()
                }

                if let secondaryTitle {
                    SecondaryActionButton(title: secondaryTitle) {
                        onSecondaryAction()
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }
}

private struct SettingsEmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text(LocalizedStringKey(detail))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }
}

private struct BuiltInSubscriptionComposer: View {
    @Binding var urlText: String
    @Binding var nameText: String
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSectionHeader(
                title: "Add Subscription",
                detail: "Paste a Clash or Mihomo YAML subscription link using http:// or https://. The name is optional."
            )

            SettingsField(
                title: "Subscription URL",
                prompt: "http://example.com/clash.yaml",
                text: $urlText
            )

            SettingsField(
                title: "Profile name",
                prompt: "Optional display name",
                text: $nameText
            )

            AdaptiveActionGroup {
                SecondaryActionButton(title: "Cancel") {
                    onCancel()
                }

                ProminentActionButton(title: "Add Subscription") {
                    onSubmit()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }
}

private struct ActionGroupHeader: View {
    let title: String

    var body: some View {
        Text(LocalizedStringKey(title))
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.42))
            .textCase(.uppercase)
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
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct SecondaryActionButton: View {
    let title: String
    var tint: Color = Color.white.opacity(0.08)
    var fillsWidth = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
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

private struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
    }
}

private struct ClashSettingsSheetContainer<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let detail: String
    let width: CGFloat
    let height: CGFloat
    let content: Content

    init(
        title: String,
        detail: String,
        width: CGFloat,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.width = width
        self.height = height
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)

                    Text(LocalizedStringKey(detail))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.86))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }

            content
        }
        .padding(24)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(
            ZStack {
                Color.black
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            }
        )
        .preferredColorScheme(.dark)
    }
}

private struct ClashLogsSheet: View {
    @ObservedObject var module: ClashModuleModel
    @State private var selectedFilter: ClashLogLevelFilter = .all

    private var filteredEntries: [ClashLogEntry] {
        module.logEntries.filter { entry in
            selectedFilter == .all || entry.level == selectedFilter
        }
    }

    var body: some View {
        ClashSettingsSheetContainer(
            title: "Logs",
            detail: "Stream Mihomo logs directly inside Fantastic Island. Filtering stays local to this sheet."
            ,
            width: 760,
            height: 540
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    CapsuleMenuPicker(
                        selection: $selectedFilter,
                        options: ClashLogLevelFilter.allCases,
                        title: \.title,
                        localizeLabel: false,
                        localizeMenuItems: false,
                        maxLabelWidth: 96
                    )

                    Spacer(minLength: 0)

                    SecondaryActionButton(title: "Copy Visible Logs") {
                        let joined = filteredEntries.map(\.rawLine).joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(joined, forType: .string)
                    }
                }

                if let error = module.logStreamError, !error.isEmpty {
                    SettingsEmptyState(
                        title: "Log stream unavailable",
                        detail: error
                    )
                } else if filteredEntries.isEmpty {
                    SettingsEmptyState(
                        title: module.isStreamingLogs ? "Waiting for log output" : "No log entries yet",
                        detail: "Fantastic Island will start showing lines here as soon as the current Clash runtime emits them."
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(filteredEntries.reversed()) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: entry.level.title)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(logTint(for: entry.level))

                                    Text(verbatim: entry.message)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.82))
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.white.opacity(0.035))
                                )
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .onAppear {
            module.startLogStreaming()
        }
        .onDisappear {
            module.stopLogStreaming()
        }
    }

    private func logTint(for level: ClashLogLevelFilter) -> Color {
        switch level {
        case .debug:
            return .white.opacity(0.56)
        case .info, .all:
            return Color(nsColor: .systemBlue)
        case .warning:
            return Color(nsColor: .systemOrange)
        case .error:
            return Color(nsColor: .systemRed)
        }
    }
}

private struct ClashRulesSheet: View {
    @ObservedObject var module: ClashModuleModel
    @State private var searchText = ""

    private var filteredRules: [ClashRuleEntry] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            return module.ruleEntries
        }

        return module.ruleEntries.filter { rule in
            rule.type.localizedStandardContains(keyword)
                || rule.payload.localizedStandardContains(keyword)
                || rule.target.localizedStandardContains(keyword)
                || (rule.source?.localizedStandardContains(keyword) ?? false)
        }
    }

    var body: some View {
        ClashSettingsSheetContainer(
            title: "Rules",
            detail: "Read the current Clash rule list without leaving Fantastic Island."
            ,
            width: 760,
            height: 560
        ) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsField(
                    title: "Search Rules",
                    prompt: "DOMAIN-SUFFIX, MATCH, Proxy, ...",
                    text: $searchText
                )

                if module.isLoadingRules {
                    SettingsEmptyState(
                        title: "Loading rules",
                        detail: "Fantastic Island is reading the active rule set from the current Clash API."
                    )
                } else if let error = module.rulesLoadError, !error.isEmpty {
                    SettingsEmptyState(
                        title: "Rules unavailable",
                        detail: error
                    )
                } else if filteredRules.isEmpty {
                    SettingsEmptyState(
                        title: "No matching rules",
                        detail: searchText.isEmpty
                            ? "The current API did not return a readable rule list."
                            : "Try a different keyword or clear the search field."
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(filteredRules) { rule in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Text(verbatim: rule.type)
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.72))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(Color.white.opacity(0.08), in: Capsule())

                                        Spacer(minLength: 0)

                                        Text(verbatim: rule.target)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.84))
                                    }

                                    Text(verbatim: rule.payload)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.82))
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)

                                    if let source = rule.source, !source.isEmpty {
                                        Text(verbatim: source)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.white.opacity(0.035))
                                )
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .task {
            module.loadRules()
        }
    }
}

private struct ClashConnectionsSheet: View {
    @ObservedObject var module: ClashModuleModel

    var body: some View {
        ClashSettingsSheetContainer(
            title: "Connections",
            detail: "Keep a lightweight overview of live connection pressure, throughput, and memory."
            ,
            width: 680,
            height: 420
        ) {
            VStack(alignment: .leading, spacing: 14) {
                AdaptiveActionGroup {
                    connectionMetricCard(title: "Active Connections", value: module.connectionCountText)
                    connectionMetricCard(title: "Upload Rate", value: module.uploadRateText)
                    connectionMetricCard(title: "Download Rate", value: module.downloadRateText)
                }

                AdaptiveActionGroup {
                    connectionMetricCard(title: "Total Upload", value: module.uploadTotalText)
                    connectionMetricCard(title: "Total Download", value: module.downloadTotalText)
                    connectionMetricCard(title: "Memory Usage", value: module.memoryUsageText)
                }

                if module.isLoadingConnectionOverview {
                    SettingsEmptyState(
                        title: "Refreshing connection overview",
                        detail: "Fantastic Island is reading the latest connection summary from the current Clash API."
                    )
                } else if let error = module.connectionOverviewError, !error.isEmpty {
                    SettingsEmptyState(
                        title: "Connection overview unavailable",
                        detail: error
                    )
                } else {
                    Text("Upload and download rate continue to come from Fantastic Island's regular Clash poller. This sheet keeps the heavier totals and memory summary in one place.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task {
            await refreshLoop()
        }
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            module.refreshConnectionsOverview()
            try? await Task.sleep(for: .seconds(4))
        }
    }

    private func connectionMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))
                .textCase(.uppercase)

            Text(verbatim: value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }
}

private struct WindDrivePresetIconButton: View {
    let preset: WindDriveLogoPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.05))

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.24) : Color.white.opacity(0.0), lineWidth: 1)

                WindDriveMarkView(
                    preset: preset,
                    customImage: nil,
                    size: 34,
                    presetForegroundStyle: AnyShapeStyle(.white.opacity(0.96))
                )
            }
            .frame(width: 74, height: 74)
        }
        .buttonStyle(.plain)
    }
}
