import Foundation
import PassKit
import os.log

#if canImport(StripeApplePay)
import StripeApplePay
import StripeCore
import StripePayments
#endif

/// Coordinator qui orchestre la feuille Apple Pay et le débit Stripe.
///
/// **Deux modes de fonctionnement** :
///
/// 1. **Mode Stripe** (recommandé, automatique dès que le SDK Stripe est ajouté
///    au projet via Swift Package Manager : `https://github.com/stripe/stripe-ios`,
///    cocher au moins le produit `StripeApplePay`).
///    Le flux complet :
///       - Apple Pay sheet présentée par `STPApplePayContext`
///       - Token Apple Pay → PaymentMethod Stripe (transparent)
///       - POST au backend Vercel pour créer un PaymentIntent confirmé
///       - SCA / 3-D Secure géré automatiquement par le SDK
///       - Débit réel sur la carte du donateur, viré sur le compte AFSR
///
/// 2. **Mode local-only** (avant ajout du SDK Stripe).
///    Affiche la sheet via `PKPaymentAuthorizationController`, enregistre
///    l'intention de don dans `DonationLedger` et signale à l'utilisateur que
///    l'AFSR le contactera pour finaliser. Aucun débit réel.
///
/// **Pré-requis Apple Developer Portal** :
///   - Merchant ID `merchant.fr.afsr.RettApp` créé.
///   - Capability Apple Pay activée sur le Bundle ID `fr.afsr.RettApp` et
///     rattachée au merchant ID.
///   - Provisioning profile régénéré.
///
/// **Pré-requis Stripe** :
///   - Compte Stripe vérifié (KYC asso terminée).
///   - Merchant ID iOS ajouté dans Stripe Dashboard → Apple Pay → iOS apps.
///   - Backend Vercel déployé (cf. `backend/` dans ce repo).
///   - `StripeAPI.defaultPublishableKey` initialisée au démarrage de l'app
///     dans `RettAppApp.init()` ou équivalent.
@MainActor
final class ApplePayDonationCoordinator: NSObject {

    enum Outcome {
        case success(amount: Decimal)
        case failed(message: String)
        case cancelled
    }

    /// URL du backend Vercel qui crée le PaymentIntent Stripe.
    /// À remplacer par l'URL réelle après déploiement.
    static let backendURL = URL(string: "https://rettapp-donations-backend.vercel.app/api/donate")!

    private let log = Logger(subsystem: "fr.afsr.RettApp", category: "Donation")
    private let amount: Decimal
    private let onComplete: (Outcome) -> Void
    private var pendingOutcome: Outcome = .cancelled

    init(amount: Decimal, onComplete: @escaping (Outcome) -> Void) {
        self.amount = amount
        self.onComplete = onComplete
    }

    /// Présente la feuille Apple Pay. Retourne `true` si elle s'est affichée.
    func present() async -> Bool {
        #if canImport(StripeApplePay)
        return await presentWithStripe()
        #else
        return await presentLocalOnly()
        #endif
    }

    // MARK: - Stripe path

    #if canImport(StripeApplePay)
    private var stripeContext: STPApplePayContext?

    private func presentWithStripe() async -> Bool {
        let request = DonationService.makeRequest(amount: amount)
        guard let context = STPApplePayContext(paymentRequest: request, delegate: self) else {
            log.error("STPApplePayContext init returned nil — vérifier StripeAPI.defaultPublishableKey + canMakePayments")
            pendingOutcome = .failed(message: "Apple Pay n'est pas configurable sur cet appareil. Vérifiez qu'une carte est ajoutée à Wallet.")
            return false
        }
        self.stripeContext = context

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            context.presentApplePay {
                // PassKit a affiché ou refusé la sheet.
                // STPApplePayContext expose pas directement le résultat ici ;
                // on retourne true et le delegate didCompleteWith couvrira le reste.
                cont.resume(returning: true)
            }
        }
    }
    #endif

    // MARK: - Local-only path (fallback sans SDK Stripe)

    private func presentLocalOnly() async -> Bool {
        let request = DonationService.makeRequest(amount: amount)
        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        controller.delegate = self
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            controller.present { presented in
                self.log.info("PassKit present() returned presented=\(presented, privacy: .public)")
                cont.resume(returning: presented)
            }
        }
    }
}

#if canImport(StripeApplePay)

// MARK: - STPApplePayContextDelegate

extension ApplePayDonationCoordinator: STPApplePayContextDelegate {

    /// Stripe SDK a converti le token Apple Pay en PaymentMethod et nous demande
    /// de créer un PaymentIntent côté backend. On POST à Vercel et on retourne
    /// le `client_secret` pour que le SDK puisse confirmer la SCA si besoin.
    func applePayContext(
        _ context: STPApplePayContext,
        didCreatePaymentMethod paymentMethod: STPPaymentMethod,
        paymentInformation: PKPayment,
        completion: @escaping STPIntentClientSecretCompletionBlock
    ) {
        let amountCents = (NSDecimalNumber(decimal: amount).multiplying(by: 100)).intValue
        let body: [String: Any] = [
            "amountCents": amountCents,
            "currency": DonationService.currencyCode.lowercased(),
            "paymentMethodId": paymentMethod.stripeId,
            "deviceLocale": Locale.current.identifier,
            "source": "RettApp"
        ]
        log.info("POST \(Self.backendURL.absoluteString, privacy: .public) amount=\(amountCents, privacy: .public) pm=\(paymentMethod.stripeId, privacy: .public)")

        var req = URLRequest(url: Self.backendURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(nil, error)
            return
        }

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                self.log.error("Backend network error: \(error.localizedDescription, privacy: .public)")
                completion(nil, error)
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(nil, NSError(domain: "RettAppDonation", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Réponse backend invalide."
                ]))
                return
            }
            self.log.info("Backend responded \(http.statusCode, privacy: .public)")
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if http.statusCode == 200,
                   let secret = json?["clientSecret"] as? String {
                    completion(secret, nil)
                } else {
                    let message = json?["message"] as? String ?? "Erreur inconnue côté Stripe (HTTP \(http.statusCode))."
                    let code = json?["error"] as? String ?? "stripe_error"
                    completion(nil, NSError(domain: "RettAppDonation", code: http.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: message,
                        "stripe_code": code
                    ]))
                }
            } catch {
                completion(nil, error)
            }
        }.resume()
    }

    func applePayContext(
        _ context: STPApplePayContext,
        didCompleteWith status: STPApplePayContext.PaymentStatus,
        error: Error?
    ) {
        switch status {
        case .success:
            log.info("Stripe Apple Pay payment succeeded.")
            DonationLedger.recordPending(amount: amount, network: "Apple Pay")
            pendingOutcome = .success(amount: amount)
        case .error:
            let message = error?.localizedDescription ?? "Le paiement n'a pas pu être finalisé."
            log.error("Stripe Apple Pay failed: \(message, privacy: .public)")
            pendingOutcome = .failed(message: message)
        case .userCancellation:
            log.info("User cancelled Apple Pay sheet.")
            pendingOutcome = .cancelled
        @unknown default:
            pendingOutcome = .failed(message: "Statut Apple Pay inconnu.")
        }
        // Le SDK ferme la sheet automatiquement ; on notifie SwiftUI.
        onComplete(pendingOutcome)
        stripeContext = nil
    }
}

#endif

// MARK: - PKPaymentAuthorizationControllerDelegate (mode local-only)

extension ApplePayDonationCoordinator: PKPaymentAuthorizationControllerDelegate {

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        let networkLabel = payment.token.paymentMethod.network?.rawValue ?? "—"
        log.info("[local-only] Payment authorized, network=\(networkLabel, privacy: .public)")
        // Aucun débit réel — on enregistre l'intention.
        DonationLedger.recordPending(amount: amount, network: networkLabel)
        pendingOutcome = .success(amount: amount)
        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss { [weak self] in
            guard let self else { return }
            self.onComplete(self.pendingOutcome)
        }
    }
}

// MARK: - DonationLedger (inchangé)

/// Stocke localement les dons effectués (montant + date + réseau).
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
