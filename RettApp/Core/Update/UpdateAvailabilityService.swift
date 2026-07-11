import Foundation
import Observation

/// Interroge l'App Store (iTunes Lookup API) pour savoir si une version plus
/// récente que celle installée est disponible, et fournit le lien direct
/// vers la fiche App Store pour la mise à jour.
///
/// Aucune donnée personnelle envoyée : on requête `bundleId=fr.afsr.RettApp`
/// sur un endpoint public d'Apple.
///
/// Design :
/// - Résultat mis en cache 24 h dans `UserDefaults` pour éviter de hammerer
///   iTunes à chaque ouverture (le rythme d'update de l'App Store est mesuré
///   en jours, pas en secondes).
/// - Quand l'utilisateur ferme le bandeau, on mémorise la version qu'il a
///   dismissée → il ne le reverra qu'à la sortie d'une version encore plus
///   récente. Sans ce garde-fou l'UX est agressive.
@Observable
@MainActor
final class UpdateAvailabilityService {
    /// Info exposée à la vue. `nil` = pas de mise à jour à proposer (soit on
    /// est à jour, soit le lookup a échoué, soit la version a été dismissée).
    var availableUpdate: UpdateInfo?

    struct UpdateInfo: Equatable {
        let latestVersion: String
        let currentVersion: String
        let appStoreURL: URL
        let releaseNotes: String?
    }

    // MARK: - Configuration

    /// Bundle id publié sur l'App Store. Doit correspondre exactement à celui
    /// du projet Xcode et à la fiche App Store.
    private let bundleId = "fr.afsr.RettApp"

    /// TTL du cache. 24 h → un utilisateur qui ouvre l'app plusieurs fois par
    /// jour ne déclenche qu'un lookup par jour. Une nouvelle version publiée
    /// pendant ce délai est vue avec au maximum 24 h de retard, acceptable.
    private let cacheTTL: TimeInterval = 24 * 3600

    // MARK: - UserDefaults keys

    private static let cacheKey       = "afsr.update.cache.v1"
    private static let cachedAtKey    = "afsr.update.cachedAt.v1"
    private static let dismissedKey   = "afsr.update.dismissedVersion.v1"

    // MARK: - Public API

    /// Charge le cache s'il est frais, sinon interroge iTunes. Idempotent —
    /// on peut appeler à chaque foreground, ça ne fera pas de requête réseau
    /// tant que le cache est valide.
    func checkForUpdate() async {
        if let cached = loadCache() {
            applyIfEligible(cached)
            return
        }
        guard let fetched = await fetchLatestFromAppStore() else { return }
        saveCache(fetched)
        applyIfEligible(fetched)
    }

    /// Ferme le bandeau pour la version courante — il ne réapparaîtra qu'à la
    /// sortie d'une version encore plus récente.
    func dismissCurrentBanner() {
        guard let info = availableUpdate else { return }
        UserDefaults.standard.set(info.latestVersion, forKey: Self.dismissedKey)
        availableUpdate = nil
    }

    // MARK: - Fetch

    private struct LookupResponse: Decodable {
        struct Result: Decodable {
            let version: String
            let trackId: Int
            let releaseNotes: String?
            let trackViewUrl: String?
        }
        let results: [Result]
    }

    private func fetchLatestFromAppStore() async -> LookupResponse.Result? {
        // Country hint fr → priorité à la fiche française si l'app est
        // publiée dans plusieurs storefronts. Fallback implicite si non
        // trouvée : le paramètre `country` est un hint.
        guard var comps = URLComponents(string: "https://itunes.apple.com/lookup") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleId),
            URLQueryItem(name: "country", value: "fr")
        ]
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10 // pas de raison de bloquer la vue plus longtemps

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)
            return decoded.results.first
        } catch {
            // Silencieux : un check d'update raté ne doit jamais gêner l'utilisateur.
            return nil
        }
    }

    // MARK: - Cache

    private struct CacheEntry: Codable {
        let version: String
        let trackId: Int
        let releaseNotes: String?
        let trackViewUrl: String?
    }

    private func loadCache() -> LookupResponse.Result? {
        let defaults = UserDefaults.standard
        guard let cachedAt = defaults.object(forKey: Self.cachedAtKey) as? Date else { return nil }
        guard Date().timeIntervalSince(cachedAt) < cacheTTL else { return nil }
        guard let data = defaults.data(forKey: Self.cacheKey),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else { return nil }
        return LookupResponse.Result(
            version: entry.version,
            trackId: entry.trackId,
            releaseNotes: entry.releaseNotes,
            trackViewUrl: entry.trackViewUrl
        )
    }

    private func saveCache(_ result: LookupResponse.Result) {
        let entry = CacheEntry(
            version: result.version,
            trackId: result.trackId,
            releaseNotes: result.releaseNotes,
            trackViewUrl: result.trackViewUrl
        )
        guard let data = try? JSONEncoder().encode(entry) else { return }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: Self.cacheKey)
        defaults.set(Date(), forKey: Self.cachedAtKey)
    }

    // MARK: - Version compare

    private func applyIfEligible(_ result: LookupResponse.Result) {
        let current = currentInstalledVersion()
        guard Self.isVersionGreater(result.version, than: current) else {
            availableUpdate = nil
            return
        }
        // Si l'utilisateur a dismissé cette version précise (ou une plus
        // récente), on ne remontre pas le bandeau — sauf si l'App Store
        // publie encore une version plus récente entre-temps.
        let dismissed = UserDefaults.standard.string(forKey: Self.dismissedKey) ?? ""
        if !dismissed.isEmpty, !Self.isVersionGreater(result.version, than: dismissed) {
            availableUpdate = nil
            return
        }

        let url = Self.appStoreURL(trackId: result.trackId, fallback: result.trackViewUrl)
        availableUpdate = UpdateInfo(
            latestVersion: result.version,
            currentVersion: current,
            appStoreURL: url,
            releaseNotes: result.releaseNotes
        )
    }

    private func currentInstalledVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    /// Compare deux versions sémantiques ("1.5.0" vs "1.6.0"). On ne fait pas
    /// de parsing SemVer complet (pré-release / build metadata) parce que
    /// l'App Store ne publie que du "X.Y.Z" — on split sur `.` et on compare
    /// composante par composante.
    static func isVersionGreater(_ candidate: String, than baseline: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = baseline.split(separator: ".").map { Int($0) ?? 0 }
        let len = max(a.count, b.count)
        for i in 0..<len {
            let ai = i < a.count ? a[i] : 0
            let bi = i < b.count ? b[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
    }

    static func appStoreURL(trackId: Int, fallback: String?) -> URL {
        // itms-apps:// ouvre directement l'App Store sur iOS, sans
        // rebond Safari. C'est la manière recommandée par Apple.
        if let url = URL(string: "itms-apps://itunes.apple.com/app/id\(trackId)") {
            return url
        }
        if let fb = fallback, let url = URL(string: fb) { return url }
        // Ultime fallback (ne devrait jamais être utilisé).
        return URL(string: "https://apps.apple.com/app/id\(trackId)")!
    }
}
