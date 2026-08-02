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

    /// Index UUID → objet de tous les enregistrements déjà en base, construit
    /// en 8 requêtes au début de l'import.
    ///
    /// Remplace le `context.fetch(predicate: id == X)` qui était fait POUR
    /// CHAQUE enregistrement importé : sur une sauvegarde de plusieurs
    /// milliers de lignes, ce scan-par-ligne rendait l'import quadratique et
    /// gelait l'application. Avec l'index, l'import est linéaire.
    final class ExistingIndex {
        var profiles: [UUID: ChildProfile] = [:]
        var medications: [UUID: Medication] = [:]
        var logs: [UUID: MedicationLog] = [:]
        var seizures: [UUID: SeizureEvent] = [:]
        var moods: [UUID: MoodEntry] = [:]
        var observations: [UUID: DailyObservation] = [:]
        var symptoms: [UUID: SymptomEvent] = [:]
        var revisions: [UUID: MedicationRevision] = [:]

        init(context: ModelContext) {
            func map<T: PersistentModel>(_ items: [T], _ key: (T) -> UUID) -> [UUID: T] {
                var d: [UUID: T] = [:]
                d.reserveCapacity(items.count)
                for i in items { d[key(i)] = i }
                return d
            }
            profiles     = map((try? context.fetch(FetchDescriptor<ChildProfile>())) ?? [], \.id)
            medications  = map((try? context.fetch(FetchDescriptor<Medication>())) ?? [], \.id)
            logs         = map((try? context.fetch(FetchDescriptor<MedicationLog>())) ?? [], \.id)
            seizures     = map((try? context.fetch(FetchDescriptor<SeizureEvent>())) ?? [], \.id)
            moods        = map((try? context.fetch(FetchDescriptor<MoodEntry>())) ?? [], \.id)
            observations = map((try? context.fetch(FetchDescriptor<DailyObservation>())) ?? [], \.id)
            symptoms     = map((try? context.fetch(FetchDescriptor<SymptomEvent>())) ?? [], \.id)
            revisions    = map((try? context.fetch(FetchDescriptor<MedicationRevision>())) ?? [], \.id)
        }
    }

    // MARK: - Export

    @MainActor
    static func export(context: ModelContext) throws -> URL {
        let profiles = (try? context.fetch(FetchDescriptor<ChildProfile>())) ?? []
        let profile = profiles.first
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
                    sexRaw: p.sexRaw, createdAt: p.createdAt,
                    lastModifiedAt: p.lastModifiedAt
                )
            },
            medications: medications.map { m in
                CombinedBackup.MedicationBackup(
                    id: m.id, name: m.name, doseAmount: m.doseAmount,
                    doseUnitRaw: m.doseUnitRaw, kindRaw: m.kindRaw,
                    isActive: m.isActive, notifyEnabled: m.notifyEnabled,
                    createdAt: m.createdAt, intakes: m.intakes,
                    childProfileId: m.childProfile?.id,
                    lastModifiedAt: m.lastModifiedAt
                )
            },
            medicationLogs: logs.map { l in
                CombinedBackup.LogBackup(
                    id: l.id, medicationId: l.medicationId,
                    medicationName: l.medicationName, scheduledTime: l.scheduledTime,
                    takenTime: l.takenTime, taken: l.taken, dose: l.dose,
                    doseUnitRaw: l.doseUnitRaw, childProfileId: l.childProfileId,
                    isAdHoc: l.isAdHoc, adhocReason: l.adhocReason,
                    lastModifiedAt: l.lastModifiedAt
                )
            },
            seizures: seizures.map { s in
                CombinedBackup.SeizureBackup(
                    id: s.id, startTime: s.startTime, endTime: s.endTime,
                    seizureTypeRaw: s.seizureTypeRaw, triggerRaw: s.triggerRaw,
                    triggerNotes: s.triggerNotes, notes: s.notes,
                    childProfileId: s.childProfileId,
                    lastModifiedAt: s.lastModifiedAt
                )
            },
            moods: moods.map { m in
                CombinedBackup.MoodBackup(
                    id: m.id, timestamp: m.timestamp, levelRaw: m.levelRaw,
                    notes: m.notes, childProfileId: m.childProfileId,
                    lastModifiedAt: m.lastModifiedAt
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
                    generalNotes: o.generalNotes, childProfileId: o.childProfileId,
                    lastModifiedAt: o.lastModifiedAt
                )
            },
            symptoms: symptoms.map { s in
                CombinedBackup.SymptomBackup(
                    id: s.id, timestamp: s.timestamp, symptomTypeRaw: s.symptomTypeRaw,
                    intensityRaw: s.intensityRaw, durationMinutes: s.durationMinutes,
                    notes: s.notes, childProfileId: s.childProfileId,
                    lastModifiedAt: s.lastModifiedAt
                )
            },
            revisions: revisions.map { r in
                CombinedBackup.RevisionBackup(
                    id: r.id, medicationId: r.medicationId, effectiveFrom: r.effectiveFrom,
                    name: r.name, doseAmount: r.doseAmount, doseUnitRaw: r.doseUnitRaw,
                    kindRaw: r.kindRaw, isActive: r.isActive,
                    notifyEnabled: r.notifyEnabled, intakes: r.intakes,
                    lastModifiedAt: r.lastModifiedAt
                )
            }
        )
        var enriched = backup
        enriched.children = profiles.map { p in
            CombinedBackup.ChildBackup(
                id: p.id, firstName: p.firstName, lastName: p.lastName,
                birthDate: p.birthDate, hasEpilepsy: p.hasEpilepsy,
                sexRaw: p.sexRaw, createdAt: p.createdAt,
                lastModifiedAt: p.lastModifiedAt
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(enriched)

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

    /// Import asynchrone par lots.
    ///
    /// Reste sur le `MainActor` (`ModelContext` n'est pas `Sendable`), mais
    /// rend la main au run-loop tous les `yieldEvery` enregistrements via
    /// `await Task.yield()` : l'interface reste vivante et peut afficher la
    /// progression au lieu de paraître gelée. Combiné à l'index pré-chargé et
    /// à la transaction du buffer d'écriture, un import de plusieurs milliers
    /// de lignes passe de « plusieurs minutes de gel » à quelques secondes
    /// avec progression visible.
    ///
    /// - Parameter progress: appelé avec (traités, total) au fil de l'import.
    @MainActor
    @discardableResult
    static func importBackup(
        contents: Data,
        context: ModelContext,
        progress: ((Int, Int) -> Void)? = nil
    ) async -> ImportResult {
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

        // INDEX PRÉ-CHARGÉ : sans lui, chaque upsert faisait un
        // `context.fetch(predicate: id == X)` — soit un scan SwiftData par
        // enregistrement (O(N²)). Sur une sauvegarde de 5 000 lignes, c'est
        // l'une des deux causes du gel de l'app. On charge ici, en 8 requêtes,
        // la table des enregistrements existants indexée par UUID.
        let index = ExistingIndex(context: context)

        // ChildProfile(s) : v2 fournit `children` (tous les profils), v1
        // seulement `child`. Deux règles de sécurité :
        //   1. CRÉER le profil s'il manque — indispensable pour qu'une
        //      restauration après effacement fonctionne réellement (l'ancien
        //      code « update-only » laissait zéro profil et affichait quand
        //      même « restauré avec succès »).
        //   2. Ne METTRE À JOUR un profil existant que si la sauvegarde est
        //      plus récente (`shouldApply`), sinon un vieux fichier écraserait
        //      des données fraîches — qui gagneraient ensuite le LWW partout.
        let childBackups = backup.children ?? backup.child.map { [$0] } ?? []
        for c in childBackups {
            let existing = index.profiles[c.id]
            if let existing {
                if shouldApply(backupTs: c.lastModifiedAt, over: existing.lastModifiedAt) {
                    existing.firstName = c.firstName
                    existing.lastName = c.lastName
                    existing.birthDate = c.birthDate
                    existing.hasEpilepsy = c.hasEpilepsy
                    existing.sexRaw = c.sexRaw
                    existing.lastModifiedAt = c.lastModifiedAt ?? existing.lastModifiedAt
                    result.childProfileApplied = true
                }
            } else {
                let new = ChildProfile(
                    id: c.id, firstName: c.firstName, lastName: c.lastName,
                    birthDate: c.birthDate, hasEpilepsy: c.hasEpilepsy,
                    sex: ChildSex(rawValue: c.sexRaw) ?? .unspecified,
                    createdAt: c.createdAt
                )
                if let ts = c.lastModifiedAt { new.lastModifiedAt = ts }
                context.insert(new)
                // Le profil doit entrer dans l'index : les médicaments
                // importés juste après s'y rattachent par childProfileId.
                index.profiles[c.id] = new
                result.childProfileApplied = true
            }
        }

        // Compteur global pour la progression + rendu de la main périodique.
        let total = backup.medications.count + backup.medicationLogs.count
            + backup.seizures.count + backup.moods.count + backup.observations.count
            + backup.symptoms.count + backup.revisions.count
        var done = 0
        let yieldEvery = 200
        progress?(0, total)

        @MainActor
        func tick() async {
            done += 1
            if done % yieldEvery == 0 {
                progress?(done, total)
                await Task.yield()
            }
        }

        for m in backup.medications {
            if upsertMedication(m, in: context, index: index) { result.medications += 1 }
            await tick()
        }
        for l in backup.medicationLogs {
            if upsertLog(l, in: context, index: index) { result.medicationLogs += 1 }
            await tick()
        }
        for s in backup.seizures {
            if upsertSeizure(s, in: context, index: index) { result.seizures += 1 }
            await tick()
        }
        for m in backup.moods {
            if upsertMood(m, in: context, index: index) { result.moods += 1 }
            await tick()
        }
        for o in backup.observations {
            if upsertObservation(o, in: context, index: index) { result.observations += 1 }
            await tick()
        }
        for s in backup.symptoms {
            if upsertSymptom(s, in: context, index: index) { result.symptoms += 1 }
            await tick()
        }
        for r in backup.revisions {
            if upsertRevision(r, in: context, index: index) { result.revisions += 1 }
            await tick()
        }
        progress?(total, total)

        do {
            // stampingTimestamps: false — les enregistrements restaurés gardent
            // leur lastModifiedAt d'origine. Ils sont bien re-poussés vers
            // CloudKit (enqueue PendingWriteStore), mais s'ils y rencontrent
            // une version plus récente, le LWW la laisse gagner : restaurer un
            // vieux fichier ne fait PAS régresser l'autre parent.
            try context.saveTouching(stampingTimestamps: false)
        } catch {
            result.errors.append("Erreur d'écriture SwiftData : \(error.localizedDescription)")
        }
        return result
    }

    /// Règle d'application d'une sauvegarde SUR un enregistrement existant :
    /// uniquement si le fichier est plus récent. Une sauvegarde v1 (sans
    /// timestamp) ne modifie JAMAIS un enregistrement existant — elle ne
    /// sert qu'à recréer les manquants (comportement le plus sûr).
    private static func shouldApply(backupTs: Date?, over localTs: Date) -> Bool {
        guard let ts = backupTs else { return false }
        return ts >= localTs
    }

    // MARK: - Per-type upserts

    @discardableResult
    private static func upsertMedication(_ m: CombinedBackup.MedicationBackup, in context: ModelContext, index: ExistingIndex) -> Bool {
        let existing = index.medications[m.id]
        let unit = DoseUnit(rawValue: m.doseUnitRaw) ?? .mg
        let kind = MedicationKind(rawValue: m.kindRaw) ?? .regular
        let child: ChildProfile? = m.childProfileId.flatMap { index.profiles[$0] }
        if let existing {
            guard shouldApply(backupTs: m.lastModifiedAt, over: existing.lastModifiedAt) else { return false }
            existing.name = m.name
            existing.doseAmount = m.doseAmount
            existing.doseUnit = unit
            existing.kind = kind
            existing.isActive = m.isActive
            existing.notifyEnabled = m.notifyEnabled
            existing.intakes = m.intakes
            existing.childProfile = child
            existing.lastModifiedAt = m.lastModifiedAt ?? existing.lastModifiedAt
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
            if let ts = m.lastModifiedAt { new.lastModifiedAt = ts }
            context.insert(new)
            index.medications[m.id] = new
        }
        return true
    }

    @discardableResult
    private static func upsertLog(_ l: CombinedBackup.LogBackup, in context: ModelContext, index: ExistingIndex) -> Bool {
        let existing = index.logs[l.id]
        let unit = DoseUnit(rawValue: l.doseUnitRaw) ?? .mg
        if let existing {
            guard shouldApply(backupTs: l.lastModifiedAt, over: existing.lastModifiedAt) else { return false }
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
            existing.lastModifiedAt = l.lastModifiedAt ?? existing.lastModifiedAt
        } else {
            let new = MedicationLog(
                id: l.id, medicationId: l.medicationId, medicationName: l.medicationName,
                scheduledTime: l.scheduledTime, takenTime: l.takenTime, taken: l.taken,
                dose: l.dose, doseUnit: unit, childProfileId: l.childProfileId,
                isAdHoc: l.isAdHoc, adhocReason: l.adhocReason
            )
            if let ts = l.lastModifiedAt { new.lastModifiedAt = ts }
            context.insert(new)
        }
        return true
    }

    @discardableResult
    private static func upsertSeizure(_ s: CombinedBackup.SeizureBackup, in context: ModelContext, index: ExistingIndex) -> Bool {
        let existing = index.seizures[s.id]
        let type = SeizureType(rawValue: s.seizureTypeRaw) ?? .other
        let trigger = SeizureTrigger(rawValue: s.triggerRaw) ?? .none
        if let existing {
            guard shouldApply(backupTs: s.lastModifiedAt, over: existing.lastModifiedAt) else { return false }
            existing.startTime = s.startTime
            existing.endTime = s.endTime
            existing.durationSeconds = max(0, Int(s.endTime.timeIntervalSince(s.startTime)))
            existing.seizureType = type
            existing.trigger = trigger
            existing.triggerNotes = s.triggerNotes
            existing.notes = s.notes
            existing.childProfileId = s.childProfileId
            existing.lastModifiedAt = s.lastModifiedAt ?? existing.lastModifiedAt
        } else {
            let new = SeizureEvent(
                id: s.id, startTime: s.startTime, endTime: s.endTime,
                seizureType: type, trigger: trigger,
                triggerNotes: s.triggerNotes, notes: s.notes,
                childProfileId: s.childProfileId
            )
            if let ts = s.lastModifiedAt { new.lastModifiedAt = ts }
            context.insert(new)
        }
        return true
    }

    @discardableResult
    private static func upsertMood(_ m: CombinedBackup.MoodBackup, in context: ModelContext, index: ExistingIndex) -> Bool {
        let existing = index.moods[m.id]
        let level = MoodLevel(rawValue: m.levelRaw) ?? .neutral
        if let existing {
            guard shouldApply(backupTs: m.lastModifiedAt, over: existing.lastModifiedAt) else { return false }
            existing.timestamp = m.timestamp
            existing.level = level
            existing.notes = m.notes
            existing.childProfileId = m.childProfileId
            existing.lastModifiedAt = m.lastModifiedAt ?? existing.lastModifiedAt
        } else {
            let new = MoodEntry(
                id: m.id, timestamp: m.timestamp, level: level,
                notes: m.notes, childProfileId: m.childProfileId
            )
            if let ts = m.lastModifiedAt { new.lastModifiedAt = ts }
            context.insert(new)
        }
        return true
    }

    @discardableResult
    private static func upsertObservation(_ o: CombinedBackup.ObservationBackup, in context: ModelContext, index: ExistingIndex) -> Bool {
        let existing = index.observations[o.id]
        let target: DailyObservation
        if let existing {
            guard shouldApply(backupTs: o.lastModifiedAt, over: existing.lastModifiedAt) else { return false }
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
        if let ts = o.lastModifiedAt { target.lastModifiedAt = ts }
        return true
    }

    @discardableResult
    private static func upsertSymptom(_ s: CombinedBackup.SymptomBackup, in context: ModelContext, index: ExistingIndex) -> Bool {
        let existing = index.symptoms[s.id]
        let type = RettSymptom(rawValue: s.symptomTypeRaw) ?? .other
        if let existing {
            guard shouldApply(backupTs: s.lastModifiedAt, over: existing.lastModifiedAt) else { return false }
            existing.timestamp = s.timestamp
            existing.symptomType = type
            existing.intensityRaw = s.intensityRaw
            existing.durationMinutes = s.durationMinutes
            existing.notes = s.notes
            existing.childProfileId = s.childProfileId
            existing.lastModifiedAt = s.lastModifiedAt ?? existing.lastModifiedAt
        } else {
            let new = SymptomEvent(
                id: s.id, timestamp: s.timestamp, symptomType: type,
                intensity: s.intensityRaw, durationMinutes: s.durationMinutes,
                notes: s.notes, childProfileId: s.childProfileId
            )
            if let ts = s.lastModifiedAt { new.lastModifiedAt = ts }
            context.insert(new)
        }
        return true
    }

    @discardableResult
    private static func upsertRevision(_ r: CombinedBackup.RevisionBackup, in context: ModelContext, index: ExistingIndex) -> Bool {
        let existing = index.revisions[r.id]
        let unit = DoseUnit(rawValue: r.doseUnitRaw) ?? .mg
        let kind = MedicationKind(rawValue: r.kindRaw) ?? .regular
        if let existing {
            guard shouldApply(backupTs: r.lastModifiedAt, over: existing.lastModifiedAt) else { return false }
            existing.medicationId = r.medicationId
            existing.effectiveFrom = r.effectiveFrom
            existing.name = r.name
            existing.doseAmount = r.doseAmount
            existing.doseUnit = unit
            existing.kind = kind
            existing.isActive = r.isActive
            existing.notifyEnabled = r.notifyEnabled
            existing.intakes = r.intakes
            existing.lastModifiedAt = r.lastModifiedAt ?? existing.lastModifiedAt
        } else {
            let new = MedicationRevision(
                id: r.id, medicationId: r.medicationId, effectiveFrom: r.effectiveFrom,
                name: r.name, doseAmount: r.doseAmount, doseUnit: unit,
                intakes: r.intakes, kind: kind,
                isActive: r.isActive, notifyEnabled: r.notifyEnabled
            )
            if let ts = r.lastModifiedAt { new.lastModifiedAt = ts }
            context.insert(new)
        }
        return true
    }
}
