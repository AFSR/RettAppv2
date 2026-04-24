import Foundation
import SwiftData

/// Importeur/exporteur CSV pour l'historique des crises.
enum SeizureImporter {

    // MARK: - Template

    static let templateFilename = "rettapp-crises-modele.csv"

    /// CSV d'exemple à proposer à l'utilisateur. Colonnes minimales : `start`, `end`.
    /// Les autres sont optionnelles.
    static var templateContent: String {
        let header = CSVParser.joinLine([
            "start", "end", "type", "trigger", "trigger_notes", "notes"
        ])
        let rows = [
            CSVParser.joinLine([
                "2025-01-15T09:30:00", "2025-01-15T09:32:34",
                "tonicClonic", "fever", "", "Forte fièvre la veille"
            ]),
            CSVParser.joinLine([
                "2025-01-22T14:05:00", "2025-01-22T14:05:45",
                "absence", "none", "", ""
            ]),
            // ligne vide d'exemple pour montrer à l'utilisateur où écrire
            CSVParser.joinLine([
                "", "", "", "", "", ""
            ])
        ]
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    static func writeTemplate() throws -> URL {
        try CSVFile.writeTemp(filename: templateFilename, content: templateContent)
    }

    // MARK: - Import

    struct ImportResult {
        let imported: Int
        let skipped: Int
        let errors: [String]
    }

    /// Parse le contenu d'un fichier CSV et insère les crises trouvées.
    /// Retourne un résumé (imported / skipped / erreurs).
    @discardableResult
    static func importCSV(
        contents: String,
        childProfile: ChildProfile?,
        context: ModelContext
    ) -> ImportResult {
        let rows = CSVParser.parseKeyed(contents)
        var imported = 0
        var skipped = 0
        var errors: [String] = []

        for (index, row) in rows.enumerated() {
            let lineNumber = index + 2  // +1 pour 1-indexed, +1 pour skip header

            guard let startStr = row["start"], let start = CSVDateParser.parse(startStr) else {
                skipped += 1
                errors.append("Ligne \(lineNumber) : date de début invalide ou manquante")
                continue
            }

            let end: Date
            if let endStr = row["end"], let parsed = CSVDateParser.parse(endStr) {
                end = parsed
            } else {
                skipped += 1
                errors.append("Ligne \(lineNumber) : date de fin invalide ou manquante")
                continue
            }

            if end < start {
                skipped += 1
                errors.append("Ligne \(lineNumber) : la date de fin est antérieure au début")
                continue
            }

            let type = SeizureType(rawValue: row["type"] ?? "") ?? .other
            let trigger = SeizureTrigger(rawValue: row["trigger"] ?? "") ?? .none

            let event = SeizureEvent(
                startTime: start,
                endTime: end,
                seizureType: type,
                trigger: trigger,
                triggerNotes: row["trigger_notes"] ?? "",
                notes: row["notes"] ?? "",
                childProfileId: childProfile?.id
            )
            context.insert(event)
            imported += 1
        }

        do {
            try context.save()
        } catch {
            errors.append("Erreur SwiftData : \(error.localizedDescription)")
        }

        return ImportResult(imported: imported, skipped: skipped, errors: errors)
    }
}
