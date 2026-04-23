import Foundation
import Observation

@Observable
final class NewsViewModel {
    var articles: [NewsArticle] = []
    var isLoading: Bool = false
    var errorMessage: String?

    private let session: URLSession
    private let cache: URLCache

    init() {
        self.cache = URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024, directory: nil)
        let config = URLSessionConfiguration.default
        config.urlCache = self.cache
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    func refresh() async {
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        do {
            let fresh = try await fetchArticles()
            await MainActor.run {
                self.articles = fresh
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func fetchArticles() async throws -> [NewsArticle] {
        var components = URLComponents(
            url: APIConfig.baseURL.appendingPathComponent("collections/articles/entries"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "sort", value: "-date"),
            URLQueryItem(name: "limit", value: "20")
        ]
        guard let url = components?.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if !APIConfig.apiKey.isEmpty {
            req.setValue("Bearer \(APIConfig.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.noData }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus(http.statusCode)
        }

        do {
            let envelope = try JSONDecoder().decode(StatamicEnvelope<[NewsArticle]>.self, from: data)
            return envelope.data
        } catch {
            throw APIError.decoding(error)
        }
    }
}
