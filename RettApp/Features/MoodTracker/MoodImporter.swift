import Foundation
import SwiftData

/// Importeur CSV pour l'historique des humeurs.
enum MoodImporter {

    static let templateFilename = "rettapp-humeurs-modele.csv"

    /// Colonnes : `timestamp` (ISO 8601), `level` (1-5), `notes` (optionnel).
    static var templateContent: String {
        let header = CSVParser.joinLine(["timestamp", "level", "notes"])
        let rows = [
            CSVParser.joinLine(["2025-01-15T10:00:00", "4", "Belle matinée"]),
            CSVParser.joinLine(["2025-01-15T18:00:00", "3", ""]),
            CSVParser.joinLine(["", "", ""])
        ]
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    static func writeTemplate() throws -> URL {
        try CSVFile.writeTemp(filename: templateFilename, content: templateContent)
    }

    struct ImportResult {
        let imported: Int
        let skipped: Int
        let errors: [String]
    }

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
            let lineNumber = index + 2

            guard let tsStr = row["timestamp"], let timestamp = CSVDateParser.parse(tsStr) else {
                skipped += 1
                errors.append("Ligne \(lineNumber) : horodatage invalide ou manquant")
                continue
            }
            guard let levelStr = row["level"], let levelInt = Int(levelStr),
                  let level = MoodLevel(rawValue: levelInt) else {
                skipped += 1
                errors.append("Ligne \(lineNumber) : niveau d'humeur invalide (attendu 1-5)")
                continue
            }

            let entry = MoodEntry(
                timestamp: timestamp,
                level: level,
                notes: row["notes"] ?? "",
                childProfileId: childProfile?.id
            )
            context.insert(entry)
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
