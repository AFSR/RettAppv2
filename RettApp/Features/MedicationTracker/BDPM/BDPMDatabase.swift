import Foundation
import SQLite3

/// Une fiche de médicament telle qu'extraite de la BDPM.
struct BDPMMedication: Hashable, Identifiable {
    /// Code Identifiant de Spécialité (CIS) — clé primaire BDPM. Négatif pour
    /// les entrées du fallback `CommonFrenchMedications` (pas un vrai CIS).
    let cis: Int
    /// Dénomination complète (« Doliprane 500 mg, comprimé pelliculé »).
    let name: String
    /// Nom court tiré du premier mot (« Doliprane »). Utilisé comme valeur
    /// pré-remplie quand l'utilisateur sélectionne une suggestion.
    let shortName: String
    /// Forme galénique (« comprimé pelliculé », « sirop », « gélule »…).
    let dosageForm: String?
    /// Substance(s) active(s), virgule-séparées (« paracétamol »).
    let activeIngredient: String?

    var id: Int { cis }

    /// Libellé affiché dans la liste d'autocomplete. Compact : « Doliprane
    /// 500 mg (paracétamol) ». La forme galénique n'est ajoutée que si le
    /// nom ne la contient pas déjà.
    var displayLabel: String {
        if let active = activeIngredient, !active.isEmpty,
           !name.lowercased().contains(active.lowercased()) {
            return "\(name) (\(active))"
        }
        return name
    }
}

/// Lecteur de la base BDPM bundlée comme ressource (`bdpm.sqlite`). Permet
/// l'autocomplete instantané sur les ~15 000 médicaments du répertoire
/// français des spécialités, sans appel réseau.
///
/// La base est générée hors-ligne via `scripts/build_bdpm_db.rb`. Si le
/// bundle ne contient pas la SQLite (ou qu'elle est corrompue), on bascule
/// silencieusement sur l'ancienne liste `CommonFrenchMedications` — l'app
/// reste fonctionnelle dans tous les cas.
@MainActor
final class BDPMDatabase {

    static let shared = BDPMDatabase()

    private var db: OpaquePointer?
    /// Vrai si l'on a réussi à ouvrir une SQLite avec au moins une ligne.
    private(set) var isReady: Bool = false

    private init() {
        openIfPossible()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    private func openIfPossible() {
        guard let url = Bundle.main.url(forResource: "bdpm", withExtension: "sqlite") else {
            return
        }
        var handle: OpaquePointer?
        // SQLITE_OPEN_READONLY + nomutex : la SQLite bundlée est read-only,
        // pas besoin de verrou, on évite les pénalités d'écriture.
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard rc == SQLITE_OK, let opened = handle else {
            sqlite3_close(handle)
            return
        }
        db = opened
        isReady = true
    }

    /// Renvoie jusqu'à `limit` suggestions matchant `query` par préfixe sur
    /// `name` ou `short_name` (insensible à la casse / aux accents via
    /// `LOWER`). Priorité aux matches exacts du nom court.
    ///
    /// Renvoie `[]` si la query est vide ou si la base n'est pas ouverte.
    /// Sans la SQLite bundlée, l'appelant peut fallback sur
    /// `CommonFrenchMedications.suggestions(matching:limit:)`.
    func suggestions(matching query: String, limit: Int = 8) -> [BDPMMedication] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard isReady, let db, !trimmed.isEmpty else { return [] }

        let needle = trimmed.lowercased() + "%"
        let sql = """
            SELECT cis, name, short_name, dosage_form, active_ingredient
            FROM medications
            WHERE short_name_lower LIKE ?1 OR name_lower LIKE ?1
            ORDER BY
              CASE WHEN short_name_lower LIKE ?1 THEN 0 ELSE 1 END,
              LENGTH(name) ASC,
              name ASC
            LIMIT ?2
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }

        // SQLITE_TRANSIENT pour que SQLite copie la chaîne — l'autre option
        // (STATIC) suppose que le pointeur survit jusqu'à l'exécution, ce qui
        // n'est pas le cas avec un String Swift qui peut être libéré
        // immédiatement après le bind.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, needle, -1, transient)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [BDPMMedication] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let cis = Int(sqlite3_column_int64(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let short = String(cString: sqlite3_column_text(stmt, 2))
            let form = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            let active = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            results.append(BDPMMedication(
                cis: cis,
                name: name,
                shortName: short,
                dosageForm: form,
                activeIngredient: active
            ))
        }
        return results
    }
}
