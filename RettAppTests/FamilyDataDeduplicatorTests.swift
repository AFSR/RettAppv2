import XCTest
import SwiftData
@testable import RettApp

/// Tests du fusionneur de doublons multi-appareil. Scénario reproduit :
/// un parent installe l'app sur un 2ᵉ appareil, re-saisit le profil et le
/// plan avant le premier pull → deux profils et deux jeux de médicaments
/// avec des UUIDs différents coexistent après synchro.
final class FamilyDataDeduplicatorTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            ChildProfile.self,
            SeizureEvent.self,
            Medication.self,
            MedicationLog.self,
            MoodEntry.self,
            DailyObservation.self,
            SymptomEvent.self,
            MedicationRevision.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    // MARK: - Profils

    func test_mergeProfiles_keepsOldest_andRepointsChildren() throws {
        let context = try makeContext()
        let original = ChildProfile(
            firstName: "Louise", hasEpilepsy: true,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let duplicate = ChildProfile(
            firstName: "Louise", hasEpilepsy: false,
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        context.insert(original)
        context.insert(duplicate)

        // Une crise rattachée au doublon — elle doit suivre le survivant.
        let seizure = SeizureEvent(
            startTime: Date(), endTime: Date(),
            seizureType: .tonicClonic,
            childProfileId: duplicate.id
        )
        context.insert(seizure)
        try context.save()

        let removed = FamilyDataDeduplicator.mergeDuplicateProfiles(in: context)
        try context.save()

        XCTAssertEqual(removed, 1)
        let profiles = try context.fetch(FetchDescriptor<ChildProfile>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.id, original.id, "le plus ancien doit survivre")
        XCTAssertEqual(seizure.childProfileId, original.id, "la crise doit être re-rattachée")
    }

    func test_mergeProfiles_epilepsyFlagIsNeverLost() throws {
        let context = try makeContext()
        // L'original n'a PAS le flag épilepsie, le doublon l'a → OR = true.
        let original = ChildProfile(firstName: "L", hasEpilepsy: false,
                                    createdAt: Date(timeIntervalSince1970: 1_000))
        let duplicate = ChildProfile(firstName: "L", hasEpilepsy: true,
                                     createdAt: Date(timeIntervalSince1970: 2_000))
        context.insert(original)
        context.insert(duplicate)
        try context.save()

        _ = FamilyDataDeduplicator.mergeDuplicateProfiles(in: context)

        XCTAssertTrue(original.hasEpilepsy, "la fusion ne doit jamais masquer le suivi épilepsie")
    }

    // MARK: - Médicaments

    func test_mergeMedications_keepsMostRecent_andRepointsLogs() throws {
        let context = try makeContext()
        // Même nom (à la casse/espace près), même unité, même type, MÊME
        // planning de prises → vrai doublon de re-saisie → fusion.
        let old = Medication(name: "Keppra", doseAmount: 500, doseUnit: .mg,
                             scheduledHours: [HourMinute(hour: 8, minute: 0)])
        old.lastModifiedAt = Date(timeIntervalSince1970: 1_000)
        let recent = Medication(name: "keppra ", doseAmount: 750, doseUnit: .mg,
                                scheduledHours: [HourMinute(hour: 8, minute: 0)])
        recent.lastModifiedAt = Date(timeIntervalSince1970: 2_000)
        context.insert(old)
        context.insert(recent)

        let log = MedicationLog(
            medicationId: old.id, medicationName: "Keppra",
            scheduledTime: Date(), taken: true,
            dose: 500, doseUnit: .mg
        )
        context.insert(log)
        try context.save()

        let removed = FamilyDataDeduplicator.mergeDuplicateMedications(in: context)
        try context.save()

        XCTAssertEqual(removed, 1)
        let meds = try context.fetch(FetchDescriptor<Medication>())
        XCTAssertEqual(meds.count, 1)
        XCTAssertEqual(meds.first?.id, recent.id, "le plus récemment modifié doit survivre")
        XCTAssertEqual(log.medicationId, recent.id, "les prises du doublon doivent être re-pointées")
    }

    func test_mergeMedications_doesNotMergeDifferentSchedules() throws {
        let context = try makeContext()
        // Même nom mais plannings différents : deux entrées LÉGITIMES
        // (ex. « Dépakine » du matin et « Dépakine » du soir saisies comme
        // deux médicaments). Elles ne doivent JAMAIS être fusionnées — la
        // fusion détruirait l'un des deux plans.
        let morning = Medication(name: "Dépakine", doseAmount: 500, doseUnit: .mg,
                                 scheduledHours: [HourMinute(hour: 8, minute: 0)])
        let evening = Medication(name: "Dépakine", doseAmount: 200, doseUnit: .mg,
                                 scheduledHours: [HourMinute(hour: 20, minute: 0)])
        context.insert(morning)
        context.insert(evening)
        try context.save()

        let removed = FamilyDataDeduplicator.mergeDuplicateMedications(in: context)

        XCTAssertEqual(removed, 0, "plannings différents = médicaments distincts, pas de fusion")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Medication>()).count, 2)
    }

    func test_mergeMedications_doesNotMergeDifferentUnitsOrKinds() throws {
        let context = try makeContext()
        // Même nom mais unités différentes → PAS de fusion (dose exprimée
        // différemment, on ne prend pas le risque).
        let mg = Medication(name: "Micropakine", doseAmount: 500, doseUnit: .mg,
                            scheduledHours: [])
        let ml = Medication(name: "Micropakine", doseAmount: 5, doseUnit: .ml,
                            scheduledHours: [])
        // Même nom mais types différents (plan vs à-la-demande) → PAS de fusion.
        let regular = Medication(name: "Rivotril", doseAmount: 1, doseUnit: .mg,
                                 scheduledHours: [], kind: .regular)
        let adhoc = Medication(name: "Rivotril", doseAmount: 1, doseUnit: .mg,
                               scheduledHours: [], kind: .adhoc)
        for m in [mg, ml, regular, adhoc] { context.insert(m) }
        try context.save()

        let removed = FamilyDataDeduplicator.mergeDuplicateMedications(in: context)

        XCTAssertEqual(removed, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Medication>()).count, 4)
    }

    func test_run_isIdempotent() throws {
        let context = try makeContext()
        let a = ChildProfile(firstName: "L", createdAt: Date(timeIntervalSince1970: 1_000))
        let b = ChildProfile(firstName: "L", createdAt: Date(timeIntervalSince1970: 2_000))
        context.insert(a)
        context.insert(b)
        try context.save()

        XCTAssertEqual(FamilyDataDeduplicator.run(in: context), 1)
        XCTAssertEqual(FamilyDataDeduplicator.run(in: context), 0, "2e passe = no-op")
    }

    // MARK: - Normalisation

    func test_normalizedName() {
        XCTAssertEqual(FamilyDataDeduplicator.normalizedName("  Keppra  "), "keppra")
        XCTAssertEqual(FamilyDataDeduplicator.normalizedName("Dépakine   Chrono"), "dépakine chrono")
        XCTAssertEqual(FamilyDataDeduplicator.normalizedName("KEPPRA"), "keppra")
    }
}
