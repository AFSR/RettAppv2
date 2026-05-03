import Foundation

#if canImport(StripeCore)
import StripeCore
#endif

/// Initialise la configuration globale du SDK Stripe au lancement de l'app.
///
/// **Avant** d'utiliser cette intégration :
///   1. Ajouter le SDK Stripe dans Xcode :
///      File → Add Package Dependencies →
///      `https://github.com/stripe/stripe-ios` →
///      cocher au moins le produit `StripeApplePay`.
///   2. Remplacer les placeholders ci-dessous par les vraies clés publiques
///      Stripe (Dashboard → Developers → API keys).
///   3. Vérifier que l'URL backend dans
///      `ApplePayDonationCoordinator.backendURL` correspond bien à votre
///      déploiement Vercel.
///
/// **Sécurité** : la clé publique (`pk_test_…` / `pk_live_…`) est faite pour
/// être embarquée dans le binaire. Elle ne permet **que** de créer des
/// PaymentMethods opaques côté Stripe. La clé secrète (`sk_…`) reste
/// exclusivement côté backend Vercel.
enum StripeBootstrap {

    /// Clé publique Stripe — mode test (Dashboard → toggle « Viewing test data »).
    /// Remplacer par la valeur réelle.
    static let publishableKeyTest = "pk_test_REPLACE_ME"

    /// Clé publique Stripe — mode live (production).
    /// Remplacer par la valeur réelle.
    static let publishableKeyLive = "pk_live_REPLACE_ME"

    /// À appeler une seule fois au démarrage de l'app.
    static func configure() {
        #if canImport(StripeCore)
        let key: String
        #if DEBUG
        key = publishableKeyTest
        #else
        key = publishableKeyLive
        #endif
        guard !key.contains("REPLACE_ME") else {
            print("⚠️ Stripe non configuré : remplacez les placeholders dans StripeBootstrap.swift")
            return
        }
        StripeAPI.defaultPublishableKey = key
        print("✅ Stripe configuré (\(key.hasPrefix("pk_test") ? "TEST" : "LIVE"))")
        #else
        print("ℹ️ SDK Stripe non installé — Apple Pay reste en mode local-only (intention de don, pas de débit réel).")
        #endif
    }
}
