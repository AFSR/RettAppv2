import Foundation
import LocalAuthentication
import Observation
import Security
import SwiftUI

// MARK: - Trousseau

/// Secrets de l'espace adhérent dans le trousseau.
///
/// Deux secrets, de portées volontairement différentes :
///
/// - le **jeton d'accès**, qui ouvre les données. Il est verrouillé : le
///   trousseau ne le rend qu'après Face ID / Touch ID, ou le code de l'iPhone
///   en repli. Il reste sur cet appareil (`ThisDeviceOnly`), jamais iCloud, et
///   disparaît si le code de l'iPhone est retiré ;
/// - le **jeton de révocation**, qui ne sert qu'à *détruire* le précédent côté
///   site et n'ouvre aucune donnée. Il est rangé hors du verrou : c'est
///   précisément quand le déverrouillage a échoué trop de fois, et que le
///   jeton d'accès est devenu inaccessible, qu'on en a besoin.
enum MemberKeychain {
    private static let service = "fr.afsr.RettApp.member"

    private enum Account {
        static let access = "api-token"
        static let revocation = "revoke-token"
    }

    enum SaveResult: Equatable {
        case saved
        /// Aucun code de verrouillage sur l'iPhone : impossible de protéger le jeton.
        case deviceNotSecured
    }

    enum ReadResult: Equatable {
        case token(String)
        case notFound
        case failed
    }

    // MARK: Jeton d'accès (verrouillé)

    static func saveProtectedAccessToken(_ token: String) -> SaveResult {
        delete(Account.access)

        // Biométrie actuelle OU code. « Actuelle » : si les visages enregistrés
        // changent, la biométrie n'ouvre plus rien — seul le code reste. Le code
        // en repli évite qu'un masque ou un doigt mouillé ne coûte la session.
        guard let control = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.biometryCurrentSet, .or, .devicePasscode],
            nil
        ) else { return .deviceNotSecured }

        var query = base(Account.access)
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessControl as String] = control

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess ? .saved : .deviceNotSecured
    }

    /// Lit le jeton avec un contexte déjà authentifié : aucune seconde invite.
    static func readAccessToken(context: LAContext) -> ReadResult {
        var query = base(Account.access)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            if let data = result as? Data, let token = String(data: data, encoding: .utf8) { return .token(token) }
            return .failed
        case errSecItemNotFound:
            return .notFound
        default:
            return .failed
        }
    }

    static func deleteAccessToken() { delete(Account.access) }

    // MARK: Jeton de révocation (hors verrou)

    static func saveRevocationToken(_ token: String) {
        delete(Account.revocation)
        var query = base(Account.revocation)
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func readRevocationToken() -> String? {
        var query = base(Account.revocation)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteRevocationToken() { delete(Account.revocation) }

    // MARK: Interne

    private static func delete(_ account: String) {
        SecItemDelete(base(account) as CFDictionary)
    }

    private static func base(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

// MARK: - Biométrie

/// Résultat d'une demande de déverrouillage.
///
/// La distinction entre « annulé » et « refusé » est la base de la politique
/// d'échec : annuler l'invite ne compte pas comme un échec (on ne déconnecte
/// pas quelqu'un parce qu'il a reçu un appel au mauvais moment), un refus oui.
enum MemberAuthOutcome {
    case success(LAContext)
    case cancelled
    case refused
    /// Ni biométrie ni code utilisable sur cet appareil.
    case unavailable
}

enum MemberBiometrics {
    @MainActor
    static func authenticate(reason: String) async -> MemberAuthOutcome {
        let context = LAContext()
        var error: NSError?

        // « Propriétaire de l'appareil » : biométrie, puis code de l'iPhone en
        // repli. Ni masque ni doigt mouillé ne doivent bloquer l'accès.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable
        }

        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return .success(context)
        } catch let error as LAError {
            switch error.code {
            case .authenticationFailed, .biometryLockout:
                return .refused
            case .passcodeNotSet, .biometryNotAvailable, .biometryNotEnrolled:
                return .unavailable
            default:
                // userCancel, systemCancel, appCancel, notInteractive…
                return .cancelled
            }
        } catch {
            return .cancelled
        }
    }
}

// MARK: - Session

/// État de connexion à l'espace adhérent, et son verrou.
///
/// Trois états :
/// - **déconnecté** : pas de session ; l'écran de connexion s'affiche ;
/// - **verrouillé** : une session existe sur l'appareil, mais son jeton est
///   dans le trousseau, derrière Face ID. L'onglet reste affiché, aucune
///   donnée ne l'est ;
/// - **déverrouillé** : le jeton est en mémoire.
///
/// L'espace se reverrouille quand l'app a passé plus d'une minute en
/// arrière-plan, et à chaque lancement. Après `maxFailures` déverrouillages
/// refusés, la session est détruite, ici comme sur le site.
///
/// Le compte AFSR n'a rien à voir avec les données de suivi (journal, crises,
/// médicaments) : celles-ci vivent sur l'appareil et dans l'iCloud personnel.
@Observable
@MainActor
final class MemberSession {
    static let shared = MemberSession()

    /// Refus de déverrouillage consécutifs avant destruction de la session.
    static let maxFailures = 5

    /// Temps passé en arrière-plan avant reverrouillage. Assez court pour
    /// qu'un téléphone posé ne reste pas ouvert, assez long pour qu'un
    /// aller-retour vers Messages (le code SMS) ne redemande pas Face ID.
    static let gracePeriod: TimeInterval = 60

    private enum Key {
        static let hasSession = "member.hasSession"
        static let failures = "member.failedUnlocks"
        static let pendingRevocation = "member.pendingRevocation"
    }

    let client = MemberAPIClient()

    /// Une session verrouillée existe sur cet appareil. Indicateur non secret :
    /// il décide de l'affichage de l'onglet, pas de l'accès aux données.
    private(set) var hasStoredSession: Bool
    private(set) var isUnlocked = false
    private(set) var isUnlocking = false
    private(set) var profile: MemberProfile?

    /// Message de l'écran de verrouillage (refus, appareil sans code…).
    private(set) var lockMessage: String?

    /// Posé quand la session a pris fin sans que la personne l'ait demandé.
    private(set) var expiredNotice: String?

    /// Posé quand la session ne peut pas être conservée entre deux lancements.
    private(set) var persistenceNotice: String?

    private var backgroundedAt: Date?
    private let defaults = UserDefaults.standard

    /// Connecté, qu'on soit verrouillé ou non : c'est ce qui fait vivre l'onglet.
    var isSignedIn: Bool { hasStoredSession || isUnlocked }

    var remainingAttempts: Int { max(0, Self.maxFailures - defaults.integer(forKey: Key.failures)) }

    init() {
        hasStoredSession = UserDefaults.standard.bool(forKey: Key.hasSession)
        client.onUnauthenticated = { [weak self] in
            self?.signOutLocally(notice: "Votre session a expiré. Reconnectez-vous pour retrouver votre espace.")
        }
        // Une révocation restée sans réseau au dernier arrêt est rejouée.
        Task { await sendPendingRevocation() }
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
            "device_name": "RettApp iOS"
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

        // Un reliquat d'une session précédente ne doit pas survivre à une nouvelle.
        defaults.removeObject(forKey: Key.pendingRevocation)

        let saved = MemberKeychain.saveProtectedAccessToken(token)
        if let revocation = result.revokeToken {
            MemberKeychain.saveRevocationToken(revocation)
        }

        hasStoredSession = saved == .saved
        defaults.set(hasStoredSession, forKey: Key.hasSession)
        defaults.set(0, forKey: Key.failures)

        persistenceNotice = saved == .saved ? nil :
            "Aucun code de verrouillage n'est activé sur cet iPhone : votre session ne peut pas être protégée, elle n'est donc pas conservée. Vous resterez connecté tant que l'app est ouverte. Activez un code dans Réglages pour rester connecté en toute sécurité."

        client.token = token
        profile = result.member
        expiredNotice = nil
        lockMessage = nil
        isUnlocked = true
        return nil
    }

    // MARK: - Verrou

    /// Demande Face ID (ou le code) et, si accepté, charge le jeton en mémoire.
    func unlock() async {
        guard hasStoredSession, !isUnlocked, !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }
        lockMessage = nil

        switch await MemberBiometrics.authenticate(reason: "Déverrouiller votre espace adhérent AFSR") {
        case .success(let context):
            switch MemberKeychain.readAccessToken(context: context) {
            case .token(let token):
                defaults.set(0, forKey: Key.failures)
                client.token = token
                isUnlocked = true
                await refreshProfile()
            case .notFound:
                // Le trousseau n'a plus le jeton : code de l'iPhone retiré,
                // appareil restauré. Il n'y a plus rien à déverrouiller.
                signOutLocally(notice: "Votre session n'est plus disponible sur cet appareil. Reconnectez-vous.")
            case .failed:
                lockMessage = "Impossible de lire votre session. Réessayez."
            }

        case .cancelled:
            // Annuler n'est pas un échec : on ne déconnecte pas quelqu'un
            // parce qu'il a reçu un appel au mauvais moment.
            break

        case .refused:
            await registerFailure()

        case .unavailable:
            lockMessage = "Activez un code de verrouillage sur cet iPhone (Réglages, Face ID et code) pour accéder à votre espace adhérent."
        }
    }

    /// Referme l'espace : le jeton quitte la mémoire, rien de personnel ne reste affiché.
    func lock() {
        guard hasStoredSession else { return }
        client.token = nil
        profile = nil
        isUnlocked = false
        MemberAPIClient.clearDownloads()
    }

    /// À appeler à chaque changement de phase de l'app.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            if isUnlocked { backgroundedAt = Date() }
        case .active:
            if let since = backgroundedAt, Date().timeIntervalSince(since) > Self.gracePeriod {
                lock()
            }
            backgroundedAt = nil
            Task { await sendPendingRevocation() }
        default:
            break
        }
    }

    /// Un refus de plus. Au-delà du seuil la session est détruite : le jeton
    /// local d'abord, la révocation côté site ensuite, dès que le réseau le permet.
    private func registerFailure() async {
        let failures = defaults.integer(forKey: Key.failures) + 1
        defaults.set(failures, forKey: Key.failures)

        guard failures >= Self.maxFailures else {
            lockMessage = "Déverrouillage refusé. Après \(Self.maxFailures) refus, vous serez déconnecté (\(failures)/\(Self.maxFailures))."
            return
        }

        defaults.set(true, forKey: Key.pendingRevocation)
        signOutLocally(notice: "Pour votre sécurité, vous avez été déconnecté après plusieurs refus de déverrouillage.")
        await sendPendingRevocation()
    }

    // MARK: - Profil

    /// Relit le profil. Une erreur réseau garde la dernière valeur connue :
    /// l'espace reste utilisable hors ligne pour ce qui est déjà affiché.
    func refreshProfile() async {
        guard isUnlocked else { return }
        if let envelope: MemberEnvelope = try? await client.get("/moi") {
            profile = envelope.member
        }
    }

    func update(profile: MemberProfile) {
        self.profile = profile
    }

    // MARK: - Déconnexion

    /// Se déconnecter, verrouillé ou non. La destruction côté site passe par
    /// le jeton de révocation, qui ne demande pas Face ID : se déconnecter ne
    /// doit jamais exiger de se déverrouiller d'abord.
    func signOut() async {
        if MemberKeychain.readRevocationToken() != nil {
            defaults.set(true, forKey: Key.pendingRevocation)
        } else if client.token != nil {
            // Session ouverte avant l'existence du jeton de révocation.
            let _: EmptyResponse? = try? await client.post("/deconnexion")
        }
        signOutLocally(notice: nil)
        await sendPendingRevocation()
    }

    /// Oublie la session ici. La révocation côté site, s'il y en a une en
    /// attente, garde son jeton jusqu'à ce qu'elle ait abouti.
    func signOutLocally(notice: String?) {
        MemberKeychain.deleteAccessToken()
        if !defaults.bool(forKey: Key.pendingRevocation) {
            MemberKeychain.deleteRevocationToken()
        }
        MemberAPIClient.clearDownloads()
        client.token = nil
        profile = nil
        isUnlocked = false
        hasStoredSession = false
        defaults.set(false, forKey: Key.hasSession)
        defaults.set(0, forKey: Key.failures)
        lockMessage = nil
        persistenceNotice = nil
        expiredNotice = notice
    }

    func dismissExpiredNotice() {
        expiredNotice = nil
    }

    /// Envoie la révocation en attente. Sans réseau elle reste en attente et
    /// sera rejouée au prochain retour au premier plan ou au prochain lancement.
    func sendPendingRevocation() async {
        guard defaults.bool(forKey: Key.pendingRevocation) else { return }
        guard let revocation = MemberKeychain.readRevocationToken() else {
            defaults.set(false, forKey: Key.pendingRevocation)
            return
        }
        do {
            let _: EmptyResponse = try await client.post("/revocation", body: ["revoke_token": revocation])
            MemberKeychain.deleteRevocationToken()
            defaults.set(false, forKey: Key.pendingRevocation)
        } catch {
            // Réseau absent ou site indisponible : on réessaiera.
        }
    }
}

/// Réponse dont le contenu n'importe pas.
struct EmptyResponse: Decodable {}
