import SwiftUI
import WebKit
import MessageUI

struct NewsDetailView: View {
    let article: NewsArticle
    @State private var bodyHeight: CGFloat = 200
    @State private var zoomedImage: ZoomedImage?
    @State private var mailDraft: MailDraft?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let url = article.featuredImageURL {
                    // L'image « scaledToFill » impose sa largeur naturelle à la
                    // pile et la fait déborder de l'écran : on fixe d'abord la
                    // taille avec une couleur, et l'image remplit en overlay.
                    Color.afsrAccent
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .overlay {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: Color.clear
                                }
                            }
                        }
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: AFSRTokens.cornerRadius))
                        .contentShape(Rectangle())
                        .onTapGesture { zoomedImage = ZoomedImage(url: url) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Agrandir la photo")
                }

                Text(article.title)
                    .font(AFSRFont.title(28))
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    if let date = article.date {
                        Text(date, style: .date)
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    shareButton
                }

                Divider()

                if article.content.isEmpty {
                    unreadableBodyFallback
                } else {
                    HTMLWebView(
                        html: article.content,
                        height: $bodyHeight,
                        onImageTap: { zoomedImage = ZoomedImage(url: $0) },
                        onMailTap: { address in
                            if MFMailComposeViewController.canSendMail() {
                                mailDraft = MailDraft(address: address)
                            } else if let url = URL(string: "mailto:\(address)") {
                                UIApplication.shared.open(url)
                            }
                        }
                    )
                        .frame(maxWidth: .infinity)
                        .frame(height: bodyHeight)

                    if let link = article.permalink {
                        Link(destination: link) {
                            Label("Lire sur afsr.fr", systemImage: "safari")
                                .font(AFSRFont.body(15))
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(Color.afsrBackground)
        // Titre court et fixe : celui de l'article, déjà affiché en grand
        // sous l'image, serait tronqué dans la barre.
        .navigationTitle("Actualité")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $zoomedImage) { ZoomableImageScreen(url: $0.url) }
        .sheet(item: $mailDraft) { draft in
            MailComposeView(recipient: draft.address, subject: article.title)
                .ignoresSafeArea()
        }
    }

    /// Partage de l'adresse de l'article sur afsr.fr vers les apps de
    /// l'utilisateur (réseaux sociaux, messages…). Absent sans permalink.
    @ViewBuilder
    private var shareButton: some View {
        if let link = article.permalink {
            ShareLink(
                item: link,
                subject: Text(article.title),
                message: Text(article.title)
            ) {
                Label("Partager", systemImage: "square.and.arrow.up")
                    .font(AFSRFont.body(15))
            }
            .buttonStyle(.borderedProminent)
            .tint(.afsrPurple)
        }
    }

    /// Le corps d'un article peut n'être fait que d'ensembles structurés —
    /// accordéons, trombinoscope, deux colonnes — que l'app ne sait pas
    /// rendre. Plutôt qu'une page blanche, on envoie sur le site, qui sait.
    private var unreadableBodyFallback: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cet article contient une mise en page que l'application ne sait pas afficher.")
                .font(AFSRFont.body(15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let link = article.permalink {
                Link(destination: link) {
                    Label("Lire sur afsr.fr", systemImage: "safari")
                        .font(AFSRFont.headline(16))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AFSRTokens.cornerRadius))
    }
}

/// Page web qui prend la hauteur de son contenu.
///
/// L'article vit dans un `ScrollView` SwiftUI : le défilement de la web view
/// est donc désactivé, et sa hauteur doit suivre le contenu — sans quoi le
/// texte est tronqué ou déborde. La hauteur remonte par un `ResizeObserver`,
/// ce qui couvre aussi les images qui finissent de charger après coup.
struct HTMLWebView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    var onImageTap: (URL) -> Void = { _ in }
    var onMailTap: (String) -> Void = { _ in }

    private static let heightHandler = "contentHeight"
    private static let imageHandler = "imageTap"

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: Self.heightHandler)
        config.userContentController.add(context.coordinator, name: Self.imageHandler)
        let script = WKUserScript(
            source: """
            new ResizeObserver(function () {
              window.webkit.messageHandlers.\(Self.heightHandler).postMessage(document.body.scrollHeight);
            }).observe(document.body);

            // Adresses e-mail en clair → liens « mailto: » cliquables.
            (function () {
              var re = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}/g;
              var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
              var nodes = [];
              while (walker.nextNode()) {
                var n = walker.currentNode;
                if (!n.parentElement.closest('a') && re.test(n.nodeValue)) nodes.push(n);
                re.lastIndex = 0;
              }
              nodes.forEach(function (n) {
                var span = document.createElement('span');
                span.innerHTML = n.nodeValue
                  .replace(/&/g, '&amp;').replace(/</g, '&lt;')
                  .replace(re, '<a href="mailto:$&">$&</a>');
                n.parentNode.replaceChild(span, n);
              });
            })();

            // Toucher une image l'ouvre en plein écran, zoomable.
            document.querySelectorAll('img').forEach(function (img) {
              if (img.closest('a')) return;
              img.addEventListener('click', function () {
                window.webkit.messageHandlers.\(Self.imageHandler).postMessage(img.currentSrc || img.src);
              });
            });
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(script)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.height = $height
        context.coordinator.onImageTap = onImageTap
        context.coordinator.onMailTap = onMailTap
        // `updateUIView` est rappelée à chaque changement de hauteur : ne
        // recharger que si le HTML a réellement changé, sinon boucle.
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html

        let wrapped = """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html { -webkit-text-size-adjust: 100%; }
          body {
            font-family: -apple-system, system-ui, sans-serif;
            font-size: 17px; line-height: 1.6; color: #222;
            margin: 0; padding: 0;
            overflow-wrap: anywhere; word-wrap: break-word;
          }
          @media (prefers-color-scheme: dark) { body { color: #eee; background: transparent; } a { color: #B8A0E6; } }
          * { max-width: 100%; box-sizing: border-box; }
          p { margin: 0 0 1em; }
          h1, h2, h3, h4 { font-family: -apple-system-rounded, system-ui; line-height: 1.25; margin: 1.4em 0 0.5em; }
          h1 { font-size: 1.5em; } h2 { font-size: 1.3em; } h3, h4 { font-size: 1.12em; }
          img, video, iframe { max-width: 100%; height: auto; border-radius: 12px; }
          iframe { aspect-ratio: 16 / 9; width: 100%; border: 0; }
          figure { margin: 1em 0; } figcaption { font-size: 0.85em; color: #888; margin-top: 4px; }
          a { color: #6B3FA0; text-decoration: underline; }
          ul, ol { padding-left: 1.3em; margin: 0 0 1em; } li { margin-bottom: 0.3em; }
          blockquote { border-left: 4px solid #6B3FA0; margin: 1em 0; padding: 0 0 0 12px; color: #666; }
          pre, code { white-space: pre-wrap; font-size: 0.9em; }
          table { display: block; overflow-x: auto; border-collapse: collapse; }
          td, th { padding: 6px 8px; border: 1px solid #8884; }
          body > *:last-child { margin-bottom: 0; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        webView.loadHTMLString(wrapped, baseURL: URL(string: "https://afsr.fr"))
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: heightHandler)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: imageHandler)
    }

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var height: Binding<CGFloat>
        var loadedHTML: String?
        var onImageTap: (URL) -> Void = { _ in }
        var onMailTap: (String) -> Void = { _ in }

        init(height: Binding<CGFloat>) { self.height = height }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "imageTap" {
                if let src = message.body as? String, let url = URL(string: src) { onImageTap(url) }
                return
            }
            guard let value = message.body as? Double else { return }
            let new = CGFloat(value).rounded(.up)
            if abs(new - height.wrappedValue) > 1 { height.wrappedValue = new }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                if url.scheme == "mailto" {
                    let address = url.absoluteString.dropFirst("mailto:".count)
                        .split(separator: "?").first.map(String.init) ?? ""
                    await MainActor.run { onMailTap(address.removingPercentEncoding ?? address) }
                    return .cancel
                }
                await MainActor.run { UIApplication.shared.open(url) }
                return .cancel
            }
            return .allow
        }
    }
}

// MARK: - Zoom photo

struct ZoomedImage: Identifiable {
    let url: URL
    var id: URL { url }
}

struct MailDraft: Identifiable {
    let address: String
    var id: String { address }
}

/// Rédaction d'un e-mail dans l'app, sans la quitter.
struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}

/// Photo en entier, plein écran : pincer pour zoomer, double-toucher pour
/// alterner, bouton pour fermer.
struct ZoomableImageScreen: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image {
                ZoomableScrollView(image: image).ignoresSafeArea()
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding(16)
            }
            .accessibilityLabel("Fermer")
        }
        .task {
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                image = UIImage(data: data)
            }
        }
    }
}

struct ZoomableScrollView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = .black

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scroll.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        // L'image occupe exactement la zone visible (aspect « fit ») ; le zoom
        // agrandit ensuite cette vue.
        context.coordinator.imageView?.frame = CGRect(origin: .zero, size: scroll.bounds.size)
        scroll.contentSize = scroll.bounds.size
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                scroll.zoom(to: CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size), animated: true)
            }
        }
    }
}

#Preview {
    NavigationStack {
        NewsDetailView(article: NewsArticle(
            id: "1",
            title: "Journée mondiale du syndrome de Rett",
            date: Date(),
            content: "<p>Chaque année, le 17 octobre, nous célébrons…</p>",
            excerpt: "Retour sur la mobilisation 2025."
        ))
    }
}
