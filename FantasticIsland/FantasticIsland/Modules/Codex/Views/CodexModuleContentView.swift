import SwiftUI

private struct GlobalInfoCardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct CodexModuleRenderState {
    let presentation: IslandModulePresentationContext
    let activityState: FanActivityState
    let sessionSurface: CodexIslandSurface
    let isNotificationMode: Bool
    let islandListSessions: [SessionSnapshot]
    let activeNotificationSession: SessionSnapshot?
    let presentedSession: SessionSnapshot?
    let shouldShowShowAllButton: Bool
    let canCollapseSessionList: Bool
    let globalInfoLiveCountText: String
    let globalInfoFiveHourValueText: String
    let globalInfoWeekValueText: String
    let globalInfoFiveHourResetCompactText: String
    let globalInfoWeekResetCompactText: String
    let tokenUsageHeatmapDays: [CodexTokenUsageDay]
    let tokenUsageHeatmapPeriodText: String
    let tokenUsageHeatmapPeakText: String
    let approvePermission: (String, CodexApprovalAction) -> Void
    let answerQuestion: (String, CodexQuestionResponse) -> Void
    let replyToSession: (String, String) -> Void
    let jumpToSession: (String) -> Void
    let showAllSessions: () -> Void
    let collapseSessionList: () -> Void
}

struct CodexModuleLiveContentView: View {
    @ObservedObject var model: CodexModuleModel
    let presentation: IslandModulePresentationContext

    var body: some View {
        CodexModuleContentView(state: model.makeRenderState(for: presentation))
    }
}

struct CodexModuleContentView: View {
    let state: CodexModuleRenderState
    @State private var measuredGlobalInfoCardHeight = Self.estimatedGlobalInfoCardHeight

    private static let estimatedGlobalInfoCardHeight: CGFloat = 58
    private static let alignedModuleBodyHeight: CGFloat =
        CodexIslandChromeMetrics.windDrivePanelHeight
        - CodexIslandChromeMetrics.moduleNavigationRowHeight
        - CodexIslandChromeMetrics.moduleColumnSpacing

    var body: some View {
        switch state.presentation {
        case .standard:
            VStack(alignment: .leading, spacing: CodexExpandedMetrics.contentSpacing) {
                globalInfoCard
                tokenHeatmapCard

                if state.islandListSessions.isEmpty {
                    emptyStateCard
                } else {
                    sessionList
                }
            }
        case let .activity(activity):
            activityContent(for: activity)
        case let .peek(activity):
            peekContent(for: activity)
        }
    }

    @ViewBuilder
    private func activityContent(for activity: IslandActivity) -> some View {
        if let session = state.presentedSession {
            if activity.kind == .transientNotification, session.phase == .completed {
                completedActivityCard(for: session)
            } else {
                CodexIslandSessionRow(
                    session: session,
                    referenceDate: .now,
                    isActionable: true,
                    surfaceStyle: .peek,
                    onApprove: { state.approvePermission(session.id, $0) },
                    onAnswer: { state.answerQuestion(session.id, $0) },
                    onReply: { state.replyToSession(session.id, $0) },
                    onJump: { state.jumpToSession(session.id) }
                )
            }
        } else {
            emptyStateCard
        }
    }

    @ViewBuilder
    private func peekContent(for activity: IslandActivity) -> some View {
        if let session = state.presentedSession {
            if activity.kind == .actionRequired {
                CodexIslandSessionRow(
                    session: session,
                    referenceDate: .now,
                    isActionable: true,
                    surfaceStyle: .peek,
                    onApprove: { state.approvePermission(session.id, $0) },
                    onAnswer: { state.answerQuestion(session.id, $0) },
                    onReply: { state.replyToSession(session.id, $0) },
                    onJump: { state.jumpToSession(session.id) }
                )
            } else {
                peekNotificationCard(for: session)
            }
        } else {
            emptyStateCard
        }
    }

    private func peekNotificationCard(for session: SessionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: CodexPeekMetrics.rowSpacing) {
                Circle()
                    .fill(CodexPeekMetrics.statusDotColor)
                    .frame(width: CodexPeekMetrics.statusDotSize, height: CodexPeekMetrics.statusDotSize)
                    .padding(.top, CodexPeekMetrics.statusDotTopPadding)

                VStack(alignment: .leading, spacing: CodexPeekMetrics.contentSpacing) {
                    HStack(alignment: .center, spacing: CodexPeekMetrics.contentSpacing) {
                        Text(completedActivityTitle(for: session))
                            .font(.system(size: CodexPeekMetrics.titleFontSize, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: CodexPeekMetrics.titleTrailingSpacerMinLength)

                        HStack(spacing: CodexPeekMetrics.badgeSpacing) {
                            CodexWorkspaceBadge(title: completedWorkspaceName(for: session), prominence: .compact)
                            compactStatusBadge("Completed")
                            compactNeutralBadge(CodexIslandSessionPresentation.ageBadge(for: session, now: .now))
                        }
                    }

                    if let promptLine = completedActivityPromptLine(for: session) {
                        Text(promptLine)
                            .font(.system(size: CodexPeekMetrics.promptFontSize, weight: .medium))
                            .foregroundStyle(.white.opacity(CodexPeekMetrics.promptOpacity))
                            .lineLimit(1)
                    }

                    Text(completedActivitySummary(for: session))
                        .font(.system(size: CodexPeekMetrics.summaryFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(CodexPeekMetrics.summaryOpacity))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, CodexPeekMetrics.cardHorizontalPadding)
            .padding(.vertical, CodexPeekMetrics.cardVerticalPadding)
        }
        .background(
            RoundedRectangle(cornerRadius: CodexExpandedMetrics.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(CodexPeekMetrics.backgroundOpacity))
        )
    }

    private func completedActivityCard(for session: SessionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(Color(red: 0.29, green: 0.86, blue: 0.46))
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(completedActivityTitle(for: session))
                            .font(.system(size: CodexExpandedMetrics.titleFontSize, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 8)

                        HStack(spacing: 6) {
                            CodexWorkspaceBadge(title: completedWorkspaceName(for: session))
                            compactStatusBadge("Completed")
                            compactNeutralBadge(CodexIslandSessionPresentation.ageBadge(for: session, now: .now))
                            completedAppIconAccessory(for: session)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }

                    if let promptLine = completedActivityPromptLine(for: session) {
                        Text(promptLine)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle()
                .fill(.white.opacity(0.04))
                .frame(height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                Text(completedActivityMessage(for: session))
                    .font(.system(size: CodexExpandedMetrics.summaryFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)
        }
        .background(
            RoundedRectangle(cornerRadius: CodexExpandedMetrics.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(CodexExpandedMetrics.cardBackgroundOpacity))
        )
        .overlay {
            RoundedRectangle(cornerRadius: CodexExpandedMetrics.cardCornerRadius, style: .continuous)
                .stroke(Color(red: 0.29, green: 0.86, blue: 0.46).opacity(0.30), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: CodexExpandedMetrics.cardCornerRadius, style: .continuous))
        .onTapGesture {
            state.jumpToSession(session.id)
        }
    }

    @ViewBuilder
    private var sessionList: some View {
        if state.isNotificationMode, let session = state.activeNotificationSession {
            CodexIslandSessionRow(
                session: session,
                referenceDate: .now,
                isActionable: true,
                onApprove: { state.approvePermission(session.id, $0) },
                onAnswer: { state.answerQuestion(session.id, $0) },
                onReply: { state.replyToSession(session.id, $0) },
                onJump: { state.jumpToSession(session.id) }
            )

            if state.shouldShowShowAllButton {
                Button("Show all \(state.islandListSessions.count) sessions") {
                    state.showAllSessions()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
        } else {
            VStack(spacing: CodexExpandedMetrics.sectionRowSpacing) {
                ForEach(state.islandListSessions) { session in
                    CodexIslandSessionRow(
                        session: session,
                        referenceDate: .now,
                        isActionable: session.phase.requiresAttention || session.id == state.sessionSurface.sessionID,
                        onApprove: { state.approvePermission(session.id, $0) },
                        onAnswer: { state.answerQuestion(session.id, $0) },
                        onReply: { state.replyToSession(session.id, $0) },
                        onJump: { state.jumpToSession(session.id) }
                    )
                }
            }

            if state.canCollapseSessionList {
                Button("Collapse") {
                    state.collapseSessionList()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
        }
    }

    private var globalInfoCard: some View {
        sectionCard {
            HStack(alignment: .center, spacing: 12) {
                Text("Global Info")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(spacing: CodexExpandedMetrics.globalInfoBadgeSpacing) {
                    quotaBadge(
                        title: "5H",
                        value: state.globalInfoFiveHourValueText,
                        resetText: state.globalInfoFiveHourResetCompactText
                    )
                    quotaBadge(
                        title: "W",
                        value: state.globalInfoWeekValueText,
                        resetText: state.globalInfoWeekResetCompactText
                    )
                    liveCountBadge
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: GlobalInfoCardHeightKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(GlobalInfoCardHeightKey.self) { height in
            guard height > 0, abs(measuredGlobalInfoCardHeight - height) >= 1 else {
                return
            }

            measuredGlobalInfoCardHeight = height
        }
    }

    private var liveCountBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.activityState.inProgressSessionCount > 0 ? Color.green.opacity(0.95) : Color.white.opacity(0.22))
                .frame(width: 7, height: 7)

            Text("LIVE \(state.globalInfoLiveCountText)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(state.activityState.inProgressSessionCount > 0 ? Color.green.opacity(0.95) : Color.white.opacity(0.52))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    private var tokenHeatmapCard: some View {
        tokenHeatmapSectionCard {
            CodexTokenHeatmapView(
                days: state.tokenUsageHeatmapDays,
                periodText: state.tokenUsageHeatmapPeriodText,
                peakText: state.tokenUsageHeatmapPeakText
            )
        }
    }

    private func quotaBadge(title: String, value: String, resetText: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.48))

            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Text(resetText)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.64))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No live conversations")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))

            Text("Open Codex to populate live sessions here.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity, minHeight: emptyStateMinimumHeight, alignment: .center)
        .padding(.horizontal, 18)
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: CodexExpandedMetrics.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CodexExpandedMetrics.cardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(CodexExpandedMetrics.cardBorderOpacity), lineWidth: 1)
        }
    }

    private var emptyStateMinimumHeight: CGFloat {
        let heatmapHeight: CGFloat = 96
        let remainingHeight =
            Self.alignedModuleBodyHeight
            - measuredGlobalInfoCardHeight
            - heatmapHeight
            - (CodexExpandedMetrics.contentSpacing * 2)
        return max(CodexExpandedMetrics.emptyStateMinimumHeight, remainingHeight)
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .islandModuleCardSurface()
    }

    private func tokenHeatmapSectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .islandModuleCardSurface()
    }

    private func compactStatusBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color(red: 0.69, green: 0.98, blue: 0.76))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color(red: 0.19, green: 0.41, blue: 0.28).opacity(0.48), in: Capsule())
    }

    private func compactNeutralBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color(red: 0.14, green: 0.14, blue: 0.15), in: Capsule())
    }

    @ViewBuilder
    private func completedAppIconAccessory(for session: SessionSnapshot) -> some View {
        if let target = session.jumpTarget,
           !CodexTerminalAppRegistry.isCodexAppTarget(target) {
            CodexSessionAppIconView(target: target)
        }
    }

    private func completedActivityTitle(for session: SessionSnapshot) -> String {
        completedDisplayTitle(for: session)
    }

    private func completedActivityPromptLine(for session: SessionSnapshot) -> String? {
        guard let prompt = session.latestUserPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty else {
            return nil
        }

        return "You: \(prompt)"
    }

    private func completedActivityMessage(for session: SessionSnapshot) -> String {
        if let text = session.completionMessageMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        if let text = session.latestAssistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        if let text = session.assistantSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        return "Completed."
    }

    private func completedActivitySummary(for session: SessionSnapshot) -> String {
        if let text = session.latestAssistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        if let text = session.assistantSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        let fullMessage = completedActivityMessage(for: session)
        if fullMessage.count <= 140 {
            return fullMessage
        }

        let endIndex = fullMessage.index(fullMessage.startIndex, offsetBy: 140)
        return "\(fullMessage[..<endIndex])…"
    }

    private func completedWorkspaceName(for session: SessionSnapshot) -> String {
        if let workspace = session.jumpTarget?.workspaceName.trimmingCharacters(in: .whitespacesAndNewlines),
           !workspace.isEmpty {
            return workspace
        }

        let raw = URL(fileURLWithPath: session.cwd).lastPathComponent
        return raw.isEmpty ? "Codex" : raw
    }

    private func completedDisplayTitle(for session: SessionSnapshot) -> String {
        let trimmed = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return completedTitleTextWithoutWorkspace(trimmed, for: session)
        }

        return "Codex"
    }

    private func completedTitleTextWithoutWorkspace(_ title: String, for session: SessionSnapshot) -> String {
        let workspaceName = completedWorkspaceName(for: session)
        let fallbackTitle = "Codex · \(workspaceName)"
        if title == workspaceName || title == fallbackTitle {
            return "Codex"
        }

        let workspacePrefix = "\(workspaceName) · "
        if title.hasPrefix(workspacePrefix) {
            let cleaned = String(title.dropFirst(workspacePrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "Codex" : cleaned
        }

        return title
    }
}

private struct CodexTokenHeatmapView: View {
    let days: [CodexTokenUsageDay]
    let periodText: String
    let peakText: String

    @State private var hoveredDayID: Date?

    private let minCellSize: CGFloat = 6.5
    private let maxCellSize: CGFloat = 8.5
    private let preferredCellSpacing: CGFloat = 2.5
    private let rowCount = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Tokens")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(periodText)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)

                Text(peakText)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }

            heatmapGrid
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Codex token usage heatmap")
    }

    private var heatmapGrid: some View {
        GeometryReader { geometry in
            let columns = weekColumns
            let spacing = cellSpacing(for: geometry.size.width, columnCount: columns.count)
            let cellSize = cellSize(for: geometry.size.width, columnCount: columns.count, spacing: spacing)

            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: spacing) {
                        ForEach(0..<rowCount, id: \.self) { row in
                            let day = row < week.count ? week[row] : nil
                            tokenCell(day: day, row: row, cellSize: cellSize)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: gridHeight)
    }

    private var gridHeight: CGFloat {
        (maxCellSize * CGFloat(rowCount)) + (preferredCellSpacing * CGFloat(rowCount - 1))
    }

    @ViewBuilder
    private func tokenCell(day: CodexTokenUsageDay?, row: Int, cellSize: CGFloat) -> some View {
        let cornerRadius = max(1.5, cellSize * 0.18)

        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fillColor(for: day?.totalTokens ?? 0))
            .frame(width: cellSize, height: cellSize)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(day == nil ? 0 : 0.06), lineWidth: 0.5)
            }
            .overlay(alignment: .top) {
                if let day, hoveredDayID == day.id {
                    CodexTokenHeatmapTooltip(
                        dateText: day.date.formatted(.dateTime.month().day().year()),
                        tokenText: exactTokenText(day.totalTokens)
                    )
                    .offset(y: row < 2 ? cellSize + 7 : -34)
                    .allowsHitTesting(false)
                    .zIndex(20)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovering in
                guard let day else {
                    return
                }

                if isHovering {
                    hoveredDayID = day.id
                } else if hoveredDayID == day.id {
                    hoveredDayID = nil
                }
            }
            .zIndex(day.map { hoveredDayID == $0.id ? 10 : 0 } ?? 0)
    }

    private var weekColumns: [[CodexTokenUsageDay?]] {
        guard let firstDay = days.first else {
            return []
        }

        let calendar = Calendar.autoupdatingCurrent
        let weekday = calendar.component(.weekday, from: firstDay.date)
        let leadingEmptyDays = (weekday - calendar.firstWeekday + 7) % 7
        var paddedDays = Array(repeating: Optional<CodexTokenUsageDay>.none, count: leadingEmptyDays)
        paddedDays.append(contentsOf: days.map(Optional.some))

        let remainder = paddedDays.count % rowCount
        if remainder > 0 {
            paddedDays.append(contentsOf: Array(repeating: Optional<CodexTokenUsageDay>.none, count: rowCount - remainder))
        }

        return stride(from: 0, to: paddedDays.count, by: rowCount).map { startIndex in
            Array(paddedDays[startIndex..<min(startIndex + rowCount, paddedDays.count)])
        }
    }

    private var maxTokenCount: Int {
        max(days.map(\.totalTokens).max() ?? 0, 1)
    }

    private func cellSpacing(for width: CGFloat, columnCount: Int) -> CGFloat {
        guard columnCount > 1 else {
            return preferredCellSpacing
        }

        return max(2.5, min(preferredCellSpacing, width / 260))
    }

    private func cellSize(for width: CGFloat, columnCount: Int, spacing: CGFloat) -> CGFloat {
        guard columnCount > 0 else {
            return minCellSize
        }

        let availableWidth = max(0, width - (CGFloat(columnCount - 1) * spacing))
        return min(maxCellSize, max(minCellSize, availableWidth / CGFloat(columnCount)))
    }

    private func fillColor(for tokens: Int) -> Color {
        guard tokens > 0 else {
            return Color.white.opacity(0.055)
        }

        let ratio = Double(tokens) / Double(maxTokenCount)
        switch ratio {
        case ..<0.20:
            return Color.white.opacity(0.18)
        case ..<0.40:
            return Color.white.opacity(0.32)
        case ..<0.65:
            return Color.white.opacity(0.50)
        case ..<0.85:
            return Color.white.opacity(0.68)
        default:
            return Color.white.opacity(0.9)
        }
    }

    private func exactTokenText(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(formatted) tokens"
    }
}

private struct CodexTokenHeatmapTooltip: View {
    let dateText: String
    let tokenText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tokenText)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)

            Text(dateText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.50))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .fixedSize(horizontal: true, vertical: true)
    }
}
