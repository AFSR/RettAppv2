import Foundation
import SwiftData

/// Service d'export + import de `CombinedBackup`. Convertit dans les deux
/// sens entre la base SwiftData et le JSON portable.
///
/// **Import** : idempotent par UUID — si un record existe déjà, on met à
/// jour ses champs. Sinon on insère. Le `saveTouching()` final pousse les
/// changements vers CloudKit via le mécanisme de sync standard.
enum CombinedBackupService {

    static let fileName = "rettapp-sauvegarde-complete.json"

    // MARK: - Export

    @MainActor
    static func export(context: ModelContext) throws -> URL {
        let profile = (try? context.fetch(FetchDescriptor<ChildProfile>()))?.first
        let medications = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<MedicationLog>())) ?? []
        let seizures = (try? context.fetch(FetchDescriptor<SeizureEvent>())) ?? []
        let moods = (try? context.fetch(FetchDescriptor<MoodEntry>())) ?? []
        let observations = (try? context.fetch(FetchDescriptor<DailyObservation>())) ?? []
        let symptoms = (try? context.fetch(FetchDescriptor<SymptomEvent>())) ?? []
        let revisions = (try? context.fetch(FetchDescriptor<MedicationRevision>())) ?? []

        let backup = CombinedBackup(
            version: CombinedBackup.currentVersion,
            exportedAt: Date(),
            child: profile.map { p in
                CombinedBackup.ChildBackup(
                    id: p.id, firstName: p.firstName, lastName: p.lastName,
                    birthDate: p.birthDate, hasEpilepsy: p.hasEpilepsy,
                    sexRaw: p.sexRaw, createdAt: p.createdAt
                )
            },
            medications: medications.map { m in
                CombinedBackup.MedicationBackup(
                    id: m.id, name: m.name, doseAmount: m.doseAmount,
                    doseUnitRaw: m.doseUnitRaw, kindRaw: m.kindRaw,
                    isActive: m.isActive, notifyEnabled: m.notifyEnabled,
                    createdAt: m.createdAt, intakes: m.intakes,
                    childProfileId: m.childProfile?.id
                )
            },
            medicationLogs: logs.map { l in
                CombinedBackup.LogBackup(
                    id: l.id, medicationId: l.medicationId,
                    medicationName: l.medicationName, scheduledTime: l.scheduledTime,
                    takenTime: l.takenTime, taken: l.taken, dose: l.dose,
                    doseUnitRaw: l.doseUnitRaw, childProfileId: l.childProfileId,
                    isAdHoc: l.isAdHoc, adhocReason: l.adhocReason
                )
            },
            seizures: seizures.map { s in
                CombinedBackup.SeizureBackup(
                    id: s.id, startTime: s.startTime, endTime: s.endTime,
                    seizureTypeRaw: s.seizureTypeRaw, triggerRaw: s.triggerRaw,
                    triggerNotes: s.triggerNotes, notes: s.notes,
                    childProfileId: s.childProfileId
                )
            },
            moods: moods.map { m in
                CombinedBackup.MoodBackup(
                    id: m.id, timestamp: m.timestamp, levelRaw: m.levelRaw,
                    notes: m.notes, childProfileId: m.childProfileId
                )
            },
            observations: observations.map { o in
                CombinedBackup.ObservationBackup(
                    id: o.id, dayStart: o.dayStart,
                    breakfastRatingRaw: o.breakfastRatingRaw, breakfastNotes: o.breakfastNotes,
                    lunchRatingRaw: o.lunchRatingRaw, lunchNotes: o.lunchNotes,
                    snackRatingRaw: o.snackRatingRaw, snackNotes: o.snackNotes,
                    dinnerRatingRaw: o.dinnerRatingRaw, dinnerNotes: o.dinnerNotes,
                    hydrationRatingRaw: o.hydrationRatingRaw, hydrationNotes: o.hydrationNotes,
                    nightSleepRatingRaw: o.nightSleepRatingRaw,
                    nightSleepDurationMinutes: o.nightSleepDurationMinutes,
                    nightSleepNotes: o.nightSleepNotes,
                    napDurationMinutes: o.napDurationMinutes, napNotes: o.napNotes,
                    generalNotes: o.generalNotes, childProfileId: o.childProfileId
                )
            },
            symptoms: symptoms.map { s in
                CombinedBackup.SymptomBackup(
                    id: s.id, timestamp: s.timestamp, symptomTypeRaw: s.symptomTypeRaw,
                    intensityRaw: s.intensityRaw, durationMinutes: s.durationMinutes,
                    notes: s.notes, childProfileId: s.childProfileId
                )
            },
            revisions: revisions.map { r in
                CombinedBackup.RevisionBackup(
                    id: r.id, medicationId: r.medicationId, effectiveFrom: r.effectiveFrom,
                    name: r.name, doseAmount: r.doseAmount, doseUnitRaw: r.doseUnitRaw,
                    kindRaw: r.kindRaw, isActive: r.isActive,
                    notifyEnabled: r.notifyEnabled, intakes: r.intakes
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)

        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Import

    struct ImportResult {
        var medications: Int = 0
        var medicationLogs: Int = 0
        var seizures: Int = 0
        var moods: Int = 0
        var observations: Int = 0
        var symptoms: Int = 0
        var revisions: Int = 0
        var childProfileApplied: Bool = false
        var errors: [String] = []

        var total: Int {
            medications + medicationLogs + seizures + moods + observations + symptoms + revisions
        }
    }

    @MainActor
    @discardableResult
    static func importBackup(contents: Data, context: ModelContext) -> ImportResult {
        var result = ImportResult()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let backup: CombinedBackup
        do {
            backup = try decoder.decode(CombinedBackup.self, from: contents)
        } catch {
            // Fallback : essaie le décodage par défaut au cas où la sauvegarde
            // vient d'une version qui n'utilisait pas ISO 8601.
            do {
                let fallback = JSONDecoder()
                backup = try fallback.decode(CombinedBackup.self, from: contents)
            } catch {
                result.errors.append("Fichier JSON invalide : \(error.localizedDescription)")
                return result
            }
        }

        if backup.version > CombinedBackup.currentVersion {
            result.errors.append("Version \(backup.version) plus récente que celle supportée (\(CombinedBackup.currentVersion)). Mettez à jour RettApp.")
            return result
        }

        // ChildProfile : on ne crée pas un second profil (l'app n'en gère
        // qu'un). On met à jour le profil existant s'il a le même UUID,
        // sinon on ignore — l'utilisateur doit configurer son enfant via
        // l'onboarding avant d'importer.
        if let c = backup.child {
            let cid = c.id
            let existing = try? context.fetch(FetchDescriptor<ChildProfile>(
                predicate: #Predicate<ChildProfile> { $0.id == cid }
            )).first
            if let existing {
                existing.firstName = c.firstName
                existing.lastName = c.lastName
                existing.birthDate = c.birthDate
                existing.hasEpilepsy = c.hasEpilepsy
                existing.sexRaw = c.sexRaw
                result.childProfileApplied = true
            }
        }

        for m in backup.medications {
            upsertMedication(m, in: context)
            result.medications += 1
        }
        for l in backup.medicationLogs {
            upsertLog(l, in: context)
            result.medicationLogs += 1
        }
        for s in backup.seizures {
            upsertSeizure(s, in: context)
            result.seizures += 1
        }
        for m in backup.moods {
            upsertMood(m, in: context)
            result.moods += 1
        }
        for o in backup.observations {
            upsertObservation(o, in: context)
            result.observations += 1
        }
        for s in backup.symptoms {
            upsertSymptom(s, in: context)
            result.symptoms += 1
        }
        for r in backup.revisions {
            upsertRevision(r, in: context)
            result.revisions += 1
        }

        do {
            try context.saveTouching()
        } catch {
            result.errors.append("Erreur d'écriture SwiftData : \(error.localizedDescription)")
        }
        return result
    }

    // MARK: - Per-type upserts

    private static func upsertMedication(_ m: CombinedBackup.MedicationBackup, in context: ModelContext) {
        let id = m.id
        let existing = try? context.fetch(FetchDescriptor<Medication>(
            predicate: #Predicate { $0.id == id }
        )).first
        let unit = DoseUnit(rawValue: m.doseUnitRaw) ?? .mg
        let kind = MedicationKind(rawValue: m.kindRaw) ?? .regular
        let cid = m.childProfileId
        let child: ChildProfile? = cid.flatMap { uuid in
            try? context.fetch(FetchDescriptor<ChildProfile>(
                predicate: #Predicate { $0.id == uuid }
            )).first
        }
        if let existing {
            existing.name = m.name
            existing.doseAmount = m.doseAmount
            existing.doseUnit = unit
            existing.kind = kind
            existing.isActive = m.isActive
            existing.notifyEnabled = m.notifyEnabled
            existing.intakes = m.intakes
            existing.childProfile = child
        } else {
            let new = Medication(
                id: m.id, name: m.name,
                doseAmount: m.doseAmount, doseUnit: unit,
                scheduledHours: m.intakes.map { HourMinute(hour: $0.hour, minute: $0.minute) },
                kind: kind, isActive: m.isActive,
                notifyEnabled: m.notifyEnabled, createdAt: m.createdAt,
                intakes: m.intakes
            )
            new.childProfile = child
            context.insert(new)
        }
    }

    private static func upsertLog(_ l: CombinedBackup.LogBackup, in context: ModelContext) {
        let id = l.id
        let existing = try? context.fetch(FetchDescriptor<MedicationLog>(
            predicate: #Predicate { $0.id == id }
        )).first
        let unit = DoseUnit(rawValue: l.doseUnitRaw) ?? .mg
        if let existing {
            existing.medicationId = l.medicationId
            existing.medicationName = l.medicationName
            existing.scheduledTime = l.scheduledTime
            existing.takenTime = l.takenTime
            existing.taken = l.taken
            existing.dose = l.dose
            existing.doseUnit = unit
            existing.childProfileId = l.childProfileId
            existing.isAdHoc = l.isAdHoc
            existing.adhocReason = l.adhocReason
        } else {
            let new = MedicationLog(
                id: l.id, medicationId: l.medicationId, medicationName: l.medicationName,
                scheduledTime: l.scheduledTime, takenTime: l.takenTime, taken: l.taken,
                dose: l.dose, doseUnit: unit, childProfileId: l.childProfileId,
                isAdHoc: l.isAdHoc, adhocReason: l.adhocReason
            )
            context.insert(new)
        }
    }

    private static func upsertSeizure(_ s: CombinedBackup.SeizureBackup, in context: ModelContext) {
        let id = s.id
        let existing = try? context.fetch(FetchDescriptor<SeizureEvent>(
            predicate: #Predicate { $0.id == id }
        )).first
        let type = SeizureType(rawValue: s.seizureTypeRaw) ?? .other
        let trigger = SeizureTrigger(rawValue: s.triggerRaw) ?? .none
        if let existing {
            existing.startTime = s.startTime
            existing.endTime = s.endTime
            existing.durationSeconds = max(0, Int(s.endTime.timeIntervalSince(s.startTime)))
            existing.seizureType = type
            existing.trigger = trigger
            existing.triggerNotes = s.triggerNotes
            existing.notes = s.notes
            existing.childProfileId = s.childProfileId
        } else {
            let new = SeizureEvent(
                id: s.id, startTime: s.startTime, endTime: s.endTime,
                seizureType: type, trigger: trigger,
                triggerNotes: s.triggerNotes, notes: s.notes,
                childProfileId: s.childProfileId
            )
            context.insert(new)
        }
    }

    private static func upsertMood(_ m: CombinedBackup.MoodBackup, in context: ModelContext) {
        let id = m.id
        let existing = try? context.fetch(FetchDescriptor<MoodEntry>(
            predicate: #Predicate { $0.id == id }
        )).first
        let level = MoodLevel(rawValue: m.levelRaw) ?? .neutral
        if let existing {
            existing.timestamp = m.timestamp
            existing.level = level
            existing.notes = m.notes
            existing.childProfileId = m.childProfileId
        } else {
            let new = MoodEntry(
                id: m.id, timestamp: m.timestamp, level: level,
                notes: m.notes, childProfileId: m.childProfileId
            )
            context.insert(new)
        }
    }

    private static func upsertObservation(_ o: CombinedBackup.ObservationBackup, in context: ModelContext) {
        let id = o.id
        let existing = try? context.fetch(FetchDescriptor<DailyObservation>(
            predicate: #Predicate { $0.id == id }
        )).first
        let target: DailyObservation
        if let existing {
            target = existing
        } else {
            target = DailyObservation(id: o.id, dayStart: o.dayStart)
            context.insert(target)
        }
        target.dayStart = o.dayStart
        target.breakfastRatingRaw = o.breakfastRatingRaw
        target.breakfastNotes = o.breakfastNotes
        target.lunchRatingRaw = o.lunchRatingRaw
        target.lunchNotes = o.lunchNotes
        target.snackRatingRaw = o.snackRatingRaw
        target.snackNotes = o.snackNotes
        target.dinnerRatingRaw = o.dinnerRatingRaw
        target.dinnerNotes = o.dinnerNotes
        target.hydrationRatingRaw = o.hydrationRatingRaw
        target.hydrationNotes = o.hydrationNotes
        target.nightSleepRatingRaw = o.nightSleepRatingRaw
        target.nightSleepDurationMinutes = o.nightSleepDurationMinutes
        target.nightSleepNotes = o.nightSleepNotes
        target.napDurationMinutes = o.napDurationMinutes
        target.napNotes = o.napNotes
        target.generalNotes = o.generalNotes
        target.childProfileId = o.childProfileId
    }

    private static func upsertSymptom(_ s: CombinedBackup.SymptomBackup, in context: ModelContext) {
        let id = s.id
        let existing = try? context.fetch(FetchDescriptor<SymptomEvent>(
            predicate: #Predicate { $0.id == id }
        )).first
        let type = RettSymptom(rawValue: s.symptomTypeRaw) ?? .other
        if let existing {
            existing.timestamp = s.timestamp
            existing.symptomType = type
            existing.intensityRaw = s.intensityRaw
            existing.durationMinutes = s.durationMinutes
            existing.notes = s.notes
            existing.childProfileId = s.childProfileId
        } else {
            let new = SymptomEvent(
                id: s.id, timestamp: s.timestamp, symptomType: type,
                intensity: s.intensityRaw, durationMinutes: s.durationMinutes,
                notes: s.notes, childProfileId: s.childProfileId
            )
            context.insert(new)
        }
    }

    private static func upsertRevision(_ r: CombinedBackup.RevisionBackup, in context: ModelContext) {
        let id = r.id
        let existing = try? context.fetch(FetchDescriptor<MedicationRevision>(
            predicate: #Predicate { $0.id == id }
        )).first
        let unit = DoseUnit(rawValue: r.doseUnitRaw) ?? .mg
        let kind = MedicationKind(rawValue: r.kindRaw) ?? .regular
        if let existing {
            existing.medicationId = r.medicationId
            existing.effectiveFrom = r.effectiveFrom
            existing.name = r.name
            existing.doseAmount = r.doseAmount
            existing.doseUnit = unit
            existing.kind = kind
            existing.isActive = r.isActive
            existing.notifyEnabled = r.notifyEnabled
            existing.intakes = r.intakes
        } else {
            let new = MedicationRevision(
                id: r.id, medicationId: r.medicationId, effectiveFrom: r.effectiveFrom,
                name: r.name, doseAmount: r.doseAmount, doseUnit: unit,
                intakes: r.intakes, kind: kind,
                isActive: r.isActive, notifyEnabled: r.notifyEnabled
            )
            context.insert(new)
        }
    }
}
