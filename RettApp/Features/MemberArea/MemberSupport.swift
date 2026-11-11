import SwiftUI
import QuickLook
import WebKit

// MARK: - Formats

enum MemberFormat {
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        // Fuseau local : « 2035-01-01 » est un jour civil, pas un instant. Lu
        // en UTC puis affiché en heure locale, il glisserait au 31 décembre
        // sous les fuseaux négatifs.
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let display: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return parser.date(from: String(raw.prefix(10)))
    }

    /// « 1 janvier 2035 », ou nil si la date est absente ou illisible.
    static func longDate(_ raw: String?) -> String? {
        date(raw).map { display.string(from: $0) }
    }

    static func amount(_ value: Double, currency: String) -> String {
        value.formatted(.currency(code: currency.isEmpty ? "EUR" : currency).locale(Locale(identifier: "fr_FR")))
    }

    /// Symbole SF correspondant à l'icône choisie dans le back-office du site.
    static func symbol(forSiteIcon icon: String) -> String {
        switch icon {
        case "publications": return "books.vertical"
        case "message": return "bubble.left.and.bubble.right"
        case "gift": return "gift"
        case "user": return "person.2"
        case "receipt": return "doc.plaintext"
        case "map-pin": return "mappin.and.ellipse"
        case "parcel": return "shippingbox"
        case "link": return "link"
        default: return "doc.text"
        }
    }
}

// MARK: - Chargement d'une ressource

/// Charge une ressource de l'API et gère les quatre états d'un écran réseau :
/// chargement, contenu, erreur avec « Réessayer », et « réservé aux adhérents ».
///
/// Le contenu reçoit aussi une fonction de rechargement, pour les écrans qui
/// modifient quelque chose puis veulent se rafraîchir.
struct MemberResourceView<Value: Decodable, Content: View>: View {
    let session: MemberSession
    let path: String
    let content: (Value, @escaping () async -> Void) -> Content

    private enum Phase {
        case loading
        case loaded(Value)
        case failed(MemberAPIError)
    }

    @State private var phase: Phase = .loading

    init(
        session: MemberSession,
        path: String,
        @ViewBuilder content: @escaping (Value, @escaping () async -> Void) -> Content
    ) {
        self.session = session
        self.path = path
        self.content = content
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView("Chargement…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let value):
                content(value) { await load(showSpinner: false) }
            case .failed(.membershipRequired(let message)):
                MemberLockedView(message: message)
            case .failed(let error):
                ContentUnavailableView {
                    Label("Impossible de charger", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Réessayer") { Task { await load(showSpinner: true) } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(Color.afsrBackground)
        .task { await load(showSpinner: true) }
    }

    private func load(showSpinner: Bool) async {
        if showSpinner { phase = .loading }
        do {
            let value: Value = try await session.client.get(path)
            phase = .loaded(value)
        } catch let error as MemberAPIError {
            // Une erreur au rafraîchissement ne doit pas effacer ce qui est
            // déjà affiché : on ne bascule en erreur que s'il n'y a rien à montrer.
            if case .loaded = phase, !showSpinner { return }
            phase = .failed(error)
        } catch {
            phase = .failed(.unreadable)
        }
    }
}

/// Contenu réservé aux adhérents à jour : même explication que le site, avec
/// le chemin pour adhérer ou renouveler.
struct MemberLockedView: View {
    var message: String = "Ce contenu est réservé aux adhérents dont l'adhésion est à jour."

    var body: some View {
        ContentUnavailableView {
            Label("Réservé aux adhérents", systemImage: "lock.fill")
        } description: {
            Text(message)
        } actions: {
            Link("Adhérer ou renouveler sur afsr.fr", destination: URL(string: "https://afsr.fr/nous-soutenir/adherer")!)
                .buttonStyle(.borderedProminent)
        }
        .background(Color.afsrBackground)
    }
}

// MARK: - Documents

/// Télécharge un document de l'espace adhérent et le présente avec Aperçu
/// (lecture, partage, impression, « Enregistrer dans Fichiers »).
///
/// Volontairement non isolée : la vue la crée dans un `@State`, c'est-à-dire
/// hors du MainActor. Seule `open` l'est, et c'est elle qui modifie l'état.
@Observable
final class MemberDocumentOpener {
    /// Clé du document en cours de téléchargement, pour griser son bouton.
    private(set) var busyKey: String?
    var previewURL: URL?
    var errorMessage: String?

    @MainActor
    func open(key: String, path: String, fallbackName: String, using session: MemberSession) async {
        guard busyKey == nil else { return }
        busyKey = key
        defer { busyKey = nil }
        do {
            previewURL = try await session.client.download(path: path, fallbackName: fallbackName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DocumentPreviewModifier: ViewModifier {
    @Bindable var opener: MemberDocumentOpener

    func body(content: Content) -> some View {
        content
            .quickLookPreview($opener.previewURL)
            .alert(
                "Téléchargement impossible",
                isPresented: Binding(
                    get: { opener.errorMessage != nil },
                    set: { if !$0 { opener.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(opener.errorMessage ?? "")
            }
    }
}

extension View {
    func memberDocumentPreview(_ opener: MemberDocumentOpener) -> some View {
        modifier(DocumentPreviewModifier(opener: opener))
    }
}

// MARK: - HTML

/// Texte HTML du site (communications, rubriques) affiché à sa hauteur réelle.
///
/// Une vue web de hauteur fixe coupait le contenu ou laissait un grand vide :
/// la hauteur est mesurée une fois la page chargée. Les liens s'ouvrent dans
/// Safari — jamais dans l'app, qui n'est pas un navigateur.
struct MemberHTMLText: View {
    let html: String
    @State private var height: CGFloat = 40

    var body: some View {
        MemberHTMLView(html: html, height: $height)
            .frame(height: height)
    }
}

private struct MemberHTMLView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        view.loadHTMLString(Self.wrap(html), baseURL: URL(string: "https://afsr.fr"))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private static func wrap(_ body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body { font: -apple-system-body; font-size: 16px; line-height: 1.5; color: #222; margin: 0; padding: 0; word-wrap: break-word; }
          @media (prefers-color-scheme: dark) { body { color: #eee; } a { color: #B8A0E6; } }
          img { max-width: 100%; height: auto; border-radius: 10px; }
          a { color: #6B3FA0; }
          p:first-child { margin-top: 0; } p:last-child { margin-bottom: 0; }
          blockquote { border-left: 4px solid #6B3FA0; margin-left: 0; padding-left: 12px; color: #666; }
        </style></head><body>\(body)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: MemberHTMLView
        var loadedHTML: String?

        init(_ parent: MemberHTMLView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { [weak self] value, _ in
                guard let measured = (value as? NSNumber)?.doubleValue, measured > 0 else { return }
                DispatchQueue.main.async { self?.parent.height = CGFloat(measured) }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                await MainActor.run { UIApplication.shared.open(url) }
                return .cancel
            }
            return .allow
        }
    }
}
