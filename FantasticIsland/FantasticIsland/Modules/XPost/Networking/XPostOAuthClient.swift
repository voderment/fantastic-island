import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Security

@MainActor
final class XPostOAuthClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    private enum Constants {
        static let authorizationURL = URL(string: "https://x.com/i/oauth2/authorize")!
        static let tokenURL = URL(string: "https://api.x.com/2/oauth2/token")!
    }

    private var activeSession: ASWebAuthenticationSession?

    func authorize(clientID: String) async throws -> XPostTokenBundle {
        guard activeSession == nil else {
            throw XPostModuleError.authorizationInProgress
        }

        let state = try Self.randomBase64URL(byteCount: 32)
        let codeVerifier = try Self.randomBase64URL(byteCount: 32)
        let codeChallenge = Self.codeChallenge(for: codeVerifier)
        let authorizationURL = try Self.authorizationURL(
            clientID: clientID,
            state: state,
            codeChallenge: codeChallenge
        )

        let callbackURL = try await authenticate(authorizationURL: authorizationURL)
        let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let queryItems = callbackComponents?.queryItems ?? []

        if let error = queryItems.value(named: "error") {
            throw XPostModuleError.authorizationFailed(error)
        }

        guard queryItems.value(named: "state") == state else {
            throw XPostModuleError.authorizationStateMismatch
        }

        guard let code = queryItems.value(named: "code"), !code.isEmpty else {
            throw XPostModuleError.authorizationMissingCode
        }

        return try await exchangeAuthorizationCode(
            code,
            clientID: clientID,
            codeVerifier: codeVerifier
        )
    }

    func refreshToken(clientID: String, refreshToken: String) async throws -> XPostTokenBundle {
        let refreshedTokenBundle = try await requestToken(
            formItems: [
                URLQueryItem(name: "grant_type", value: "refresh_token"),
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "refresh_token", value: refreshToken),
            ]
        )
        guard refreshedTokenBundle.refreshToken == nil else {
            return refreshedTokenBundle
        }

        return XPostTokenBundle(
            accessToken: refreshedTokenBundle.accessToken,
            refreshToken: refreshToken,
            tokenType: refreshedTokenBundle.tokenType,
            scope: refreshedTokenBundle.scope,
            expiresAt: refreshedTokenBundle.expiresAt
        )
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
    }

    private func authenticate(authorizationURL: URL) async throws -> URL {
        defer {
            activeSession = nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: XPostModuleSettings.callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                    return
                }

                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: XPostModuleError.authorizationCanceled)
                    return
                }

                continuation.resume(throwing: error ?? XPostModuleError.authorizationMissingCallback)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session

            if !session.start() {
                continuation.resume(throwing: XPostModuleError.authorizationCouldNotStart)
            }
        }
    }

    private func exchangeAuthorizationCode(
        _ code: String,
        clientID: String,
        codeVerifier: String
    ) async throws -> XPostTokenBundle {
        try await requestToken(
            formItems: [
                URLQueryItem(name: "grant_type", value: "authorization_code"),
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "redirect_uri", value: XPostModuleSettings.callbackURL.absoluteString),
                URLQueryItem(name: "code_verifier", value: codeVerifier),
                URLQueryItem(name: "code", value: code),
            ]
        )
    }

    private func requestToken(formItems: [URLQueryItem]) async throws -> XPostTokenBundle {
        struct TokenResponse: Decodable {
            let accessToken: String
            let refreshToken: String?
            let tokenType: String
            let expiresIn: TimeInterval?
            let scope: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case tokenType = "token_type"
                case expiresIn = "expires_in"
                case scope
            }
        }

        var request = URLRequest(url: Constants.tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = Self.formBody(from: formItems)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 300).contains(httpResponse.statusCode) {
            throw XPostHTTPError(
                statusCode: httpResponse.statusCode,
                responseText: String(decoding: data, as: UTF8.self)
            )
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return XPostTokenBundle(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            tokenType: tokenResponse.tokenType,
            scope: tokenResponse.scope,
            expiresAt: Date().addingTimeInterval(tokenResponse.expiresIn ?? 7_200)
        )
    }

    private static func authorizationURL(
        clientID: String,
        state: String,
        codeChallenge: String
    ) throws -> URL {
        var components = URLComponents(url: Constants.authorizationURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: XPostModuleSettings.callbackURL.absoluteString),
            URLQueryItem(name: "scope", value: XPostModuleSettings.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let url = components?.url else {
            throw XPostModuleError.invalidAuthorizationURL
        }

        return url
    }

    private static func randomBase64URL(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw XPostModuleError.randomGenerationFailed
        }

        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func formBody(from items: [URLQueryItem]) -> Data? {
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}

private extension Array where Element == URLQueryItem {
    func value(named name: String) -> String? {
        first { $0.name == name }?.value
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
