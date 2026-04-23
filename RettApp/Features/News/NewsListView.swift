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
                List {
                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    ForEach(viewModel.articles) { article in
                        NavigationLink(value: article) {
                            NewsRow(article: article)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.afsrBackground)
            }
        }
        .background(Color.afsrBackground)
        .navigationTitle("Actualités")
        .navigationDestination(for: NewsArticle.self) { NewsDetailView(article: $0) }
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
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

private struct NewsRow: View {
    let article: NewsArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let url = article.featuredImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Color.afsrAccent
                    }
                }
                .frame(height: 180)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: AFSRTokens.cornerRadiusSmall))
            }
            Text(article.title)
                .font(AFSRFont.headline())
                .foregroundStyle(.primary)
            if let date = article.date {
                Text(date, style: .date)
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
            }
            if let excerpt = article.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .font(AFSRFont.body(15))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(AFSRTokens.spacing)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: AFSRTokens.cornerRadius))
        .shadow(color: .black.opacity(AFSRTokens.shadowOpacity), radius: AFSRTokens.shadowRadius, x: 0, y: 2)
    }
}

#Preview {
    NavigationStack { NewsListView() }
}
