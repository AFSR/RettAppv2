import XCTest
import CloudKit
import SwiftData
@testable import RettApp

/// Tests de round-trip pour les mappers `SwiftData ↔ CloudKit` :
/// 1. instancier un modèle local
/// 2. l'encoder via `toCKRecord(zoneID:)`
/// 3. le décoder via `upsert(from:in:)` dans un autre `ModelContext`
/// 4. vérifier que toutes les valeurs significatives ont survécu.
///
/// On utilise un `ModelContainer` 100 % in-memory pour ne rien écrire sur
/// disque et garantir des tests rapides et hermétiques. Aucun appel réseau,
/// `CKRecord` est un simple value type qu'on peut construire offline.
final class CKRecordRoundtripTests: XCTestCase {

    private let zoneID = CKRecordZone.ID(zoneName: "FamilyData", ownerName: CKCurrentUserDefaultName)

    // MARK: - Helpers

    /// Crée un `ModelContext` in-memory pour héberger les modèles du test.
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            ChildProfile.self,
            SeizureEvent.self,
            Medication.self,
            MedicationLog.self,
            MoodEntry.self,
            DailyObservation.self,
            SymptomEvent.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    // MARK: - ChildProfile

    func test_childProfile_roundtrip() throws {
        let context = try makeContext()
        let id = UUID()
        let birth = Date(timeIntervalSince1970: 1_500_000_000)
        let created = Date(timeIntervalSince1970: 1_600_000_000)
        let source = ChildProfile(
            id: id,
            firstName: "Alice",
            lastName: "Durand",
            birthDate: birth,
            hasEpilepsy: true,
            sex: .girl,
            createdAt: created
        )
        let record = source.toCKRecord(zoneID: zoneID)

        XCTAssertEqual(record.recordType, CKRecordType.childProfile)
        XCTAssertEqual(record.recordID.recordName, id.uuidString)

        ChildProfile.upsert(from: record, in: context)
        let fetched = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.id == id })).first
        )
        XCTAssertEqual(fetched.firstName, "Alice")
        XCTAssertEqual(fetched.lastName, "Durand")
        XCTAssertEqual(fetched.birthDate, birth)
        XCTAssertTrue(fetched.hasEpilepsy)
        XCTAssertEqual(fetched.sex, .girl)
    }

    // MARK: - Medication

    func test_medication_roundtrip() throws {
        let context = try makeContext()
        let id = UUID()
        let intakes = [
            MedicationIntake(hour: 8,  minute: 0, dose: 5, weekdays: MedicationIntake.weekdaysOnly, notifyEnabled: true),
            MedicationIntake(hour: 20, minute: 0, dose: 10, weekdays: MedicationIntake.weekendOnly, notifyEnabled: false)
        ]
        let source = Medication(
            id: id,
            name: "Keppra",
            doseAmount: 5,
            doseUnit: .mg,
            scheduledHours: intakes.map { HourMinute(hour: $0.hour, minute: $0.minute) },
            kind: .regular,
            isActive: true,
            notifyEnabled: true,
            intakes: intakes
        )
        let record = source.toCKRecord(zoneID: zoneID)
        Medication.upsert(from: record, in: context)

        let fetched = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.id == id })).first
        )
        XCTAssertEqual(fetched.name, "Keppra")
        XCTAssertEqual(fetched.doseAmount, 5)
        XCTAssertEqual(fetched.doseUnit, .mg)
        XCTAssertEqual(fetched.kind, .regular)
        XCTAssertTrue(fetched.isActive)
        XCTAssertTrue(fetched.notifyEnabled)
        XCTAssertEqual(fetched.intakes.count, 2)
        // Les intakes sont triés par heure dans le setter.
        XCTAssertEqual(fetched.intakes.first?.hour, 8)
        XCTAssertEqual(fetched.intakes.first?.weekdays, MedicationIntake.weekdaysOnly)
        XCTAssertEqual(fetched.intakes.last?.hour, 20)
        XCTAssertEqual(fetched.intakes.last?.notifyEnabled, false)
    }

    // MARK: - MedicationLog

    func test_medicationLog_roundtrip() throws {
        let context = try makeContext()
        let id = UUID()
        let medId = UUID()
        let scheduled = Date(timeIntervalSince1970: 1_700_000_000)
        let taken = scheduled.addingTimeInterval(60)
        let source = MedicationLog(
            id: id,
            medicationId: medId,
            medicationName: "Doliprane",
            scheduledTime: scheduled,
            takenTime: taken,
            taken: true,
            dose: 150,
            doseUnit: .mg,
            isAdHoc: true,
            adhocReason: "fièvre"
        )
        let record = source.toCKRecord(zoneID: zoneID)
        MedicationLog.upsert(from: record, in: context)

        let fetched = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MedicationLog>(predicate: #Predicate { $0.id == id })).first
        )
        XCTAssertEqual(fetched.medicationId, medId)
        XCTAssertEqual(fetched.medicationName, "Doliprane")
        XCTAssertEqual(fetched.scheduledTime, scheduled)
        XCTAssertEqual(fetched.takenTime, taken)
        XCTAssertTrue(fetched.taken)
        XCTAssertEqual(fetched.dose, 150)
        XCTAssertEqual(fetched.doseUnit, .mg)
        XCTAssertTrue(fetched.isAdHoc)
        XCTAssertEqual(fetched.adhocReason, "fièvre")
    }

    // MARK: - SeizureEvent

    func test_seizure_roundtrip() throws {
        let context = try makeContext()
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(125)
        let source = SeizureEvent(
            id: id, startTime: start, endTime: end,
            seizureType: .focal, trigger: .fever,
            triggerNotes: "rhino", notes: "très bref"
        )
        let record = source.toCKRecord(zoneID: zoneID)
        SeizureEvent.upsert(from: record, in: context)

        let fetched = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SeizureEvent>(predicate: #Predicate { $0.id == id })).first
        )
        XCTAssertEqual(fetched.startTime, start)
        XCTAssertEqual(fetched.endTime, end)
        XCTAssertEqual(fetched.durationSeconds, 125)
        XCTAssertEqual(fetched.seizureType, .focal)
        XCTAssertEqual(fetched.trigger, .fever)
        XCTAssertEqual(fetched.triggerNotes, "rhino")
        XCTAssertEqual(fetched.notes, "très bref")
    }

    // MARK: - MoodEntry

    func test_mood_roundtrip() throws {
        let context = try makeContext()
        let id = UUID()
        let ts = Date(timeIntervalSince1970: 1_700_100_000)
        let source = MoodEntry(id: id, timestamp: ts, level: .good, notes: "câline")
        let record = source.toCKRecord(zoneID: zoneID)
        MoodEntry.upsert(from: record, in: context)

        let fetched = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MoodEntry>(predicate: #Predicate { $0.id == id })).first
        )
        XCTAssertEqual(fetched.timestamp, ts)
        XCTAssertEqual(fetched.level, .good)
        XCTAssertEqual(fetched.notes, "câline")
    }

    // MARK: - DailyObservation

    func test_dailyObservation_roundtrip() throws {
        let context = try makeContext()
        let id = UUID()
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let source = DailyObservation(
            id: id,
            dayStart: day,
            breakfastRating: .good, breakfastNotes: "bon appétit",
            hydrationRating: .ok,
            nightSleepRating: .veryPoor, nightSleepDurationMinutes: 380,
            generalNotes: "journée chargée"
        )
        let record = source.toCKRecord(zoneID: zoneID)
        DailyObservation.upsert(from: record, in: context)

        let fetched = try XCTUnwrap(
            try context.fetch(FetchDescriptor<DailyObservation>(predicate: #Predicate { $0.id == id })).first
        )
        XCTAssertEqual(fetched.dayStart, day)
        XCTAssertEqual(fetched.breakfastRatingRaw, QualityRating.good.rawValue)
        XCTAssertEqual(fetched.breakfastNotes, "bon appétit")
        XCTAssertEqual(fetched.hydrationRatingRaw, QualityRating.ok.rawValue)
        XCTAssertEqual(fetched.nightSleepRatingRaw, QualityRating.veryPoor.rawValue)
        XCTAssertEqual(fetched.nightSleepDurationMinutes, 380)
        XCTAssertEqual(fetched.generalNotes, "journée chargée")
    }

    // MARK: - SymptomEvent (Phase 4)

    func test_symptom_roundtrip() throws {
        let context = try makeContext()
        let id = UUID()
        let ts = Date(timeIntervalSince1970: 1_700_500_000)
        let source = SymptomEvent(
            id: id, timestamp: ts,
            symptomType: .breathingApnea,
            intensity: 3, durationMinutes: 5,
            notes: "10 s d'apnée"
        )
        let record = source.toCKRecord(zoneID: zoneID)
        XCTAssertEqual(record.recordType, CKRecordType.symptom)

        SymptomEvent.upsert(from: record, in: context)
        let fetched = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SymptomEvent>(predicate: #Predicate { $0.id == id })).first
        )
        XCTAssertEqual(fetched.timestamp, ts)
        XCTAssertEqual(fetched.symptomType, .breathingApnea)
        XCTAssertEqual(fetched.intensityRaw, 3)
        XCTAssertEqual(fetched.durationMinutes, 5)
        XCTAssertEqual(fetched.notes, "10 s d'apnée")
    }

    // MARK: - Conflict resolution in practice

    /// Vérifie que `upsert` ignore un CKRecord plus ancien que la copie locale
    /// — pas seulement au niveau de `SyncConflictResolver` (testé ailleurs)
    /// mais sur le chemin complet `toCKRecord → upsert` côté Medication.
    func test_medication_staleRecordIsSkipped() throws {
        let context = try makeContext()
        let id = UUID()

        let local = Medication(
            id: id, name: "Frais",
            doseAmount: 5, doseUnit: .mg,
            scheduledHours: [HourMinute(hour: 8, minute: 0)],
            kind: .regular
        )
        local.lastModifiedAt = Date(timeIntervalSince1970: 2_000)
        context.insert(local)
        try context.save()

        // Construit un CKRecord avec timestamp antérieur.
        let stale = local.toCKRecord(zoneID: zoneID)
        stale["name"] = "Périmé" as CKRecordValue
        stale.writeLastModified(Date(timeIntervalSince1970: 1_000))

        Medication.upsert(from: stale, in: context)
        let fetched = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.id == id })).first
        )
        XCTAssertEqual(fetched.name, "Frais", "Le local plus récent doit être préservé")
    }

    func test_medication_freshRecordIsApplied() throws {
        let context = try makeContext()
        let id = UUID()

        let local = Medication(
            id: id, name: "Ancien",
            doseAmount: 5, doseUnit: .mg,
            scheduledHours: [HourMinute(hour: 8, minute: 0)],
            kind: .regular
        )
        local.lastModifiedAt = Date(timeIntervalSince1970: 1_000)
        context.insert(local)
        try context.save()

        let fresh = local.toCKRecord(zoneID: zoneID)
        fresh["name"] = "Mis à jour" as CKRecordValue
        fresh.writeLastModified(Date(timeIntervalSince1970: 2_000))

        Medication.upsert(from: fresh, in: context)
        let fetched = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.id == id })).first
        )
        XCTAssertEqual(fetched.name, "Mis à jour")
    }
}
