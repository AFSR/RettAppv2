import Foundation

/// Analyse statistique des données de suivi pour le rapport médecin.
/// Aucune dépendance externe — tout est calculé localement.
enum MedicalReportAnalysis {

    // MARK: - Inputs / outputs

    struct Input {
        let periodStart: Date
        let periodEnd: Date
        let seizures: [SeizureEvent]
        let medications: [Medication]
        let logs: [MedicationLog]            // logs sur la période (planifiés ET adhoc)
        let moods: [MoodEntry]
        let observations: [DailyObservation]
        let symptoms: [SymptomEvent]         // observations de symptômes sur la période
    }

    /// Échelle d'agrégation pour les graphiques, choisie en fonction de la longueur
    /// de la période — pour rester lisible (≈ 30 buckets max).
    enum Granularity {
        case daily, weekly, monthly

        var label: String {
            switch self {
            case .daily:   return "jour"
            case .weekly:  return "semaine"
            case .monthly: return "mois"
            }
        }
        var calendarComponent: Calendar.Component {
            switch self {
            case .daily: return .day
            case .weekly: return .weekOfYear
            case .monthly: return .month
            }
        }
    }

    static func granularity(for periodDays: Int) -> Granularity {
        switch periodDays {
        case ..<31:   return .daily
        case 31..<180: return .weekly
        default:      return .monthly
        }
    }

    /// Bucket d'agrégation : nombre + durée totale + dérivés.
    struct Bucket {
        let start: Date
        var count: Int = 0
        var totalDurationSec: Int = 0
        var avgDurationSec: Double {
            count > 0 ? Double(totalDurationSec) / Double(count) : 0
        }
    }

    /// Découpe la période en buckets vides selon la granularité.
    static func buckets(start: Date, end: Date, granularity: Granularity, calendar: Calendar = .current) -> [Bucket] {
        var result: [Bucket] = []
        var cursor = calendar.dateInterval(of: granularity.calendarComponent, for: start)?.start ?? start
        while cursor < end {
            result.append(Bucket(start: cursor))
            cursor = calendar.date(byAdding: granularity.calendarComponent, value: 1, to: cursor) ?? end
        }
        return result
    }

    /// Indexe les crises dans les buckets passés en paramètre.
    static func fillSeizureBuckets(_ buckets: inout [Bucket], seizures: [SeizureEvent], calendar: Calendar = .current) {
        for s in seizures {
            guard let i = buckets.lastIndex(where: { $0.start <= s.startTime }) else { continue }
            buckets[i].count += 1
            buckets[i].totalDurationSec += s.durationSeconds
        }
    }

    // MARK: - Synthèse globale

    struct OverallStats {
        let periodDays: Int
        let totalCount: Int
        let totalDurationSec: Int
        let avgDurationSec: Double
        let typeBreakdown: [(type: SeizureType, count: Int, percentage: Double)]
        let triggerBreakdown: [(trigger: SeizureTrigger, count: Int, percentage: Double)]
        let crisesPerWeek: Double
        let dailyAdherence: Double      // 0..1, pour les meds réguliers
        let avgMoodLevel: Double?       // 1..5, nil si pas de saisie
        let medicationCount: Int        // actifs + adhoc
    }

    static func computeOverall(_ input: Input, calendar: Calendar = .current) -> OverallStats {
        let total = input.seizures.count
        let totalSec = input.seizures.reduce(0) { $0 + $1.durationSeconds }
        let avg = total > 0 ? Double(totalSec) / Double(total) : 0

        // Type breakdown
        var typeCounts: [SeizureType: Int] = [:]
        for s in input.seizures { typeCounts[s.seizureType, default: 0] += 1 }
        let typeBreakdown: [(type: SeizureType, count: Int, percentage: Double)] = typeCounts.map { (type, c) in
            (type, c, total > 0 ? Double(c) / Double(total) * 100 : 0)
        }.sorted { $0.count > $1.count }

        // Trigger breakdown (en excluant .none pour pertinence clinique)
        var trigCounts: [SeizureTrigger: Int] = [:]
        for s in input.seizures { trigCounts[s.trigger, default: 0] += 1 }
        let trigBreakdown: [(trigger: SeizureTrigger, count: Int, percentage: Double)] = trigCounts.map { (t, c) in
            (t, c, total > 0 ? Double(c) / Double(total) * 100 : 0)
        }.sorted { $0.count > $1.count }

        // Période en jours
        let days = max(1, calendar.dateComponents([.day], from: input.periodStart, to: input.periodEnd).day ?? 1)
        let perWeek = days > 0 ? Double(total) / Double(days) * 7.0 : 0

        // Adhérence : sur logs non-adhoc uniquement
        let plannedLogs = input.logs.filter { !$0.isAdHoc }
        let takenLogs = plannedLogs.filter { $0.taken }
        let adherence = plannedLogs.isEmpty ? 0 : Double(takenLogs.count) / Double(plannedLogs.count)

        // Humeur moyenne
        let avgMood: Double? = input.moods.isEmpty ? nil :
            input.moods.map { Double($0.levelRaw) }.reduce(0, +) / Double(input.moods.count)

        return OverallStats(
            periodDays: days,
            totalCount: total,
            totalDurationSec: totalSec,
            avgDurationSec: avg,
            typeBreakdown: typeBreakdown,
            triggerBreakdown: trigBreakdown,
            crisesPerWeek: perWeek,
            dailyAdherence: adherence,
            avgMoodLevel: avgMood,
            medicationCount: input.medications.filter { $0.isActive }.count
        )
    }

    // MARK: - Corrélations

    /// Coefficient de Pearson entre deux séries alignées de même longueur.
    /// Retourne nil si la variance d'une des séries est nulle.
    static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 3 else { return nil }
        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var num = 0.0
        var dx2 = 0.0
        var dy2 = 0.0
        for i in 0..<xs.count {
            let dx = xs[i] - meanX
            let dy = ys[i] - meanY
            num += dx * dy
            dx2 += dx * dx
            dy2 += dy * dy
        }
        guard dx2 > 1e-9, dy2 > 1e-9 else { return nil }
        return num / (dx2.squareRoot() * dy2.squareRoot())
    }

    /// Force qualitative d'une corrélation (en valeur absolue).
    enum CorrelationStrength {
        case negligible, weak, moderate, strong
        var label: String {
            switch self {
            case .negligible: return "négligeable"
            case .weak:       return "faible"
            case .moderate:   return "modérée"
            case .strong:     return "forte"
            }
        }
        static func classify(_ r: Double) -> CorrelationStrength {
            let a = abs(r)
            switch a {
            case ..<0.2:  return .negligible
            case ..<0.4:  return .weak
            case ..<0.6:  return .moderate
            default:       return .strong
            }
        }
    }

    /// Construit des séries journalières alignées pour les corrélations.
    /// Pour chaque jour de la période, calcule :
    ///   - nb crises
    ///   - durée totale (s)
    ///   - humeur moyenne (1-5, nil si pas de saisie)
    ///   - rating repas (1-5, nil si pas de saisie)
    ///   - rating sommeil nuit (1-5, nil si pas de saisie)
    ///   - observance (0..1) — sur logs planifiés du jour
    struct DailySignals {
        let day: Date
        let seizureCount: Int
        let seizureDurationSec: Int
        let moodAvg: Double?
        let mealRating: Double?
        let nightSleepRating: Double?
        let adherence: Double?
    }

    static func dailySignals(_ input: Input, calendar: Calendar = .current) -> [DailySignals] {
        var result: [DailySignals] = []
        let start = calendar.startOfDay(for: input.periodStart)
        let end = calendar.startOfDay(for: input.periodEnd)
        var cursor = start
        while cursor <= end {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor

            let daySeizures = input.seizures.filter { $0.startTime >= cursor && $0.startTime < dayEnd }
            let count = daySeizures.count
            let durSec = daySeizures.reduce(0) { $0 + $1.durationSeconds }

            let dayMoods = input.moods.filter { $0.timestamp >= cursor && $0.timestamp < dayEnd }
            let moodAvg: Double? = dayMoods.isEmpty ? nil
                : dayMoods.map { Double($0.levelRaw) }.reduce(0, +) / Double(dayMoods.count)

            let obs = input.observations.first { calendar.isDate($0.dayStart, inSameDayAs: cursor) }
            let meal: Double? = (obs?.averageMealRatingRaw ?? 0) > 0 ? Double(obs!.averageMealRatingRaw) : nil
            let sleep: Double? = (obs?.nightSleepRatingRaw ?? 0) > 0 ? Double(obs!.nightSleepRatingRaw) : nil

            let dayLogs = input.logs.filter { !$0.isAdHoc && $0.scheduledTime >= cursor && $0.scheduledTime < dayEnd }
            let adherence: Double? = dayLogs.isEmpty ? nil
                : Double(dayLogs.filter { $0.taken }.count) / Double(dayLogs.count)

            result.append(DailySignals(
                day: cursor,
                seizureCount: count,
                seizureDurationSec: durSec,
                moodAvg: moodAvg,
                mealRating: meal,
                nightSleepRating: sleep,
                adherence: adherence
            ))
            cursor = dayEnd
        }
        return result
    }

    /// Une corrélation calculée entre la fréquence des crises et un autre signal.
    struct Correlation {
        let signal: String          // ex. "Humeur moyenne"
        let r: Double               // coefficient
        let n: Int                  // nb de jours communs
        var strength: CorrelationStrength { CorrelationStrength.classify(r) }
        var direction: String { r >= 0 ? "positive" : "négative" }
    }

    // MARK: - Plan change impact (versioning awareness)

    /// Statistiques agrégées sur une fenêtre temporelle, utilisées pour
    /// comparer la situation avant/après un changement du plan médicamenteux.
    struct PlanChangeWindowStats {
        let days: Int
        let seizuresPerDay: Double
        let seizureMinutesPerDay: Double
        let moodAvg: Double?       // 1-5
        let sleepRatingAvg: Double? // 1-5
    }

    /// Une révision du plan tombée pendant la période, accompagnée des
    /// stats des fenêtres avant/après. Permet au médecin de juger si la
    /// modification semble avoir eu un effet sur les signaux (crises,
    /// humeur, sommeil) — sans inférer de causalité.
    struct PlanChangeImpact {
        let revisionDate: Date
        let medicationName: String
        let before: PlanChangeWindowStats
        let after: PlanChangeWindowStats

        var seizureDeltaPerDay: Double { after.seizuresPerDay - before.seizuresPerDay }
        var seizureDurationDeltaMinPerDay: Double {
            after.seizureMinutesPerDay - before.seizureMinutesPerDay
        }
    }

    /// Pour chaque révision tombée dans la période, calcule les stats des
    /// fenêtres `windowDays` avant et après. Les fenêtres sont tronquées par
    /// les bornes de la période — pas de fuite en dehors du rapport.
    static func planChangeImpacts(
        _ input: Input,
        revisions: [MedicationRevision],
        windowDays: Int = 14,
        calendar: Calendar = .current
    ) -> [PlanChangeImpact] {
        let inPeriod = revisions
            .filter { $0.effectiveFrom >= input.periodStart && $0.effectiveFrom <= input.periodEnd }
            .sorted { $0.effectiveFrom < $1.effectiveFrom }

        return inPeriod.map { rev in
            let date = rev.effectiveFrom
            let beforeStart = calendar.date(byAdding: .day, value: -windowDays, to: date) ?? date
            let beforeBounded = max(beforeStart, input.periodStart)
            let afterEnd = calendar.date(byAdding: .day, value: windowDays, to: date) ?? date
            let afterBounded = min(afterEnd, input.periodEnd)

            let before = windowStats(from: beforeBounded, to: date, in: input)
            let after = windowStats(from: date, to: afterBounded, in: input)

            return PlanChangeImpact(
                revisionDate: date,
                medicationName: rev.name,
                before: before,
                after: after
            )
        }
    }

    private static func windowStats(
        from start: Date,
        to end: Date,
        in input: Input
    ) -> PlanChangeWindowStats {
        let interval = end.timeIntervalSince(start)
        let days = max(1, Int((interval / 86_400).rounded()))
        let seizures = input.seizures.filter { $0.startTime >= start && $0.startTime < end }
        let moods = input.moods.filter { $0.timestamp >= start && $0.timestamp < end }
        let obs = input.observations.filter { $0.dayStart >= start && $0.dayStart < end }

        let seizureCount = seizures.count
        let seizureMin = Double(seizures.reduce(0) { $0 + $1.durationSeconds }) / 60.0
        let moodAvg: Double? = moods.isEmpty ? nil
            : moods.map { Double($0.levelRaw) }.reduce(0, +) / Double(moods.count)
        let sleepRatings = obs.compactMap { o -> Int? in
            o.nightSleepRatingRaw > 0 ? o.nightSleepRatingRaw : nil
        }
        let sleepAvg: Double? = sleepRatings.isEmpty ? nil
            : Double(sleepRatings.reduce(0, +)) / Double(sleepRatings.count)

        return PlanChangeWindowStats(
            days: days,
            seizuresPerDay: Double(seizureCount) / Double(days),
            seizureMinutesPerDay: seizureMin / Double(days),
            moodAvg: moodAvg,
            sleepRatingAvg: sleepAvg
        )
    }

    // MARK: - Corrélations par segment (plan-conscient)

    /// Un segment temporel borné par deux dates où le plan médicamenteux est
    /// supposé stable (aucune révision tombée entre les deux bornes). Sert à
    /// recalculer les corrélations sans mélanger plusieurs régimes.
    struct PlanSegment: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date
        /// Corrélations calculées sur ce segment uniquement. Vide si moins
        /// de 5 jours communs avec un signal renseigné.
        let correlations: [Correlation]
        /// Nombre de jours du segment (utile pour l'UI).
        var durationDays: Int {
            max(1, Int((end.timeIntervalSince(start) / 86_400).rounded()))
        }
    }

    /// Découpe la période en sous-segments bornés par chaque révision du
    /// plan, et recalcule les corrélations sur chacun. Permet au médecin de
    /// vérifier si une corrélation tient à travers les régimes de traitement
    /// ou si elle est portée par un seul.
    ///
    /// Skip les segments < 5 jours (impossible de calculer Pearson) ou
    /// sans aucune corrélation exploitable.
    static func segmentedCorrelations(
        _ input: Input,
        revisions: [MedicationRevision],
        calendar: Calendar = .current
    ) -> [PlanSegment] {
        let cutoffs = revisions
            .map { $0.effectiveFrom }
            .filter { $0 > input.periodStart && $0 < input.periodEnd }
            .sorted()

        // Boucle sur les segments [start, cutoff], [cutoff, next], …, [last, end]
        var bounds: [Date] = [input.periodStart] + cutoffs + [input.periodEnd]
        bounds = Array(Set(bounds)).sorted() // dédoublonne au cas où deux modifs au même instant

        var segments: [PlanSegment] = []
        for i in 0..<(bounds.count - 1) {
            let start = bounds[i]
            let end = bounds[i + 1]
            let segmentDays = end.timeIntervalSince(start) / 86_400
            if segmentDays < 5 { continue }

            // On reconstruit un Input limité au segment puis on appelle la
            // pipeline existante. Léger côté perf (filtre Array) — la
            // période d'un rapport est plafonnée à ~3 mois max.
            let scoped = Input(
                periodStart: start,
                periodEnd: end,
                seizures: input.seizures.filter { $0.startTime >= start && $0.startTime < end },
                medications: input.medications,
                logs: input.logs.filter { $0.scheduledTime >= start && $0.scheduledTime < end },
                moods: input.moods.filter { $0.timestamp >= start && $0.timestamp < end },
                observations: input.observations.filter { $0.dayStart >= start && $0.dayStart < end },
                symptoms: input.symptoms.filter { $0.timestamp >= start && $0.timestamp < end }
            )
            let signals = dailySignals(scoped, calendar: calendar)
            let corrs = correlations(from: signals)
            if !corrs.isEmpty {
                segments.append(PlanSegment(start: start, end: end, correlations: corrs))
            }
        }
        return segments
    }

    /// Renvoie la révision dont le passage est associé à la baisse la plus
    /// marquée du nombre journalier de crises (delta absolu, peu importe le
    /// sens — utile pour les régressions aussi). nil quand aucune révision
    /// n'a un delta significatif (> 0,1 crise/jour de différence).
    static func mostImpactfulPlanChange(
        impacts: [PlanChangeImpact],
        minAbsDelta: Double = 0.1
    ) -> PlanChangeImpact? {
        return impacts
            .filter { abs($0.seizureDeltaPerDay) >= minAbsDelta }
            .max(by: { abs($0.seizureDeltaPerDay) < abs($1.seizureDeltaPerDay) })
    }

    /// Calcule les corrélations à partir des signaux journaliers.
    /// Garde uniquement les jours où les deux signaux sont présents.
    static func correlations(from signals: [DailySignals]) -> [Correlation] {
        var out: [Correlation] = []

        func corr(_ name: String, _ extractor: (DailySignals) -> Double?) {
            let pairs: [(Double, Double)] = signals.compactMap { s in
                guard let v = extractor(s) else { return nil }
                return (Double(s.seizureCount), v)
            }
            guard pairs.count >= 5 else { return }
            let xs = pairs.map { $0.0 }
            let ys = pairs.map { $0.1 }
            if let r = pearson(xs, ys) {
                out.append(Correlation(signal: name, r: r, n: pairs.count))
            }
        }

        corr("Humeur moyenne", { $0.moodAvg })
        corr("Qualité des repas", { $0.mealRating })
        corr("Qualité du sommeil de nuit", { $0.nightSleepRating })
        corr("Observance médicamenteuse", { $0.adherence })

        return out
    }

    // MARK: - Analyse du plan médicamenteux

    struct MedicationAnalysis {
        struct PerMed {
            let medication: Medication
            let scheduledIntakes: Int
            let takenIntakes: Int
            let adherence: Double          // 0..1
            /// Écart-type des décalages (s) entre takenTime et scheduledTime — sur prises réellement prises.
            let timingStdDevSec: Double
            /// Décalage moyen (s, signé : + = en retard, - = en avance).
            let timingMeanSec: Double
            let missedIntakes: Int
            let lateIntakes: Int           // > 30 min de retard
        }

        /// Synthèse d'un médicament pris à la demande sur la période.
        struct AdHocMed {
            let name: String
            let occurrences: Int           // nb de prises
            let totalDose: Double          // dose cumulée
            let unitLabel: String
            let lastTaken: Date?
            let mostFrequentReason: String?  // raison ad-hoc la plus fréquente
        }

        let perMedication: [PerMed]
        let adHocSummary: [AdHocMed]
        let regularMedicationsCount: Int
        let adhocMedicationsCount: Int
        /// Adhérence pondérée par nb de prises planifiées.
        let weightedAdherence: Double
    }

    static func analyzeMedicationPlan(_ input: Input) -> MedicationAnalysis {
        var perMed: [MedicationAnalysis.PerMed] = []
        var totalScheduled = 0
        var totalTaken = 0

        for med in input.medications.filter({ $0.kind == .regular }) {
            let medLogs = input.logs.filter { !$0.isAdHoc && $0.medicationId == med.id }
            let scheduled = medLogs.count
            let taken = medLogs.filter { $0.taken }.count
            let adherence = scheduled > 0 ? Double(taken) / Double(scheduled) : 0

            // Décalages (en secondes, signés)
            let deltas: [Double] = medLogs.compactMap { l in
                guard l.taken, let t = l.takenTime else { return nil }
                return t.timeIntervalSince(l.scheduledTime)
            }
            let meanDelta: Double = deltas.isEmpty ? 0 : deltas.reduce(0, +) / Double(deltas.count)
            let std: Double = {
                guard deltas.count > 1 else { return 0 }
                let m = meanDelta
                let v = deltas.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(deltas.count - 1)
                return v.squareRoot()
            }()
            let missed = medLogs.filter { !$0.taken }.count
            let late = medLogs.filter { l in
                if l.taken, let t = l.takenTime {
                    return t.timeIntervalSince(l.scheduledTime) > 30 * 60
                }
                return false
            }.count

            perMed.append(MedicationAnalysis.PerMed(
                medication: med,
                scheduledIntakes: scheduled,
                takenIntakes: taken,
                adherence: adherence,
                timingStdDevSec: std,
                timingMeanSec: meanDelta,
                missedIntakes: missed,
                lateIntakes: late
            ))

            totalScheduled += scheduled
            totalTaken += taken
        }

        let weighted = totalScheduled > 0 ? Double(totalTaken) / Double(totalScheduled) : 0
        let regularCount = input.medications.filter { $0.kind == .regular && $0.isActive }.count
        let adhocCount = input.medications.filter { $0.kind == .adhoc && $0.isActive }.count

        // ── Synthèse des prises ad-hoc sur la période
        // Groupe par nom (les ad-hoc peuvent être saisis librement, on consolide par libellé).
        var adhocByName: [String: (count: Int, totalDose: Double, lastTaken: Date?, unit: String, reasons: [String])] = [:]
        for log in input.logs where log.isAdHoc {
            let key = log.medicationName
            var entry = adhocByName[key] ?? (0, 0, nil, log.doseUnit.label, [])
            entry.count += 1
            entry.totalDose += log.dose
            if let t = log.takenTime, t > (entry.lastTaken ?? .distantPast) {
                entry.lastTaken = t
            }
            if !log.adhocReason.isEmpty {
                entry.reasons.append(log.adhocReason)
            }
            adhocByName[key] = entry
        }
        let adHocSummary: [MedicationAnalysis.AdHocMed] = adhocByName
            .map { (name, data) in
                let topReason = Dictionary(grouping: data.reasons, by: { $0 })
                    .max(by: { $0.value.count < $1.value.count })?.key
                return MedicationAnalysis.AdHocMed(
                    name: name,
                    occurrences: data.count,
                    totalDose: data.totalDose,
                    unitLabel: data.unit,
                    lastTaken: data.lastTaken,
                    mostFrequentReason: topReason
                )
            }
            .sorted { $0.occurrences > $1.occurrences }

        return MedicationAnalysis(
            perMedication: perMed,
            adHocSummary: adHocSummary,
            regularMedicationsCount: regularCount,
            adhocMedicationsCount: adhocCount,
            weightedAdherence: weighted
        )
    }

    // MARK: - Analyse des symptômes Rett

    struct SymptomAnalysis {
        struct PerSymptom {
            let type: RettSymptom
            let occurrences: Int
            /// Intensité moyenne sur les observations où l'intensité a été renseignée (>0).
            let avgIntensity: Double?
            /// Durée totale (minutes) cumulée — 0 si aucun épisode n'a renseigné de durée.
            let totalDurationMinutes: Int
            let lastObserved: Date?
        }
        let totalObservations: Int
        let perSymptom: [PerSymptom]   // triés par fréquence décroissante
    }

    static func analyzeSymptoms(_ input: Input) -> SymptomAnalysis {
        var groups: [RettSymptom: [SymptomEvent]] = [:]
        for s in input.symptoms { groups[s.symptomType, default: []].append(s) }

        let perSymptom: [SymptomAnalysis.PerSymptom] = groups.map { (type, events) in
            let withIntensity = events.filter { $0.intensityRaw > 0 }
            let avg: Double? = withIntensity.isEmpty ? nil
                : withIntensity.map { Double($0.intensityRaw) }.reduce(0, +) / Double(withIntensity.count)
            let totalMin = events.reduce(0) { $0 + $1.durationMinutes }
            let last = events.map(\.timestamp).max()
            return SymptomAnalysis.PerSymptom(
                type: type, occurrences: events.count,
                avgIntensity: avg, totalDurationMinutes: totalMin,
                lastObserved: last
            )
        }
        .sorted { $0.occurrences > $1.occurrences }

        return SymptomAnalysis(totalObservations: input.symptoms.count, perSymptom: perSymptom)
    }

    // MARK: - Synthèse textuelle pour le médecin

    /// Construit un texte de synthèse en français en consolidant les stats + corrélations
    /// + analyse meds. Destiné à être collé tel quel dans le PDF.
    static func synthesisText(
        overall: OverallStats,
        correlations: [Correlation],
        medicationAnalysis: MedicationAnalysis,
        symptomAnalysis: SymptomAnalysis,
        planChangesInPeriod: Int = 0,
        mostImpactfulChange: PlanChangeImpact? = nil,
        childFirstName: String
    ) -> String {
        let name = childFirstName.isEmpty ? "L'enfant" : childFirstName
        var lines: [String] = []

        // Période + volume
        lines.append("Sur la période (\(overall.periodDays) jours), \(name) a présenté \(overall.totalCount) crise\(overall.totalCount > 1 ? "s" : ""), soit en moyenne \(String(format: "%.1f", overall.crisesPerWeek)) crise\(overall.crisesPerWeek > 1 ? "s" : "") par semaine.")

        // Type prédominant
        if let top = overall.typeBreakdown.first {
            lines.append("Le type prédominant est : \(top.type.label) (\(top.count) crises, soit \(Int(top.percentage.rounded())) % du total).")
        }

        // Déclencheurs
        let topTrigger = overall.triggerBreakdown
            .filter { $0.trigger != .none }
            .first
        if let t = topTrigger, t.count > 0 {
            lines.append("Déclencheur le plus fréquemment identifié : \(t.trigger.label) (\(t.count) cas).")
        } else {
            lines.append("Aucun déclencheur prédominant identifié sur la période.")
        }

        // Durée
        lines.append("Durée moyenne d'une crise : \(formatDur(Int(overall.avgDurationSec))).")

        // Médication
        if medicationAnalysis.regularMedicationsCount > 0 {
            let pct = Int((medicationAnalysis.weightedAdherence * 100).rounded())
            lines.append("Observance médicamenteuse pondérée : \(pct) % sur \(medicationAnalysis.regularMedicationsCount) traitement\(medicationAnalysis.regularMedicationsCount > 1 ? "s" : "") récurrent\(medicationAnalysis.regularMedicationsCount > 1 ? "s" : "").")
        }
        let totalAdHocIntakes = medicationAnalysis.adHocSummary.reduce(0) { $0 + $1.occurrences }
        if totalAdHocIntakes > 0 {
            let topName = medicationAnalysis.adHocSummary.first?.name ?? ""
            lines.append("\(totalAdHocIntakes) prise\(totalAdHocIntakes > 1 ? "s" : "") ponctuelle\(totalAdHocIntakes > 1 ? "s" : "") (à la demande) sur la période — principalement \(topName).")
        } else if medicationAnalysis.adhocMedicationsCount > 0 {
            lines.append("\(medicationAnalysis.adhocMedicationsCount) traitement à la demande référencé mais aucune prise enregistrée sur la période.")
        }
        if planChangesInPeriod > 0 {
            lines.append("Plan médicamenteux modifié \(planChangesInPeriod) fois sur la période (voir section « Évolutions du plan médicamenteux » ci-dessus pour le détail des changements).")
        }
        if let impact = mostImpactfulChange {
            let df = DateFormatter()
            df.locale = Locale(identifier: "fr_FR")
            df.dateFormat = "dd/MM/yyyy"
            let delta = impact.seizureDeltaPerDay
            let beforeRate = String(format: "%.2f", impact.before.seizuresPerDay)
            let afterRate = String(format: "%.2f", impact.after.seizuresPerDay)
            let direction = delta < 0 ? "baisse" : "hausse"
            let absDelta = String(format: "%.2f", abs(delta))
            lines.append("La modification la plus marquée du plan est celle du \(impact.medicationName) le \(df.string(from: impact.revisionDate)) : \(direction) du nombre journalier de crises de \(beforeRate) à \(afterRate) (delta de \(absDelta) crise/jour sur la fenêtre 14 jours avant/après). Corrélation observationnelle, à interpréter dans le contexte clinique complet.")
        }

        // Humeur
        if let avg = overall.avgMoodLevel {
            let label = MoodLevel(rawValue: Int(avg.rounded()))?.label ?? "—"
            lines.append("Humeur moyenne renseignée : \(String(format: "%.1f", avg))/5 (« \(label) »).")
        }

        // Symptômes Rett
        if symptomAnalysis.totalObservations > 0 {
            let topThree = symptomAnalysis.perSymptom.prefix(3)
                .map { "\($0.type.label) (\($0.occurrences))" }
                .joined(separator: ", ")
            lines.append("Symptômes Rett observés : \(symptomAnalysis.totalObservations) saisie\(symptomAnalysis.totalObservations > 1 ? "s" : "") sur la période. Principaux : \(topThree).")
        }

        // Corrélations
        let significant = correlations.filter { abs($0.r) >= 0.2 }
        if !significant.isEmpty {
            lines.append("")
            lines.append("Pistes de corrélation observées (à interpréter avec prudence — n'établissent pas de causalité) :")
            for c in significant.sorted(by: { abs($0.r) > abs($1.r) }) {
                let r = String(format: "%.2f", c.r)
                lines.append("• \(c.signal) : corrélation \(c.direction) \(c.strength.label) (r = \(r), n = \(c.n) jours).")
            }
        } else if !correlations.isEmpty {
            lines.append("")
            lines.append("Aucune corrélation marquée détectée entre la fréquence des crises et les autres signaux suivis (humeur, repas, sommeil, observance).")
        } else {
            lines.append("")
            lines.append("Données insuffisantes pour calculer des corrélations (au moins 5 jours communs requis par signal).")
        }

        return lines.joined(separator: "\n")
    }

    private static func formatDur(_ seconds: Int) -> String {
        if seconds == 0 { return "0 s" }
        let m = seconds / 60
        let s = seconds % 60
        if m == 0 { return "\(s) s" }
        if s == 0 { return "\(m) min" }
        return "\(m) min \(s) s"
    }
}
