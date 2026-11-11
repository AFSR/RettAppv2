import Foundation

// MARK: - API configuration

enum APIConfig {
    /// Base URL de l'API de contenu Statamic de l'AFSR.
    static var baseURL: URL = URL(string: "https://afsr.fr/api")!

    /// Handle de la collection Statamic des actualités.
    ///
    /// ⚠️ C'est bien `news`, le handle, et non « actualites » : `Actualités`
    /// n'est que le titre d'affichage de la collection dans le back-office
    /// (voir `content/collections/news.yaml` côté site). Se tromper ici donne
    /// un 404 silencieux, donc une liste vide sans explication.
    static var newsCollection: String = "news"

    /// Bearer token optionnel. L'API de contenu est publique en lecture, donc
    /// vide en pratique ; conservé pour un éventuel durcissement côté site.
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
        case .badStatus(404):
            return "Les actualités ne sont pas encore disponibles. Réessayez plus tard."
        case .badStatus(let code): return "Réponse serveur \(code)."
        case .decoding: return "Impossible de lire la réponse du serveur."
        case .noData: return "Aucune donnée reçue."
        }
    }
}

// MARK: - JSON souple

/// Valeur JSON quelconque.
///
/// Statamic renvoie des champs **augmentés**, dont la forme dépend du type de
/// champ et de sa configuration : un Bard sans ensembles devient une chaîne
/// HTML, un Bard **avec** ensembles devient un tableau de nœuds ; un champ
/// `assets` devient un tableau d'objets même quand `max_files` vaut 1. Décoder
/// ces champs en types stricts casserait à la première évolution du blueprint,
/// pour une rubrique qui n'est qu'informative. On décode donc largement, puis
/// on extrait ce qu'on sait lire.
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .null }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    /// Première URL trouvée dans la valeur, à quelque profondeur que ce soit,
    /// sous l'une des clés usuelles de Statamic pour un asset.
    var firstAssetURL: URL? {
        switch self {
        case .string(let s):
            return URL(string: s)
        case .array(let items):
            for item in items {
                if let url = item.firstAssetURL { return url }
            }
            return nil
        case .object(let dict):
            for key in ["permalink", "url"] {
                if let s = dict[key]?.stringValue, let url = URL(string: s) { return url }
            }
            return nil
        default:
            return nil
        }
    }

    /// Fragments HTML contenus dans un champ Bard.
    ///
    /// Un Bard avec ensembles mélange des nœuds de texte augmentés en HTML
    /// — `{ "type": "text", "text": "<p>…" }` — et des ensembles structurés :
    /// accordéon, deux colonnes, trombinoscope, bloc d'appel à l'action.
    ///
    /// Plusieurs de ces ensembles **contiennent eux-mêmes du texte** : les
    /// deux colonnes portent chacune leur propre Bard, l'accordéon aussi. Un
    /// article réel d'afsr.fr en contient, et s'arrêter au premier niveau
    /// reviendrait à en perdre la moitié. On descend donc dans les valeurs,
    /// et ce qu'on ne sait pas lire est simplement ignoré — quand il ne reste
    /// rien, `NewsDetailView` propose la page du site, qui sait tout rendre.
    var htmlFragments: [String] {
        switch self {
        case .string(let s):
            return s.isEmpty ? [] : [s]
        case .array(let items):
            return items.flatMap(\.htmlFragments)
        case .object(let dict):
            if let text = dict["text"]?.stringValue, !text.isEmpty {
                return [text]
            }
            // On ne descend que dans les tableaux et les objets. Prendre
            // aussi les chaînes rendrait du HTML avec le nom d'un ensemble
            // (« two_columns ») ou le libellé d'un bouton : seule la clé
            // « text » porte du HTML dans un Bard augmenté.
            //
            // Clés triées : l'ordre d'un dictionnaire Swift n'est pas stable,
            // et deux lectures du même article donneraient des paragraphes
            // dans un ordre différent. Le tri place aussi « content_left »
            // avant « content_right », qui est l'ordre de lecture.
            return dict.keys.sorted().flatMap { key -> [String] in
                switch dict[key] {
                case .array, .object: return dict[key]?.htmlFragments ?? []
                default:              return []
                }
            }
        default:
            return []
        }
    }
}

// MARK: - Article model

struct NewsArticle: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let slug: String?
    let date: Date?
    /// Corps en HTML, reconstitué depuis le champ Bard. Peut être vide quand
    /// l'article n'est fait que d'ensembles structurés : dans ce cas la vue
    /// de détail renvoie vers `permalink`.
    let content: String
    let excerpt: String?
    let featuredImageURL: URL?
    /// Adresse de l'article sur afsr.fr. Sert de filet quand le corps n'est
    /// pas restituable dans l'app, et de bouton « Lire sur le site ».
    let permalink: URL?

    enum CodingKeys: String, CodingKey {
        case id, title, slug, date, content, excerpt, permalink, url
        // Handle réel du blueprint « news » côté site.
        case featuredPicture = "featured_picture"
        // Ancien nom, conservé pour ne pas dépendre d'un renommage côté site.
        case featuredImage = "featured_image"
    }

    init(
        id: String,
        title: String,
        slug: String? = nil,
        date: Date? = nil,
        content: String,
        excerpt: String? = nil,
        featuredImageURL: URL? = nil,
        permalink: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.slug = slug
        self.date = date
        self.content = content
        self.excerpt = excerpt
        self.featuredImageURL = featuredImageURL
        self.permalink = permalink
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // `id` peut remonter en nombre selon le pilote de stockage.
        if let s = try? c.decode(String.self, forKey: .id) {
            self.id = s
        } else if let n = try? c.decode(Int.self, forKey: .id) {
            self.id = String(n)
        } else {
            self.id = UUID().uuidString
        }

        self.title = (try? c.decode(String.self, forKey: .title)) ?? "Sans titre"
        self.slug = try? c.decodeIfPresent(String.self, forKey: .slug)

        if let dateString = try? c.decodeIfPresent(String.self, forKey: .date) {
            self.date = NewsArticle.parseDate(dateString)
        } else {
            self.date = nil
        }

        let body = (try? c.decodeIfPresent(JSONValue.self, forKey: .content)) ?? nil
        let fragments = body?.htmlFragments ?? []
        self.content = fragments.joined(separator: "\n")

        if let given = try? c.decodeIfPresent(String.self, forKey: .excerpt), !given.isEmpty {
            self.excerpt = given
        } else {
            self.excerpt = NewsArticle.plainTextExcerpt(fromHTML: self.content)
        }

        let picture = (try? c.decodeIfPresent(JSONValue.self, forKey: .featuredPicture)) ?? nil
        let legacy = (try? c.decodeIfPresent(JSONValue.self, forKey: .featuredImage)) ?? nil
        self.featuredImageURL = picture?.firstAssetURL ?? legacy?.firstAssetURL

        let link = (try? c.decodeIfPresent(String.self, forKey: .permalink))
            ?? (try? c.decodeIfPresent(String.self, forKey: .url))
        self.permalink = link.flatMap(URL.init(string:))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(slug, forKey: .slug)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(excerpt, forKey: .excerpt)
        try c.encodeIfPresent(permalink?.absoluteString, forKey: .permalink)
        if let date {
            try c.encode(ISO8601DateFormatter().string(from: date), forKey: .date)
        }
        if let featuredImageURL {
            try c.encode(featuredImageURL.absoluteString, forKey: .featuredPicture)
        }
    }

    // MARK: - Helpers

    /// Résumé en texte brut, pour la liste. Le blueprint « news » n'a pas de
    /// champ chapô : on prend les premiers mots du corps, balises retirées.
    static func plainTextExcerpt(fromHTML html: String, limit: Int = 180) -> String? {
        guard !html.isEmpty else { return nil }
        var text = html.replacingOccurrences(
            of: "<[^>]+>", with: " ", options: .regularExpression
        )
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        // Coupe au dernier espace pour ne pas trancher un mot en deux.
        if let lastSpace = cut.lastIndex(of: " ") {
            return String(cut[..<lastSpace]) + "…"
        }
        return String(cut) + "…"
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

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        if let d = isoFormatter.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: s) { return d }
        if let d = dateTimeFormatter.date(from: s) { return d }
        return shortFormatter.date(from: s)
    }
}

// MARK: - Statamic envelope

struct StatamicEnvelope<T: Codable>: Codable {
    let data: T
}
