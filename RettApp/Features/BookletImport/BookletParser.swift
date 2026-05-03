import Foundation

/// Heuristique de parsing de l'OCR du cahier de suivi. Le cahier est rempli à
/// la main, donc l'OCR n'est jamais parfait — on extrait ce qu'on peut et on
/// laisse le parent compléter / corriger dans le formulaire.
///
/// Stratégie : recherche de mots-clés ("petit-déjeuner", "déjeuner", "goûter",
/// "dîner", "sieste", "sommeil", "hydratation"…) suivis d'évaluations
/// (★★★, "bien", "moyen", "mauvais", chiffres) ou de durées ("1h30", "8h").
struct BookletParser {
    struct Extracted {
        var dayDate: Date?
        var breakfastRating: Int = 0
        var breakfastNotes: String = ""
        var lunchRating: Int = 0
        var lunchNotes: String = ""
        var snackRating: Int = 0
        var snackNotes: String = ""
        var dinnerRating: Int = 0
        var dinnerNotes: String = ""
        var hydrationRating: Int = 0
        var hydrationNotes: String = ""
        var nightSleepRating: Int = 0
        var nightSleepDurationMinutes: Int = 0
        var nightSleepNotes: String = ""
        var napDurationMinutes: Int = 0
        var napNotes: String = ""
        var generalNotes: String = ""
        /// Texte brut OCR conservé pour permettre à l'utilisateur de tout vérifier.
        var rawOCR: String = ""
    }

    static func parse(_ text: String) -> Extracted {
        var out = Extracted()
        out.rawOCR = text
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        out.dayDate = findDate(in: lines)

        for raw in lines {
            let lower = raw.lowercased()
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))

            if matches(lower, ["petit", "dejeuner"]) || matches(lower, ["petit-dejeuner"]) {
                out.breakfastRating = ratingFrom(line: raw)
                out.breakfastNotes = stripLabelAndRating(raw)
            } else if matches(lower, ["dejeuner"]) && !lower.contains("petit") {
                out.lunchRating = ratingFrom(line: raw)
                out.lunchNotes = stripLabelAndRating(raw)
            } else if matches(lower, ["gouter"]) || matches(lower, ["collation"]) {
                out.snackRating = ratingFrom(line: raw)
                out.snackNotes = stripLabelAndRating(raw)
            } else if matches(lower, ["diner"]) || matches(lower, ["souper"]) {
                out.dinnerRating = ratingFrom(line: raw)
                out.dinnerNotes = stripLabelAndRating(raw)
            } else if matches(lower, ["hydrat"]) || matches(lower, ["boisson"]) || matches(lower, ["eau"]) {
                out.hydrationRating = ratingFrom(line: raw)
                out.hydrationNotes = stripLabelAndRating(raw)
            } else if matches(lower, ["sieste"]) {
                out.napDurationMinutes = durationMinutesFrom(line: raw)
                out.napNotes = stripLabelAndRating(raw)
            } else if matches(lower, ["sommeil"]) || matches(lower, ["nuit"]) {
                out.nightSleepRating = ratingFrom(line: raw)
                out.nightSleepDurationMinutes = durationMinutesFrom(line: raw)
                out.nightSleepNotes = stripLabelAndRating(raw)
            } else if matches(lower, ["remarque"]) || matches(lower, ["note"]) || matches(lower, ["divers"]) {
                if !out.generalNotes.isEmpty { out.generalNotes += "\n" }
                out.generalNotes += stripLabelAndRating(raw)
            }
        }
        return out
    }

    // MARK: - Helpers

    private static func matches(_ haystack: String, _ needles: [String]) -> Bool {
        needles.allSatisfy { haystack.contains($0) }
    }

    /// Cherche une note 1-5 dans la ligne. Reconnaît :
    /// - étoiles ★ ou *
    /// - chiffre /5 (ex. "3/5", "4 sur 5")
    /// - vocabulaire qualitatif (très bien=5, bien=4, moyen=3, peu=2, mauvais=1)
    private static func ratingFrom(line: String) -> Int {
        // Étoiles
        let stars = line.filter { $0 == "★" || $0 == "*" }.count
        if stars >= 1, stars <= 5 { return stars }
        // Chiffre /5
        if let match = line.range(of: #"([1-5])\s*/\s*5"#, options: .regularExpression) {
            if let n = Int(line[match].first.map(String.init) ?? "") {
                return n
            }
        }
        if let match = line.range(of: #"([1-5])\s*sur\s*5"#, options: .regularExpression) {
            if let n = Int(line[match].first.map(String.init) ?? "") {
                return n
            }
        }
        // Qualitatif
        let lower = line.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
        if lower.contains("tres bien") || lower.contains("excellent") { return 5 }
        if lower.contains("bien") && !lower.contains("pas bien") { return 4 }
        if lower.contains("moyen") || lower.contains("correct") { return 3 }
        if lower.contains("peu") || lower.contains("difficile") { return 2 }
        if lower.contains("mauvais") || lower.contains("rien") || lower.contains("refuse") { return 1 }
        return 0
    }

    /// Cherche une durée en minutes — formats acceptés : "1h30", "1 h 30", "8h", "45 min", "90 minutes"
    private static func durationMinutesFrom(line: String) -> Int {
        // 1h30 / 1 h 30 / 1h
        if let m = line.range(of: #"(\d{1,2})\s*[hH]\s*(\d{0,2})"#, options: .regularExpression) {
            let str = String(line[m])
            let parts = str.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if parts.count >= 2 { return parts[0] * 60 + parts[1] }
            if parts.count == 1 { return parts[0] * 60 }
        }
        // 45 min / 90 minutes
        if let m = line.range(of: #"(\d{1,3})\s*min"#, options: .regularExpression) {
            let str = String(line[m])
            if let n = str.split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }).first {
                return n
            }
        }
        return 0
    }

    /// Retire les mots-clés de label et les notations chiffrées pour ne garder que le texte libre.
    private static func stripLabelAndRating(_ line: String) -> String {
        var s = line
        let labels = [
            "petit-déjeuner", "petit-dejeuner", "petit déjeuner", "petit dejeuner",
            "déjeuner", "dejeuner",
            "goûter", "gouter", "collation",
            "dîner", "diner", "souper",
            "hydratation", "boisson", "eau",
            "sieste",
            "sommeil", "nuit",
            "remarque", "remarques", "note", "notes", "divers"
        ]
        for label in labels {
            if let r = s.range(of: label, options: [.caseInsensitive, .diacriticInsensitive]) {
                s.removeSubrange(r)
            }
        }
        s = s.replacingOccurrences(of: ":", with: "")
        s = s.replacingOccurrences(of: "★", with: "")
        s = s.replacingOccurrences(of: "*", with: "")
        s = s.replacingOccurrences(of: #"\d\s*/\s*5"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\d+\s*sur\s*5"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\d{1,2}\s*[hH]\s*\d{0,2}"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\d{1,3}\s*min(utes)?"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Détecte une date au format "DD/MM/YYYY" ou "DD MMMM YYYY" en français.
    private static func findDate(in lines: [String]) -> Date? {
        let cal = Calendar(identifier: .gregorian)
        let fr = Locale(identifier: "fr_FR")
        let formatters: [DateFormatter] = [
            { let f = DateFormatter(); f.locale = fr; f.dateFormat = "dd/MM/yyyy"; return f }(),
            { let f = DateFormatter(); f.locale = fr; f.dateFormat = "d/M/yyyy"; return f }(),
            { let f = DateFormatter(); f.locale = fr; f.dateFormat = "dd-MM-yyyy"; return f }(),
            { let f = DateFormatter(); f.locale = fr; f.dateFormat = "d MMMM yyyy"; return f }(),
            { let f = DateFormatter(); f.locale = fr; f.dateFormat = "dd MMMM yyyy"; return f }()
        ]
        for line in lines {
            for f in formatters {
                if let d = f.date(from: line) { return cal.startOfDay(for: d) }
                // Cherche aussi à l'intérieur d'une ligne plus longue
                if let m = line.range(of: #"\d{1,2}[/\- ]\d{1,2}[/\- ]\d{2,4}"#, options: .regularExpression) {
                    let snippet = String(line[m])
                    if let d = f.date(from: snippet) { return cal.startOfDay(for: d) }
                }
            }
        }
        return nil
    }
}
