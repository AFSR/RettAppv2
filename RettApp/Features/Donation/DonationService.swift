import Foundation
import PassKit
import os.log

/// Service centralisant la configuration Apple Pay pour les dons à l'AFSR.
///
/// Conformité réglementaire :
/// - Apple Store Review Guideline 3.2.1(vii) autorise Apple Pay pour les
///   dons aux associations reconnues. L'AFSR (loi 1901, RUP) est éligible.
/// - Côté traitement bancaire, le token PassKit (`PKPaymentToken`) doit être
///   transmis à un PSP (Stripe / Adyen / etc.) configuré côté AFSR pour
///   réaliser le débit. Tant que ce backend n'existe pas, on stocke le don
///   localement (cf. `DonationLedger`) et on signale à l'utilisateur via
///   l'historique.
enum DonationService {

    static let log = Logger(subsystem: "fr.afsr.RettApp", category: "Donation")

    /// Identifiant marchand déclaré dans les entitlements. **Doit** être
    /// préalablement créé dans Apple Developer Portal → Certificates,
    /// Identifiers & Profiles → Identifiers → Merchant IDs et associé au
    /// même Team ID que celui qui signe l'app.
    static let merchantId = "merchant.fr.afsr.RettApp"

    /// Pays de l'AFSR (FR).
    static let countryCode = "FR"

    /// Devise des dons (euro).
    static let currencyCode = "EUR"

    /// Réseaux de cartes acceptés. Visa/Mastercard/Cartes Bancaires couvrent
    /// l'essentiel du marché français. Amex est ajouté par confort.
    static let supportedNetworks: [PKPaymentNetwork] = [
        .visa, .masterCard, .amex, .cartesBancaires
    ]

    /// Capacités requises : 3DS pour la conformité PSD2 (SCA).
    static let merchantCapabilities: PKMerchantCapability = [.threeDSecure]

    /// État de disponibilité Apple Pay sur cet appareil et compte.
    enum Availability: Equatable {
        case ready
        case noWalletConfigured       // Wallet non disponible (iPad sans cellular ou compte iCloud sans Wallet)
        case noEligibleCard            // Wallet présent mais aucune carte des réseaux supportés
        case unavailable               // Cas génériques (région non supportée, etc.)

        var userMessage: String {
            switch self {
            case .ready:
                return ""
            case .noWalletConfigured:
                return "Apple Pay n'est pas disponible sur cet appareil. Vous pouvez utiliser le formulaire web de l'AFSR ci-dessous."
            case .noEligibleCard:
                return "Aucune carte compatible n'est ajoutée à Wallet. Ajoutez une carte Visa, Mastercard, Amex ou Cartes Bancaires dans l'application Cartes, puis revenez ici."
            case .unavailable:
                return "Apple Pay n'est pas activé sur cet appareil. Vous pouvez utiliser le formulaire web de l'AFSR ci-dessous."
            }
        }
    }

    /// Diagnostic complet de la disponibilité Apple Pay.
    static func availability() -> Availability {
        if !PKPaymentAuthorizationController.canMakePayments() {
            log.info("canMakePayments() = false → noWalletConfigured")
            return .noWalletConfigured
        }
        if !PKPaymentAuthorizationController.canMakePayments(usingNetworks: supportedNetworks, capabilities: merchantCapabilities) {
            log.info("canMakePayments(usingNetworks:) = false → noEligibleCard")
            return .noEligibleCard
        }
        return .ready
    }

    /// Construit la requête de paiement pour un montant donné.
    static func makeRequest(amount: Decimal) -> PKPaymentRequest {
        let request = PKPaymentRequest()
        request.merchantIdentifier = merchantId
        request.supportedNetworks = supportedNetworks
        request.merchantCapabilities = merchantCapabilities
        request.countryCode = countryCode
        request.currencyCode = currencyCode

        request.paymentSummaryItems = [
            PKPaymentSummaryItem(
                label: "Don à l'AFSR",
                amount: NSDecimalNumber(decimal: amount),
                type: .final
            )
        ]
        log.info("Request prepared: merchantId=\(merchantId, privacy: .public) amount=\(NSDecimalNumber(decimal: amount).stringValue, privacy: .public) \(currencyCode, privacy: .public)")
        return request
    }

    /// URL de la page de don de l'AFSR (fallback en navigateur).
    static let fallbackURL = URL(string: "https://afsr.fr/nous-soutenir/faire-un-don")!

    /// Préréglages de montants en euros affichés en V1.
    static let presetAmounts: [Decimal] = [10, 25, 50, 100]
}
