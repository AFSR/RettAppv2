import Foundation

/// Les adresses du site de l'association auxquelles l'application renvoie.
///
/// Rassemblées ici pour une raison précise : la politique de confidentialité et
/// les mentions légales ne sont pas des liens ordinaires. La première est
/// **citée dans la fiche App Store**, et une adresse citée là qui ne répond
/// plus fait refuser une mise à jour. Trois littéraux éparpillés dans les
/// réglages, c'étaient trois occasions d'en changer deux sur trois.
///
/// Les pages propres à l'application vivent dans un dossier dédié du site,
/// `/rettapp/`, servi par le site lui-même depuis son dépôt. Les anciennes
/// adresses (`/politique-de-confidentialite`, `/mentions-legales`,
/// `/confidentialite`…) y redirigent, pour les versions déjà publiées.
enum AFSRLinks {

    static let site = URL(string: "https://afsr.fr")!

    static let don = URL(string: "https://afsr.fr/nous-soutenir/faire-un-don")!

    /// Dossier des pages de l'application.
    static let rettapp = URL(string: "https://afsr.fr/rettapp")!

    /// Présentation de l'app, aussi **Support URL** dans App Store Connect.
    static let support = rettapp

    static let faq = rettapp.appendingPathComponent("faq")

    /// Adresse canonique, celle à déclarer dans App Store Connect (fiche française).
    static let confidentialite = rettapp.appendingPathComponent("confidentialite")

    static let mentionsLegales = rettapp.appendingPathComponent("mentions-legales")
}
