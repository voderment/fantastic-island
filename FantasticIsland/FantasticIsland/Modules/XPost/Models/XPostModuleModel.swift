import Combine
import Foundation
import SwiftUI

enum XPostModuleError: LocalizedError, Equatable {
    case authorizationInProgress
    case authorizationCanceled
    case authorizationCouldNotStart
    case authorizationMissingCallback
    case authorizationMissingCode
    case authorizationStateMismatch
    case authorizationFailed(String)
    case invalidAuthorizationURL
    case randomGenerationFailed
    case missingClientID
    case notAuthenticated
    case refreshTokenUnavailable
    case invalidPostText

    var errorDescription: String? {
        switch self {
        case .authorizationInProgress:
            return "X authorization is already in progress."
        case .authorizationCanceled:
            return "X sign-in was canceled."
        case .authorizationCouldNotStart:
            return "X sign-in could not start."
        case .authorizationMissingCallback:
            return "X sign-in did not return a callback URL."
        case .authorizationMissingCode:
            return "X sign-in did not return an authorization code."
        case .authorizationStateMismatch:
            return "X sign-in returned an invalid state."
        case let .authorizationFailed(error):
            return "X sign-in failed: \(error)"
        case .invalidAuthorizationURL:
            return "X sign-in URL could not be created."
        case .randomGenerationFailed:
            return "Secure random generation failed."
        case .missingClientID:
            return "Add an X OAuth 2.0 Client ID in settings first."
        case .notAuthenticated:
            return "Sign in with X before posting."
        case .refreshTokenUnavailable:
            return "X session expired. Sign in again."
        case .invalidPostText:
            return "This post cannot be sent. Check the text length and remove URLs."
        }
    }
}

@MainActor
final class XPostModuleModel: ObservableObject, IslandModule {
    static let moduleID = "xpost"

    private static let preferredExpandedContentHeight: CGFloat =
        CodexIslandChromeMetrics.moduleChromeHeight + 204

    let id = XPostModuleModel.moduleID
    let title = "X Post"
    let symbolName = "square.and.pencil"
    let iconAssetName: String? = "Xicon"

    @Published var draftText = ""
    @Published private(set) var configuredClientID = XPostModuleSettings.clientID
    @Published private(set) var account = XPostModuleSettings.account
    @Published private(set) var hasToken = XPostModuleSettings.tokenBundle != nil
    @Published private(set) var isSigningIn = false
    @Published private(set) var isPosting = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastCreatedPostID: String?
    @Published private(set) var composerFocusRequestID: UUID?

    private let oauthClient = XPostOAuthClient()
    private let apiClient = XPostAPIClient()

    var collapsedSummaryItems: [CollapsedSummaryItem] {
        [
            CollapsedSummaryItem(
                id: "\(id).summary.status",
                moduleID: id,
                title: "Twitter",
                text: account?.displayHandle ?? (configuredClientID.isEmpty ? "Setup Required" : "Ready"),
                isEnabledByDefault: false
            ),
        ]
    }

    var taskActivityContribution: TaskActivityContribution {
        TaskActivityContribution()
    }

    var preferredOpenedContentHeight: CGFloat {
        Self.preferredExpandedContentHeight
    }

    var allowsInternalScrolling: Bool { false }

    var validation: XPostTextValidation {
        XPostTextValidator.validate(draftText)
    }

    var isAuthenticated: Bool {
        hasToken && account != nil
    }

    var accountStatusText: String {
        if let account {
            return "Signed in as \(account.displayName)"
        }

        if configuredClientID.isEmpty {
            return "Add your X OAuth Client ID to sign in."
        }

        return "Not signed in."
    }

    var postButtonTitle: String {
        isPosting ? "Posting..." : "Post"
    }

    var canSignIn: Bool {
        !configuredClientID.isEmpty && !isSigningIn && !isPosting
    }

    var canPost: Bool {
        !isPosting
            && !isSigningIn
            && isAuthenticated
            && validation.isValid
    }

    func makeRenderSnapshot(presentation: IslandModulePresentationContext) -> IslandModuleRenderSnapshot {
        IslandModuleRenderSnapshot(
            id: "\(id)::\(presentation.cacheKey)",
            moduleID: id,
            presentation: presentation,
            preferredHeight: preferredOpenedContentHeight,
            allowsInternalScrolling: allowsInternalScrolling,
            view: AnyView(XPostModuleContentView(model: self))
        )
    }

    func makeLiveContentView(presentation: IslandModulePresentationContext) -> AnyView {
        AnyView(XPostModuleContentView(model: self))
    }

    func updateConfiguredClientID(_ value: String) {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedValue != configuredClientID else {
            return
        }

        XPostModuleSettings.clientID = normalizedValue
        XPostModuleSettings.clearAuthentication()
        configuredClientID = normalizedValue
        account = nil
        hasToken = false
        lastCreatedPostID = nil
        statusMessage = normalizedValue.isEmpty ? nil : "Client ID updated. Sign in again."
        errorMessage = nil
    }

    func signIn() {
        guard canSignIn else {
            if configuredClientID.isEmpty {
                errorMessage = XPostModuleError.missingClientID.localizedDescription
            }
            return
        }

        isSigningIn = true
        errorMessage = nil
        statusMessage = "Opening X sign-in..."

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let tokenBundle = try await oauthClient.authorize(clientID: configuredClientID)
                XPostModuleSettings.tokenBundle = tokenBundle
                let resolvedAccount = try await apiClient.fetchCurrentUser(accessToken: tokenBundle.accessToken)
                XPostModuleSettings.account = resolvedAccount
                account = resolvedAccount
                hasToken = true
                statusMessage = "Signed in as \(resolvedAccount.displayHandle)."
                errorMessage = nil
            } catch {
                XPostModuleSettings.clearAuthentication()
                account = nil
                hasToken = false
                statusMessage = nil
                errorMessage = displayMessage(for: error)
            }

            isSigningIn = false
        }
    }

    func disconnect() {
        XPostModuleSettings.clearAuthentication()
        account = nil
        hasToken = false
        statusMessage = "Disconnected from X."
        errorMessage = nil
        lastCreatedPostID = nil
    }

    func requestComposerFocus() {
        composerFocusRequestID = UUID()
    }

    func markComposerFocusRequestHandled(_ requestID: UUID) {
        guard composerFocusRequestID == requestID else {
            return
        }

        composerFocusRequestID = nil
    }

    func submitPost() {
        let currentValidation = validation
        guard currentValidation.isValid else {
            errorMessage = XPostModuleError.invalidPostText.localizedDescription
            return
        }
        guard canPost else {
            errorMessage = isAuthenticated
                ? XPostModuleError.invalidPostText.localizedDescription
                : XPostModuleError.notAuthenticated.localizedDescription
            return
        }

        isPosting = true
        errorMessage = nil
        statusMessage = "Posting to X..."

        Task { @MainActor [weak self, postText = currentValidation.trimmedText] in
            guard let self else {
                return
            }

            do {
                let tokenBundle = try await validTokenBundle()
                let createdPost = try await createPostWithSingleRefreshRetry(
                    text: postText,
                    tokenBundle: tokenBundle
                )
                draftText = ""
                lastCreatedPostID = createdPost.id
                statusMessage = "Posted successfully."
                errorMessage = nil
            } catch {
                statusMessage = nil
                errorMessage = displayMessage(for: error)
            }

            isPosting = false
        }
    }

    private func createPostWithSingleRefreshRetry(
        text: String,
        tokenBundle: XPostTokenBundle
    ) async throws -> XPostCreatedPost {
        do {
            return try await apiClient.createPost(text: text, accessToken: tokenBundle.accessToken)
        } catch let error as XPostHTTPError where error.statusCode == 401 {
            let refreshedTokenBundle = try await refreshTokenBundle(from: tokenBundle)
            return try await apiClient.createPost(text: text, accessToken: refreshedTokenBundle.accessToken)
        }
    }

    private func validTokenBundle() async throws -> XPostTokenBundle {
        guard !configuredClientID.isEmpty else {
            throw XPostModuleError.missingClientID
        }

        guard let tokenBundle = XPostModuleSettings.tokenBundle else {
            throw XPostModuleError.notAuthenticated
        }

        if tokenBundle.shouldRefresh {
            return try await refreshTokenBundle(from: tokenBundle)
        }

        return tokenBundle
    }

    private func refreshTokenBundle(from tokenBundle: XPostTokenBundle) async throws -> XPostTokenBundle {
        guard let refreshToken = tokenBundle.refreshToken, !refreshToken.isEmpty else {
            XPostModuleSettings.clearAuthentication()
            account = nil
            hasToken = false
            throw XPostModuleError.refreshTokenUnavailable
        }

        let refreshedTokenBundle = try await oauthClient.refreshToken(
            clientID: configuredClientID,
            refreshToken: refreshToken
        )
        XPostModuleSettings.tokenBundle = refreshedTokenBundle
        hasToken = true
        return refreshedTokenBundle
    }

    private func displayMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}
