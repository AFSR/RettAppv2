import Foundation

/// Drapeaux fonctionnalités — permettent d'activer/désactiver des modules sans commit.
enum FeatureFlags {
    /// Module Actualités, alimenté par l'API de contenu Statamic d'afsr.fr.
    ///
    /// ⚠️ Dépend d'un déploiement côté site : l'API de contenu doit être
    /// active et exposer la collection `news` (branche
    /// `claude/app-content-api-and-mobile-login` du dépôt AFSR/website).
    /// Tant que ce n'est pas en ligne, l'onglet s'affiche mais reste vide —
    /// `NewsViewModel` remonte un 404 et `NewsListView` montre un état vide
    /// explicite, sans erreur technique ni plantage.
    ///
    /// **Ne pas publier l'app sur l'App Store avant que le site soit
    /// déployé**, sous peine d'un onglet vide en production.
    static let newsEnabled: Bool = true
}
