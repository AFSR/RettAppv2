import Foundation

/// Erreurs de l'API de l'espace adhérent, traduites pour l'écran.
///
/// Les messages viennent du site quand il en fournit un : c'est lui qui sait
/// pourquoi un code est refusé ou une demande limitée, et il le dit en
/// français. Ceux d'ici ne servent que quand la réponse n'en porte pas.
enum MemberAPIError: LocalizedError, Equatable {
    /// Le jeton n'est plus valable : il faut se reconnecter.
    case unauthenticated
    /// Contenu réservé aux adhérents à jour.
    case membershipRequired(String)
    /// Saisie refusée ; `fields` est indexé par champ du formulaire du site.
    case validation(String, fields: [String: String])
    case throttled(String)
    case server(String)
    case offline
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Votre session a expiré. Reconnectez-vous."
        case .membershipRequired(let message), .validation(let message, _),
             .throttled(let message), .server(let message):
            return message
        case .offline:
            return "Impossible de joindre afsr.fr. Vérifiez votre connexion et réessayez."
        case .unreadable:
            return "La réponse du serveur n'a pas pu être lue. Réessayez dans un instant."
        }
    }
}

/// Corps d'erreur renvoyé par le site.
private struct ErrorBody: Decodable {
    let code: String?
    let message: String?
    let errors: [String: [String]]?
}

/// Client de l'API `/api/membre`.
///
/// Sans cookie : l'identité vient du jeton « Bearer » que la session lui
/// confie. Tout passe en GET ou en POST — le pare-feu de l'hébergement du site
/// refuse PATCH, PUT et DELETE.
@MainActor
final class MemberAPIClient {
    static let host = "afsr.fr"
    static let apiPrefix = "/api/membre"

    /// Jeton courant, posé par `MemberSession`.
    var token: String?

    /// Appelé quand le site répond 401 à une requête portant un jeton.
    var onUnauthenticated: (() -> Void)?

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            config.waitsForConnectivity = false
            // Éphémère : ni cache disque ni cookies. Ces réponses sont des
            // données personnelles et n'ont rien à faire dans un cache.
            config.urlCache = nil
            config.httpCookieStorage = nil
            self.session = URLSession(configuration: config)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    // MARK: - Requêtes

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(method: "GET", path: Self.apiPrefix + path, body: nil)
    }

    func post<T: Decodable>(_ path: String, body: [String: String] = [:]) async throws -> T {
        try await send(method: "POST", path: Self.apiPrefix + path, body: try JSONEncoder().encode(body))
    }

    /// Corps JSON libre : valeurs imbriquées, nombres, booléens. Pour les envois
    /// qui ne tiennent pas dans un dictionnaire de chaînes (avis sur un lieu).
    func postJSON<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            throw MemberAPIError.unreadable
        }
        return try await send(method: "POST", path: Self.apiPrefix + path, body: data)
    }

    /// Télécharge un document dans un dossier temporaire et renvoie son
    /// adresse. `path` est le chemin complet fourni par le site
    /// (`download_path`) ou celui d'une route de l'API.
    func download(path: String, fallbackName: String) async throws -> URL {
        let request = try makeRequest(method: "GET", path: path, body: nil, accept: "*/*")

        let (temporary, response): (URL, URLResponse)
        do {
            (temporary, response) = try await session.download(for: request)
        } catch {
            throw MemberAPIError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw MemberAPIError.unreadable }

        guard (200..<300).contains(http.statusCode) else {
            let data = (try? Data(contentsOf: temporary)) ?? Data()
            throw mapError(status: http.statusCode, data: data)
        }

        let name = Self.safeFileName(response.suggestedFilename ?? fallbackName)
        let folder = Self.downloadsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let destination = folder.appendingPathComponent(name)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    // MARK: - Fichiers temporaires

    /// Les documents téléchargés (attestations fiscales, magazines filigranés)
    /// sont des données personnelles : ils restent dans le dossier temporaire
    /// et sont effacés à la déconnexion.
    static var downloadsDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("afsr-documents", isDirectory: true)
    }

    static func clearDownloads() {
        try? FileManager.default.removeItem(at: downloadsDirectory)
    }

    /// Nom de fichier sans séparateur de chemin : il vient du serveur.
    nonisolated static func safeFileName(_ proposed: String) -> String {
        let cleaned = proposed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned.hasPrefix(".") ? "document" : cleaned
    }

    // MARK: - Internes

    private func send<T: Decodable>(method: String, path: String, body: Data?) async throws -> T {
        let request = try makeRequest(method: method, path: path, body: body, accept: "application/json")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MemberAPIError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw MemberAPIError.unreadable }

        guard (200..<300).contains(http.statusCode) else {
            throw mapError(status: http.statusCode, data: data)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MemberAPIError.unreadable
        }
    }

    private func makeRequest(method: String, path: String, body: Data?, accept: String) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.path = path

        guard let url = components.url else { throw MemberAPIError.unreadable }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    private func mapError(status: Int, data: Data) -> MemberAPIError {
        let body = try? decoder.decode(ErrorBody.self, from: data)
        let message = body?.message

        switch status {
        case 401:
            if token != nil { onUnauthenticated?() }
            return .unauthenticated
        case 403 where body?.code == "membership_required":
            return .membershipRequired(message ?? "Ce contenu est réservé aux adhérents dont l'adhésion est à jour.")
        case 422:
            // Un message par champ : le premier suffit à l'écran, les autres
            // se corrigent au fil des envois.
            var fields: [String: String] = [:]
            for (field, messages) in body?.errors ?? [:] {
                if let first = messages.first { fields[field] = first }
            }
            // Le message d'un champ est plus précis que le résumé générique du site.
            let summary = fields.values.sorted().first ?? message ?? "Certaines informations sont incorrectes."
            return .validation(summary, fields: fields)
        case 429:
            return .throttled(message ?? "Trop de tentatives. Patientez une minute avant de réessayer.")
        default:
            return .server(message ?? "Le service est momentanément indisponible (code \(status)). Réessayez dans un instant.")
        }
    }
}
