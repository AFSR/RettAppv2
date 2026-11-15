import Foundation

/// Passage des données SwiftData aux jours résumés de `JournalFactors`.
extension JournalFactors {

    /// Nombre de jours regardés. Indépendant de l'échelle du Bilan : une
    /// semaine ne contient jamais assez de jours pour conclure, alors que
    /// trois mois en contiennent assez pour qu'un lien apparaisse.
    static let lookbackDays = 90

    /// - Parameter end: borne haute exclue (en pratique la fin de la fenêtre
    ///   du Bilan, plafonnée à demain pour ne pas compter de jours à venir).
    static func days(
        seizures: [SeizureEvent],
        symptoms: [SymptomEvent],
        observations: [DailyObservation],
        moods: [MoodEntry],
        logs: [MedicationLog],
        endingBefore end: Date,
        calendar: Calendar = .current
    ) -> [Day] {
        let endDay = calendar.startOfDay(for: end)
        guard let first = calendar.date(byAdding: .day, value: -lookbackDays, to: endDay) else { return [] }

        func key(_ d: Date) -> Date { calendar.startOfDay(for: d) }

        var seizuresByDay: [Date: [SeizureEvent]] = [:]
        for e in seizures where e.startTime >= first && e.startTime < endDay {
            seizuresByDay[key(e.startTime), default: []].append(e)
        }
        var symptomsByDay: [Date: [SymptomEvent]] = [:]
        for e in symptoms where e.timestamp >= first && e.timestamp < endDay {
            symptomsByDay[key(e.timestamp), default: []].append(e)
        }
        var moodsByDay: [Date: [MoodEntry]] = [:]
        for e in moods where e.timestamp >= first && e.timestamp < endDay {
            moodsByDay[key(e.timestamp), default: []].append(e)
        }
        var logsByDay: [Date: [MedicationLog]] = [:]
        for l in logs where !l.isAdHoc && l.scheduledTime >= first && l.scheduledTime < endDay {
            logsByDay[key(l.scheduledTime), default: []].append(l)
        }
        var observationByDay: [Date: DailyObservation] = [:]
        for o in observations { observationByDay[key(o.dayStart)] = o }

        // Nom le plus récent de chaque médicament, pour une seule étiquette
        // même si le nom a été corrigé pendant la période.
        var names: [UUID: String] = [:]
        for l in logs.sorted(by: { $0.scheduledTime < $1.scheduledTime }) where !l.isAdHoc {
            names[l.medicationId] = l.medicationName
        }

        var result: [Day] = []
        var cursor = first
        while cursor < endDay {
            var day = Day(start: cursor)

            let s = seizuresByDay[cursor] ?? []
            day.seizureCount = s.count
            day.seizureSeconds = s.reduce(0) { $0 + $1.durationSeconds }
            for e in symptomsByDay[cursor] ?? [] { day.symptomCounts[e.symptomType, default: 0] += 1 }

            if let o = observationByDay[cursor] {
                if o.nightSleepRatingRaw > 0 { day.factors[.sleepQuality] = Double(o.nightSleepRatingRaw) }
                if o.nightSleepDurationMinutes > 0 { day.factors[.sleepHours] = Double(o.nightSleepDurationMinutes) / 60 }
                if o.averageMealRatingRaw > 0 { day.factors[.meals] = Double(o.averageMealRatingRaw) }
                if o.hydrationRatingRaw > 0 { day.factors[.hydration] = Double(o.hydrationRatingRaw) }
                if let n = o.stoolCount { day.factors[.stoolCount] = Double(n) }
                if o.urineOutputRaw > 0 { day.factors[.urine] = Double(o.urineOutputRaw) }
            }
            if let m = moodsByDay[cursor], !m.isEmpty {
                day.factors[.mood] = m.map { Double($0.levelRaw) }.reduce(0, +) / Double(m.count)
            }
            if let l = logsByDay[cursor], !l.isEmpty {
                day.factors[.adherence] = Double(l.filter(\.taken).count) / Double(l.count)

                // Plan médicamenteux, médicament par médicament. La dose vient
                // des prises planifiées (et non des prises faites) : ainsi
                // une prise oubliée ne se déguise pas en baisse de dosage,
                // elle est portée par `.medicationTaken`.
                for (medId, group) in Dictionary(grouping: l, by: \.medicationId) {
                    let ref = MedicationRef(id: medId, name: names[medId] ?? group[0].medicationName)
                    day.factors[.medicationDose(ref)] = group.reduce(0) { $0 + $1.dose }
                    day.factors[.medicationTaken(ref)] = Double(group.filter(\.taken).count) / Double(group.count)
                }
            }

            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
}
