import Foundation

struct XPostTokenBundle: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let scope: String?
    let expiresAt: Date

    var shouldRefresh: Bool {
        Date() >= expiresAt.addingTimeInterval(-90)
    }
}

struct XPostAccount: Codable, Equatable {
    let id: String
    let name: String
    let username: String

    var displayHandle: String { "@\(username)" }
    var displayName: String {
        name.isEmpty ? displayHandle : "\(name) \(displayHandle)"
    }
}

enum XPostModuleSettings {
    static let callbackURL = URL(string: "fantastic-island://x-oauth/callback")!
    static let callbackScheme = "fantastic-island"
    static let scopes = ["tweet.read", "tweet.write", "users.read", "offline.access"]

    private static let clientIDKey = "xpost.module.clientID"
    private static let accountIDKey = "xpost.module.account.id"
    private static let accountNameKey = "xpost.module.account.name"
    private static let accountUsernameKey = "xpost.module.account.username"
    private static let keychainService = "FantasticIsland.XPost"
    private static let tokenBundleAccount = "xpost.module.oauthTokenBundle"

    static var clientID: String {
        get { UserDefaults.standard.string(forKey: clientIDKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: clientIDKey) }
    }

    static var account: XPostAccount? {
        get {
            guard let id = nonEmptyString(forKey: accountIDKey),
                  let username = nonEmptyString(forKey: accountUsernameKey) else {
                return nil
            }

            return XPostAccount(
                id: id,
                name: UserDefaults.standard.string(forKey: accountNameKey) ?? "",
                username: username
            )
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.id, forKey: accountIDKey)
                UserDefaults.standard.set(newValue.name, forKey: accountNameKey)
                UserDefaults.standard.set(newValue.username, forKey: accountUsernameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: accountIDKey)
                UserDefaults.standard.removeObject(forKey: accountNameKey)
                UserDefaults.standard.removeObject(forKey: accountUsernameKey)
            }
        }
    }

    static var tokenBundle: XPostTokenBundle? {
        get {
            guard let data = KeychainSecretStore.loadData(service: keychainService, account: tokenBundleAccount) else {
                return nil
            }

            return try? JSONDecoder().decode(XPostTokenBundle.self, from: data)
        }
        set {
            guard let newValue,
                  let data = try? JSONEncoder().encode(newValue) else {
                KeychainSecretStore.delete(service: keychainService, account: tokenBundleAccount)
                return
            }

            KeychainSecretStore.saveData(data, service: keychainService, account: tokenBundleAccount)
        }
    }

    static func clearAuthentication() {
        tokenBundle = nil
        account = nil
    }

    private static func nonEmptyString(forKey key: String) -> String? {
        let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}
