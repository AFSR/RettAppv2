import Foundation
import PassKit

/// Service centralisant la configuration Apple Pay pour les dons à l'AFSR.
///
/// Conformité réglementaire :
/// - Apple Store Review Guideline 3.2.1(vii) autorise Apple Pay pour les
///   dons aux associations reconnues. L'AFSR (loi 1901, RUP) est éligible.
/// - Côté traitement bancaire, le token PassKit (`PKPaymentToken`) doit être
///   transmis à un PSP (Stripe / Adyen / etc.) configuré côté AFSR pour
///   réaliser le débit. Tant que ce backend n'existe pas, on stocke le don
///   localement et on signale à l'utilisateur que la confirmation arrivera
///   par e-mail (mode "demo" ; à remplacer par un vrai POST en V2).
enum DonationService {
    /// Identifiant marchand déclaré dans les entitlements. Doit correspondre
    /// au merchant ID provisionné dans Apple Developer pour l'AFSR.
    static let merchantId = "merchant.fr.afsr.RettApp"

    /// Pays de l'AFSR (FR).
    static let countryCode = "FR"

    /// Devise des dons (euro).
    static let currencyCode = "EUR"

    /// Réseaux acceptés. Visa/Mastercard/Cartes Bancaires couvrent l'essentiel
    /// du marché français. Amex est rajouté par confort.
    static let supportedNetworks: [PKPaymentNetwork] = [
        .visa, .masterCard, .amex, .cartesBancaires
    ]

    /// Capacités requises : 3DS pour la conformité PSD2 (Strong Customer Authentication).
    static let merchantCapabilities: PKMerchantCapability = [.threeDSecure]

    /// Vrai si l'appareil peut afficher le bouton Apple Pay (Wallet présente +
    /// au moins une carte enregistrée compatible avec nos réseaux).
    static var canMakePayments: Bool {
        PKPaymentAuthorizationController.canMakePayments(
            usingNetworks: supportedNetworks,
            capabilities: merchantCapabilities
        )
    }

    /// Vrai si l'appareil supporte Apple Pay au niveau du système (Wallet présente
    /// même sans carte). Utile pour afficher « Ajouter une carte » au lieu de masquer.
    static var deviceSupportsApplePay: Bool {
        PKPaymentAuthorizationController.canMakePayments()
    }

    /// Construit la requête de paiement pour un montant donné.
    static func makeRequest(amount: Decimal, includeFees: Bool = false) -> PKPaymentRequest {
        let request = PKPaymentRequest()
        request.merchantIdentifier = merchantId
        request.supportedNetworks = supportedNetworks
        request.merchantCapabilities = merchantCapabilities
        request.countryCode = countryCode
        request.currencyCode = currencyCode

        let label = "Don à l'AFSR"
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(
                label: label,
                amount: NSDecimalNumber(decimal: amount),
                type: .final
            )
        ]
        // Pas de billing/shipping address par défaut — un don n'en a pas besoin.
        // L'utilisateur peut toujours fournir un e-mail si on l'active plus tard.
        return request
    }

    /// URL de la page de don de l'AFSR (fallback en navigateur).
    static let fallbackURL = URL(string: "https://afsr.fr/nous-soutenir/faire-un-don")!

    /// Préréglages de montants en euros affichés en V1.
    static let presetAmounts: [Decimal] = [10, 25, 50, 100]
}
