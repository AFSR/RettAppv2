import Foundation

/// Heuristique de parsing de l'OCR du cahier de suivi.
///
/// Le cahier a évolué : il n'utilise plus de saisie texte libre mais des cases
/// à cocher avec des codes pré-définis (R/P/M/B/T pour les repas,
/// 0/1/2-3/4+ pour les crises, <6/6-8/8-10/>10 pour le sommeil…).
///
/// La détection de coches manuscrites est imparfaite sans pixel-analysis ; on
/// se base donc sur l'OCR du texte avoisinant chaque section pour faire au
/// mieux. La convention :
///   1. On scanne le texte ligne par ligne.
///   2. Pour chaque section on regarde le mot-clé (« petit-déjeuner »,
///      « hydratation », « sieste », etc.).
///   3. On regarde si l'un des codes d'option (R/P/M/B/T/F/E/B/D/h/min…)
///      apparaît à proximité du mot-clé sur la même ligne ou la suivante,
///      et on en déduit une valeur.
///   4. Le résultat est *toujours* à vérifier par l'utilisateur dans le
///      formulaire de revue — d'où le grand DisclosureGroup « Texte OCR brut ».
struct BookletParser {

    struct Extracted {
        var dayDate: Date?
        var breakfastRating: Int = 0
        var lunchRating: Int = 0
        var snackRating: Int = 0
        var dinnerRating: Int = 0
        var hydrationRating: Int = 0
        var nightSleepRating: Int = 0
        var nightSleepDurationMinutes: Int = 0
        var napDurationMinutes: Int = 0
        var generalNotes: String = ""
        var rawOCR: String = ""
    }

    static func parse(_ text: String) -> Extracted {
        var out = Extracted()
        out.rawOCR = text
        let rawLines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Index normalisé : minuscules + sans accents
        let normalizedLines: [String] = rawLines.map {
            $0.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
        }

        out.dayDate = findDate(in: rawLines)

        // ── Repas — quantité (R/P/M/B/T → 1/2/3/4/5)
        out.breakfastRating = mealRating(near: ["petit", "dejeuner"], lines: normalizedLines, exclude: nil)
        out.lunchRating     = mealRating(near: ["dejeuner"], lines: normalizedLines, exclude: ["petit"])
        out.snackRating     = mealRating(near: ["gouter"], lines: normalizedLines, exclude: nil)
            .nonZeroOr(mealRating(near: ["collation"], lines: normalizedLines, exclude: nil))
        out.dinnerRating    = mealRating(near: ["diner"], lines: normalizedLines, exclude: nil)
            .nonZeroOr(mealRating(near: ["souper"], lines: normalizedLines, exclude: nil))

        // ── Hydratation (F/M/B/E → 1/3/4/5)
        out.hydrationRating = hydrationRating(near: ["hydrat"], lines: normalizedLines)
            .nonZeroOr(hydrationRating(near: ["boisson"], lines: normalizedLines))
            .nonZeroOr(hydrationRating(near: ["apport"], lines: normalizedLines))

        // ── Sommeil de nuit — qualité (B/M/D)
        out.nightSleepRating = sleepQualityRating(near: ["qualite", "sommeil"], lines: normalizedLines)
            .nonZeroOr(sleepQualityRating(near: ["nuit"], lines: normalizedLines))

        // ── Sommeil de nuit — durée (<6 / 6-8 / 8-10 / >10 h)
        out.nightSleepDurationMinutes = sleepDurationMinutes(near: ["sommeil", "nuit"], lines: normalizedLines)
            .nonZeroOr(sleepDurationMinutes(near: ["sommeil", "h"], lines: normalizedLines))

        // ── Sieste — durée (Non / <30 / 30-60 / >60 min)
        let napMatin = napMinutes(near: ["sieste", "matin"], lines: normalizedLines)
        let napAprem = napMinutes(near: ["sieste", "apres"], lines: normalizedLines)
            .nonZeroOr(napMinutes(near: ["sieste", "midi"], lines: normalizedLines))
        // Si on a les deux, on additionne ; sinon on prend ce qu'on a.
        out.napDurationMinutes = napMatin + napAprem

        // ── Notes : on copie tel quel le texte des lignes "remarque/note/divers"
        for raw in rawLines {
            let lower = raw.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
            if lower.contains("remarque") || lower.contains("evenement") {
                let stripped = raw
                    .replacingOccurrences(of: "Remarque(s)?", with: "", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: "Évén?ement(s)? ?particulier(s)?", with: "", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: ":", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !stripped.isEmpty {
                    if !out.generalNotes.isEmpty { out.generalNotes += "\n" }
                    out.generalNotes += stripped
                }
            }
        }

        return out
    }

    // MARK: - Per-section heuristics

    /// R/P/M/B/T → 1/2/3/4/5 (Refusé / Peu / Moyen / Bien / Très bien)
    private static func mealRating(near keywords: [String], lines: [String], exclude: [String]?) -> Int {
        let window = window(in: lines, near: keywords, exclude: exclude, radius: 2)
        guard !window.isEmpty else { return 0 }
        // On cherche un code seul ou entouré de séparateurs : "R", " R ", " R)", "(R)"
        for code in ["t", "b", "m", "p", "r"] {  // ordre du plus haut au plus bas pour gérer "Refus" → R
            if hasIsolatedCode(code, in: window) {
                switch code {
                case "r": return 1
                case "p": return 2
                case "m": return 3
                case "b": return 4
                case "t": return 5
                default: return 0
                }
            }
        }
        // Fallback : vocabulaire qualitatif libre (anciennes versions du cahier)
        let joined = window.joined(separator: " ")
        if joined.contains("tres bien") || joined.contains("excellent") { return 5 }
        if joined.contains("bien") && !joined.contains("pas bien") { return 4 }
        if joined.contains("moyen") || joined.contains("correct") { return 3 }
        if joined.contains("peu") { return 2 }
        if joined.contains("refus") || joined.contains("rien") { return 1 }
        return 0
    }

    /// F/M/B/E → 1/2/4/5 (Faible / Moyenne / Bonne / Excellente). Pas de niveau 3
    /// car les options du cahier ne couvrent pas un « moyen exact ».
    private static func hydrationRating(near keywords: [String], lines: [String]) -> Int {
        let window = window(in: lines, near: keywords, exclude: nil, radius: 2)
        guard !window.isEmpty else { return 0 }
        for code in ["e", "b", "m", "f"] {
            if hasIsolatedCode(code, in: window) {
                switch code {
                case "f": return 1
                case "m": return 2
                case "b": return 4
                case "e": return 5
                default: return 0
                }
            }
        }
        let joined = window.joined(separator: " ")
        if joined.contains("excellent") { return 5 }
        if joined.contains("bonne") { return 4 }
        if joined.contains("moyenne") { return 2 }
        if joined.contains("faible") { return 1 }
        return 0
    }

    /// B/M/D → 4/3/2 (Bonne / Moyenne / Difficile)
    private static func sleepQualityRating(near keywords: [String], lines: [String]) -> Int {
        let window = window(in: lines, near: keywords, exclude: nil, radius: 2)
        guard !window.isEmpty else { return 0 }
        for code in ["d", "b", "m"] {
            if hasIsolatedCode(code, in: window) {
                switch code {
                case "b": return 4
                case "m": return 3
                case "d": return 2
                default: return 0
                }
            }
        }
        let joined = window.joined(separator: " ")
        if joined.contains("bonne") { return 4 }
        if joined.contains("moyenne") { return 3 }
        if joined.contains("difficile") || joined.contains("agite") { return 2 }
        return 0
    }

    /// Durée du sommeil de nuit en minutes : <6 → 300, 6-8 → 420, 8-10 → 540, >10 → 660
    /// Si le texte contient une durée explicite (« 8h », « 7h30 »), on la priorise.
    private static func sleepDurationMinutes(near keywords: [String], lines: [String]) -> Int {
        let window = window(in: lines, near: keywords, exclude: nil, radius: 2)
        guard !window.isEmpty else { return 0 }
        let joined = window.joined(separator: " ")
        // Durée explicite
        if let m = explicitDurationMinutes(in: joined), m > 60 {
            return m
        }
        // Plages de cases
        if joined.contains(">10") { return 660 }
        if joined.contains("8-10") || joined.contains("8 a 10") { return 540 }
        if joined.contains("6-8") || joined.contains("6 a 8") { return 420 }
        if joined.contains("<6") { return 300 }
        return 0
    }

    /// Sieste : Non → 0, <30 → 20, 30-60 → 45, >60 → 75 (minutes).
    /// Durée explicite (« 1h30 ») prioritaire.
    private static func napMinutes(near keywords: [String], lines: [String]) -> Int {
        let window = window(in: lines, near: keywords, exclude: nil, radius: 2)
        guard !window.isEmpty else { return 0 }
        let joined = window.joined(separator: " ")
        if let m = explicitDurationMinutes(in: joined), m > 0 { return m }
        if joined.contains(">60") { return 75 }
        if joined.contains("30-60") || joined.contains("30 a 60") { return 45 }
        if joined.contains("<30") { return 20 }
        if joined.contains("non") || joined.contains("pas de sieste") { return 0 }
        return 0
    }

    /// Cherche une durée explicite (« 8h », « 1h30 », « 45 min ») et retourne en minutes.
    private static func explicitDurationMinutes(in text: String) -> Int? {
        // 1h30 / 1 h 30 / 1h
        if let m = text.range(of: #"(\d{1,2})\s*[hH]\s*(\d{0,2})"#, options: .regularExpression) {
            let str = String(text[m])
            let parts = str.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if parts.count >= 2 { return parts[0] * 60 + parts[1] }
            if parts.count == 1 { return parts[0] * 60 }
        }
        if let m = text.range(of: #"(\d{1,3})\s*min"#, options: .regularExpression) {
            let str = String(text[m])
            if let n = str.split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }).first {
                return n
            }
        }
        return nil
    }

    // MARK: - Window selection

    /// Retourne les lignes proches (radius en avant/arrière) d'au moins une ligne
    /// contenant TOUS les mots de `keywords`, en excluant celles qui contiennent
    /// l'un des mots `exclude`.
    private static func window(in lines: [String], near keywords: [String], exclude: [String]?, radius: Int) -> [String] {
        var indices: [Int] = []
        for (i, line) in lines.enumerated() {
            let containsAll = keywords.allSatisfy { line.contains($0) }
            let excluded = (exclude ?? []).contains { line.contains($0) }
            if containsAll && !excluded { indices.append(i) }
        }
        guard !indices.isEmpty else { return [] }
        var window: [String] = []
        for i in indices {
            let lo = max(0, i - radius)
            let hi = min(lines.count - 1, i + radius)
            for j in lo...hi { window.append(lines[j]) }
        }
        return window
    }

    /// Vrai si un caractère / sigle d'option apparaît isolé (entouré
    /// d'espaces, ponctuation ou en début/fin de ligne) dans le texte.
    /// On évite ainsi de matcher « R » dans « Repas » ou « B » dans « Bien ».
    /// L'OCR introduit du bruit ; on tolère donc aussi le caractère seul.
    private static func hasIsolatedCode(_ code: String, in lines: [String]) -> Bool {
        let pattern = #"(^|[\s\.\,\;\:\(\)\[\]\/\\\|\-\=])"# + code + #"($|[\s\.\,\;\:\(\)\[\]\/\\\|\-\=])"#
        for line in lines {
            if line.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    /// Détecte une date au format français.
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
                if let m = line.range(of: #"\d{1,2}[/\- ]\d{1,2}[/\- ]\d{2,4}"#, options: .regularExpression) {
                    let snippet = String(line[m])
                    if let d = f.date(from: snippet) { return cal.startOfDay(for: d) }
                }
            }
        }
        return nil
    }
}

// MARK: - Helper

private extension Int {
    /// Retourne `self` s'il est non nul, sinon la valeur fournie.
    func nonZeroOr(_ fallback: Int) -> Int { self != 0 ? self : fallback }
}
