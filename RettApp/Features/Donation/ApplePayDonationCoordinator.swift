import Foundation
import PassKit
import os.log

/// Coordinator UIKit-style qui orchestre la feuille Apple Pay et notifie
/// SwiftUI via callbacks. Utilise `PKPaymentAuthorizationController` (et non
/// le VC) car il est plus simple à présenter sans hiérarchie de vues UIKit.
///
/// **Pré-requis Apple Developer Portal** (sinon Apple Pay échoue silencieusement) :
///   1. Créer un Merchant ID `merchant.fr.afsr.RettApp` dans Identifiers →
///      Merchant IDs.
///   2. Cocher la capability « Apple Pay » sur le Bundle ID `fr.afsr.RettApp`
///      et lui rattacher le Merchant ID ci-dessus.
///   3. Régénérer le Provisioning Profile et resigner le binaire.
///   4. Optionnel mais recommandé : enregistrer un Payment Processing
///      Certificate signé par un PSP (Stripe / Adyen) pour pouvoir débiter
///      réellement. Sans certificat, le `payment.token` est généré mais
///      inutilisable côté serveur.
@MainActor
final class ApplePayDonationCoordinator: NSObject, PKPaymentAuthorizationControllerDelegate {

    enum Outcome {
        case success(amount: Decimal)
        case failed(message: String)
        case cancelled
    }

    private let log = Logger(subsystem: "fr.afsr.RettApp", category: "Donation")

    private let amount: Decimal
    private let onComplete: (Outcome) -> Void

    private var pendingOutcome: Outcome = .cancelled
    private var didReceiveAuthorization = false

    init(amount: Decimal, onComplete: @escaping (Outcome) -> Void) {
        self.amount = amount
        self.onComplete = onComplete
    }

    /// Présente la feuille Apple Pay et retourne `true` une fois qu'elle est
    /// effectivement affichée par PassKit.
    func present() async -> Bool {
        let request = DonationService.makeRequest(amount: amount)
        log.info("Presenting PKPaymentAuthorizationController for amount=\(NSDecimalNumber(decimal: self.amount).stringValue, privacy: .public)")
        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        controller.delegate = self
        let presented = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            controller.present { presented in
                cont.resume(returning: presented)
            }
        }
        log.info("PassKit present() callback returned presented=\(presented, privacy: .public)")
        return presented
    }

    // MARK: - Delegate

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        didReceiveAuthorization = true
        let networkLabel = payment.token.paymentMethod.network?.rawValue ?? "—"
        log.info("Payment authorized by user, network=\(networkLabel, privacy: .public), token bytes=\(payment.token.paymentData.count, privacy: .public)")

        // ⚠️ Pour un vrai débit, il faut POST `payment.token.paymentData` à un
        //    backend AFSR qui parle à un PSP (Stripe / Adyen) et déchiffre le
        //    token. Sans ce backend, le token reste dormant et aucun montant
        //    n'est réellement prélevé sur la carte.
        //
        //    En l'absence du backend, on enregistre l'intention de don localement
        //    et on signale clairement dans l'historique que ces dons sont
        //    « en attente de traitement par l'AFSR ».
        DonationLedger.recordPending(amount: amount, network: networkLabel)
        pendingOutcome = .success(amount: amount)
        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        log.info("PassKit didFinish; didReceiveAuthorization=\(self.didReceiveAuthorization, privacy: .public)")
        controller.dismiss { [weak self] in
            guard let self else { return }
            self.onComplete(self.pendingOutcome)
        }
    }
}

/// Stocke localement les dons effectués (montant + date + réseau). En attendant
/// que le backend AFSR de traitement Apple Pay soit opérationnel, ces entrées
/// reflètent une « intention de don » — pas un débit confirmé.
enum DonationLedger {
    private static let key = "DonationLedger.entries.v1"

    struct Entry: Codable, Identifiable {
        let id: UUID
        let date: Date
        let amount: Decimal
        let network: String
    }

    static func recordPending(amount: Decimal, network: String) {
        var existing = all()
        existing.append(Entry(id: UUID(), date: Date(), amount: amount, network: network))
        guard let data = try? JSONEncoder().encode(existing) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func all() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return decoded.sorted { $0.date > $1.date }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
