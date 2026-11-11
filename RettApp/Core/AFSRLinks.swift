import Foundation

/// Les adresses du site de l'association auxquelles l'application renvoie.
///
/// Rassemblées ici pour une raison précise : la politique de confidentialité et
/// les mentions légales ne sont pas des liens ordinaires. La première est
/// **citée dans la fiche App Store**, et une adresse citée là qui ne répond
/// plus fait refuser une mise à jour. Trois littéraux éparpillés dans les
/// réglages, c'étaient trois occasions d'en changer deux sur trois.
///
/// Ces pages vivaient jusqu'ici sur un sous-domaine séparé, servi par six
/// fichiers HTML écrits à la main que rien ne déployait et dont plus personne
/// ne savait où ils étaient hébergés. Elles sont désormais servies par le site
/// lui-même, depuis son dépôt, et déployées avec lui.
enum AFSRLinks {

    static let site = URL(string: "https://afsr.fr")!

    static let don = URL(string: "https://afsr.fr/nous-soutenir/faire-un-don")!

    /// Adresse canonique, celle à déclarer dans App Store Connect.
    /// « /confidentialite » y redirige, pour les versions déjà publiées.
    static let confidentialite = URL(string: "https://afsr.fr/politique-de-confidentialite")!

    static let mentionsLegales = URL(string: "https://afsr.fr/mentions-legales")!
}
