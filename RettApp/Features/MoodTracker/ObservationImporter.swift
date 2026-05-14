import Foundation
import SwiftData

/// Importeur CSV pour les observations quotidiennes historiques (repas,
/// hydratation, sommeil).
enum ObservationImporter {

    static let templateFilename = "rettapp-observations-modele.csv"

    /// Colonnes : `day` (YYYY-MM-DD), `breakfast`/`lunch`/`snack`/`dinner`
    /// (note 1-5), `hydration` (1-5), `night_sleep_minutes` (entier),
    /// `night_sleep_rating` (1-5), `nap_minutes` (entier), `notes`.
    /// Toutes les colonnes sauf `day` sont optionnelles.
    static var templateContent: String {
        let header = CSVParser.joinLine([
            "day", "breakfast", "lunch", "snack", "dinner",
            "hydration", "night_sleep_minutes", "night_sleep_rating",
            "nap_minutes", "notes"
        ])
        let rows = [
            CSVParser.joinLine([
                "2025-01-15", "4", "3", "4", "5",
                "4", "540", "4", "45", "Très bonne journée"
            ]),
            CSVParser.joinLine([
                "2025-01-16", "3", "2", "", "3",
                "3", "420", "3", "0", ""
            ]),
            CSVParser.joinLine([
                "", "", "", "", "", "", "", "", "", ""
            ])
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
        let cal = Calendar.current

        for (index, row) in rows.enumerated() {
            let lineNumber = index + 2

            // Accepte yyyy-MM-dd OU ISO 8601 complet
            guard let dayStr = row["day"], let day = CSVDateParser.parse(dayStr) else {
                skipped += 1
                errors.append("Ligne \(lineNumber) : date du jour invalide (format yyyy-MM-dd attendu)")
                continue
            }
            let dayStart = cal.startOfDay(for: day)

            // Cherche une observation existante pour ce jour, sinon en crée une
            let descriptor = FetchDescriptor<DailyObservation>(
                predicate: #Predicate<DailyObservation> { $0.dayStart == dayStart }
            )
            let obs: DailyObservation
            if let existing = (try? context.fetch(descriptor))?.first {
                obs = existing
            } else {
                obs = DailyObservation(dayStart: dayStart, childProfileId: childProfile?.id)
                context.insert(obs)
            }

            if let r = parseRating(row["breakfast"]) { obs.breakfastRatingRaw = r }
            if let r = parseRating(row["lunch"])     { obs.lunchRatingRaw = r }
            if let r = parseRating(row["snack"])     { obs.snackRatingRaw = r }
            if let r = parseRating(row["dinner"])    { obs.dinnerRatingRaw = r }
            if let r = parseRating(row["hydration"]) { obs.hydrationRatingRaw = r }
            if let m = row["night_sleep_minutes"].flatMap(Int.init), m > 0 {
                obs.nightSleepDurationMinutes = m
            }
            if let r = parseRating(row["night_sleep_rating"]) { obs.nightSleepRatingRaw = r }
            if let m = row["nap_minutes"].flatMap(Int.init), m > 0 {
                obs.napDurationMinutes = m
            }
            if let notes = row["notes"], !notes.isEmpty {
                obs.generalNotes = obs.generalNotes.isEmpty ? notes : obs.generalNotes + "\n" + notes
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

    private static func parseRating(_ s: String?) -> Int? {
        guard let s, let v = Int(s), (1...5).contains(v) else { return nil }
        return v
    }
}
