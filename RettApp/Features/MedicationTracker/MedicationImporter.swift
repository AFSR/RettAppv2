import Foundation
import SwiftData

/// Importeur/exporteur CSV pour le plan médicamenteux.
enum MedicationImporter {

    static let templateFilename = "rettapp-medicaments-modele.csv"

    /// Colonnes :
    /// - `name` : nom du médicament (requis)
    /// - `dose_amount` : quantité numérique (requis, virgule ou point)
    /// - `dose_unit` : `mg` | `ml` | `tablet`
    /// - `scheduled_hours` : heures de prise au format `HH:MM`, séparées par `|`
    ///   (ex. `08:00|12:00|20:00`)
    /// - `active` : `1`/`0` (optionnel, 1 par défaut)
    static var templateContent: String {
        let header = CSVParser.joinLine([
            "name", "dose_amount", "dose_unit", "scheduled_hours", "kind", "active"
        ])
        let rows = [
            CSVParser.joinLine(["Keppra", "500", "mg", "08:00|20:00", "regular", "1"]),
            CSVParser.joinLine(["Dépakine", "250", "mg", "08:00|12:00|20:00", "regular", "1"]),
            CSVParser.joinLine(["Doliprane (à la demande)", "150", "mg", "", "adhoc", "1"]),
            CSVParser.joinLine(["", "", "", "", "", ""])
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

            let name = (row["name"] ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                // ligne vide : on ne compte pas comme erreur
                continue
            }

            let doseStr = (row["dose_amount"] ?? "").replacingOccurrences(of: ",", with: ".")
            guard let dose = Double(doseStr) else {
                skipped += 1
                errors.append("Ligne \(lineNumber) : dose_amount invalide ('\(doseStr)')")
                continue
            }

            let unitRaw = (row["dose_unit"] ?? "mg").lowercased()
            let unit = DoseUnit(rawValue: unitRaw) ?? .mg

            let kindRaw = (row["kind"] ?? "regular").lowercased()
            let kind: MedicationKind = MedicationKind(rawValue: kindRaw) ?? .regular

            let hours = parseHours(row["scheduled_hours"] ?? "")
            if kind == .regular && hours.isEmpty {
                skipped += 1
                errors.append("Ligne \(lineNumber) : un médicament récurrent doit avoir au moins une heure de prise (scheduled_hours)")
                continue
            }

            let activeRaw = (row["active"] ?? "1").lowercased()
            let isActive = ["1", "true", "yes", "oui"].contains(activeRaw)

            let med = Medication(
                name: name,
                doseAmount: dose,
                doseUnit: unit,
                scheduledHours: hours,
                kind: kind,
                isActive: isActive
            )
            med.childProfile = childProfile
            context.insert(med)
            imported += 1
        }

        do {
            try context.save()
        } catch {
            errors.append("Erreur SwiftData : \(error.localizedDescription)")
        }

        return ImportResult(imported: imported, skipped: skipped, errors: errors)
    }

    private static func parseHours(_ raw: String) -> [HourMinute] {
        raw.split(whereSeparator: { $0 == "|" || $0 == "," })
            .compactMap { token -> HourMinute? in
                let parts = token.trimmingCharacters(in: .whitespaces).split(separator: ":")
                guard parts.count == 2,
                      let h = Int(parts[0]),
                      let m = Int(parts[1]),
                      (0...23).contains(h),
                      (0...59).contains(m)
                else { return nil }
                return HourMinute(hour: h, minute: m)
            }
    }
}
