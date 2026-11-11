import Foundation
import Observation

/// Sait si la personne est connectée à son compte AFSR.
///
/// La session vit dans un cookie de la web view, que l'app ne peut pas lire
/// de façon fiable : le site ouvre aussi une session aux visiteurs anonymes,
/// un cookie de session ne prouve donc rien. On déduit l'état des pages que
/// la web view charge : une page de `/mon-compte` qui n'est pas une page de
/// connexion ne s'affiche que connecté ; une page de connexion ou de
/// déconnexion signifie l'inverse. Toute autre page ne change rien.
///
/// L'état est conservé entre les lancements (le cookie l'est aussi). Il est
/// corrigé à la prochaine ouverture de l'espace adhérent si la session a
/// expiré entre-temps.
@Observable
final class MemberSessionStore {
    static let shared = MemberSessionStore()

    private static let key = "member.isLoggedIn"

    private(set) var isLoggedIn: Bool

    private init() {
        isLoggedIn = UserDefaults.standard.bool(forKey: Self.key)
    }

    /// À appeler à chaque page afsr.fr chargée dans l'espace adhérent.
    func pageLoaded(_ url: URL?) {
        guard let url, let host = url.host?.lowercased(),
              AFSRWebView.internalHosts.contains(host) else { return }
        let path = url.path.lowercased()

        if path.contains("connexion") || path.contains("login") {
            set(false)
        } else if path.hasPrefix("/mon-compte") {
            set(true)
        }
    }

    private func set(_ value: Bool) {
        guard value != isLoggedIn else { return }
        isLoggedIn = value
        UserDefaults.standard.set(value, forKey: Self.key)
    }
}
