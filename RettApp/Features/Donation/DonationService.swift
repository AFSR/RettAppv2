import Foundation

/// Service centralisant la configuration de la fonctionnalité « Soutenir
/// l'AFSR ».
///
/// **Apple Pay temporairement désactivé.** Le bouton intégré à l'app sera
/// disponible quand :
///   - le compte Stripe AFSR sera finalisé,
///   - le backend Vercel sera déployé,
///   - le merchant ID `merchant.fr.afsr.RettApp` sera validé chez Apple
///     Developer Portal et Stripe.
///
/// En attendant, l'utilisateur est dirigé vers le formulaire de don du site
/// de l'AFSR. Le code Apple Pay (PassKit + Stripe) est isolé dans
/// `disabled-features/donation-applepay/` pour que PassKit ne soit pas linké
/// dans le binaire publié sur l'App Store (cf. Guideline 2.1 d'Apple :
/// frameworks importés sans intégration visible = motif de refus).
enum DonationService {

    /// Feature flag — la vue Donation s'adapte (lien web simple). Tant que
    /// les fichiers Apple Pay sont en `disabled-features/`, ce flag DOIT
    /// rester à `false` (sinon compilation échoue).
    static let isApplePayEnabled = false

    /// URL de la page de don de l'AFSR.
    static let fallbackURL = URL(string: "https://afsr.fr/nous-soutenir/faire-un-don")!
}
