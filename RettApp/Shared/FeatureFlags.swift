import Foundation

/// Drapeaux fonctionnalités — permettent d'activer/désactiver des modules sans commit.
enum FeatureFlags {
    /// Module Actualités (Statamic). Désactivé tant que l'API Statamic n'est pas
    /// configurée côté afsr.fr. Réactivable en passant à `true`.
    static let newsEnabled: Bool = false
}
