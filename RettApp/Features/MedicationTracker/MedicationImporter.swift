import Foundation
import SwiftData

/// Importeur/exporteur CSV pour le plan médicamenteux.
enum MedicationImporter {

    static let templateFilename = "rettapp-medicaments-modele.csv"

    /// Colonnes :
    /// - `name` : nom du médicament (requis)
    /// - `dose_amount` : dose par défaut (requis)
    /// - `dose_unit` : `mg` | `ml` | `tablet`
    /// - `scheduled_hours` : prises séparées par `|`. Chaque prise au format
    ///   `HH:MM[@dose][/jours][!notif]`. Exemples :
    ///   - `08:00|20:00` → deux prises, dose par défaut, tous les jours
    ///   - `08:00@5|20:00@10` → 5 le matin, 10 le soir
    ///   - `08:00/MTWRF|10:00/SU` → en semaine vs week-end
    ///   - `08:00!off` → désactive le rappel pour cette prise
    ///   - jours : `M`=lun, `T`=mar, `W`=mer, `R`=jeu, `F`=ven, `S`=sam, `U`=dim
    /// - `kind` : `regular` (défaut) ou `adhoc`
    /// - `active` : `1`/`0` (optionnel, 1 par défaut)
    static var templateContent: String {
        let header = CSVParser.joinLine([
            "name", "dose_amount", "dose_unit", "scheduled_hours", "kind", "active"
        ])
        let rows = [
            CSVParser.joinLine(["Keppra", "500", "mg", "08:00|20:00", "regular", "1"]),
            CSVParser.joinLine(["Dépakine", "250", "mg", "08:00@250/MTWRF|10:00@500/SU", "regular", "1"]),
            CSVParser.joinLine(["Mélatonine", "5", "mg", "20:30!off", "regular", "1"]),
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
            guard !name.isEmpty else { continue }

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

            let intakes = parseIntakes(row["scheduled_hours"] ?? "", defaultDose: dose)
            if kind == .regular && intakes.isEmpty {
                skipped += 1
                errors.append("Ligne \(lineNumber) : un médicament récurrent doit avoir au moins une heure de prise (scheduled_hours)")
                continue
            }

            let activeRaw = (row["active"] ?? "1").lowercased()
            let isActive = ["1", "true", "yes", "oui"].contains(activeRaw)

            let hours = intakes.map { HourMinute(hour: $0.hour, minute: $0.minute) }
            let med = Medication(
                name: name,
                doseAmount: dose,
                doseUnit: unit,
                scheduledHours: hours,
                kind: kind,
                isActive: isActive,
                intakes: intakes
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

    /// Parse un token comme `HH:MM[@dose][/jours][!notif]`.
    /// - `dose` : nombre (point ou virgule décimale)
    /// - `jours` : combinaison de M T W R F S U, ou `WD` (semaine), `WE` (week-end), `*` (tous)
    /// - `notif` : `off` ou `0` désactive le rappel
    private static func parseIntakes(_ raw: String, defaultDose: Double) -> [MedicationIntake] {
        raw.split(whereSeparator: { $0 == "|" || $0 == ";" })
            .compactMap { tokenSub -> MedicationIntake? in
                let token = tokenSub.trimmingCharacters(in: .whitespaces)
                guard !token.isEmpty else { return nil }
                return parseOneIntake(token, defaultDose: defaultDose)
            }
    }

    private static func parseOneIntake(_ token: String, defaultDose: Double) -> MedicationIntake? {
        var remaining = token
        var notifyEnabled = true
        var weekdays = MedicationIntake.allWeekdays
        var dose = defaultDose

        if let bangIdx = remaining.firstIndex(of: "!") {
            let flag = String(remaining[remaining.index(after: bangIdx)...]).lowercased()
            if flag == "off" || flag == "0" || flag == "no" || flag == "non" {
                notifyEnabled = false
            }
            remaining = String(remaining[..<bangIdx])
        }
        if let slashIdx = remaining.firstIndex(of: "/") {
            let daysToken = String(remaining[remaining.index(after: slashIdx)...]).uppercased()
            weekdays = parseWeekdays(daysToken) ?? weekdays
            remaining = String(remaining[..<slashIdx])
        }
        if let atIdx = remaining.firstIndex(of: "@") {
            let doseToken = String(remaining[remaining.index(after: atIdx)...])
                .replacingOccurrences(of: ",", with: ".")
            if let v = Double(doseToken) { dose = v }
            remaining = String(remaining[..<atIdx])
        }

        let parts = remaining.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let m = Int(parts[1].trimmingCharacters(in: .whitespaces)),
              (0...23).contains(h),
              (0...59).contains(m)
        else { return nil }

        return MedicationIntake(
            hour: h, minute: m, dose: dose,
            weekdays: weekdays, notifyEnabled: notifyEnabled
        )
    }

    /// Convertit une chaîne de codes (M/T/W/R/F/S/U, ou WD/WE/*) en set Calendar (1=Sun).
    private static func parseWeekdays(_ token: String) -> Set<Int>? {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if trimmed == "*" || trimmed == "ALL" { return MedicationIntake.allWeekdays }
        if trimmed == "WD" || trimmed == "WEEK" { return MedicationIntake.weekdaysOnly }
        if trimmed == "WE" || trimmed == "WEEKEND" { return MedicationIntake.weekendOnly }
        var out = Set<Int>()
        for ch in trimmed {
            switch ch {
            case "M": out.insert(2)
            case "T": out.insert(3)
            case "W": out.insert(4)
            case "R": out.insert(5) // R = Thursday (R évite la collision avec T)
            case "F": out.insert(6)
            case "S": out.insert(7)
            case "U": out.insert(1) // U = Sunday
            default: continue
            }
        }
        return out.isEmpty ? nil : out
    }
}
