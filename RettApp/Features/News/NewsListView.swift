import SwiftUI

struct NewsListView: View {
    @State private var viewModel = NewsViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.articles.isEmpty {
                ProgressView("Chargement des actualités…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.articles.isEmpty {
                EmptyStateView(
                    title: "Aucune actualité",
                    message: viewModel.errorMessage ?? "Aucun article disponible.",
                    systemImage: "newspaper",
                    actionTitle: "Actualiser"
                ) { Task { await viewModel.refresh() } }
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        if let error = viewModel.errorMessage {
                            errorBanner(error)
                        }
                        // Identité par position : deux entrées au même `id` (traductions,
                        // doublons du site) ne doivent pas se confondre et envoyer vers
                        // l'article voisin.
                        ForEach(Array(viewModel.articles.enumerated()), id: \.offset) { index, article in
                            NavigationLink {
                                NewsDetailView(article: article)
                            } label: {
                                NewsCard(article: article, isFeatured: index == 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color.afsrBackground)
            }
        }
        .background(Color.afsrBackground)
        .navigationTitle("Actualités")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task { if viewModel.articles.isEmpty { await viewModel.refresh() } }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.afsrWarning)
            Text(message)
                .font(AFSRFont.caption())
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(12)
        .background(Color.afsrWarning.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Carte d'article. La première de la liste (`isFeatured`) est plus grande,
/// avec le titre superposé à l'image ; les suivantes empilent image, texte
/// et invitation à lire.
private struct NewsCard: View {
    let article: NewsArticle
    let isFeatured: Bool

    private let corner: CGFloat = 22

    var body: some View {
        Group {
            if isFeatured, article.featuredImageURL != nil {
                featured
            } else {
                standard
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .shadow(color: .afsrShadow, radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: Variantes

    private var featured: some View {
        ZStack(alignment: .bottomLeading) {
            image(height: 280)
            LinearGradient(
                colors: [.clear, .afsrPurpleDark.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 8) {
                badge("À la une", filled: true)
                Text(article.title)
                    .font(AFSRFont.title(24))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if let date = article.date {
                    Text(date, format: .dateTime.day().month(.wide).year())
                        .font(AFSRFont.caption())
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(18)
        }
        .frame(height: 280)
    }

    private var standard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if article.featuredImageURL != nil {
                image(height: 170)
            }
            VStack(alignment: .leading, spacing: 10) {
                if let date = article.date {
                    badge(date.formatted(.dateTime.day().month(.abbreviated).year()), filled: false)
                }
                Text(article.title)
                    .font(AFSRFont.headline())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                if let excerpt = article.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(AFSRFont.body(15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                HStack(spacing: 4) {
                    Text("Lire l'article")
                    Image(systemName: "arrow.right")
                }
                .font(AFSRFont.caption())
                .fontWeight(.semibold)
                .foregroundStyle(Color.afsrPurpleAdaptive)
                .padding(.top, 2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.afsrSurface)
    }

    // MARK: Éléments

    private func image(height: CGFloat) -> some View {
        Color.afsrAccent
            .frame(height: height)
            .overlay {
                AsyncImage(url: article.featuredImageURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Image(systemName: "newspaper")
                            .font(.largeTitle)
                            .foregroundStyle(Color.afsrPurple.opacity(0.4))
                    }
                }
            }
            .clipped()
            // `clipped()` ne limite que le dessin, pas la zone tactile : une
            // photo « scaledToFill » plus haute que son cadre déborde, et celle
            // de la carte suivante recouvre le bas de la carte précédente —
            // d'où « Lire l'article » qui ouvrait l'article suivant.
            .contentShape(Rectangle())
    }

    private func badge(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(AFSRFont.caption())
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(filled ? Color.white : Color.afsrPurpleAdaptive)
            .background(
                filled ? Color.afsrPurple : Color.afsrPurple.opacity(0.12),
                in: Capsule()
            )
    }
}

#Preview {
    NavigationStack { NewsListView() }
}
