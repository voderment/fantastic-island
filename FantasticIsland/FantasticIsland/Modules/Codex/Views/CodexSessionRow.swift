import AppKit
import SwiftUI

struct CodexSessionAppIconView: View {
    let target: CodexTerminalJumpTarget
    let renderSize: CGFloat
    let displaySize: CGFloat
    let cornerRadius: CGFloat

    @State private var icon: NSImage?
    @State private var loadedKey = ""

    init(
        target: CodexTerminalJumpTarget,
        renderSize: CGFloat = 36,
        displaySize: CGFloat = 18,
        cornerRadius: CGFloat = 4
    ) {
        self.target = target
        self.renderSize = renderSize
        self.displaySize = displaySize
        self.cornerRadius = cornerRadius
        let key = Self.iconKey(for: target, renderSize: renderSize)
        _loadedKey = State(initialValue: key)
        _icon = State(initialValue: CodexTerminalAppRegistry.appIcon(for: target, size: renderSize))
    }

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: displaySize, height: displaySize)
                    .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
                    .accessibilityLabel(target.displayLabel)
            }
        }
        .onAppear(perform: refreshIconIfNeeded)
        .onChange(of: iconKey) { _, _ in
            refreshIconIfNeeded()
        }
    }

    private var iconKey: String {
        Self.iconKey(for: target, renderSize: renderSize)
    }

    private static func iconKey(for target: CodexTerminalJumpTarget, renderSize: CGFloat) -> String {
        let appKey = CodexTerminalAppRegistry.normalizedBundleIdentifier(for: target)
            ?? target.terminalApp.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(appKey)|\(Int(max(1, renderSize.rounded())))"
    }

    private func refreshIconIfNeeded() {
        guard loadedKey != iconKey else {
            return
        }

        loadedKey = iconKey
        icon = CodexTerminalAppRegistry.appIcon(for: target, size: renderSize)
    }
}

struct CodexIslandSessionRow: View {
    enum SurfaceStyle {
        case standard
        case peek
    }

    private enum StatusBadgeTone {
        case running
        case busy
        case completed
        case approval
        case question
        case neutral
    }

    let session: SessionSnapshot
    let referenceDate: Date
    var isActionable: Bool = false
    var surfaceStyle: SurfaceStyle = .standard
    var onApprove: ((CodexApprovalAction) -> Void)?
    var onAnswer: ((CodexQuestionResponse) -> Void)?
    var onReply: ((String) -> Void)?
    var onJump: (() -> Void)?

    @State private var isHighlighted = false
    @State private var replyText = ""
    @State private var selections: [String: Set<String>] = [:]

    private var presence: CodexIslandSessionPresence {
        CodexIslandSessionPresentation.presence(for: session, at: referenceDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            standardHeader

            if isActionable {
                actionableBody
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .islandModuleCardSurface(
            cornerRadius: IslandCardMetrics.moduleCardCornerRadius,
            fillColor: rowFillColor,
            strokeColor: borderColor
        )
        .contentShape(RoundedRectangle(cornerRadius: IslandCardMetrics.moduleCardCornerRadius, style: .continuous))
        .onTapGesture {
            onJump?()
        }
        .onHover { hovering in
            isHighlighted = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
    }

    private var borderColor: Color {
        if usesPeekStyle {
            return Color.white.opacity(isHighlighted ? 0.12 : 0.08)
        }

        if isActionable {
            return statusColor.opacity(isHighlighted ? 0.34 : 0.24)
        }

        return isHighlighted ? .white.opacity(0.14) : IslandCardMetrics.moduleCardStrokeColor
    }

    private var rowFillColor: Color {
        if usesPeekStyle {
            return Color.white.opacity(
                isHighlighted
                    ? min(CodexPeekMetrics.backgroundOpacity + 0.02, 0.16)
                    : CodexPeekMetrics.backgroundOpacity
            )
        }

        if isHighlighted {
            return Color.white.opacity(isActionable ? 0.075 : 0.065)
        }

        return isActionable ? Color.white.opacity(0.06) : IslandCardMetrics.moduleCardFillColor
    }

    private var standardHeader: some View {
        HStack(alignment: .top, spacing: headerRowSpacing) {
            statusDot
                .padding(.top, statusDotTopPadding)

            VStack(alignment: .leading, spacing: headerContentSpacing) {
                HStack(alignment: .top, spacing: headerContentSpacing) {
                    Text(headlineText)
                        .font(.system(size: headlineFontSize, weight: .semibold))
                        .foregroundStyle(headlineColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(0)

                    Spacer(minLength: titleTrailingSpacerMinLength)

                    HStack(spacing: badgeSpacing) {
                        compactBadge(toolLabel, tone: statusBadgeTone)
                        compactBadge(CodexIslandSessionPresentation.ageBadge(for: session, now: referenceDate))
                        appIconAccessory
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                }

                if showsPromptLineInHeader, let promptLineText {
                    Text(promptLineText)
                        .font(.system(size: promptFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(promptOpacity))
                        .lineLimit(1)
                }

                if showsActivityLineInHeader, let activityLineText {
                    Text(activityLineText)
                        .font(.system(size: activityFontSize, weight: .medium))
                        .foregroundStyle(activityColor.opacity(activityOpacity))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, headerHorizontalPadding)
        .padding(.vertical, headerVerticalPadding)
    }

    private var headlineText: String {
        if let prompt = session.latestUserPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            return "\(workspaceName) · \(prompt)"
        }
        return "\(workspaceName) · \(displayTitle)"
    }

    private var workspaceName: String {
        if let workspace = session.jumpTarget?.workspaceName.trimmingCharacters(in: .whitespacesAndNewlines),
           !workspace.isEmpty {
            return workspace
        }
        let raw = URL(fileURLWithPath: session.cwd).lastPathComponent
        return raw.isEmpty ? "Codex" : raw
    }

    private var displayTitle: String {
        let trimmed = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return "Codex"
    }

    private var toolLabel: String {
        if session.phase == .waitingForApproval {
            return "Approval"
        }
        if session.phase == .waitingForAnswer {
            return "Question"
        }
        if let currentTool = session.currentTool?.trimmingCharacters(in: .whitespacesAndNewlines),
           !currentTool.isEmpty {
            switch currentTool {
            case "exec_command", "Bash":
                return "Bash"
            case "apply_patch":
                return "Patch"
            case "write_stdin":
                return "Input"
            default:
                return currentTool.replacingOccurrences(of: "_", with: " ").localizedCapitalized
            }
        }

        switch session.phase {
        case .busy:
            return "Working"
        case .running:
            return "Thinking"
        case .completed:
            return "Completed"
        case .waitingForApproval:
            return "Approval"
        case .waitingForAnswer:
            return "Question"
        }
    }

    @ViewBuilder
    private var appIconAccessory: some View {
        if let target = session.jumpTarget {
            CodexSessionAppIconView(target: target)
        }
    }

    private var promptLineText: String? {
        if let prompt = session.latestUserPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            return "You: \(prompt)"
        }
        return nil
    }

    private var activityLineText: String? {
        if let request = session.permissionRequest?.summary.trimmingCharacters(in: .whitespacesAndNewlines),
           !request.isEmpty {
            return request
        }

        if let question = session.questionPrompt?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !question.isEmpty {
            return question
        }

        if let preview = session.currentCommandPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preview.isEmpty {
            return preview
        }

        if let assistant = session.latestAssistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !assistant.isEmpty {
            return assistant
        }

        if let summary = session.assistantSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            return summary
        }

        return session.phase.displayName
    }

    private var showsPromptLineInHeader: Bool {
        !(usesPeekStyle && session.phase.requiresAttention)
    }

    private var showsActivityLineInHeader: Bool {
        !(usesPeekStyle && session.phase.requiresAttention)
    }

    private var headlineColor: Color {
        presence == .inactive ? .white.opacity(0.78) : .white
    }

    private var statusColor: Color {
        if session.phase == .waitingForApproval {
            return .orange.opacity(0.94)
        }
        if session.phase == .waitingForAnswer {
            return .yellow.opacity(0.96)
        }

        switch presence {
        case .running:
            return Color(red: 0.34, green: 0.61, blue: 0.99)
        case .active:
            return Color(red: 0.29, green: 0.86, blue: 0.46)
        case .inactive:
            return .white.opacity(0.38)
        }
    }

    private var activityColor: Color {
        if session.phase.requiresAttention {
            return .orange.opacity(0.94)
        }
        if session.phase == .completed {
            return .white.opacity(presence == .inactive ? 0.46 : 0.58)
        }
        return statusColor
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: statusDotSize, height: statusDotSize)
    }

    private var usesPeekStyle: Bool {
        surfaceStyle == .peek
    }

    private var headerRowSpacing: CGFloat {
        usesPeekStyle ? CodexPeekMetrics.rowSpacing : 12
    }

    private var statusDotTopPadding: CGFloat {
        usesPeekStyle ? CodexPeekMetrics.statusDotTopPadding : 6
    }

    private var headerContentSpacing: CGFloat {
        usesPeekStyle ? CodexPeekMetrics.contentSpacing : 7
    }

    private var headlineFontSize: CGFloat {
        usesPeekStyle ? CodexPeekMetrics.titleFontSize : (isActionable ? 15 : 13.5)
    }

    private var titleTrailingSpacerMinLength: CGFloat {
        usesPeekStyle ? CodexPeekMetrics.titleTrailingSpacerMinLength : 6
    }

    private var badgeSpacing: CGFloat {
        usesPeekStyle ? CodexPeekMetrics.badgeSpacing : 6
    }

    private var promptFontSize: CGFloat {
        usesPeekStyle ? CodexPeekMetrics.promptFontSize : 11.5
    }

    private var promptOpacity: CGFloat {
        usesPeekStyle ? CodexPeekMetrics.promptOpacity : 0.62
    }

    private var activityFontSize: CGFloat {
        usesPeekStyle ? CodexPeekMetrics.summaryFontSize : 11
    }

    private var activityOpacity: CGFloat {
        usesPeekStyle ? CodexPeekMetrics.summaryOpacity : 0.94
    }

    private var headerHorizontalPadding: CGFloat {
        usesPeekStyle ? CodexPeekMetrics.cardHorizontalPadding : 16
    }

    private var headerVerticalPadding: CGFloat {
        usesPeekStyle ? CodexPeekMetrics.cardVerticalPadding : 14
    }

    private var statusDotSize: CGFloat {
        usesPeekStyle ? CodexPeekMetrics.statusDotSize : 9
    }

    private var statusBadgeTone: StatusBadgeTone {
        switch session.phase {
        case .running:
            return .running
        case .busy:
            return .busy
        case .completed:
            return .completed
        case .waitingForApproval:
            return .approval
        case .waitingForAnswer:
            return .question
        }
    }

    private func compactBadge(_ title: String, tone: StatusBadgeTone = .neutral) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(badgeForegroundColor(for: tone))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(badgeBackgroundColor(for: tone), in: Capsule())
    }

    private func badgeForegroundColor(for tone: StatusBadgeTone) -> Color {
        switch tone {
        case .running:
            return .white.opacity(0.96)
        case .busy:
            return .white.opacity(0.93)
        case .completed:
            return Color(red: 0.69, green: 0.98, blue: 0.76)
        case .approval:
            return Color(red: 1, green: 0.83, blue: 0.58)
        case .question:
            return Color(red: 1, green: 0.91, blue: 0.62)
        case .neutral:
            return presence == .inactive ? .white.opacity(0.42) : .white.opacity(0.62)
        }
    }

    private func badgeBackgroundColor(for tone: StatusBadgeTone) -> Color {
        switch tone {
        case .running:
            return Color.white.opacity(0.18)
        case .busy:
            return Color(red: 0.22, green: 0.36, blue: 0.62).opacity(0.42)
        case .completed:
            return Color(red: 0.19, green: 0.41, blue: 0.28).opacity(0.48)
        case .approval:
            return Color(red: 0.42, green: 0.27, blue: 0.06).opacity(0.56)
        case .question:
            return Color(red: 0.40, green: 0.33, blue: 0.07).opacity(0.56)
        case .neutral:
            return Color(red: 0.14, green: 0.14, blue: 0.15)
        }
    }

    @ViewBuilder
    private var actionableBody: some View {
        switch session.phase {
        case .waitingForApproval:
            if usesPeekStyle {
                peekApprovalActionBody
            } else {
                approvalActionBody
            }
        case .waitingForAnswer:
            if usesPeekStyle {
                peekQuestionActionBody
            } else {
                questionActionBody
            }
        case .completed:
            completionActionBody
        case .running, .busy:
            EmptyView()
        }
    }

    private var approvalActionBody: some View {
        let canResolve = session.canResolvePermission && onApprove != nil

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
                Text(toolLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(commandPreviewText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if let path = session.permissionRequest?.affectedPath.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    Text(path)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.08, blue: 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.orange.opacity(0.18))
            )

            HStack(spacing: 8) {
                Button(session.permissionRequest?.secondaryActionTitle ?? "No") {
                    onApprove?(.deny)
                }
                .buttonStyle(CodexWideButtonStyle(kind: .secondary))
                .disabled(!canResolve)

                Button(session.permissionRequest?.primaryActionTitle ?? "Yes") {
                    onApprove?(.allowOnce)
                }
                .buttonStyle(CodexWideButtonStyle(kind: .warning))
                .disabled(!canResolve)

                if let alwaysTitle = session.permissionRequest?.alwaysActionTitle {
                    Button(alwaysTitle) {
                        onApprove?(.allowAlways)
                    }
                    .buttonStyle(CodexWideButtonStyle(kind: .danger))
                    .disabled(!canResolve)
                }
            }
        }
    }

    private var commandPreviewText: String {
        if let preview = session.currentCommandPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preview.isEmpty {
            return "$ \(preview)"
        }
        if let summary = session.permissionRequest?.summary.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            return summary
        }
        return session.assistantSummary ?? "Approval required."
    }

    private var questionActionBody: some View {
        CodexStructuredQuestionPromptView(
            prompt: session.questionPrompt,
            selections: $selections,
            isEnabled: session.canAnswerQuestion && onAnswer != nil,
            onAnswer: { response in
                onAnswer?(response)
            }
        )
    }

    private var peekApprovalActionBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.permissionRequest?.title ?? "Approval Required")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.orange.opacity(0.96))
                .lineLimit(1)

            Text(compactApprovalSummary)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let preview = compactApprovalPreview {
                Text(preview)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if session.canResolvePermission, onApprove != nil {
                    Button(session.permissionRequest?.secondaryActionTitle ?? "No") {
                        onApprove?(.deny)
                    }
                    .buttonStyle(CodexWideButtonStyle(kind: .secondary))

                    Button(session.permissionRequest?.primaryActionTitle ?? "Yes") {
                        onApprove?(.allowOnce)
                    }
                    .buttonStyle(CodexWideButtonStyle(kind: .warning))
                }

                if onJump != nil {
                    Button(peekContinueButtonTitle) {
                        onJump?()
                    }
                    .buttonStyle(CodexWideButtonStyle(kind: .secondary))
                }
            }
        }
    }

    @ViewBuilder
    private var peekQuestionActionBody: some View {
        if let inlineQuestion = inlinePeekQuestion {
            VStack(alignment: .leading, spacing: 10) {
                Text(inlineQuestion.promptText)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.yellow.opacity(0.96))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    ForEach(inlineQuestion.options, id: \.self) { option in
                        Button(option) {
                            onAnswer?(inlineQuestion.response(for: option))
                        }
                        .buttonStyle(CodexWideButtonStyle(kind: .secondary))
                        .disabled(!(session.canAnswerQuestion && onAnswer != nil))
                    }

                    if onJump != nil {
                        Button(peekContinueButtonTitle) {
                            onJump?()
                        }
                        .buttonStyle(CodexWideButtonStyle(kind: .secondary))
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(session.questionPrompt?.title ?? "Codex needs your input.")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.yellow.opacity(0.96))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(compactQuestionSummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)

                if onJump != nil {
                    Button(peekContinueButtonTitle) {
                        onJump?()
                    }
                    .buttonStyle(CodexWideButtonStyle(kind: .secondary))
                }
            }
        }
    }

    private var completionActionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(completionPromptLabel)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text("DONE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.29, green: 0.86, blue: 0.46).opacity(0.96))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(.white.opacity(0.04))
                .frame(height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                CodexMarkdownText(value: completionMessageText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .frame(maxHeight: 260)

            if onReply != nil && session.canSendText {
                Rectangle()
                    .fill(.white.opacity(0.04))
                    .frame(height: 1)

                completionReplyInput
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }

    private var completionPromptLabel: String {
        if let prompt = session.latestUserPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            return "You: \(prompt)"
        }
        return "You:"
    }

    private var completionMessageText: String {
        if let text = session.completionMessageMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        if let text = session.latestAssistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        return session.assistantSummary ?? "Completed."
    }

    private var completionReplyInput: some View {
        HStack(spacing: 8) {
            CodexReplyTextField(
                placeholder: "Reply to session",
                text: $replyText,
                onSubmit: { submitReply() }
            )
            .frame(height: 32)

            Button {
                submitReply()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(replyText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? .white.opacity(0.2) : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func submitReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        replyText = ""
        onReply?(text)
    }

    private var compactApprovalSummary: String {
        if let summary = session.permissionRequest?.summary.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            return summary
        }
        if let assistant = session.assistantSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !assistant.isEmpty {
            return assistant
        }
        return "Codex is waiting for approval before continuing."
    }

    private var compactApprovalPreview: String? {
        if let preview = session.currentCommandPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preview.isEmpty {
            return "$ \(preview)"
        }
        return nil
    }

    private var compactQuestionSummary: String {
        guard let prompt = session.questionPrompt else {
            return "Continue in Codex to answer this prompt."
        }

        if prompt.questions.count > 1 {
            return "This step contains \(prompt.questions.count) prompts. Continue in Codex to answer them in sequence."
        }

        if let first = prompt.questions.first {
            if first.allowsCustomAnswer || first.isSecret || first.multiSelect || first.options.count > 3 {
                return "This prompt needs richer input than the notch should handle. Continue in Codex to respond."
            }
        }

        if prompt.options.count > 3 {
            return "This prompt has more options than the notch should show at once. Continue in Codex to respond."
        }

        return "Continue in Codex to answer this prompt."
    }

    private var peekContinueButtonTitle: String {
        if session.sessionSurface == .codexApp {
            return "Continue in Codex"
        }
        return "Open Session"
    }

    private var inlinePeekQuestion: InlinePeekQuestion? {
        guard session.canAnswerQuestion, onAnswer != nil,
              let prompt = session.questionPrompt else {
            return nil
        }

        if prompt.questions.count > 1 {
            return nil
        }

        if let item = prompt.questions.first {
            guard !item.allowsCustomAnswer,
                  !item.isSecret,
                  !item.multiSelect,
                  !item.options.isEmpty,
                  item.options.count <= 3 else {
                return nil
            }

            let labels = item.options.map(\.label)
            return InlinePeekQuestion(
                promptText: item.question,
                options: labels,
                responseBuilder: { option in
                    CodexQuestionResponse(answers: [item.id: [option]])
                }
            )
        }

        guard !prompt.options.isEmpty, prompt.options.count <= 3 else {
            return nil
        }

        return InlinePeekQuestion(
            promptText: prompt.title,
            options: prompt.options,
            responseBuilder: { option in
                CodexQuestionResponse(answer: option)
            }
        )
    }
}

private struct InlinePeekQuestion {
    let promptText: String
    let options: [String]
    let responseBuilder: (String) -> CodexQuestionResponse

    func response(for option: String) -> CodexQuestionResponse {
        responseBuilder(option)
    }
}

private struct CodexStructuredQuestionPromptView: View {
    let prompt: CodexQuestionPrompt?
    @Binding var selections: [String: Set<String>]
    var isEnabled: Bool
    let onAnswer: (CodexQuestionResponse) -> Void

    @State private var activeQuestionIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if questionItems.isEmpty,
               let title = prompt?.title.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.yellow.opacity(0.96))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if questionItems.isEmpty {
                HStack(spacing: 10) {
                    ForEach(prompt?.options.prefix(3) ?? [], id: \.self) { option in
                        Button(option) {
                            onAnswer(CodexQuestionResponse(answer: option))
                        }
                        .buttonStyle(CodexWideButtonStyle(kind: .secondary))
                        .disabled(!isEnabled)
                    }
                }
            } else if questionItems.count == 1, let item = questionItems.first {
                VStack(alignment: .leading, spacing: 12) {
                    questionItemView(item)

                    Button("Submit") {
                        onAnswer(CodexQuestionResponse(answers: answerMap))
                    }
                    .buttonStyle(CodexWideButtonStyle(kind: .primary))
                    .disabled(!isEnabled || !hasCompleteSelection)
                }
            } else {
                pagedQuestionFlow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: questionIDs) { _, _ in
            activeQuestionIndex = 0
        }
    }

    private var questionItems: [CodexQuestionItem] {
        prompt?.questions ?? []
    }

    private var questionIDs: [String] {
        questionItems.map(\.id)
    }

    private var answerMap: [String: [String]] {
        Dictionary(uniqueKeysWithValues: questionItems.compactMap { item in
            let selected = selectedLabels(for: item)
            guard !selected.isEmpty else {
                return nil
            }
            return (item.id, selected.sorted())
        })
    }

    private var hasCompleteSelection: Bool {
        questionItems.allSatisfy { !selectedLabels(for: $0).isEmpty }
    }

    private var currentQuestionIndex: Int {
        guard !questionItems.isEmpty else {
            return 0
        }

        return min(max(activeQuestionIndex, 0), questionItems.count - 1)
    }

    private var currentQuestion: CodexQuestionItem? {
        guard !questionItems.isEmpty else {
            return nil
        }

        return questionItems[currentQuestionIndex]
    }

    private var pagedQuestionFlow: some View {
        VStack(alignment: .leading, spacing: 14) {
            questionProgressHeader

            if let currentQuestion {
                questionItemView(currentQuestion)
            }

            HStack(spacing: 8) {
                Button {
                    activeQuestionIndex = max(currentQuestionIndex - 1, 0)
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(CodexQuestionNavigationButtonStyle())
                .disabled(!isEnabled || currentQuestionIndex == 0)

                Button {
                    if currentQuestionIndex == questionItems.count - 1 {
                        onAnswer(CodexQuestionResponse(answers: answerMap))
                    } else {
                        activeQuestionIndex = min(currentQuestionIndex + 1, questionItems.count - 1)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentQuestionIndex == questionItems.count - 1 ? "Submit" : "Next")
                        if currentQuestionIndex < questionItems.count - 1 {
                            Image(systemName: "chevron.right")
                        }
                    }
                }
                .buttonStyle(CodexQuestionNavigationButtonStyle(isPrimary: currentQuestionIndex == questionItems.count - 1))
                .disabled(!isEnabled || !canAdvanceCurrentQuestion)
            }
        }
    }

    private var questionProgressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Question \(currentQuestionIndex + 1) of \(questionItems.count)")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(answerMap.count)/\(questionItems.count) answered")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))

                    Capsule()
                        .fill(Color(red: 0.26, green: 0.45, blue: 0.86).opacity(0.95))
                        .frame(width: geometry.size.width * progressFraction)
                }
            }
            .frame(height: 3)
        }
    }

    private var progressFraction: CGFloat {
        guard !questionItems.isEmpty else {
            return 0
        }

        return CGFloat(currentQuestionIndex + 1) / CGFloat(questionItems.count)
    }

    private var canAdvanceCurrentQuestion: Bool {
        guard let currentQuestion else {
            return false
        }

        if currentQuestionIndex == questionItems.count - 1 {
            return hasCompleteSelection
        }

        return !selectedLabels(for: currentQuestion).isEmpty
    }

    private func selectedLabels(for item: CodexQuestionItem) -> Set<String> {
        selections[item.id] ?? []
    }

    private func questionItemView(_ item: CodexQuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !item.header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(item.header)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text(item.question)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(item.options.prefix(4), id: \.label) { option in
                    Button(option.label) {
                        toggle(option: option.label, for: item)
                    }
                    .buttonStyle(CodexQuestionChoiceButtonStyle(isSelected: selectedLabels(for: item).contains(option.label)))
                    .disabled(!isEnabled)
                }
            }
        }
    }

    private func toggle(option: String, for item: CodexQuestionItem) {
        var selected = selections[item.id] ?? []
        if item.multiSelect {
            if selected.contains(option) {
                selected.remove(option)
            } else {
                selected.insert(option)
            }
        } else {
            selected = selected.contains(option) ? [] : [option]
        }
        selections[item.id] = selected
    }
}

private struct CodexReplyTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                .font: NSFont.systemFont(ofSize: 13),
            ]
        )
        field.delegate = context.coordinator
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                guard !textView.hasMarkedText() else { return false }
                onSubmit()
                return true
            }
            return false
        }
    }
}

private struct CodexCompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.10), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct CodexCompactIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color(red: 0.14, green: 0.14, blue: 0.15), in: Capsule())
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct CodexWideButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case warning
        case danger
    }

    let kind: Kind

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(backgroundColor(configuration.isPressed), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? 1 : 0.42)
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return .white.opacity(0.48)
        }

        switch kind {
        case .primary, .warning, .danger:
            return .white
        case .secondary:
            return .white.opacity(0.88)
        }
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        if !isEnabled {
            return Color.white.opacity(0.08)
        }

        let pressedFactor: Double = isPressed ? 0.78 : 1.0
        switch kind {
        case .primary:
            return Color(red: 0.26, green: 0.45, blue: 0.86).opacity(pressedFactor)
        case .secondary:
            return Color.white.opacity(isPressed ? 0.12 : 0.16)
        case .warning:
            return Color(red: 0.85, green: 0.55, blue: 0.15).opacity(pressedFactor)
        case .danger:
            return Color(red: 0.82, green: 0.22, blue: 0.22).opacity(pressedFactor)
        }
    }
}

private struct CodexQuestionChoiceButtonStyle: ButtonStyle {
    let isSelected: Bool

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 12)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 1 : 0.75)
            }
            .opacity(isEnabled ? 1 : 0.46)
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return .white.opacity(0.46)
        }

        return isSelected ? .white : .white.opacity(0.86)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return Color.white.opacity(0.06)
        }

        if isSelected {
            return Color(red: 0.26, green: 0.45, blue: 0.86).opacity(isPressed ? 0.70 : 0.92)
        }

        return Color.white.opacity(isPressed ? 0.12 : 0.09)
    }

    private var borderColor: Color {
        isSelected ? Color.white.opacity(0.24) : Color.white.opacity(0.07)
    }
}

private struct CodexQuestionNavigationButtonStyle: ButtonStyle {
    var isPrimary = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? 1 : 0.38)
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return .white.opacity(0.44)
        }

        return isPrimary ? .white : .white.opacity(0.78)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return Color.white.opacity(0.06)
        }

        if isPrimary {
            return Color(red: 0.26, green: 0.45, blue: 0.86).opacity(isPressed ? 0.74 : 0.96)
        }

        return Color.white.opacity(isPressed ? 0.11 : 0.08)
    }
}

private struct CodexMarkdownText: View {
    let value: String

    var body: some View {
        if let attributed = try? AttributedString(markdown: value) {
            Text(attributed)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.90))
                .textSelection(.enabled)
        } else {
            Text(value)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.90))
                .textSelection(.enabled)
        }
    }
}
