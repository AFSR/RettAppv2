import Foundation

/// Façade unifiée pour l'autocomplete des médicaments à la saisie. Préfère la
/// base BDPM bundlée (~15 000 spécialités quand l'utilisateur l'a rafraîchie
/// via `scripts/build_bdpm_db.rb`, sinon ~50 médicaments curatés en seed) et
/// retombe sur la liste statique `CommonFrenchMedications` quand SQLite n'est
/// pas disponible (cas du Preview SwiftUI sans bundle complet).
///
/// Toujours appeler ce façade plutôt que `CommonFrenchMedications` ou
/// `BDPMDatabase` directement — ça garantit le comportement cohérent dans
/// tous les écrans de saisie.
@MainActor
enum MedicationCatalog {

    static func suggestions(matching query: String, limit: Int = 6) -> [BDPMMedication] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let bdpm = BDPMDatabase.shared.suggestions(matching: trimmed, limit: limit)
        if !bdpm.isEmpty { return bdpm }

        // Fallback : convertit la liste statique en BDPMMedication pour que
        // les vues n'aient qu'un seul type à afficher.
        return CommonFrenchMedications
            .suggestions(matching: trimmed, limit: limit)
            .enumerated()
            .map { idx, raw in
                let short = raw.split(separator: "(").first.map(String.init)?
                    .trimmingCharacters(in: .whitespaces) ?? raw
                let active = raw.range(of: #"\(([^)]+)\)"#, options: .regularExpression)
                    .flatMap { String(raw[$0]).trimmingCharacters(in: CharacterSet(charactersIn: "() ")) }
                return BDPMMedication(
                    cis: -(idx + 1),
                    name: raw,
                    shortName: short,
                    dosageForm: nil,
                    activeIngredient: active
                )
            }
    }
}
