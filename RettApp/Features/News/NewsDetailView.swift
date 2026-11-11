import SwiftUI
import WebKit

struct NewsDetailView: View {
    let article: NewsArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let url = article.featuredImageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color.afsrAccent
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: AFSRTokens.cornerRadius))
                }

                Text(article.title)
                    .font(AFSRFont.title(28))

                if let date = article.date {
                    Text(date, style: .date)
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                }

                if article.content.isEmpty {
                    unreadableBodyFallback
                } else {
                    HTMLWebView(html: article.content)
                        .frame(minHeight: 400)

                    if let link = article.permalink {
                        Link(destination: link) {
                            Label("Lire sur afsr.fr", systemImage: "safari")
                                .font(AFSRFont.body(15))
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding()
        }
        .background(Color.afsrBackground)
        .navigationBarTitleDisplayMode(.inline)
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

struct HTMLWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let wrapped = """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body { font-family: -apple-system, system-ui, sans-serif; font-size: 17px; color: #222; line-height: 1.5; padding: 0; margin: 0; }
          @media (prefers-color-scheme: dark) { body { color: #eee; background: transparent; } a { color: #B8A0E6; } }
          img { max-width: 100%; height: auto; border-radius: 12px; }
          a { color: #6B3FA0; }
          h1, h2, h3 { font-family: -apple-system-rounded, system-ui; }
          blockquote { border-left: 4px solid #6B3FA0; padding-left: 12px; color: #666; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        webView.loadHTMLString(wrapped, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                await MainActor.run { UIApplication.shared.open(url) }
                return .cancel
            }
            return .allow
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
