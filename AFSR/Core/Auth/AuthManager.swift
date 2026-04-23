import Foundation
import AuthenticationServices
import Security
import Observation

enum AuthState: Equatable {
    case checking
    case signedOut
    case signedIn(userID: String)
}

@Observable
final class AuthManager: NSObject {
    var state: AuthState = .checking
    var lastError: String?

    private let keychainAccount = "afsr.auth.appleUserID"
    private let keychainService = "fr.afsr.RettApp"

    override init() {
        super.init()
    }

    // MARK: - Session persistence

    func restoreSession() async {
        guard let storedID = readKeychain() else {
            await MainActor.run { self.state = .signedOut }
            return
        }
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let credentialState = try await provider.credentialState(forUserID: storedID)
            await MainActor.run {
                switch credentialState {
                case .authorized:
                    self.state = .signedIn(userID: storedID)
                default:
                    self.clearKeychain()
                    self.state = .signedOut
                }
            }
        } catch {
            await MainActor.run {
                self.state = .signedOut
            }
        }
    }

    func signOut() {
        clearKeychain()
        state = .signedOut
    }

    // MARK: - Sign in with Apple callback

    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                self.lastError = "Identifiants invalides."
                return
            }
            let userID = credential.user
            writeKeychain(userID)
            self.state = .signedIn(userID: userID)
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                self.lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Keychain helpers

    private func writeKeychain(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func clearKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Preview helper

    static func previewSignedIn() -> AuthManager {
        let m = AuthManager()
        m.state = .signedIn(userID: "preview-user")
        return m
    }
}
