import Foundation
import SwiftData
import os.log

/// Convertit un `BookletScanResult` validé par l'utilisateur en records
/// SwiftData insérés/mis à jour dans le journal.
///
/// Pour chaque jour de la semaine et chaque case cochée :
///   - Médicaments → `MedicationLog` marqué pris
///   - Crises → noté dans `DailyObservation.generalNotes` (sauf option « 0 »)
///   - Humeur → `MoodEntry` à midi du jour concerné
///   - Repas → `DailyObservation.{breakfast,lunch,snack,dinner}RatingRaw`
///   - Hydratation → `DailyObservation.hydrationRatingRaw`
///   - Sommeil → `DailyObservation.{nightSleep,nap}*`
///   - Symptômes Rett → `SymptomEvent` à 9h (matin) ou 15h (après-midi)
///   - Événements → `DailyObservation.generalNotes`
@MainActor
enum BookletInsertionService {

    private static let log = Logger(subsystem: "fr.afsr.RettApp", category: "BookletInsert")

    static func apply(
        _ result: BookletScanResult,
        in context: ModelContext,
        childProfile: ChildProfile?,
        existingMedications: [Medication]
    ) -> Summary {
        var summary = Summary()
        let cal = Calendar.current
        let childId = childProfile?.id

        let totalChecked = result.checks.values.filter { $0 }.count
        log.info("apply() — \(totalChecked, privacy: .public) cases cochées à insérer ; jour de départ \(result.schema.start, privacy: .public) ; \(result.schema.days, privacy: .public) jours")

        // Pré-charge ou crée les DailyObservation par jour
        var observations: [Int: DailyObservation] = [:]
        for d in 0..<result.schema.days {
            guard let day = result.date(forDay: d, calendar: cal) else {
                log.error("Jour \(d, privacy: .public) — impossible de calculer la date")
                continue
            }
            let dayStart = cal.startOfDay(for: day)
            let descriptor = FetchDescriptor<DailyObservation>(
                predicate: #Predicate<DailyObservation> { $0.dayStart == dayStart }
            )
            do {
                if let existing = try context.fetch(descriptor).first {
                    observations[d] = existing
                    log.info("Jour \(d, privacy: .public) (\(dayStart.ISO8601Format(), privacy: .public)) — DailyObservation existante réutilisée")
                } else {
                    let obs = DailyObservation(dayStart: dayStart, childProfileId: childId)
                    context.insert(obs)
                    observations[d] = obs
                    log.info("Jour \(d, privacy: .public) (\(dayStart.ISO8601Format(), privacy: .public)) — DailyObservation nouvelle créée")
                }
            } catch {
                log.error("Fetch DailyObservation échoué : \(error.localizedDescription, privacy: .public)")
                let obs = DailyObservation(dayStart: dayStart, childProfileId: childId)
                context.insert(obs)
                observations[d] = obs
            }
        }

        for (cell, isChecked) in result.checks where isChecked {
            guard let day = result.date(forDay: cell.dayIndex, calendar: cal) else { continue }
            let dayStart = cal.startOfDay(for: day)

            switch cell.section {
            case .medication:
                guard cell.rowIndex < result.schema.meds.count else { continue }
                let label = result.schema.meds[cell.rowIndex]
                if applyMedicationCheck(label: label, on: dayStart,
                                        existingMedications: existingMedications,
                                        childId: childId, in: context) {
                    summary.medicationsTaken += 1
                }

            case .seizure:
                // optionIndex 0 = « 0 crise », on n'ajoute rien (pas pertinent)
                guard cell.optionIndex > 0 else { continue }
                let typeIdx = cell.rowIndex
                let optIdx = cell.optionIndex
                let typeLabel = SeizureType.allCases[safe: typeIdx]?.label ?? "Crise"
                let countLabel = ["0", "1", "2-3", "4+"][safe: optIdx] ?? "?"
                if let obs = observations[cell.dayIndex] {
                    appendNote(to: obs, "\(typeLabel) : \(countLabel)")
                    log.info("Jour \(cell.dayIndex, privacy: .public) — Crise notée : \(typeLabel, privacy: .public) \(countLabel, privacy: .public)")
                    summary.seizuresNoted += 1
                }

            case .mood:
                let level: MoodLevel = [.veryGood, .good, .neutral, .worried, .veryDifficult][safe: cell.rowIndex] ?? .neutral
                let timestamp = cal.date(byAdding: .hour, value: 12, to: dayStart) ?? dayStart
                let entry = MoodEntry(timestamp: timestamp, level: level, childProfileId: childId)
                context.insert(entry)
                log.info("Jour \(cell.dayIndex, privacy: .public) — Humeur \(level.label, privacy: .public) (raw \(level.rawValue, privacy: .public))")
                summary.moodEntries += 1

            case .meals:
                guard let obs = observations[cell.dayIndex] else { continue }
                let rating = cell.optionIndex + 1  // R/P/M/B/T → 1/2/3/4/5
                // Conversion Character → String pour éviter toute ambiguïté
                let mealLetters = result.schema.mealSlots.map { String($0) }
                guard cell.rowIndex < mealLetters.count else { continue }
                let slot = mealLetters[cell.rowIndex]
                switch slot {
                case "B":
                    obs.breakfastRatingRaw = rating
                    log.info("Jour \(cell.dayIndex, privacy: .public) — Petit-déjeuner = \(rating, privacy: .public)/5")
                case "L":
                    obs.lunchRatingRaw = rating
                    log.info("Jour \(cell.dayIndex, privacy: .public) — Déjeuner = \(rating, privacy: .public)/5")
                case "S":
                    obs.snackRatingRaw = rating
                    log.info("Jour \(cell.dayIndex, privacy: .public) — Goûter = \(rating, privacy: .public)/5")
                case "D":
                    obs.dinnerRatingRaw = rating
                    log.info("Jour \(cell.dayIndex, privacy: .public) — Dîner = \(rating, privacy: .public)/5")
                default:
                    log.error("Slot repas inconnu : \(slot, privacy: .public)")
                }
                summary.mealEntries += 1

            case .hydration:
                guard let obs = observations[cell.dayIndex] else { continue }
                // F/M/B/E → 2/3/4/5 (mappé sur QualityRating 1-5, on garde Faible=2 plutôt que veryPoor=1
                // pour réserver veryPoor à un cas pathologique)
                let mapping = [2, 3, 4, 5]
                if let rating = mapping[safe: cell.optionIndex] {
                    obs.hydrationRatingRaw = rating
                    log.info("Jour \(cell.dayIndex, privacy: .public) — Hydratation = \(rating, privacy: .public)/5")
                }

            case .sleep:
                guard let obs = observations[cell.dayIndex] else { continue }
                switch cell.rowIndex {
                case 0:
                    // Durée nuit : <6/6-8/8-10/>10 → 300/420/540/660 minutes
                    let mapping = [300, 420, 540, 660]
                    if let m = mapping[safe: cell.optionIndex] {
                        obs.nightSleepDurationMinutes = m
                        log.info("Jour \(cell.dayIndex, privacy: .public) — Sommeil nuit = \(m, privacy: .public) min")
                    }
                case 1:
                    // Qualité : B/M/D → 4/3/2
                    let mapping = [4, 3, 2]
                    if let r = mapping[safe: cell.optionIndex] {
                        obs.nightSleepRatingRaw = r
                        log.info("Jour \(cell.dayIndex, privacy: .public) — Qualité sommeil = \(r, privacy: .public)/5")
                    }
                case 2, 3:
                    // Sieste matin/aprem : Non/<30/30-60/>60 → 0/20/45/75 min
                    let mapping = [0, 20, 45, 75]
                    if let m = mapping[safe: cell.optionIndex] {
                        // Additionne matin + après-midi pour éviter d'écraser
                        obs.napDurationMinutes = max(obs.napDurationMinutes, 0) + m
                        log.info("Jour \(cell.dayIndex, privacy: .public) — Sieste +\(m, privacy: .public) min (cumul=\(obs.napDurationMinutes, privacy: .public))")
                    }
                case 4:
                    let labels = ["0 réveil", "1-2 réveils", "3+ réveils"]
                    if let lbl = labels[safe: cell.optionIndex] {
                        appendNote(to: obs, "Nuit : \(lbl)")
                        log.info("Jour \(cell.dayIndex, privacy: .public) — Réveils : \(lbl, privacy: .public)")
                    }
                default:
                    log.error("Ligne sommeil inconnue : \(cell.rowIndex, privacy: .public)")
                }

            case .symptoms:
                guard cell.rowIndex < result.schema.symptoms.count,
                      let symptom = RettSymptom(rawValue: result.schema.symptoms[cell.rowIndex])
                else { continue }
                let hour = (cell.half == .morning) ? 9 : 15
                let timestamp = cal.date(byAdding: .hour, value: hour, to: dayStart) ?? dayStart
                let event = SymptomEvent(
                    timestamp: timestamp,
                    symptomType: symptom,
                    childProfileId: childId
                )
                context.insert(event)
                log.info("Jour \(cell.dayIndex, privacy: .public) — Symptôme \(symptom.label, privacy: .public) à \(hour, privacy: .public)h")
                summary.symptomEvents += 1

            case .events:
                guard let obs = observations[cell.dayIndex] else { continue }
                let labels = [
                    "Pleurs / cris inexpliqués",
                    "Agitation marquée",
                    "Selles inhabituelles",
                    "Vomissements / régurgitations",
                    "Comportement nouveau",
                    "Autre événement notable"
                ]
                if let lbl = labels[safe: cell.rowIndex] {
                    appendNote(to: obs, lbl)
                    log.info("Jour \(cell.dayIndex, privacy: .public) — Événement : \(lbl, privacy: .public)")
                    summary.eventsNoted += 1
                }
            }
        }

        // Sauvegarde explicite avec logging d'erreur — try? cachait les échecs
        do {
            try context.save()
            log.info("Sauvegarde réussie. Total : \(summary.summaryText, privacy: .public)")
        } catch {
            log.error("ÉCHEC sauvegarde SwiftData : \(error.localizedDescription, privacy: .public)")
        }
        return summary
    }

    // MARK: - Helpers

    /// Renvoie `true` si la prise a été marquée (médicament trouvé et log
    /// inséré ou mis à jour), `false` sinon (médicament introuvable, etc.)
    private static func applyMedicationCheck(
        label: String, on dayStart: Date,
        existingMedications: [Medication], childId: UUID?,
        in context: ModelContext
    ) -> Bool {
        guard let atRange = label.range(of: " @ ") else {
            log.error("Libellé médicament malformé (pas de '@') : \(label, privacy: .public)")
            return false
        }
        let timeStr = String(label[atRange.upperBound...])
        let parts = timeStr.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else {
            log.error("Heure médicament malformée : \(timeStr, privacy: .public)")
            return false
        }
        let nameDosePart = String(label[..<atRange.lowerBound])

        // Cherche par préfixe du nom (ex. "Keppra 250 mg" matche "Keppra")
        guard let med = existingMedications
            .filter({ $0.isActive })
            .first(where: { nameDosePart.hasPrefix($0.name) })
        else {
            log.error("Médicament introuvable : \(nameDosePart, privacy: .public)")
            return false
        }

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: dayStart)
        comps.hour = parts[0]; comps.minute = parts[1]
        guard let scheduledTime = cal.date(from: comps) else { return false }

        let medId = med.id
        let descriptor = FetchDescriptor<MedicationLog>(
            predicate: #Predicate<MedicationLog> { $0.medicationId == medId }
        )
        let logsForMed = (try? context.fetch(descriptor)) ?? []
        if let existing = logsForMed.first(where: { $0.scheduledTime == scheduledTime }) {
            existing.taken = true
            existing.takenTime = existing.takenTime ?? scheduledTime
            log.info("Médicament \(med.name, privacy: .public) à \(timeStr, privacy: .public) — log existant marqué pris (\(scheduledTime.ISO8601Format(), privacy: .public))")
        } else {
            let logEntry = MedicationLog(
                medicationId: med.id,
                medicationName: med.name,
                scheduledTime: scheduledTime,
                takenTime: scheduledTime,
                taken: true,
                dose: med.doseAmount,
                doseUnit: med.doseUnit,
                childProfileId: childId
            )
            context.insert(logEntry)
            log.info("Médicament \(med.name, privacy: .public) à \(timeStr, privacy: .public) — nouveau log inséré (\(scheduledTime.ISO8601Format(), privacy: .public))")
        }
        return true
    }

    private static func appendNote(to obs: DailyObservation, _ text: String) {
        if obs.generalNotes.isEmpty {
            obs.generalNotes = text
        } else if !obs.generalNotes.contains(text) {
            obs.generalNotes += "\n" + text
        }
    }

    struct Summary {
        var medicationsTaken: Int = 0
        var seizuresNoted: Int = 0
        var moodEntries: Int = 0
        var mealEntries: Int = 0
        var symptomEvents: Int = 0
        var eventsNoted: Int = 0

        var totalChecks: Int {
            medicationsTaken + seizuresNoted + moodEntries + mealEntries + symptomEvents + eventsNoted
        }

        var summaryText: String {
            var parts: [String] = []
            if medicationsTaken > 0 { parts.append("\(medicationsTaken) prise\(medicationsTaken > 1 ? "s" : "") de médicament") }
            if moodEntries > 0      { parts.append("\(moodEntries) humeur\(moodEntries > 1 ? "s" : "")") }
            if mealEntries > 0      { parts.append("\(mealEntries) repas") }
            if symptomEvents > 0    { parts.append("\(symptomEvents) symptôme\(symptomEvents > 1 ? "s" : "")") }
            if seizuresNoted > 0    { parts.append("\(seizuresNoted) note\(seizuresNoted > 1 ? "s" : "") de crise") }
            if eventsNoted > 0      { parts.append("\(eventsNoted) événement\(eventsNoted > 1 ? "s" : "")") }
            return parts.joined(separator: " · ")
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
