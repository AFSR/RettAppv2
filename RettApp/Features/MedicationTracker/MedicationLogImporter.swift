import Foundation
import SwiftData

/// Importeur/exporteur CSV pour les prises de médicament (`MedicationLog`).
///
/// Sert à pré-remplir le journal d'observance à partir d'un suivi externe
/// (tableur Excel/Numbers, dossier médical exporté, ancien outil de suivi).
/// Distinct de `MedicationImporter` qui gère le **plan** lui-même.
///
/// Lien avec le plan : le champ `medication_name` est utilisé pour retrouver
/// le `Medication` existant. Pour les prises ponctuelles (`is_adhoc = 1`),
/// si le médicament n'existe pas dans le plan on enregistre quand même la
/// prise avec un `medicationId` dédié — utile pour les antipyrétiques pris
/// occasionnellement.
enum MedicationLogImporter {

    static let templateFilename = "rettapp-prises-modele.csv"

    /// Colonnes :
    /// - `scheduled_time` : horodatage prévu (requis, ISO 8601 ou yyyy-MM-dd HH:mm)
    /// - `medication_name` : nom du médicament (requis, doit matcher le plan
    ///   pour une prise planifiée ; libre pour `is_adhoc = 1`)
    /// - `taken` : `1`/`0` (défaut 0)
    /// - `taken_time` : horodatage de la prise réelle (optionnel, requis si
    ///   `taken = 1` pour distinguer décalage d'avec `scheduled_time`)
    /// - `dose` : dose effectivement donnée (optionnel — hérite du plan sinon)
    /// - `dose_unit` : `mg` | `ml` | `tablet` (optionnel — hérite du plan sinon)
    /// - `is_adhoc` : `1`/`0` (défaut 0). Si 1, c'est une prise ponctuelle
    ///   hors plan régulier.
    /// - `adhoc_reason` : motif libre pour les prises ponctuelles
    ///   (« fièvre », « post-crise », etc.)
    static var templateContent: String {
        let header = CSVParser.joinLine([
            "scheduled_time", "medication_name", "taken", "taken_time",
            "dose", "dose_unit", "is_adhoc", "adhoc_reason"
        ])
        let rows = [
            // Prise prévue à 8h, prise effectivement à 8h05
            CSVParser.joinLine(["2025-10-15T08:00", "Keppra", "1", "2025-10-15T08:05",
                                "500", "mg", "0", ""]),
            // Prise prévue à 20h, oubliée
            CSVParser.joinLine(["2025-10-15T20:00", "Keppra", "0", "",
                                "500", "mg", "0", ""]),
            // Prise ponctuelle (Doliprane pour fièvre, hors plan régulier)
            CSVParser.joinLine(["2025-10-15T15:30", "Doliprane", "1", "2025-10-15T15:30",
                                "150", "mg", "1", "fièvre 38.5"]),
            CSVParser.joinLine(["", "", "", "", "", "", "", ""])
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

        // Index des médicaments par nom pour lookup rapide. `uniquingKeysWith`
        // protège contre les doublons potentiels (utilisateur ayant créé
        // manuellement deux « Likozam », ou import lancé deux fois) — on
        // garde le premier rencontré, les logs s'attacheront à celui-là.
        // L'utilisateur peut dédupliquer après coup via Settings.
        let medsByName: [String: Medication] = {
            let fetched = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
            return Dictionary(fetched.map { ($0.name, $0) },
                              uniquingKeysWith: { first, _ in first })
        }()

        for (index, row) in rows.enumerated() {
            let lineNumber = index + 2

            let scheduledRaw = (row["scheduled_time"] ?? "").trimmingCharacters(in: .whitespaces)
            guard !scheduledRaw.isEmpty else { continue }
            guard let scheduledTime = CSVDateParser.parse(scheduledRaw) else {
                skipped += 1
                errors.append("Ligne \(lineNumber) : scheduled_time invalide ('\(scheduledRaw)')")
                continue
            }

            let medName = (row["medication_name"] ?? "").trimmingCharacters(in: .whitespaces)
            guard !medName.isEmpty else {
                skipped += 1
                errors.append("Ligne \(lineNumber) : medication_name requis")
                continue
            }

            let takenRaw = (row["taken"] ?? "0").lowercased()
            let taken = ["1", "true", "yes", "oui"].contains(takenRaw)

            let takenTimeRaw = (row["taken_time"] ?? "").trimmingCharacters(in: .whitespaces)
            let takenTime: Date? = takenTimeRaw.isEmpty ? nil : CSVDateParser.parse(takenTimeRaw)

            let adhocRaw = (row["is_adhoc"] ?? "0").lowercased()
            let isAdHoc = ["1", "true", "yes", "oui"].contains(adhocRaw)

            // Médicament cible : pour une prise planifiée, on attend qu'il
            // existe dans le plan. Pour une prise ponctuelle, on accepte
            // un nom libre et on génère un UUID éphémère.
            let medicationId: UUID
            let resolvedName: String
            let defaultDose: Double
            let defaultUnit: DoseUnit
            if let med = medsByName[medName] {
                medicationId = med.id
                resolvedName = med.name
                defaultDose = med.doseAmount
                defaultUnit = med.doseUnit
            } else if isAdHoc {
                medicationId = UUID()
                resolvedName = medName
                defaultDose = 0
                defaultUnit = .mg
            } else {
                skipped += 1
                errors.append("Ligne \(lineNumber) : médicament '\(medName)' introuvable dans le plan (pour une prise hors plan, utilisez is_adhoc = 1)")
                continue
            }

            let doseStr = (row["dose"] ?? "").replacingOccurrences(of: ",", with: ".")
            let dose: Double = Double(doseStr) ?? defaultDose

            let unitRaw = (row["dose_unit"] ?? "").lowercased()
            let unit = DoseUnit(rawValue: unitRaw) ?? defaultUnit

            let adhocReason = (row["adhoc_reason"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            // Idempotence : on évite le doublon si une prise existe déjà pour
            // (medicationId, scheduledTime). Met à jour les champs sinon.
            let descriptor = FetchDescriptor<MedicationLog>(
                predicate: #Predicate<MedicationLog> { log in
                    log.medicationId == medicationId && log.scheduledTime == scheduledTime
                }
            )
            if let existing = (try? context.fetch(descriptor))?.first {
                existing.medicationName = resolvedName
                existing.taken = taken
                existing.takenTime = takenTime
                existing.dose = dose
                existing.doseUnit = unit
                existing.isAdHoc = isAdHoc
                existing.adhocReason = adhocReason
                existing.childProfileId = childProfile?.id
            } else {
                let log = MedicationLog(
                    medicationId: medicationId,
                    medicationName: resolvedName,
                    scheduledTime: scheduledTime,
                    takenTime: takenTime,
                    taken: taken,
                    dose: dose,
                    doseUnit: unit,
                    childProfileId: childProfile?.id,
                    isAdHoc: isAdHoc,
                    adhocReason: adhocReason
                )
                context.insert(log)
            }
            imported += 1
        }

        do {
            try context.saveTouching()
        } catch {
            errors.append("Erreur SwiftData : \(error.localizedDescription)")
        }

        return ImportResult(imported: imported, skipped: skipped, errors: errors)
    }
}
