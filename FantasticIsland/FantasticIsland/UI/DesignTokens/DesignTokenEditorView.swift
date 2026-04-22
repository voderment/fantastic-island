#if DEBUG
import AppKit
import SwiftUI

struct DesignTokenEditorView: View {
    @ObservedObject var model: IslandAppModel
    @ObservedObject var store: IslandDebugTokenStore
    @Environment(\.locale) private var locale

    @State private var selectedGroup: IslandDesignTokenGroup = .shell
    @State private var selectedWritebackGroups = Set(IslandDesignTokenGroup.allCases)
    @State private var statusMessage = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            divider
            editorPane
            divider
            inspectorPane
        }
        .frame(minWidth: 1180, minHeight: 760)
        .preferredColorScheme(.dark)
        .background(Color.black)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(DesignTokenEditorLocalization.text(.sidebarSection, locale: locale))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))

            ForEach(IslandDesignTokenGroup.allCases) { group in
                Button {
                    selectedGroup = group
                } label: {
                    HStack {
                        Text(group.rawValue)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                        Spacer()
                    }
                    .foregroundStyle(selectedGroup == group ? Color.black : .white.opacity(0.86))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selectedGroup == group ? Color.white.opacity(0.92) : Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 220, alignment: .topLeading)
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            toolbar

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(IslandDesignTokenSchema.descriptors(for: selectedGroup)) { descriptor in
                        tokenEditorRow(descriptor)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                actionButton(DesignTokenEditorLocalization.text(.revert, locale: locale)) {
                    store.revert()
                    statusMessage = DesignTokenEditorLocalization.text(.revertedMessage, locale: locale)
                }

                actionButton(DesignTokenEditorLocalization.text(.saveConfig, locale: locale)) {
                    do {
                        let url = try store.saveConfig()
                        statusMessage = DesignTokenEditorLocalization.saveSucceededMessage(path: url.path, locale: locale)
                    } catch {
                        statusMessage = "\(DesignTokenEditorLocalization.text(.saveFailedPrefix, locale: locale)): \(error.localizedDescription)"
                    }
                }

                actionButton(DesignTokenEditorLocalization.text(.writeBack, locale: locale)) {
                    do {
                        let urls = try store.writeBack(groups: selectedWritebackGroups)
                        statusMessage = DesignTokenEditorLocalization.writebackSucceededMessage(fileCount: urls.count, locale: locale)
                    } catch {
                        statusMessage = "\(DesignTokenEditorLocalization.text(.writebackFailedPrefix, locale: locale)): \(error.localizedDescription)"
                    }
                }

                actionButton(DesignTokenEditorLocalization.text(.writeBackAll, locale: locale)) {
                    do {
                        let urls = try store.writeBackAll()
                        statusMessage = DesignTokenEditorLocalization.writebackSucceededMessage(fileCount: urls.count, locale: locale)
                    } catch {
                        statusMessage = "\(DesignTokenEditorLocalization.text(.writebackAllFailedPrefix, locale: locale)): \(error.localizedDescription)"
                    }
                }

                actionButton(DesignTokenEditorLocalization.text(.openWorkspace, locale: locale)) {
                    NSWorkspace.shared.open(DesignTokenWriter().workspaceDirectory())
                }
            }

            Text(statusMessage.isEmpty ? DesignTokenEditorLocalization.text(.ready, locale: locale) : statusMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(store.hasUnsavedChanges ? .orange.opacity(0.9) : .white.opacity(0.55))
        }
    }

    @ViewBuilder
    private func tokenEditorRow(_ descriptor: IslandDesignTokenDescriptor) -> some View {
        let isModified = store.isModified(descriptor)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(descriptor.key.writebackSymbolName ?? descriptor.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)

                    Text(descriptor.key.rawValue)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.34))

                    Text(descriptor.displayDetail(for: locale))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    if isModified {
                        Button(DesignTokenEditorLocalization.text(.resetSingleToken, locale: locale)) {
                            store.revert(descriptor)
                            statusMessage = DesignTokenEditorLocalization.singleTokenRevertedMessage(
                                tokenName: descriptor.key.rawValue,
                                locale: locale
                            )
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange.opacity(0.95))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                    }

                    switch descriptor.kind {
                    case let .slider(range, step):
                        VStack(alignment: .trailing, spacing: 6) {
                            Slider(
                                value: Binding(
                                    get: { descriptor.getNumber(store.workingTokens) },
                                    set: { store.setNumber($0, for: descriptor) }
                                ),
                                in: range,
                                step: step
                            )
                            .frame(width: 220)

                            Text(formattedNumber(descriptor.getNumber(store.workingTokens)))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.74))
                        }
                    case let .number(step):
                        Stepper(
                            value: Binding(
                                get: { descriptor.getNumber(store.workingTokens) },
                                set: { store.setNumber($0, for: descriptor) }
                            ),
                            step: step
                        ) {
                            Text(formattedNumber(descriptor.getNumber(store.workingTokens)))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 220)
                    case .color:
                        ColorPicker(
                            "",
                            selection: Binding(
                                get: { descriptor.getColor(store.workingTokens).swiftUIColor },
                                set: {
                                    let resolved = NSColor($0)
                                    let rgb = resolved.usingColorSpace(.deviceRGB) ?? resolved
                                    store.setColor(
                                        IslandColorToken(
                                            red: Double(rgb.redComponent),
                                            green: Double(rgb.greenComponent),
                                            blue: Double(rgb.blueComponent),
                                            opacity: Double(rgb.alphaComponent)
                                        ),
                                        for: descriptor
                                    )
                                }
                            ),
                            supportsOpacity: true
                        )
                        .labelsHidden()
                        .frame(width: 180, alignment: .trailing)
                    }
                }
            }
        }
        .padding(14)
        .background(
            (isModified ? Color.orange.opacity(0.07) : Color.white.opacity(0.04)),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isModified ? Color.orange.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var inspectorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                debugPane

                divider

                Text(DesignTokenEditorLocalization.text(.writebackSection, locale: locale))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(IslandDesignTokenGroup.allCases) { group in
                        Toggle(
                            group.rawValue,
                            isOn: Binding(
                                get: { selectedWritebackGroups.contains(group) },
                                set: { isOn in
                                    if isOn {
                                        selectedWritebackGroups.insert(group)
                                    } else {
                                        selectedWritebackGroups.remove(group)
                                    }
                                }
                            )
                        )
                        .toggleStyle(.switch)
                        .foregroundStyle(.white.opacity(0.88))
                    }
                }

                divider

                VStack(alignment: .leading, spacing: 8) {
                    Text(DesignTokenEditorLocalization.text(.sessionSection, locale: locale))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))

                    infoLine(
                        title: DesignTokenEditorLocalization.text(.dirty, locale: locale),
                        value: store.hasUnsavedChanges
                            ? DesignTokenEditorLocalization.text(.yes, locale: locale)
                            : DesignTokenEditorLocalization.text(.no, locale: locale)
                    )
                    infoLine(
                        title: DesignTokenEditorLocalization.text(.selected, locale: locale),
                        value: selectedGroup.rawValue
                    )
                    infoLine(
                        title: DesignTokenEditorLocalization.text(.writebackCount, locale: locale),
                        value: DesignTokenEditorLocalization.writebackGroupCountMessage(
                            groupCount: selectedWritebackGroups.count,
                            locale: locale
                        )
                    )
                }

                divider

                VStack(alignment: .leading, spacing: 10) {
                    Text(DesignTokenEditorLocalization.text(.savedConfigsSection, locale: locale))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))

                    if store.savedConfigs.isEmpty {
                        Text(DesignTokenEditorLocalization.text(.noSavedConfigs, locale: locale))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(store.savedConfigs) { config in
                                savedConfigRow(config)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.visible)
        .padding(20)
        .frame(width: 260, alignment: .topLeading)
    }

    private var debugPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(DesignTokenEditorLocalization.text(.debugSurfaceSection, locale: locale))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))

            VStack(alignment: .leading, spacing: 8) {
                Text(DesignTokenEditorLocalization.text(.panelLockTitle, locale: locale))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))

                HStack(spacing: 8) {
                    ForEach(IslandDebugPanelLockMode.allCases) { mode in
                        capsuleChoiceButton(
                            DesignTokenEditorLocalization.debugLockModeTitle(mode, locale: locale),
                            isSelected: model.debugPanelLockMode == mode
                        ) {
                            model.setDebugPanelLockMode(mode)
                            statusMessage = DesignTokenEditorLocalization.debugLockModeChangedMessage(
                                mode: mode,
                                locale: locale
                            )
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(DesignTokenEditorLocalization.text(.mockScenarioTitle, locale: locale))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))

                ForEach(IslandDebugMockScenario.allCases) { scenario in
                    Button {
                        model.setDebugSelectedMockScenario(scenario)
                        statusMessage = DesignTokenEditorLocalization.debugScenarioSelectedMessage(
                            scenario: scenario,
                            locale: locale
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(DesignTokenEditorLocalization.debugScenarioTitle(scenario, locale: locale))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.92))

                            Text(DesignTokenEditorLocalization.debugScenarioDetail(scenario, locale: locale))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.46))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(model.debugSelectedMockScenario == scenario ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(model.debugSelectedMockScenario == scenario ? Color.white.opacity(0.16) : Color.white.opacity(0.06), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            actionButton(DesignTokenEditorLocalization.text(.triggerMockScenario, locale: locale)) {
                model.triggerSelectedDebugMockScenario()
                statusMessage = DesignTokenEditorLocalization.debugTriggerSucceededMessage(
                    scenario: model.debugSelectedMockScenario,
                    locale: locale
                )
            }
            .opacity(model.debugSelectedMockScenario == .none ? 0.45 : 1)
            .disabled(model.debugSelectedMockScenario == .none)

            infoLine(
                title: DesignTokenEditorLocalization.text(.debugActiveState, locale: locale),
                value: model.debugActiveMockScenario.map {
                    DesignTokenEditorLocalization.debugScenarioTitle($0, locale: locale)
                } ?? DesignTokenEditorLocalization.text(.none, locale: locale)
            )
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: 1)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func capsuleChoiceButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(isSelected ? Color.black : .white.opacity(0.88))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.92) : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private func savedConfigRow(_ config: DesignTokenSavedConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(config.displayName)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Text(savedConfigTimestamp(config.savedAt))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.46))

            Button(DesignTokenEditorLocalization.text(.loadSavedConfig, locale: locale)) {
                do {
                    try store.loadSavedConfig(config)
                    statusMessage = DesignTokenEditorLocalization.loadedSavedConfigMessage(
                        configName: config.displayName,
                        locale: locale
                    )
                } catch {
                    statusMessage = "\(DesignTokenEditorLocalization.text(.saveFailedPrefix, locale: locale)): \(error.localizedDescription)"
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func infoLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.84))
        }
    }

    private func formattedNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }

        return String(format: "%.3f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    private func savedConfigTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
#endif
