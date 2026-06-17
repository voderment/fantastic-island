import Combine
import SwiftUI

@MainActor
final class DiagnosticsModuleModel: ObservableObject, IslandModule {
    static let moduleID = "diagnostics"

    let id = DiagnosticsModuleModel.moduleID
    let title = "Diagnostics"
    let symbolName = "stethoscope"
    private let agentsModule: CodexModuleModel
    private var cancellables: Set<AnyCancellable> = []

    init(agentsModule: CodexModuleModel) {
        self.agentsModule = agentsModule
        agentsModule.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var collapsedSummaryItems: [CollapsedSummaryItem] {
        [
            CollapsedSummaryItem(
                id: "\(id).summary.status",
                moduleID: id,
                title: "Diagnostics",
                text: agentsModule.hookDiagnosticsHasProblems ? "Needs care" : "Ready",
                isEnabledByDefault: false
            ),
        ]
    }

    var taskActivityContribution: TaskActivityContribution {
        agentsModule.hookDiagnosticsHasProblems
            ? TaskActivityContribution(activeTaskCount: 1, lastEventAt: .now)
            : TaskActivityContribution()
    }

    var preferredOpenedContentHeight: CGFloat { 212 }
    var allowsInternalScrolling: Bool { false }

    func makeLiveContentView(presentation _: IslandModulePresentationContext) -> AnyView {
        AnyView(DiagnosticsModuleContentView(agentsModule: agentsModule))
    }
}

private struct DiagnosticsModuleContentView: View {
    @ObservedObject var agentsModule: CodexModuleModel

    private var diagnosticItems: [AgentHookProviderDiagnostic] {
        agentsModule.hookDiagnosticItems
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.07))
            providerGrid
            Divider().overlay(Color.white.opacity(0.07))
            quotaStrip
            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(agentsModule.hookDiagnosticsHasProblems ? Color.orange.opacity(0.86) : Color.green.opacity(0.82))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text("Agent Health")
                    .font(IslandVisualLanguage.islandLabel(11.5))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                Text(agentsModule.hookDiagnosticsCompactSummaryText.uppercased())
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            statusChip(title: "BRIDGE", value: agentsModule.bridgeStatusText)
            statusChip(title: "APP", value: appServerCompactText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var providerGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ],
            alignment: .leading,
            spacing: 7
        ) {
            ForEach(diagnosticItems) { item in
                providerCell(item)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func providerCell(_ item: AgentHookProviderDiagnostic) -> some View {
        HStack(spacing: 7) {
            Image(systemName: item.provider.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(providerTint(item).opacity(0.82))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.provider.compactName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)

                Text(item.statusText.uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(providerTint(item).opacity(0.82))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text("\(item.installedEventCount)/\(item.expectedEventCount)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(item.hooksInstalled ? 0.58 : 0.32))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(Color.white.opacity(item.isHealthy ? 0.032 : 0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(providerTint(item).opacity(item.isHealthy ? 0.08 : 0.18), lineWidth: 0.75)
        }
        .help("\(item.provider.displayName): \(diagnosticDetail(item))")
    }

    private var quotaStrip: some View {
        HStack(spacing: 6) {
            ForEach(agentsModule.providerQuotaItems) { item in
                VStack(spacing: 1) {
                    Text(item.title.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.36))
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Text(item.fiveHourText)
                        Text(item.weekText)
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var actionRow: some View {
        HStack(spacing: 7) {
            diagnosticsButton(symbolName: "arrow.clockwise", label: agentsModule.hooksActionTitle) {
                agentsModule.installOrReinstallHooks()
            }

            diagnosticsButton(symbolName: "wrench.and.screwdriver", label: "Repair Quota Bridge") {
                agentsModule.installUsageBridges()
            }

            diagnosticsButton(symbolName: "terminal", label: "SSH Setup") {
                agentsModule.revealRemoteSSHSetupScript()
            }

            diagnosticsButton(symbolName: "folder", label: "Open ~/.codex") {
                agentsModule.openCodexDirectory()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func diagnosticsButton(
        symbolName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 27, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.64))
        .background(Color.white.opacity(0.048), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .help(label)
    }

    private func statusChip(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.32))
            Text(value.uppercased())
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(statusTint(value).opacity(0.84))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(Color.white.opacity(0.038), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var appServerCompactText: String {
        let status = agentsModule.appServerStatusText
        if status.hasPrefix("Connected") {
            return "Connected"
        }
        return status
    }

    private func providerTint(_ item: AgentHookProviderDiagnostic) -> Color {
        switch (item.hookState, item.usageBridgeState) {
        case (.installed, .managed), (.installed, .unsupported):
            return Color.green
        case (.installed, .custom):
            return Color.yellow
        case (.installed, .missing):
            return Color.orange
        case (.missing, _):
            return .white.opacity(0.42)
        case (.invalidConfig, _), (_, .invalidConfig):
            return Color.red
        }
    }

    private func statusTint(_ value: String) -> Color {
        let normalized = value.lowercased()
        if normalized.hasPrefix("connected") || normalized == "ready" {
            return Color.green
        }
        if normalized == "starting" || normalized == "connecting" {
            return Color.orange
        }
        return Color.red
    }

    private func diagnosticDetail(_ item: AgentHookProviderDiagnostic) -> String {
        let bridgeText: String
        switch item.usageBridgeState {
        case .managed:
            bridgeText = "quota bridge managed"
        case .missing:
            bridgeText = "quota bridge missing"
        case .custom:
            bridgeText = "custom quota line preserved"
        case .invalidConfig:
            bridgeText = "quota bridge unreadable"
        case .unsupported:
            bridgeText = "quota bridge not needed"
        }

        return "\(bridgeText) - \(item.configPath)"
    }
}
