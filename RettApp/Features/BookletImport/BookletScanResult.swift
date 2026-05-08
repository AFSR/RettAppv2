import Foundation

/// Résultat structuré d'un scan de cahier de suivi.
/// Chaque ligne `Cell` indique : section, jour, indices logiques, état (coché ou non).
/// L'utilisateur peut modifier librement chaque case via la review UI avant
/// l'insertion réelle dans le journal.
struct BookletScanResult {
    let schema: BookletSchema
    /// État coché/non-coché pour chaque cellule du layout.
    /// Clé = `BookletLayoutEngine.Cell` ; valeur = vrai si coché.
    var checks: [BookletLayoutEngine.Cell: Bool]

    /// Date Swift du jour `dayIndex` (0 = lundi de la semaine du schéma).
    func date(forDay dayIndex: Int, calendar: Calendar = .current) -> Date? {
        schema.date(forDayIndex: dayIndex, calendar: calendar)
    }

    /// Toutes les cellules cochées.
    var checkedCells: [BookletLayoutEngine.Cell] {
        checks.filter { $0.value }.map(\.key)
    }
}
