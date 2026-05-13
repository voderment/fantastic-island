import AppKit
import SwiftUI

struct XPostModuleContentView: View {
    @ObservedObject var model: XPostModuleModel
    @State private var isComposerFocused = false

    private let composerTextInset = EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.configuredClientID.isEmpty, model.isAuthenticated {
                composer
            } else {
                setupState
            }

            feedback
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var setupState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(setupTitle))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))

            Text(LocalizedStringKey(setupDetail))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            if !model.configuredClientID.isEmpty {
                Button {
                    model.signIn()
                } label: {
                    Text(LocalizedStringKey(model.isSigningIn ? "Signing in..." : "Sign in with X"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.9))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(model.canSignIn ? 0.92 : 0.44))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!model.canSignIn)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                XPostComposerTextView(
                    text: $model.draftText,
                    isEnabled: !model.isPosting && !model.isSigningIn,
                    textInset: composerTextInset,
                    focusRequestID: model.composerFocusRequestID,
                    onFocusChange: { isComposerFocused = $0 },
                    onFocusRequestHandled: { model.markComposerFocusRequestHandled($0) },
                    onSubmit: submitFromComposer
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if model.draftText.isEmpty {
                    Text("What's happening?")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.34))
                        .padding(composerTextInset)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 116, maxHeight: 116)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isComposerFocused ? 0.072 : 0.055))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(composerStrokeColor, lineWidth: isComposerFocused ? 1.8 : 1)
            }
            .shadow(color: composerGlowColor, radius: isComposerFocused ? 7 : 0)

            HStack(spacing: 10) {
                Text(LocalizedStringKey(footerMessage))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(footerTint)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(model.validation.weightedLength)/\(XPostTextValidator.maxWeightedLength)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(counterTint)

                Button {
                    model.submitPost()
                } label: {
                    Text(LocalizedStringKey(model.postButtonTitle))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.9))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.white.opacity(model.canPost ? 0.92 : 0.36))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!model.canPost)
            }
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let errorMessage = model.errorMessage, !errorMessage.isEmpty {
            Text(LocalizedStringKey(errorMessage))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.red.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        } else if let statusMessage = model.statusMessage, !statusMessage.isEmpty {
            Text(LocalizedStringKey(statusMessage))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.green.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var setupTitle: String {
        model.configuredClientID.isEmpty ? "Client ID Required" : "Sign in Required"
    }

    private var setupDetail: String {
        model.configuredClientID.isEmpty
            ? "Configure your own X OAuth 2.0 Client ID in settings. Fantastic Island never uses maintainer API credits."
            : "Sign in once with X to allow Fantastic Island to publish text posts from the island."
    }

    private var validationMessage: String {
        if model.validation.containsURL {
            return "URLs are blocked in this version because X charges more for URL posts."
        }
        if model.validation.isOverLimit {
            return "Post is too long."
        }
        return model.accountStatusText
    }

    private var footerMessage: String {
        validationMessage
    }

    private var footerTint: Color {
        if model.validation.containsURL || model.validation.isOverLimit {
            return Color.red.opacity(0.9)
        }

        return Color.white.opacity(0.48)
    }

    private var counterTint: Color {
        if model.validation.containsURL || model.validation.isOverLimit {
            return Color.red.opacity(0.9)
        }

        return Color.white.opacity(0.62)
    }

    private var composerStrokeColor: Color {
        if model.validation.containsURL || model.validation.isOverLimit {
            return Color.red.opacity(isComposerFocused ? 0.74 : 0.32)
        }

        if isComposerFocused {
            return Color.white.opacity(0.78)
        }

        return Color.white.opacity(0.06)
    }

    private var composerGlowColor: Color {
        if model.validation.containsURL || model.validation.isOverLimit {
            return Color.red.opacity(isComposerFocused ? 0.28 : 0)
        }

        return Color.white.opacity(isComposerFocused ? 0.12 : 0)
    }

    private func submitFromComposer() {
        guard model.canPost else {
            return
        }

        model.submitPost()
    }
}

private struct XPostComposerTextView: NSViewRepresentable {
    @Binding var text: String

    let isEnabled: Bool
    let textInset: EdgeInsets
    let focusRequestID: UUID?
    let onFocusChange: (Bool) -> Void
    let onFocusRequestHandled: (UUID) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onFocusChange: onFocusChange,
            onFocusRequestHandled: onFocusRequestHandled,
            onSubmit: onSubmit
        )
    }

    func makeNSView(context: Context) -> NSView {
        let hostView = XPostComposerHostView()
        let scrollView = hostView.scrollView
        scrollView.drawsBackground = false
        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScroller = nil
        scrollView.horizontalScroller = nil
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layer?.backgroundColor = NSColor.clear.cgColor

        let textView = XPostNativeTextView()
        textView.delegate = context.coordinator
        textView.onFocusChange = { [weak coordinator = context.coordinator] isFocused in
            coordinator?.setFocused(isFocused)
        }
        textView.drawsBackground = false
        textView.isEditable = isEnabled
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.string = text
        textView.font = .systemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor.white.withAlphaComponent(0.94)
        textView.insertionPointColor = .white
        textView.wantsLayer = true
        textView.layer?.backgroundColor = NSColor.clear.cgColor
        textView.textContainerInset = NSSize(
            width: textInset.leading,
            height: textInset.top
        )
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.backgroundColor = .clear

        hostView.setDocumentView(textView)
        context.coordinator.textView = textView
        return hostView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let hostView = nsView as? XPostComposerHostView else {
            return
        }

        let scrollView = hostView.scrollView
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEnabled
        textView.textColor = NSColor.white.withAlphaComponent(isEnabled ? 0.94 : 0.48)
        textView.textContainerInset = NSSize(
            width: textInset.leading,
            height: textInset.top
        )
        context.coordinator.setFocused(textView.window?.firstResponder === textView)
        context.coordinator.focusIfNeeded(requestID: focusRequestID)
        hostView.needsLayout = true
    }

    private final class XPostComposerHostView: NSView {
        let scrollView = XPostComposerScrollView()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            scrollView.frame = bounds
            scrollView.autoresizingMask = [.width, .height]
            addSubview(scrollView)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func layout() {
            super.layout()
            scrollView.frame = bounds
            scrollView.layoutSubtreeIfNeeded()
        }

        func setDocumentView(_ textView: NSTextView) {
            scrollView.documentView = textView
            needsLayout = true
        }
    }

    private final class XPostComposerScrollView: NSScrollView {
        override func layout() {
            super.layout()
            updateDocumentFrame()
        }

        private func updateDocumentFrame() {
            guard let textView = documentView as? NSTextView else {
                return
            }

            let visibleSize = contentView.bounds.size
            guard visibleSize.width > 0, visibleSize.height > 0 else {
                return
            }

            var targetFrame = textView.frame
            targetFrame.origin = .zero
            targetFrame.size.width = visibleSize.width
            targetFrame.size.height = max(visibleSize.height, measuredTextHeight(for: textView))

            if abs(textView.frame.width - targetFrame.width) > 0.5 ||
                abs(textView.frame.height - targetFrame.height) > 0.5 ||
                textView.frame.origin != targetFrame.origin {
                textView.frame = targetFrame
            }
        }

        private func measuredTextHeight(for textView: NSTextView) -> CGFloat {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return contentView.bounds.height
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            return ceil(usedRect.height + textView.textContainerInset.height * 2)
        }
    }

    private final class XPostNativeTextView: NSTextView {
        var onFocusChange: ((Bool) -> Void)?

        override func becomeFirstResponder() -> Bool {
            let didBecomeFirstResponder = super.becomeFirstResponder()
            if didBecomeFirstResponder {
                onFocusChange?(true)
            }
            return didBecomeFirstResponder
        }

        override func resignFirstResponder() -> Bool {
            let didResignFirstResponder = super.resignFirstResponder()
            if didResignFirstResponder {
                onFocusChange?(false)
            }
            return didResignFirstResponder
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        let onFocusChange: (Bool) -> Void
        let onFocusRequestHandled: (UUID) -> Void
        let onSubmit: () -> Void
        weak var textView: NSTextView?

        private var handledFocusRequestID: UUID?
        private var isFocused = false

        init(
            text: Binding<String>,
            onFocusChange: @escaping (Bool) -> Void,
            onFocusRequestHandled: @escaping (UUID) -> Void,
            onSubmit: @escaping () -> Void
        ) {
            self.text = text
            self.onFocusChange = onFocusChange
            self.onFocusRequestHandled = onFocusRequestHandled
            self.onSubmit = onSubmit
        }

        func setFocused(_ focused: Bool) {
            guard isFocused != focused else {
                return
            }

            isFocused = focused
            onFocusChange(focused)
        }

        func focusIfNeeded(requestID: UUID?) {
            guard let requestID,
                  handledFocusRequestID != requestID,
                  let textView else {
                return
            }

            handledFocusRequestID = requestID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self, weak textView] in
                guard let self,
                      let textView else {
                    return
                }

                textView.window?.makeFirstResponder(textView)
                setFocused(textView.window?.firstResponder === textView)
                onFocusRequestHandled(requestID)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text.wrappedValue = textView.string
        }

        func textDidBeginEditing(_ notification: Notification) {
            setFocused(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            setFocused(false)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            if textView.hasMarkedText() {
                return false
            }

            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            if modifiers.contains(.shift) || modifiers.contains(.option) {
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }

            onSubmit()
            return true
        }
    }
}
