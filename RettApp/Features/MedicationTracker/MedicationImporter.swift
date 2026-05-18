import Foundation
import SwiftData

/// Importeur/exporteur CSV pour le plan médicamenteux.
enum MedicationImporter {

    static let templateFilename = "rettapp-medicaments-modele.csv"

    /// Colonnes :
    /// - `name` : nom du médicament (requis)
    /// - `dose_amount` : dose par défaut (requis, virgule ou point)
    /// - `dose_unit` : `mg` | `ml` | `tablet`
    /// - `scheduled_hours` : heures de prise séparées par `|`
    ///   (ex. `08:00|20:00`). Pour un ad-hoc, laissez vide.
    ///   Forme avancée par prise : `HH:MM[@dose][/jours][!off]`
    ///   - `08:00@250/MTWRF` → 250 mg en semaine seulement
    ///   - `20:30!off` → désactive le rappel pour cette prise
    ///   - jours : `M`=lun, `T`=mar, `W`=mer, `R`=jeu, `F`=ven, `S`=sam, `U`=dim,
    ///     `WD`=semaine, `WE`=week-end, `*`=tous
    /// - `kind` : `regular` (défaut) ou `adhoc`
    /// - `active` : `1` (défaut) ou `0`
    /// - `effective_from` (**optionnel**, `yyyy-MM-dd` ou ISO 8601) :
    ///   - vide → état actuel du médicament
    ///   - daté → révision historique ajoutée à l'historique du plan.
    ///     Plusieurs lignes pour un même nom reconstruisent l'historique.
    static var templateContent: String {
        let header = CSVParser.joinLine([
            "name", "dose_amount", "dose_unit", "scheduled_hours", "kind", "active", "effective_from"
        ])
        let rows = [
            // Exemple récurrent simple
            CSVParser.joinLine(["Keppra", "500", "mg", "08:00|20:00", "regular", "1", ""]),
            // Exemple ad-hoc (sans horaires)
            CSVParser.joinLine(["Doliprane", "150", "mg", "", "adhoc", "1", ""]),
            // Ligne vide à compléter — laissez l'effective_from vide pour
            // un état actuel, ou mettez une date passée pour ajouter à
            // l'historique du plan.
            CSVParser.joinLine(["", "", "", "", "", "", ""])
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

        // (1) Parse toutes les lignes en `ParsedRow` (sans effet de bord),
        //     puis groupe par nom de médicament. Permet de traiter les
        //     révisions historiques d'un même med dans l'ordre chronologique.
        struct ParsedRow {
            let lineNumber: Int
            let name: String
            let dose: Double
            let unit: DoseUnit
            let kind: MedicationKind
            let intakes: [MedicationIntake]
            let isActive: Bool
            let effectiveFrom: Date?
        }

        var parsed: [ParsedRow] = []
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

            // Parsing optionnel de l'horodatage de révision.
            let effectiveFromRaw = (row["effective_from"] ?? "").trimmingCharacters(in: .whitespaces)
            var effectiveFrom: Date? = nil
            if !effectiveFromRaw.isEmpty {
                if let date = CSVDateParser.parse(effectiveFromRaw) {
                    effectiveFrom = date
                } else {
                    skipped += 1
                    errors.append("Ligne \(lineNumber) : effective_from invalide ('\(effectiveFromRaw)'). Format attendu : yyyy-MM-dd ou ISO 8601.")
                    continue
                }
            }

            parsed.append(ParsedRow(
                lineNumber: lineNumber,
                name: name,
                dose: dose,
                unit: unit,
                kind: kind,
                intakes: intakes,
                isActive: isActive,
                effectiveFrom: effectiveFrom
            ))
        }

        // (2) Group by name (case-sensitive, comme l'UI). Pour chaque
        //     groupe, on construit (ou retrouve) un `Medication` et on
        //     insère les révisions horodatées.
        let groups = Dictionary(grouping: parsed) { $0.name }

        for (name, group) in groups {
            // Cherche un Medication existant avec ce nom — pour éviter de
            // dupliquer quand on relance un import.
            let medQuery = FetchDescriptor<Medication>(
                predicate: #Predicate { $0.name == name }
            )
            let existing = (try? context.fetch(medQuery))?.first

            // La ligne « état courant » = celle sans effective_from. S'il y
            // en a plusieurs (erreur), on garde la dernière vue dans le CSV.
            // Si aucune n'est marquée « courant », on prend la révision la
            // plus récente comme état courant.
            let currentRow: ParsedRow
            let historyRows: [ParsedRow]
            if let withoutDate = group.last(where: { $0.effectiveFrom == nil }) {
                currentRow = withoutDate
                historyRows = group.filter { $0.effectiveFrom != nil }
            } else {
                // Aucune ligne « courante » : la révision la plus récente
                // sert d'état courant.
                let sorted = group.sorted { ($0.effectiveFrom ?? .distantPast) < ($1.effectiveFrom ?? .distantPast) }
                guard let last = sorted.last else { continue }
                currentRow = last
                historyRows = sorted
            }

            let med: Medication
            if let existing {
                existing.name = currentRow.name
                existing.doseAmount = currentRow.dose
                existing.doseUnit = currentRow.unit
                existing.kind = currentRow.kind
                existing.isActive = currentRow.isActive
                existing.intakes = currentRow.intakes
                if existing.childProfile == nil { existing.childProfile = childProfile }
                med = existing
            } else {
                let hours = currentRow.intakes.map { HourMinute(hour: $0.hour, minute: $0.minute) }
                let new = Medication(
                    name: currentRow.name,
                    doseAmount: currentRow.dose,
                    doseUnit: currentRow.unit,
                    scheduledHours: hours,
                    kind: currentRow.kind,
                    isActive: currentRow.isActive,
                    intakes: currentRow.intakes
                )
                new.childProfile = childProfile
                context.insert(new)
                med = new
            }
            imported += 1

            // Insère les révisions historiques pour ce med, triées par date.
            let sortedHistory = historyRows.sorted {
                ($0.effectiveFrom ?? .distantPast) < ($1.effectiveFrom ?? .distantPast)
            }
            for rev in sortedHistory {
                guard let date = rev.effectiveFrom else { continue }
                let revision = MedicationRevision(
                    medicationId: med.id,
                    effectiveFrom: date,
                    name: rev.name,
                    doseAmount: rev.dose,
                    doseUnit: rev.unit,
                    intakes: rev.intakes,
                    kind: rev.kind,
                    isActive: rev.isActive,
                    notifyEnabled: true
                )
                context.insert(revision)
            }
        }

        do {
            try context.saveTouching()
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
