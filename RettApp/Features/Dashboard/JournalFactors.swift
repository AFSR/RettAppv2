import Foundation

/// Cherche, dans le journal, ce qui accompagne les crises et les symptômes.
///
/// `MedicalReportAnalysis.correlations` ne croise que quatre signaux avec le
/// nombre de crises. Ici on croise **tous** les champs du journal (sommeil,
/// repas, hydratation, selles, urines, humeur, observance) avec les crises
/// **et** chaque symptôme suivi, le jour même et la veille.
///
/// Ce type ne touche ni SwiftData ni l'interface : il reçoit des jours déjà
/// résumés (`Day`) et rend des constats. C'est ce qui le rend testable sans
/// simulateur, et ce qui garantit que rien ne sort de l'appareil.
enum JournalFactors {

    // MARK: - Entrées

    /// Ce qui est connu d'une journée. Un facteur `nil` veut dire « non
    /// renseigné », jamais « zéro » : zéro selle est une information, une
    /// case vide n'en est pas une.
    struct Day {
        let start: Date
        var factors: [Factor: Double] = [:]
        var seizureCount = 0
        var seizureSeconds = 0
        var symptomCounts: [RettSymptom: Int] = [:]
    }

    /// Un traitement, identifié par son **nom normalisé** et non par
    /// l'identifiant d'un plan. Changer un dosage se fait en arrêtant un plan
    /// et en en créant un autre (voir `MedicationPlanChange`) : deux
    /// identifiants pour un seul traitement. Les séparer donnerait deux
    /// séries à dose constante, et le changement de dose — ce qu'on cherche —
    /// disparaîtrait de l'analyse.
    struct MedicationRef: Hashable {
        let key: String
        let name: String

        init(name: String) {
            self.name = name
            self.key = MedicationPlanChange.seriesKey(forName: name)
        }

        static func == (a: Self, b: Self) -> Bool { a.key == b.key }
        func hash(into h: inout Hasher) { h.combine(key) }
    }

    /// Ce qu'on sait croiser : les champs du journal et le plan médicamenteux.
    ///
    /// Seuls les médicaments **réguliers** y figurent. Un médicament à la
    /// demande se prend *à cause* d'une crise ou d'un symptôme : le croiser
    /// ferait conclure que le Rivotril « provoque » les crises, ce qui
    /// renverse la causalité.
    enum Factor: Hashable {
        case sleepQuality, sleepHours, meals, hydration
        case stoolCount, urine, mood, adherence
        /// Dose quotidienne prévue au plan, d'après les prises planifiées du
        /// jour : c'est ce qui change quand on modifie le dosage.
        case medicationDose(MedicationRef)
        /// Part des prises planifiées du jour réellement faites, pour ce médicament.
        case medicationTaken(MedicationRef)

        var id: String {
            switch self {
            case .sleepQuality: return "sleepQuality"
            case .sleepHours:   return "sleepHours"
            case .meals:        return "meals"
            case .hydration:    return "hydration"
            case .stoolCount:   return "stoolCount"
            case .urine:        return "urine"
            case .mood:         return "mood"
            case .adherence:    return "adherence"
            case .medicationDose(let m):  return "dose|\(m.key)"
            case .medicationTaken(let m): return "taken|\(m.key)"
            }
        }

        var isMedication: Bool {
            switch self {
            case .medicationDose, .medicationTaken: return true
            default: return false
            }
        }

        /// Sujet de la phrase « les jours où … est plus élevé / plus bas » :
        /// pas d'adjectif à accorder, donc un seul gabarit pour tous.
        var label: String {
            switch self {
            case .sleepQuality: return "la qualité du sommeil de nuit"
            case .sleepHours:   return "la durée du sommeil de nuit"
            case .meals:        return "la qualité des repas"
            case .hydration:    return "l'hydratation"
            case .stoolCount:   return "le nombre de selles"
            case .urine:        return "la quantité d'urines"
            case .mood:         return "l'humeur"
            case .adherence:    return "l'observance des médicaments"
            case .medicationDose(let m):  return "la dose quotidienne de \(m.name)"
            case .medicationTaken(let m): return "la part des prises de \(m.name) faites"
            }
        }

        var systemImage: String {
            switch self {
            case .sleepQuality, .sleepHours: return "bed.double.fill"
            case .meals:      return "fork.knife"
            case .hydration:  return "drop.fill"
            case .stoolCount, .urine: return "toilet.fill"
            case .mood:       return "face.smiling"
            case .adherence, .medicationDose, .medicationTaken: return "pill.fill"
            }
        }
    }

    /// Ce qu'on cherche à expliquer.
    enum Outcome: Hashable {
        case seizures
        case seizureDuration
        case symptom(RettSymptom)

        var label: String {
            switch self {
            case .seizures:        return "de crises"
            case .seizureDuration: return "de temps passé en crise"
            case .symptom(let s): return "de « \(s.label) »"
            }
        }
    }

    /// Même jour, ou la veille du facteur → le lendemain du résultat.
    enum Lag: Int {
        case sameDay = 0
        case previousDay = 1
    }

    // MARK: - Sortie

    struct Finding: Identifiable {
        let factor: Factor
        let outcome: Outcome
        let lag: Lag
        let r: Double
        let n: Int
        let pValue: Double

        var id: String { "\(factor.id)|\(outcome)|\(lag.rawValue)" }
        /// Facteur haut ↔ résultat plus fréquent.
        var increases: Bool { r > 0 }

        var sentence: String {
            let when = lag == .sameDay ? "Les jours où" : "Le lendemain d'un jour où"
            // Toujours « plus de » : r < 0 se lit « quand c'est bas, il y en a
            // plus », ce qu'un parent comprend mieux que « quand c'est haut,
            // il y en a moins » — c'est la même information.
            let level = increases ? "est plus élevé" : "est plus bas"
            return "\(when) \(factor.label) \(level), il y a plus \(outcome.label)."
        }

        var caveat: String {
            let base = "Lien \(MedicalReportAnalysis.CorrelationStrength.classify(r).label), observé sur \(n) jours. "
                + "Ce n'est pas une cause."
            // Un traitement change rarement seul (croissance, saison, autre
            // médicament) : on le dit, et on renvoie au médecin plutôt que
            // de laisser lire une consigne dans un coefficient.
            guard factor.isMedication else { return base }
            return base + " Un changement de traitement coïncide souvent avec d'autres changements. "
                + "Ne modifiez jamais un traitement sans l'avis du médecin."
        }
    }

    // MARK: - Seuils

    /// Jours communs minimum pour une paire. Sous ce seuil, c'est du hasard.
    static let minimumDays = 14
    /// Un symptôme ou des crises présents sur moins de jours que cela ne
    /// permettent pas de conclure : un seul épisode ferait toute la corrélation.
    static let minimumDaysWithOutcome = 4
    /// Au moins « modérée » au sens de `CorrelationStrength`.
    static let minimumAbsR = 0.4
    /// On teste ici des centaines de paires : au seuil usuel de 5 %, une
    /// dizaine apparaîtrait par pur hasard. D'où 1 %, et peu de constats.
    static let maximumP = 0.01
    static let maximumShown = 5

    // MARK: - Calcul

    /// - Parameter days: jours consécutifs, du plus ancien au plus récent.
    static func findings(in days: [Day]) -> [Finding] {
        guard days.count > 1 else { return [] }

        // « Autre » n'est pas un symptôme : y chercher une cause n'aurait
        // pas de sens, et la phrase serait incompréhensible.
        var seen = Set<RettSymptom>()
        for d in days { for (s, _) in d.symptomCounts where s != .other { seen.insert(s) } }
        let outcomes: [Outcome] = [.seizures, .seizureDuration]
            + seen.sorted { $0.rawValue < $1.rawValue }.map(Outcome.symptom)

        // Les facteurs sont ceux réellement présents : un médicament absent
        // de la période n'a pas de série à croiser.
        let factors = Set(days.flatMap { $0.factors.keys }).sorted { $0.id < $1.id }

        var found: [Finding] = []
        for factor in factors {
            for outcome in outcomes {
                for lag in [Lag.sameDay, .previousDay] {
                    if let f = finding(factor, outcome, lag, days) { found.append(f) }
                }
            }
        }

        // Pour un même couple facteur/résultat, un seul constat : le plus
        // fort, sinon on répéterait la même chose le jour même puis la veille.
        var best: [String: Finding] = [:]
        for f in found {
            let key = "\(f.factor.id)|\(f.outcome)"
            if let old = best[key], abs(old.r) >= abs(f.r) { continue }
            best[key] = f
        }
        return Array(best.values.sorted { abs($0.r) > abs($1.r) }.prefix(maximumShown))
    }

    /// Nombre de jours où au moins un facteur est renseigné — ce que l'écran
    /// dit à la famille quand il manque des données.
    static func daysWithJournal(in days: [Day]) -> Int {
        days.filter { !$0.factors.isEmpty }.count
    }

    private static func finding(
        _ factor: Factor, _ outcome: Outcome, _ lag: Lag, _ days: [Day]
    ) -> Finding? {
        var xs: [Double] = []
        var ys: [Double] = []
        for i in lag.rawValue..<days.count {
            guard let x = days[i - lag.rawValue].factors[factor] else { continue }
            xs.append(x)
            ys.append(value(of: outcome, on: days[i]))
        }
        guard xs.count >= minimumDays else { return nil }
        guard ys.filter({ $0 > 0 }).count >= minimumDaysWithOutcome else { return nil }
        guard let r = MedicalReportAnalysis.pearson(xs, ys), abs(r) >= minimumAbsR else { return nil }
        let p = pValue(r: r, n: xs.count)
        guard p < maximumP else { return nil }
        return Finding(factor: factor, outcome: outcome, lag: lag, r: r, n: xs.count, pValue: p)
    }

    private static func value(of outcome: Outcome, on day: Day) -> Double {
        switch outcome {
        case .seizures:        return Double(day.seizureCount)
        case .seizureDuration: return Double(day.seizureSeconds)
        case .symptom(let s): return Double(day.symptomCounts[s] ?? 0)
        }
    }

    /// Test bilatéral de r ≠ 0 par transformation de Fisher (approximation
    /// normale, correcte dès une quinzaine de points).
    static func pValue(r: Double, n: Int) -> Double {
        guard n > 3, abs(r) < 1 else { return abs(r) >= 1 ? 0 : 1 }
        let z = 0.5 * log((1 + r) / (1 - r)) * Double(n - 3).squareRoot()
        return erfc(abs(z) / 2.0.squareRoot())
    }
}
