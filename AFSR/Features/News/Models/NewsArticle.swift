import Foundation

// MARK: - API configuration

enum APIConfig {
    /// Base URL Statamic de l'AFSR. À remplacer par la vraie URL avant release.
    static var baseURL: URL = URL(string: "https://www.afsr.fr/api")!
    /// Bearer token optionnel (laisser vide si endpoint public).
    static var apiKey: String = ""
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case network(Error)
    case badStatus(Int)
    case decoding(Error)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL invalide."
        case .network(let e): return "Erreur réseau : \(e.localizedDescription)"
        case .badStatus(let code): return "Réponse serveur \(code)."
        case .decoding: return "Impossible de lire la réponse du serveur."
        case .noData: return "Aucune donnée reçue."
        }
    }
}

// MARK: - Article model

struct NewsArticle: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let slug: String?
    let date: Date?
    let content: String
    let excerpt: String?
    let featuredImageURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, title, slug, date, content, excerpt
        case featuredImage = "featured_image"
    }

    init(
        id: String,
        title: String,
        slug: String? = nil,
        date: Date? = nil,
        content: String,
        excerpt: String? = nil,
        featuredImageURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.slug = slug
        self.date = date
        self.content = content
        self.excerpt = excerpt
        self.featuredImageURL = featuredImageURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.slug = try c.decodeIfPresent(String.self, forKey: .slug)
        self.content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.excerpt = try c.decodeIfPresent(String.self, forKey: .excerpt)
        if let dateString = try c.decodeIfPresent(String.self, forKey: .date) {
            self.date = NewsArticle.parseDate(dateString)
        } else {
            self.date = nil
        }
        // Featured image: Statamic renvoie soit une string, soit un objet { url: "..." }.
        if let asString = try? c.decodeIfPresent(String.self, forKey: .featuredImage) {
            self.featuredImageURL = URL(string: asString)
        } else if let imgObj = try? c.decodeIfPresent(FeaturedImage.self, forKey: .featuredImage) {
            self.featuredImageURL = imgObj.url
        } else {
            self.featuredImageURL = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(slug, forKey: .slug)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(excerpt, forKey: .excerpt)
        if let date {
            try c.encode(ISO8601DateFormatter().string(from: date), forKey: .date)
        }
        if let featuredImageURL {
            try c.encode(FeaturedImage(url: featuredImageURL), forKey: .featuredImage)
        }
    }

    private struct FeaturedImage: Codable {
        let url: URL?
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        if let d = isoFormatter.date(from: s) { return d }
        if let d = shortFormatter.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }
}

// MARK: - Statamic envelope

struct StatamicEnvelope<T: Codable>: Codable {
    let data: T
}
