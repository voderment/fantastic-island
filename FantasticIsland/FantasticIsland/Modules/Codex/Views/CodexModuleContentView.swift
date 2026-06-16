import SwiftUI

private struct GlobalInfoCardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct CodexModuleRenderState {
    let presentation: IslandModulePresentationContext
    let activityState: AgentActivityState
    let sessionSurface: CodexIslandSurface
    let isNotificationMode: Bool
    let islandListSessions: [SessionSnapshot]
    let sessionListTotalCount: Int
    let activeNotificationSession: SessionSnapshot?
    let selectedConversationSession: SessionSnapshot?
    let presentedSession: SessionSnapshot?
    let shouldShowShowAllButton: Bool
    let canCollapseSessionList: Bool
    let globalInfoLiveCountText: String
    let globalInfoFiveHourValueText: String
    let globalInfoWeekValueText: String
    let globalInfoFiveHourResetCompactText: String
    let globalInfoWeekResetCompactText: String
    let providerQuotaItems: [AgentProviderQuotaDisplayItem]
    let hookDiagnosticItems: [AgentHookProviderDiagnostic]
    let hookDiagnosticsSummaryText: String
    let hookDiagnosticsHasProblems: Bool
    let tokenUsageHeatmapDays: [CodexTokenUsageDay]
    let tokenUsageHeatmapPeriodText: String
    let tokenUsageHeatmapPeakText: String
    let approvePermission: (String, CodexApprovalAction) -> Void
    let answerQuestion: (String, CodexQuestionResponse) -> Void
    let canReplyToSession: (SessionSnapshot) -> Bool
    let replyPlaceholder: (SessionSnapshot) -> String
    let replyToSession: (String, String) -> Void
    let transcriptTurnsForSession: (SessionSnapshot) -> [AgentTranscriptTurn]
    let openConversation: (String) -> Void
    let openSessionApp: (String) -> Void
    let showNewSession: () -> Void
    let startNewSession: (AgentNewSessionRequest) -> Void
    let showAllSessions: () -> Void
    let collapseSessionList: () -> Void
}

struct AgentProviderQuotaDisplayItem: Identifiable {
    let id: AgentProvider
    let title: String
    let fiveHourText: String
    let weekText: String
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
    @State private var newSessionProvider = AgentProvider.codex
    @State private var newSessionPath = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var newSessionPrompt = ""
    @State private var conversationReplyText = ""
    @State private var conversationAnswerText = ""

    private static let estimatedGlobalInfoCardHeight: CGFloat = 58
    private static let alignedModuleBodyHeight: CGFloat =
        176
        - CodexIslandChromeMetrics.moduleNavigationRowHeight
        - CodexIslandChromeMetrics.moduleColumnSpacing
    private static let providerGridColumns = [
        GridItem(.adaptive(minimum: 72), spacing: 8)
    ]

    var body: some View {
        switch state.presentation {
        case .standard:
            VStack(alignment: .leading, spacing: 6) {
                if case .newSession = state.sessionSurface {
                    newSessionCard
                } else if let session = state.selectedConversationSession {
                    conversationDetail(for: session)
                } else {
                    agentsHeaderBar
                    hookDiagnosticsStrip
                    sessionList
                    providerQuotaFooter
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
                    canReply: state.canReplyToSession(session),
                    replyPlaceholder: state.replyPlaceholder(session),
                    onApprove: { state.approvePermission(session.id, $0) },
                    onAnswer: { state.answerQuestion(session.id, $0) },
                    onReply: { state.replyToSession(session.id, $0) },
                    onOpenConversation: { state.openConversation(session.id) },
                    onOpenApp: { state.openSessionApp(session.id) }
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
                    canReply: state.canReplyToSession(session),
                    replyPlaceholder: state.replyPlaceholder(session),
                    onApprove: { state.approvePermission(session.id, $0) },
                    onAnswer: { state.answerQuestion(session.id, $0) },
                    onReply: { state.replyToSession(session.id, $0) },
                    onOpenConversation: { state.openConversation(session.id) },
                    onOpenApp: { state.openSessionApp(session.id) }
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

            Text(completedActivityMessage(for: session))
                .font(.system(size: CodexExpandedMetrics.summaryFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .textSelection(.enabled)
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
            state.openConversation(session.id)
        }
    }

    @ViewBuilder
    private var sessionList: some View {
        if state.isNotificationMode, let session = state.activeNotificationSession {
            CodexIslandSessionRow(
                session: session,
                referenceDate: .now,
                isActionable: true,
                canReply: state.canReplyToSession(session),
                replyPlaceholder: state.replyPlaceholder(session),
                onApprove: { state.approvePermission(session.id, $0) },
                onAnswer: { state.answerQuestion(session.id, $0) },
                onReply: { state.replyToSession(session.id, $0) },
                onOpenConversation: { state.openConversation(session.id) },
                onOpenApp: { state.openSessionApp(session.id) }
            )

            if state.shouldShowShowAllButton {
                Button("Show all \(state.sessionListTotalCount) sessions") {
                    state.showAllSessions()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
        } else {
            VStack(spacing: 0) {
                if state.islandListSessions.isEmpty {
                    emptyStateCard
                }

                ForEach(state.islandListSessions) { session in
                    CodexIslandSessionRow(
                        session: session,
                        referenceDate: .now,
                        isActionable: false,
                        canReply: state.canReplyToSession(session),
                        replyPlaceholder: state.replyPlaceholder(session),
                        onApprove: { state.approvePermission(session.id, $0) },
                        onAnswer: { state.answerQuestion(session.id, $0) },
                        onReply: { state.replyToSession(session.id, $0) },
                        onOpenConversation: { state.openConversation(session.id) },
                        onOpenApp: { state.openSessionApp(session.id) }
                    )
                }
            }
        }
    }

    private var agentsHeaderBar: some View {
        sectionCard {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Text("Agents")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                liveCountBadge
                sessionScopeButton

                Spacer(minLength: 0)

                Button {
                    state.showNewSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.82))
                .background(Color.white.opacity(0.075), in: Circle())
                .help("New Session")
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

    @ViewBuilder
    private var providerQuotaFooter: some View {
        if !state.providerQuotaItems.isEmpty {
            providerQuotaStrip
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private var liveCountBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.activityState.activeSessionCount > 0 ? Color.green.opacity(0.95) : Color.white.opacity(0.22))
                .frame(width: 7, height: 7)

            Text("\(state.globalInfoLiveCountText) active")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(state.activityState.activeSessionCount > 0 ? Color.green.opacity(0.95) : Color.white.opacity(0.52))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    @ViewBuilder
    private var sessionScopeButton: some View {
        if state.shouldShowShowAllButton {
            Button {
                state.showAllSessions()
            } label: {
                Text("All \(state.sessionListTotalCount)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.68))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.055), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Show all active agent sessions")
        } else if shouldOfferTopSessionsButton {
            Button {
                state.collapseSessionList()
            } label: {
                Text("Top")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.54))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.04), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Show top active agent sessions")
        }
    }

    private var shouldOfferTopSessionsButton: Bool {
        state.canCollapseSessionList
            && !state.isNotificationMode
            && state.sessionListTotalCount > CodexIslandSessionPresentation.compactOverviewSessionLimit
            && state.islandListSessions.count == state.sessionListTotalCount
    }

    @ViewBuilder
    private var hookDiagnosticsStrip: some View {
        if !state.hookDiagnosticItems.isEmpty, state.hookDiagnosticsHasProblems {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(state.hookDiagnosticItems) { item in
                        hookDiagnosticPill(item)
                    }
                }

                Spacer(minLength: 0)

                Text(state.hookDiagnosticsSummaryText.uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(hookDiagnosticsSummaryTint)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Agent hook diagnostics \(state.hookDiagnosticsSummaryText)")
        }
    }

    private func hookDiagnosticPill(_ item: AgentHookProviderDiagnostic) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(hookDiagnosticTint(item))
                .frame(width: 6, height: 6)

            Text(item.provider.quotaShortName)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Color.white.opacity(item.isHealthy ? 0.045 : 0.075), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .help("\(item.provider.displayName): \(item.statusText)")
    }

    private var hookDiagnosticsSummaryTint: Color {
        state.hookDiagnosticsHasProblems ? Color.orange.opacity(0.84) : Color.green.opacity(0.8)
    }

    private func hookDiagnosticTint(_ item: AgentHookProviderDiagnostic) -> Color {
        switch (item.hookState, item.usageBridgeState) {
        case (.installed, .managed), (.installed, .unsupported):
            return Color.green.opacity(0.9)
        case (.installed, .custom):
            return Color.yellow.opacity(0.9)
        case (.installed, .missing):
            return Color.orange.opacity(0.9)
        case (.missing, _):
            return Color.white.opacity(0.28)
        case (.invalidConfig, _), (_, .invalidConfig):
            return Color.red.opacity(0.92)
        }
    }

    private var providerQuotaStrip: some View {
        HStack(spacing: 5) {
            Text("5H/W")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.36))
                .lineLimit(1)
                .frame(width: 30, alignment: .leading)

            ForEach(state.providerQuotaItems) { item in
                providerQuotaPill(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Provider five hour and weekly limits")
    }

    private func providerQuotaPill(_ item: AgentProviderQuotaDisplayItem) -> some View {
        HStack(spacing: 3) {
            Text(item.title)
                .foregroundStyle(.white.opacity(0.74))

            Text("\(item.fiveHourText)/\(item.weekText)")
                .foregroundStyle(.white.opacity(item.fiveHourText == "--" && item.weekText == "--" ? 0.35 : 0.62))
                .minimumScaleFactor(0.72)
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .lineLimit(1)
        .padding(.horizontal, 5)
        .padding(.vertical, 3.5)
        .frame(maxWidth: .infinity, minHeight: 20)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
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

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("No live conversations")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))

            Text("Start or open an agent session to populate the island.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.32))

            Button {
                state.showNewSession()
            } label: {
                Label("New Session", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .center)
        .padding(.horizontal, 18)
        .background(Color.white.opacity(0.012))
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.05)).frame(height: 1)
        }
    }

    private func conversationDetail(for session: SessionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    state.showAllSessions()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.78))
                .help("Back to conversations")

                VStack(alignment: .leading, spacing: 3) {
                    Text(conversationTitle(for: session))
                        .font(IslandVisualLanguage.islandTitle(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(session.provider.displayName) · \(conversationWorkspace(for: session))")
                        .font(IslandVisualLanguage.islandLabel(10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    state.openSessionApp(session.id)
                } label: {
                    Label("Open App", systemImage: "arrow.up.forward.app")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.82))
                .islandGlassCapsule()
                .help("Open \(session.provider.displayName)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(.white.opacity(0.055))
                .frame(height: 1)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    let turns = state.transcriptTurnsForSession(session)
                    if turns.isEmpty {
                        if let prompt = session.latestUserPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
                            conversationBubble(label: "You", text: prompt, isUser: true, role: .user)
                        }
                        if let body = conversationBody(for: session) {
                            conversationBubble(label: session.provider.compactName, text: body, isUser: false, role: .assistant)
                        }
                    } else {
                        ForEach(turns) { turn in
                            conversationBubble(
                                label: conversationLabel(for: turn),
                                text: turn.text,
                                isUser: turn.role == .user,
                                role: turn.role
                            )
                        }
                    }

                    if session.phase == .waitingForApproval, let request = session.permissionRequest {
                        approvalPanel(session: session, request: request)
                    }

                    if session.phase == .waitingForAnswer, let prompt = session.questionPrompt {
                        questionPanel(session: session, prompt: prompt)
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 560)

            Rectangle()
                .fill(.white.opacity(0.055))
                .frame(height: 1)

            if state.canReplyToSession(session) {
                replyComposer(for: session)
            } else {
                unsupportedReplyFooter(for: session)
            }
        }
        .islandModuleCardSurface()
    }

    private var newSessionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    state.showAllSessions()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.78))

                Text("New Session")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()
            }

            LazyVGrid(columns: Self.providerGridColumns, alignment: .leading, spacing: 8) {
                ForEach(AgentProvider.allCases) { provider in
                    Button {
                        newSessionProvider = provider
                    } label: {
                        Label(provider.compactName, systemImage: provider.symbolName)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(AgentProviderChoiceButtonStyle(isSelected: newSessionProvider == provider))
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Workspace")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
                TextField("Workspace path", text: $newSessionPath)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Opening Prompt")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
                TextField(newSessionProvider.canLaunchWithPromptInTerminal ? "Optional prompt" : "Prompt is copied after the workspace opens", text: $newSessionPrompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Button {
                state.startNewSession(AgentNewSessionRequest(
                    provider: newSessionProvider,
                    workingDirectory: newSessionPath,
                    initialPrompt: newSessionPrompt
                ))
            } label: {
                Label("Start \(newSessionProvider.displayName)", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AgentPrimaryButtonStyle())
        }
        .padding(14)
        .islandModuleCardSurface()
    }

    private func approvalPanel(session: SessionSnapshot, request: CodexPermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(request.title)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(.orange.opacity(0.96))

            Text(request.summary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(request.secondaryActionTitle) {
                    state.approvePermission(session.id, .deny)
                }
                .buttonStyle(AgentInlineButtonStyle())

                Button(request.primaryActionTitle) {
                    state.approvePermission(session.id, .allowOnce)
                }
                .buttonStyle(AgentInlineButtonStyle(isProminent: true))
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func questionPanel(session: SessionSnapshot, prompt: CodexQuestionPrompt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prompt.title)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(.yellow.opacity(0.96))
                .fixedSize(horizontal: false, vertical: true)

            if !prompt.options.isEmpty {
                HStack(spacing: 8) {
                    ForEach(prompt.options.prefix(3), id: \.self) { option in
                        Button(option) {
                            state.answerQuestion(session.id, CodexQuestionResponse(answer: option))
                        }
                        .buttonStyle(AgentInlineButtonStyle())
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Type an answer", text: $conversationAnswerText)
                    .textFieldStyle(.plain)
                    .font(IslandVisualLanguage.islandBody(12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .islandGlassPanel(cornerRadius: 8)

                Button {
                    let answer = conversationAnswerText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !answer.isEmpty else { return }
                    conversationAnswerText = ""
                    state.answerQuestion(session.id, CodexQuestionResponse(answer: answer))
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(12)
        .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func replyComposer(for session: SessionSnapshot) -> some View {
        let placeholder = state.replyPlaceholder(session)

        return HStack(spacing: 8) {
            TextField(placeholder, text: $conversationReplyText)
                .textFieldStyle(.plain)
                .font(IslandVisualLanguage.islandBody(12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            Button {
                let reply = conversationReplyText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !reply.isEmpty else { return }
                conversationReplyText = ""
                state.replyToSession(session.id, reply)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.9))
            .disabled(conversationReplyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.025))
    }

    private func unsupportedReplyFooter(for session: SessionSnapshot) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.54))

            Text(state.replyPlaceholder(session))
                .font(IslandVisualLanguage.islandBody(11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                state.openSessionApp(session.id)
            } label: {
                Text("Open App")
                    .font(IslandVisualLanguage.islandLabel(10.5, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.82))
            .islandGlassCapsule()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.025))
    }

    private func conversationBubble(label: String, text: String, isUser: Bool, role: AgentTranscriptTurn.Role) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(IslandVisualLanguage.islandLabel(10, weight: .bold))
                .foregroundStyle(conversationAccent(for: role).opacity(0.82))
            Text(text)
                .font(IslandVisualLanguage.islandBody(12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    conversationAccent(for: role).opacity(isUser ? 0.15 : 0.09),
                    Color.white.opacity(isUser ? 0.065 : 0.04),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(conversationAccent(for: role).opacity(isUser ? 0.22 : 0.13), lineWidth: 0.75)
        }
    }

    private func conversationAccent(for role: AgentTranscriptTurn.Role) -> Color {
        switch role {
        case .user:
            return Color(red: 0.72, green: 0.82, blue: 1.0)
        case .assistant:
            return IslandVisualLanguage.accent
        case .tool:
            return Color(red: 1.0, green: 0.74, blue: 0.38)
        case .system:
            return Color.white.opacity(0.72)
        }
    }

    private func conversationLabel(for turn: AgentTranscriptTurn) -> String {
        switch turn.role {
        case .user:
            return "You"
        case .assistant:
            return turn.toolName == nil ? "Assistant" : "Assistant"
        case .tool:
            return turn.toolName ?? "Tool"
        case .system:
            return "System"
        }
    }

    private func conversationTitle(for session: SessionSnapshot) -> String {
        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? session.provider.displayName : title
    }

    private func conversationWorkspace(for session: SessionSnapshot) -> String {
        if let workspace = session.jumpTarget?.workspaceName.trimmingCharacters(in: .whitespacesAndNewlines),
           !workspace.isEmpty {
            return workspace
        }

        let name = URL(fileURLWithPath: session.cwd).lastPathComponent
        return name.isEmpty ? session.provider.displayName : name
    }

    private func conversationBody(for session: SessionSnapshot) -> String? {
        [
            session.completionMessageMarkdown,
            session.latestAssistantMessage,
            session.assistantSummary,
            session.currentCommandPreview,
            session.phase.displayName,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    }

    private var emptyStateMinimumHeight: CGFloat {
        let remainingHeight =
            Self.alignedModuleBodyHeight
            - measuredGlobalInfoCardHeight
            - CodexExpandedMetrics.contentSpacing
        return max(CodexExpandedMetrics.emptyStateMinimumHeight, remainingHeight)
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.018))
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.055)).frame(height: 1)
        }
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
           !CodexTerminalAppRegistry.isProviderAppTarget(target) {
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
        return raw.isEmpty ? session.provider.displayName : raw
    }

    private func completedDisplayTitle(for session: SessionSnapshot) -> String {
        let trimmed = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return completedTitleTextWithoutWorkspace(trimmed, for: session)
        }

        return session.provider.displayName
    }

    private func completedTitleTextWithoutWorkspace(_ title: String, for session: SessionSnapshot) -> String {
        let workspaceName = completedWorkspaceName(for: session)
        let fallbackTitle = "\(session.provider.displayName) · \(workspaceName)"
        if title == workspaceName || title == fallbackTitle {
            return session.provider.displayName
        }

        let workspacePrefix = "\(workspaceName) · "
        if title.hasPrefix(workspacePrefix) {
            let cleaned = String(title.dropFirst(workspacePrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? session.provider.displayName : cleaned
        }

        return title
    }
}

private struct AgentProviderChoiceButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity, minHeight: 34)
            .padding(.horizontal, 8)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.08), lineWidth: 1)
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isSelected {
            return Color.white.opacity(isPressed ? 0.18 : 0.14)
        }

        return Color.white.opacity(isPressed ? 0.10 : 0.06)
    }
}

private struct AgentPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 11)
            .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
    }
}

private struct AgentInlineButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white.opacity(isProminent ? 0.96 : 0.82))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isProminent {
            return Color.white.opacity(isPressed ? 0.20 : 0.15)
        }

        return Color.white.opacity(isPressed ? 0.12 : 0.09)
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
        .accessibilityLabel("Agent token usage heatmap")
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
            .scaleEffect(hoveredDayID == day?.id ? 1.08 : 1, anchor: .center)
            .animation(.easeOut(duration: 0.12), value: hoveredDayID)
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
