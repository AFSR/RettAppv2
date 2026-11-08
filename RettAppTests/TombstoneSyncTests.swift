import XCTest
import CloudKit
@testable import RettApp

/// Circulation des suppressions entre parents.
///
/// La règle tenue ici est celle du reste de la synchronisation, étendue à la
/// suppression : **le plus récent gagne**. Une suppression postérieure à la
/// dernière modification refuse l'enregistrement entrant ; une modification
/// postérieure à la suppression la périme.
///
/// Sans cela, un appareil resté hors ligne, une écriture en attente datant
/// d'avant ou une vieille restauration faisaient renaître ce qu'un parent
/// avait délibérément retiré.
final class TombstoneSyncTests: XCTestCase {

    private var deposees: [UUID] = []
    private let zoneID = CKRecordZone.ID(zoneName: "FamilyData", ownerName: CKCurrentUserDefaultName)

    override func tearDown() {
        for id in deposees { TrashStore.forget(id: id) }
        deposees = []
        super.tearDown()
    }

    @discardableResult
    private func supprimer(_ target: String, le date: Date, restorable: Bool = true) -> String {
        TrashStore.record(
            recordName: target,
            recordType: CKRecordType.seizure,
            summary: "Crise de test",
            payload: TrashStore.emptyBackup(),
            deletedAt: date,
            restorable: restorable
        )
        if let item = TrashStore.items().first(where: { $0.recordName == target }) {
            deposees.append(item.id)
        }
        return target
    }

    // MARK: - Nommage

    func test_nomDeterministe() {
        let cible = UUID().uuidString
        let a = TrashStore.cloudRecordName(forTarget: cible)
        let b = TrashStore.cloudRecordName(forTarget: cible)

        XCTAssertEqual(a, b, "deux appareils supprimant la même chose doivent écrire la même pierre tombale")
        XCTAssertNotEqual(a, cible, "la pierre tombale ne doit pas réutiliser le nom du défunt")
        XCTAssertEqual(TrashStore.target(fromCloudRecordName: a), cible)
    }

    func test_unNomOrdinaireNEstPasUnePierreTombale() {
        XCTAssertNil(TrashStore.target(fromCloudRecordName: UUID().uuidString))
    }

    // MARK: - La règle du plus récent

    /// Le revenant : supprimé après sa dernière modification, donc refusé.
    func test_entrantPlusAncienQueLaSuppression_estRefuse() {
        let cible = UUID().uuidString
        let modifie = Date().addingTimeInterval(-3600)
        supprimer(cible, le: Date())

        XCTAssertTrue(TrashStore.shouldRejectIncoming(recordName: cible, lastModifiedAt: modifie))
    }

    /// La recréation délibérée : modifié après la suppression, donc accepté.
    /// Sans ce cas, restaurer depuis la corbeille d'un parent ne pourrait
    /// jamais atteindre l'autre.
    func test_entrantPlusRecentQueLaSuppression_estAccepte() {
        let cible = UUID().uuidString
        supprimer(cible, le: Date().addingTimeInterval(-3600))

        XCTAssertFalse(TrashStore.shouldRejectIncoming(recordName: cible, lastModifiedAt: Date()))
    }

    func test_sansPierreTombale_rienNEstRefuse() {
        XCTAssertFalse(
            TrashStore.shouldRejectIncoming(recordName: UUID().uuidString, lastModifiedAt: Date())
        )
    }

    /// Un entrant sans horodatage ne peut pas prouver qu'il est postérieur :
    /// la suppression, elle, est datée, donc elle l'emporte.
    func test_entrantSansHorodatage_estRefuse() {
        let cible = UUID().uuidString
        supprimer(cible, le: Date())

        XCTAssertTrue(TrashStore.shouldRejectIncoming(recordName: cible, lastModifiedAt: nil))
    }

    // MARK: - Aller-retour CloudKit

    func test_construitPuisRelitLaMemePierreTombale() throws {
        let cible = UUID().uuidString
        let quand = Date(timeIntervalSince1970: 1_700_000_000)
        supprimer(cible, le: quand)

        let record = try XCTUnwrap(TrashStore.makeCloudRecord(forTarget: cible, zoneID: zoneID))
        XCTAssertEqual(record.recordType, CKRecordType.tombstone)
        XCTAssertEqual(record["targetRecordName"] as? String, cible)
        XCTAssertEqual(record[SyncFields.lastModifiedAt] as? Date, quand,
                       "la pierre tombale doit se comparer aux autres avec le même champ")

        // Reçue sur un appareil qui ne la connaît pas : elle doit y protéger
        // contre la réinsertion.
        TrashStore.forget(id: try XCTUnwrap(TrashStore.items().first { $0.recordName == cible }).id)
        XCTAssertFalse(TrashStore.shouldRejectIncoming(recordName: cible, lastModifiedAt: quand.addingTimeInterval(-60)))

        TrashStore.applyCloudRecord(record)
        if let item = TrashStore.items().first(where: { $0.recordName == cible }) { deposees.append(item.id) }

        XCTAssertTrue(TrashStore.shouldRejectIncoming(recordName: cible, lastModifiedAt: quand.addingTimeInterval(-60)))
    }

    /// RÉGRESSION : une pierre tombale reçue ne doit pas être repoussée, sinon
    /// les deux appareils se la renverraient indéfiniment.
    func test_pierreTombaleRecue_nEstPasRestaurableNiRenvoyee() throws {
        let cible = UUID().uuidString
        supprimer(cible, le: Date(), restorable: false)

        let item = try XCTUnwrap(TrashStore.items().first { $0.recordName == cible })
        XCTAssertFalse(item.restorable, "elle ne transporte pas le contenu : rien à remettre en place")
    }

    func test_pierreTombalePlusAncienneNEcrasePasLaPlusRecente() throws {
        let cible = UUID().uuidString
        let recent = Date()
        supprimer(cible, le: recent)

        let ancienne = CKRecord(
            recordType: CKRecordType.tombstone,
            recordID: CKRecord.ID(recordName: TrashStore.cloudRecordName(forTarget: cible), zoneID: zoneID)
        )
        ancienne["targetRecordName"] = cible as CKRecordValue
        ancienne["targetRecordType"] = CKRecordType.seizure as CKRecordValue
        ancienne["deletedAt"] = recent.addingTimeInterval(-7200) as CKRecordValue

        TrashStore.applyCloudRecord(ancienne)

        let item = try XCTUnwrap(TrashStore.items().first { $0.recordName == cible })
        XCTAssertEqual(item.deletedAt.timeIntervalSince1970, recent.timeIntervalSince1970, accuracy: 1)
    }
}
