import SwiftUI

struct XPostModuleContentView: View {
    @ObservedObject var model: XPostModuleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !model.configuredClientID.isEmpty, model.isAuthenticated {
                composer
            } else {
                setupState
            }

            feedback
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.10))

                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text("Twitter")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                Text(LocalizedStringKey(model.accountStatusText))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
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
            TextEditor(text: $model.draftText)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 116, maxHeight: 116)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.055))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(textEditorStrokeColor, lineWidth: 1)
                }

            HStack(spacing: 10) {
                Text(validationMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(validationTint)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(model.validation.weightedLength)/\(XPostTextValidator.maxWeightedLength)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(validationTint)

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
        if model.validation.isEmpty {
            return "Text-only posts. URLs, media, replies, and threads are not supported."
        }
        return "Ready to post text only."
    }

    private var validationTint: Color {
        if model.validation.containsURL || model.validation.isOverLimit {
            return Color.red.opacity(0.9)
        }
        if model.validation.isEmpty {
            return Color.white.opacity(0.48)
        }
        return Color.green.opacity(0.82)
    }

    private var textEditorStrokeColor: Color {
        if model.validation.containsURL || model.validation.isOverLimit {
            return Color.red.opacity(0.32)
        }

        return Color.white.opacity(0.06)
    }
}
