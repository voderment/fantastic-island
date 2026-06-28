import AppKit
import SwiftUI

struct XPostModuleContentView: View {
    @ObservedObject var model: XPostModuleModel
    @State private var isComposerFocused = false

    private let composerFieldHeight: CGFloat = 118

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
            GeometryReader { geometry in
                XPostComposerField(
                    text: $model.draftText,
                    placeholder: NSLocalizedString("What's happening?", comment: ""),
                    isEnabled: !model.isPosting && !model.isSigningIn,
                    isInvalid: model.validation.containsURL || model.validation.isOverLimit,
                    focusRequestID: model.composerFocusRequestID,
                    onFocusChange: { isComposerFocused = $0 },
                    onFocusRequestHandled: { model.markComposerFocusRequestHandled($0) },
                    onSubmit: submitFromComposer
                )
                .frame(width: max(0, geometry.size.width), height: composerFieldHeight)
            }
            .frame(maxWidth: .infinity, minHeight: composerFieldHeight, maxHeight: composerFieldHeight)
            .layoutPriority(1)

            composerFooter
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var composerFooter: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(LocalizedStringKey(footerMessage))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(footerTint)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Text("\(model.validation.weightedLength)/\(XPostTextValidator.maxWeightedLength)")
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(counterTint)
                .frame(minWidth: 46, alignment: .trailing)

            Button {
                model.submitPost()
            } label: {
                Text(LocalizedStringKey(model.postButtonTitle))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.black.opacity(model.canPost ? 0.9 : 0.48))
                    .frame(minWidth: 70, minHeight: 34)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(model.canPost ? 0.92 : 0.22))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!model.canPost)
        }
        .frame(minHeight: 34)
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

    private func submitFromComposer() {
        guard model.canPost else {
            return
        }

        model.submitPost()
    }
}

private struct XPostComposerField: NSViewRepresentable {
    @Binding var text: String

    let placeholder: String
    let isEnabled: Bool
    let isInvalid: Bool
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
        let textView = hostView.textView
        textView.delegate = context.coordinator
        hostView.onFocusChange = { [weak coordinator = context.coordinator] isFocused in
            coordinator?.setFocused(isFocused)
        }
        textView.onFocusChange = { [weak hostView] isFocused in
            hostView?.setFocused(isFocused)
        }
        hostView.configureTextView()
        hostView.update(
            text: text,
            placeholder: placeholder,
            isEnabled: isEnabled,
            isInvalid: isInvalid,
            isFocused: false
        )
        context.coordinator.textView = textView
        return hostView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let hostView = nsView as? XPostComposerHostView else {
            return
        }

        let textView = hostView.textView
        let isFocused = textView.window?.firstResponder === textView

        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEnabled
        hostView.update(
            text: text,
            placeholder: placeholder,
            isEnabled: isEnabled,
            isInvalid: isInvalid,
            isFocused: isFocused
        )
        context.coordinator.setFocused(isFocused)
        context.coordinator.focusIfNeeded(requestID: focusRequestID)
        hostView.needsLayout = true
    }

    private final class XPostComposerHostView: NSView {
        let textView = XPostNativeTextView(frame: .zero)
        var onFocusChange: ((Bool) -> Void)?

        private let placeholderLabel = NSTextField(labelWithString: "")

        private let horizontalInset: CGFloat = 16
        private let verticalInset: CGFloat = 14
        private var isInvalid = false
        private var isFocused = false
        private var isEnabled = true

        override var isFlipped: Bool { true }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.masksToBounds = true

            placeholderLabel.font = .systemFont(ofSize: 15, weight: .medium)
            placeholderLabel.isBezeled = false
            placeholderLabel.drawsBackground = false
            placeholderLabel.isEditable = false
            placeholderLabel.isSelectable = false
            placeholderLabel.lineBreakMode = .byTruncatingTail

            addSubview(textView)
            addSubview(placeholderLabel)
            updateAppearance()
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point) else {
                return nil
            }

            return self
        }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else {
                return
            }

            window?.makeFirstResponder(textView)
            setFocused(textView.window?.firstResponder === textView)
            textView.mouseDown(with: event)
        }

        override func layout() {
            super.layout()
            textView.frame = bounds
            placeholderLabel.frame = placeholderRect
            updateTextContainerSize()
        }

        func configureTextView() {
            textView.drawsBackground = false
            textView.isEditable = true
            textView.isSelectable = true
            textView.allowsUndo = true
            textView.isRichText = false
            textView.importsGraphics = false
            textView.font = .systemFont(ofSize: 15, weight: .medium)
            textView.textColor = NSColor.white.withAlphaComponent(0.94)
            textView.insertionPointColor = .white
            textView.focusRingType = .none
            textView.textContainerInset = NSSize(width: horizontalInset, height: verticalInset)
            textView.textContainer?.lineFragmentPadding = 0
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.heightTracksTextView = false
            textView.minSize = .zero
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width, .height]
            textView.backgroundColor = .clear
        }

        func update(
            text: String,
            placeholder: String,
            isEnabled: Bool,
            isInvalid: Bool,
            isFocused: Bool
        ) {
            if textView.string != text {
                textView.string = text
            }
            placeholderLabel.stringValue = placeholder
            placeholderLabel.isHidden = !text.isEmpty
            placeholderLabel.textColor = NSColor.white.withAlphaComponent(isFocused ? 0.36 : 0.28)
            textView.isEditable = isEnabled
            textView.textColor = NSColor.white.withAlphaComponent(isEnabled ? 0.94 : 0.48)

            self.isEnabled = isEnabled
            self.isInvalid = isInvalid
            setFocused(isFocused, notify: false)
            updateAppearance()
            needsLayout = true
        }

        func setFocused(_ focused: Bool, notify: Bool = true) {
            let didChange = isFocused != focused
            isFocused = focused
            updateAppearance()

            if notify, didChange {
                onFocusChange?(focused)
            }
        }

        private var placeholderRect: NSRect {
            NSRect(
                x: horizontalInset,
                y: verticalInset + 1,
                width: max(0, bounds.width - (horizontalInset * 2)),
                height: 22
            )
        }

        private func updateAppearance() {
            guard let layer else {
                return
            }

            layer.cornerRadius = 18
            layer.cornerCurve = .continuous
            layer.backgroundColor = NSColor.black.withAlphaComponent(isFocused ? 0.22 : 0.14).cgColor
            layer.borderWidth = isFocused ? 1.2 : 1
            layer.borderColor = borderColor.cgColor
            placeholderLabel.textColor = NSColor.white.withAlphaComponent(isFocused ? 0.36 : 0.28)
        }

        private var borderColor: NSColor {
            if isInvalid {
                return NSColor.systemRed.withAlphaComponent(isFocused ? 0.74 : 0.34)
            }

            if isFocused {
                return NSColor.white.withAlphaComponent(0.78)
            }

            return NSColor.white.withAlphaComponent(0.18)
        }

        private func updateTextContainerSize() {
            guard let textContainer = textView.textContainer else {
                return
            }

            textContainer.containerSize = NSSize(
                width: max(0, bounds.width - (horizontalInset * 2)),
                height: CGFloat.greatestFiniteMagnitude
            )
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
