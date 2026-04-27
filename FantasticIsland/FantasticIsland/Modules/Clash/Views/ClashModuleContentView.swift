import SwiftUI

struct ClashModuleContentView: View {
    @ObservedObject var model: ClashModuleModel
    @Environment(\.islandModuleScrollOffset) private var scrollOffset
    @State private var expandedGroupID: String?
    @State private var expandedGroupTopInContent: CGFloat?
    @State private var expandedGroupCardHeight: CGFloat = 0
    @State private var expandedGroupHeaderHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: ClashExpandedMetrics.outerSpacing) {
            controlCard
            sectionTitle("节点列表")

            if model.proxyGroups.isEmpty {
                sectionCard {
                    Text("暂无可切换节点组。")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(spacing: ClashExpandedMetrics.cardSpacing) { // 与 Codex 模组列表保持一致的卡片间距
                    ForEach(model.proxyGroups) { group in
                        proxyGroupCard(group)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(alignment: .top) {
            if let expandedGroup, shouldPinExpandedGroupHeader {
                proxyGroupPinnedHeaderCard(expandedGroup)
                    .offset(y: scrollOffset)
            }
        }
        .onPreferenceChange(ClashExpandedGroupCardFramePreferenceKey.self) { frame in
            guard frame.isNull == false else { return }

            if expandedGroupTopInContent == nil {
                expandedGroupTopInContent = max(0, frame.minY + scrollOffset)
            }

            if abs(expandedGroupCardHeight - frame.height) > 0.5 {
                expandedGroupCardHeight = frame.height
            }
        }
        .onPreferenceChange(ClashExpandedGroupHeaderHeightPreferenceKey.self) { height in
            guard height > 0 else { return }

            if abs(expandedGroupHeaderHeight - height) > 0.5 {
                expandedGroupHeaderHeight = height
            }
        }
    }

    private var controlCard: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: ClashExpandedMetrics.outerSpacing) {
                if model.moduleMode == .managed {
                    managedCaptureControls
                } else {
                    attachCaptureControls
                }

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                HStack(spacing: ClashExpandedMetrics.sectionTitleSpacing) {
                    ForEach(ClashConnectionMode.allCases) { mode in
                        connectionModeButton(for: mode)
                    }
                }
            }
        }
    }

    private var managedCaptureControls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("托管接管")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))

                Text("系统代理")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
            }

            trafficRateLabel(
                symbol: "arrow.up",
                text: model.status == .runningOwned ? model.uploadRateText : "-",
                activeColor: Color.green.opacity(0.92),
                isEnabled: model.status == .runningOwned
            )

            trafficRateLabel(
                symbol: "arrow.down",
                text: model.status == .runningOwned ? model.downloadRateText : "-",
                activeColor: Color.blue.opacity(0.95),
                isEnabled: model.status == .runningOwned
            )

            Toggle("", isOn: managedSystemProxyBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .foregroundStyle(.primary)
        }
    }

    private var attachCaptureControls: some View {
        HStack(spacing: 12) {
            Text("系统代理")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))

            Spacer(minLength: 0)

            trafficRateLabel(
                symbol: "arrow.up",
                text: model.isTrafficRateAvailable ? model.uploadRateText : "-",
                activeColor: Color.green.opacity(0.92),
                isEnabled: model.isTrafficRateAvailable
            )

            trafficRateLabel(
                symbol: "arrow.down",
                text: model.isTrafficRateAvailable ? model.downloadRateText : "-",
                activeColor: Color.blue.opacity(0.95),
                isEnabled: model.isTrafficRateAvailable
            )

            Toggle("", isOn: systemProxyBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .foregroundStyle(.primary)
        }
    }

    private func trafficRateLabel(symbol: String, text: String, activeColor: Color, isEnabled: Bool) -> some View {
        let tint = isEnabled ? activeColor : Color.white.opacity(0.26)

        return HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(tint)
    }

    private func connectionModeButton(for mode: ClashConnectionMode) -> some View {
        Button {
            model.updateConnectionMode(mode)
        } label: {
            Text(LocalizedStringKey(mode.title))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, ClashExpandedMetrics.actionPillVerticalPadding)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: ClashExpandedMetrics.actionPillCornerRadius, style: .continuous)
                .fill(mode == model.controlState.connectionMode ? Color.white.opacity(0.24) : Color.white.opacity(0.10))
        )
        .overlay {
            RoundedRectangle(cornerRadius: ClashExpandedMetrics.actionPillCornerRadius, style: .continuous)
                .stroke(mode == model.controlState.connectionMode ? Color.white.opacity(0.26) : Color.white.opacity(0.10), lineWidth: 1)
        }
        .foregroundStyle(mode == model.controlState.connectionMode ? .white : .white.opacity(0.8))
    }

    private var expandedGroup: ClashProxyGroupSummary? {
        guard let expandedGroupID else { return nil }
        return model.proxyGroups.first(where: { $0.id == expandedGroupID })
    }

    private var shouldPinExpandedGroupHeader: Bool {
        guard let topInContent = expandedGroupTopInContent,
              expandedGroupCardHeight > 0,
              expandedGroupHeaderHeight > 0 else {
            return false
        }

        let cardBottomInContent = topInContent + expandedGroupCardHeight
        return scrollOffset > topInContent
            && scrollOffset < cardBottomInContent - expandedGroupHeaderHeight
    }

    private func proxyGroupCard(_ group: ClashProxyGroupSummary) -> some View {
        sectionCard {
            VStack(alignment: .leading, spacing: expandedGroupID == group.id ? 10 : 0) {
                proxyGroupHeaderContent(group)
                    .background {
                        if expandedGroupID == group.id {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ClashExpandedGroupHeaderHeightPreferenceKey.self,
                                    value: geometry.size.height
                                )
                            }
                        }
                    }

                if expandedGroupID == group.id {
                    proxyOptionsList(for: group)
                }
            }
        }
        .background {
            if expandedGroupID == group.id {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ClashExpandedGroupCardFramePreferenceKey.self,
                        value: geometry.frame(in: .named(IslandModuleScrollCoordinateSpace.name))
                    )
                }
            }
        }
    }

    private func proxyGroupPinnedHeaderCard(_ group: ClashProxyGroupSummary) -> some View {
        sectionCard(
            fillColor: Color.black.opacity(0.96),
            strokeColor: Color.white.opacity(0.08)
        ) {
            proxyGroupHeaderContent(group)
        }
        .shadow(color: .black.opacity(0.32), radius: 12, y: 4)
    }

    private func proxyGroupHeaderContent(_ group: ClashProxyGroupSummary) -> some View {
        VStack(alignment: .leading, spacing: ClashExpandedMetrics.sectionTitleSpacing) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(group.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))

                        Text(group.type.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.48))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.10), in: Capsule())
                    }

                    HStack(spacing: 8) {
                        Text(group.current)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)

                        if let currentDelay = group.currentDelay {
                            Text("\(currentDelay) ms")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.52))
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button {
                        focusExpandedGroup(group)
                        model.testLatency(in: group.name)
                    } label: {
                        actionPillLabel(title: latencyButtonTitle(for: group))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.88))
                    .disabled(isTestingLatency(for: group))

                    Button {
                        if expandedGroupID == group.id {
                            resetExpandedGroupPinningMetrics()
                            withAnimation(.easeInOut(duration: 0.18)) {
                                expandedGroupID = nil
                            }
                        } else {
                            focusExpandedGroup(group)
                        }
                    } label: {
                        actionPillLabel(
                            title: "节点",
                            trailingSymbolName: expandedGroupID == group.id ? "chevron.up" : "chevron.down"
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.88))
                }
            }

            latencyStatusText(for: group)
        }
    }

    private func latencyStatusText(for group: ClashProxyGroupSummary) -> some View {
        Group {
            switch model.controlState.latencyTestState {
            case .idle:
                EmptyView()
            case let .testing(testingGroup, testingProxy) where testingGroup == group.name:
                Text("正在测速 · \(testingProxy)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            case let .failed(failedGroup, failedProxy, message) where failedGroup == group.name:
                Text(message.isEmpty ? "测速失败 · \(failedProxy)" : "测速失败 · \(failedProxy) · \(message)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.red.opacity(0.9))
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func latencyButtonTitle(for group: ClashProxyGroupSummary) -> String {
        isTestingLatency(for: group) ? "测速中" : "全部测速"
    }

    private func focusExpandedGroup(_ group: ClashProxyGroupSummary) {
        guard expandedGroupID != group.id else { return }
        resetExpandedGroupPinningMetrics()
        withAnimation(.easeInOut(duration: 0.18)) {
            expandedGroupID = group.id
        }
    }

    private func isTestingLatency(for group: ClashProxyGroupSummary) -> Bool {
        model.controlState.latencyTestState.isTesting
            && model.controlState.latencyTestState.currentGroup == group.name
    }

    private func proxyOptionsList(for group: ClashProxyGroupSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(group.options) { option in
                proxyOptionRow(option, in: group)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func proxyOptionRow(_ option: ClashProxyOptionSummary, in group: ClashProxyGroupSummary) -> some View {
        Button {
            model.selectProxy(option.name, in: group.name)
            resetExpandedGroupPinningMetrics()
            withAnimation(.easeInOut(duration: 0.18)) {
                expandedGroupID = nil
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.name == group.current ? "checkmark" : "circle")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(option.name == group.current ? .white.opacity(0.9) : .white.opacity(0.18))
                    .frame(width: 10)

                Text(option.name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)

                Spacer(minLength: 8)

                proxyLatencyBadge(for: option, in: group)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(option.name == group.current ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(option.name == group.current ? Color.white.opacity(0.14) : Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isTestingLatency(for: group))
    }

    private func proxyLatencyBadge(for option: ClashProxyOptionSummary, in group: ClashProxyGroupSummary) -> some View {
        let isTestingCurrentOption: Bool
        if case let .testing(testingGroup, testingProxy) = model.controlState.latencyTestState {
            isTestingCurrentOption = testingGroup == group.name && testingProxy == option.name
        } else {
            isTestingCurrentOption = false
        }

        let isFailedCurrentOption: Bool
        if case let .failed(failedGroup, failedProxy, _) = model.controlState.latencyTestState {
            isFailedCurrentOption = failedGroup == group.name && failedProxy == option.name
        } else {
            isFailedCurrentOption = false
        }

        let backgroundColor: Color
        let foregroundColor: Color
        let text: String

        if isTestingCurrentOption {
            backgroundColor = .white.opacity(0.10)
            foregroundColor = .white.opacity(0.78)
            text = "..."
        } else if isFailedCurrentOption {
            backgroundColor = Color.red.opacity(0.85)
            foregroundColor = .white
            text = "ERR"
        } else if let delay = option.delay {
            text = "\(delay) ms"
            switch delay {
            case ..<300:
                backgroundColor = Color.green.opacity(0.9)
            case ..<450:
                backgroundColor = Color.orange.opacity(0.92)
            default:
                backgroundColor = Color.red.opacity(0.88)
            }
            foregroundColor = .white
        } else {
            backgroundColor = .white.opacity(0.08)
            foregroundColor = .white.opacity(0.52)
            text = "--"
        }

        return Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(backgroundColor, in: Capsule())
    }

    private var systemProxyBinding: Binding<Bool> {
        Binding(
            get: { model.controlState.captureMode == .systemProxy && model.controlState.capturePhase == .active },
            set: { newValue in
                model.updateSystemProxyEnabled(newValue)
            }
        )
    }

    private var managedSystemProxyBinding: Binding<Bool> {
        Binding(
            get: { model.managedSystemProxyEnabled },
            set: { newValue in
                model.updateManagedSystemProxyEnabled(newValue)
            }
        )
    }

    private func resetExpandedGroupPinningMetrics() {
        expandedGroupTopInContent = nil
        expandedGroupCardHeight = 0
        expandedGroupHeaderHeight = 0
    }

    private func sectionCard<Content: View>(
        fillColor: Color = IslandCardMetrics.moduleCardFillColor,
        strokeColor: Color = IslandCardMetrics.moduleCardStrokeColor,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .islandModuleCardSurface(fillColor: fillColor, strokeColor: strokeColor)
        .clipShape(RoundedRectangle(cornerRadius: IslandCardMetrics.moduleCardCornerRadius, style: .continuous))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.84))
    }

    private func actionPillLabel(title: String, trailingSymbolName: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 11, weight: .bold, design: .monospaced))

            if let trailingSymbolName {
                Image(systemName: trailingSymbolName)
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 18)
        .padding(.vertical, ClashExpandedMetrics.actionPillVerticalPadding + 4)
        .background(
            Color.white.opacity(0.12),
            in: RoundedRectangle(cornerRadius: ClashExpandedMetrics.actionPillCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ClashExpandedMetrics.actionPillCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

}

private struct ClashExpandedGroupCardFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.isNull == false {
            value = next
        }
    }
}

private struct ClashExpandedGroupHeaderHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
