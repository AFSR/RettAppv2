import Foundation
import PassKit

/// Coordinator UIKit-style qui orchestre la feuille Apple Pay et notifie
/// SwiftUI via callbacks. Utilise `PKPaymentAuthorizationController` (et non le
/// VC) car il est plus simple à présenter sans hiérarchie de vues UIKit.
@MainActor
final class ApplePayDonationCoordinator: NSObject, PKPaymentAuthorizationControllerDelegate {

    enum Outcome {
        case success(amount: Decimal)
        case failed(message: String)
        case cancelled
    }

    private let amount: Decimal
    private let onComplete: (Outcome) -> Void

    /// Résultat final passé au handler de PassKit dans `didFinish`.
    /// On le mémorise dans `didAuthorizePayment` pour pouvoir l'utiliser en sortie.
    private var pendingOutcome: Outcome = .cancelled

    init(amount: Decimal, onComplete: @escaping (Outcome) -> Void) {
        self.amount = amount
        self.onComplete = onComplete
    }

    /// Présente la feuille Apple Pay. Retourne `false` si la requête n'a pas pu être
    /// affichée (rare — uniquement si le merchant ID est mal configuré).
    func present() -> Bool {
        let request = DonationService.makeRequest(amount: amount)
        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        controller.delegate = self
        var didPresent = false
        controller.present { presented in
            didPresent = presented
        }
        return didPresent
    }

    // MARK: - Delegate

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        // Idéalement : POST `payment.token.paymentData` à `https://api.afsr.fr/donations`
        // avec montant et devise. La route renvoie 200 si le PSP (Stripe/Adyen) a
        // accepté le débit.
        //
        // En l'absence du backend, on enregistre le don localement et on simule
        // une réussite pour ne pas bloquer la file d'attente Apple Pay.
        DonationLedger.recordPending(amount: amount, network: payment.token.paymentMethod.network?.rawValue ?? "—")
        pendingOutcome = .success(amount: amount)
        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss { [weak self] in
            guard let self else { return }
            // Si pendingOutcome est resté à .cancelled (ie didAuthorizePayment n'a jamais
            // été appelé), c'est que l'utilisateur a annulé.
            self.onComplete(self.pendingOutcome)
        }
    }
}

/// Stocke localement les dons effectués (montant + date + réseau) en attendant
/// que le backend AFSR de traitement Apple Pay soit opérationnel. Permet aussi
/// à l'utilisateur de retrouver l'historique de ses dons depuis l'app.
enum DonationLedger {
    private static let key = "DonationLedger.entries.v1"

    struct Entry: Codable, Identifiable {
        let id: UUID
        let date: Date
        let amount: Decimal
        let network: String   // "Visa", "Mastercard", "CartesBancaires", etc.
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
