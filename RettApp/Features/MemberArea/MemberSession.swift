import Foundation
import Observation
import Security

/// Jeton de connexion rangé dans le trousseau.
///
/// Le trousseau et non UserDefaults : le jeton ouvre l'accès aux dons, aux
/// attestations fiscales et aux coordonnées de la famille. Il reste sur cet
/// appareil (`ThisDeviceOnly`) — jamais synchronisé via iCloud — et lisible
/// dès le premier déverrouillage, pour qu'une ouverture de l'app en arrière-plan
/// ne rate pas la lecture.
enum MemberKeychain {
    private static let service = "fr.afsr.RettApp.member"
    private static let account = "api-token"

    static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        delete()
        var query = baseQuery()
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// État de connexion à l'espace adhérent.
///
/// Le compte AFSR n'a rien à voir avec les données de suivi (journal, crises,
/// médicaments) : celles-ci vivent sur l'appareil et dans l'iCloud personnel.
/// Se connecter ou se déconnecter ici ne les touche pas.
@Observable
@MainActor
final class MemberSession {
    static let shared = MemberSession()

    let client = MemberAPIClient()

    private(set) var isSignedIn: Bool
    private(set) var profile: MemberProfile?

    /// Posé quand le site a invalidé le jeton : l'écran de connexion l'affiche
    /// pour que la déconnexion ne paraisse pas inexpliquée.
    private(set) var expiredNotice: String?

    init() {
        let stored = MemberKeychain.read()
        isSignedIn = stored != nil
        client.token = stored
        client.onUnauthenticated = { [weak self] in
            self?.signOutLocally(notice: "Votre session a expiré. Reconnectez-vous pour retrouver votre espace.")
        }
    }

    // MARK: - Connexion

    /// Demande l'envoi d'un code. La réponse est la même que le compte existe
    /// ou non : l'écran ne doit donc pas prétendre savoir.
    func requestCode(identifier: String) async throws -> LoginChallenge {
        try await client.post("/connexion", body: ["identifier": identifier.trimmingCharacters(in: .whitespaces)])
    }

    /// Échange le code contre un jeton. Renvoie les comptes à départager quand
    /// plusieurs fiches partagent l'identifiant, `nil` quand la connexion est faite.
    func verify(challenge: String, code: String) async throws -> (selection: String, accounts: [MemberAccountChoice])? {
        let result: LoginResult = try await client.post("/connexion/verification", body: [
            "challenge": challenge,
            "code": code,
            "device_name": Self.deviceName
        ])
        return try finish(result)
    }

    func chooseAccount(selection: String, account: String) async throws {
        let result: LoginResult = try await client.post("/connexion/compte", body: [
            "selection": selection,
            "account": account
        ])
        _ = try finish(result)
    }

    private func finish(_ result: LoginResult) throws -> (selection: String, accounts: [MemberAccountChoice])? {
        if result.status == "choose_account", let selection = result.selection, let accounts = result.accounts {
            return (selection, accounts)
        }
        guard result.status == "authenticated", let token = result.token else {
            throw MemberAPIError.unreadable
        }
        MemberKeychain.save(token)
        client.token = token
        profile = result.member
        expiredNotice = nil
        isSignedIn = true
        return nil
    }

    // MARK: - Profil

    /// Relit le profil. Une erreur réseau garde la dernière valeur connue :
    /// l'espace reste utilisable hors ligne pour ce qui est déjà affiché.
    func refreshProfile() async {
        guard isSignedIn else { return }
        if let envelope: MemberEnvelope = try? await client.get("/moi") {
            profile = envelope.member
        }
    }

    func update(profile: MemberProfile) {
        self.profile = profile
    }

    // MARK: - Déconnexion

    /// Révoque le jeton côté site si le réseau le permet, puis l'oublie ici
    /// dans tous les cas : se déconnecter ne doit jamais dépendre du réseau.
    func signOut() async {
        if isSignedIn {
            let _: EmptyResponse? = try? await client.post("/deconnexion")
        }
        signOutLocally(notice: nil)
    }

    func signOutLocally(notice: String?) {
        MemberKeychain.delete()
        MemberAPIClient.clearDownloads()
        client.token = nil
        profile = nil
        isSignedIn = false
        expiredNotice = notice
    }

    func dismissExpiredNotice() {
        expiredNotice = nil
    }

    private static var deviceName: String {
        // Le nom de l'appareil est une donnée personnelle (« iPhone de Marie ») :
        // on n'envoie que le modèle.
        "RettApp iOS"
    }
}

/// Réponse dont le contenu n'importe pas.
struct EmptyResponse: Decodable {}
