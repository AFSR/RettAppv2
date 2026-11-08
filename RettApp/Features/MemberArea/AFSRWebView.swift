import SwiftUI
import WebKit

/// Vue web intégrée pour les pages d'afsr.fr affichées dans l'app.
///
/// Elle se signale au site en ajoutant un jeton à son User-Agent, ce qui fait
/// rendre les pages sans en-tête, sans pied de page, sans fil d'Ariane ni
/// bandeau de consentement (voir `App\Classes\AppShell` côté site). Le jeton
/// vaut pour toutes les navigations — liens, formulaires, redirections —
/// contrairement à un paramètre d'URL qu'un lien interne perdrait.
///
/// Deux règles de navigation :
/// - ce qui reste sur afsr.fr s'ouvre ici ;
/// - tout le reste part dans Safari, pour qu'on ne se retrouve jamais à
///   naviguer le web entier dans une app sans barre d'adresse.
struct AFSRWebView: UIViewRepresentable {
    let url: URL

    /// Remonté à la vue parente pour afficher un indicateur et gérer le retour.
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    /// Demande de retour en arrière, consommée puis remise à `false`.
    @Binding var goBackRequested: Bool
    @Binding var errorMessage: String?

    /// Hôtes considérés comme internes. Tout le reste sort vers Safari.
    static let internalHosts: Set<String> = ["afsr.fr", "www.afsr.fr"]

    /// Jeton ajouté au User-Agent. Doit correspondre à `afsr.app_shell_token`
    /// côté site — s'ils divergent, les pages reviennent avec tout le chrome
    /// du site, ce qui se voit immédiatement mais ne casse rien.
    static let appShellToken = "RettApp"

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Le site identifie la session par un cookie : un magasin persistant
        // évite de redemander le code SMS à chaque ouverture de l'écran.
        config.websiteDataStore = .default()

        // `applicationNameForUserAgent` **ajoute** au User-Agent par défaut de
        // WebKit au lieu de le remplacer, contrairement à `customUserAgent`.
        // Le site garde donc toutes les informations dont il se sert pour son
        // rendu, et y trouve en plus notre jeton.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
        config.applicationNameForUserAgent = "\(Self.appShellToken)/\(version)"

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Le coordinateur garde une copie de la vue ; sans cette ligne il
        // écrirait dans les liaisons d'une version périmée.
        context.coordinator.parentView = self

        if goBackRequested {
            // Remis à false sur la boucle suivante pour ne pas muter l'état
            // pendant que SwiftUI met la vue à jour.
            DispatchQueue.main.async {
                goBackRequested = false
                if webView.canGoBack { webView.goBack() }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parentView: AFSRWebView

        init(_ parentView: AFSRWebView) {
            self.parentView = parentView
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let target = navigationAction.request.url else { return .allow }

            // Un lien « mailto: » ou « tel: » n'est pas une page : il revient
            // au système. Sans cela, la vue affiche une erreur.
            if let scheme = target.scheme?.lowercased(), scheme != "http", scheme != "https" {
                await MainActor.run { UIApplication.shared.open(target) }
                return .cancel
            }

            let host = target.host?.lowercased() ?? ""
            if AFSRWebView.internalHosts.contains(host) {
                return .allow
            }

            // Lien sortant touché par la personne : on quitte l'app pour
            // Safari. Les chargements que la page déclenche elle-même
            // (ressources, redirections) ne passent pas par ce cas.
            if navigationAction.navigationType == .linkActivated {
                await MainActor.run { UIApplication.shared.open(target) }
                return .cancel
            }

            return .allow
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parentView.isLoading = true
            parentView.errorMessage = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parentView.isLoading = false
            parentView.canGoBack = webView.canGoBack
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(error, webView: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            finish(error, webView: webView)
        }

        private func finish(_ error: Error, webView: WKWebView) {
            parentView.isLoading = false
            parentView.canGoBack = webView.canGoBack
            // Une navigation annulée volontairement (lien sortant parti dans
            // Safari) remonte comme une erreur : ce n'en est pas une.
            let nsError = error as NSError
            guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
            parentView.errorMessage = error.localizedDescription
        }
    }
}
