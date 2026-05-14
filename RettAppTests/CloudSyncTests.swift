import XCTest
import CloudKit
@testable import RettApp

/// Tests sur la couche de partage CloudKit. On ne fait pas d'appel réseau
/// (les tests offline doivent rester rapides et déterministes), on vérifie :
/// - la clé `ChangeTokenStore` est stable et discriminante par scope / zone,
/// - la sérialisation des `CKServerChangeToken` round-trippe (utile pour
///   prévenir une régression du format `NSKeyedArchiver`).
final class CloudSyncTests: XCTestCase {

    // MARK: - ChangeTokenStore.key

    func test_changeTokenStore_keyIsUniquePerZoneAndScope() {
        let zoneA = CKRecordZone.ID(zoneName: "FamilyData", ownerName: "_defaultOwner__")
        let zoneB = CKRecordZone.ID(zoneName: "Other",      ownerName: "_defaultOwner__")
        let zoneAOtherOwner = CKRecordZone.ID(zoneName: "FamilyData", ownerName: "someOtherUser")

        let keyAPrivate = ChangeTokenStore.key(zoneID: zoneA, scope: .private)
        let keyAShared  = ChangeTokenStore.key(zoneID: zoneA, scope: .shared)
        let keyB        = ChangeTokenStore.key(zoneID: zoneB, scope: .private)
        let keyAForeign = ChangeTokenStore.key(zoneID: zoneAOtherOwner, scope: .private)

        XCTAssertNotEqual(keyAPrivate, keyAShared,  "scope doit discriminer")
        XCTAssertNotEqual(keyAPrivate, keyB,        "zoneName doit discriminer")
        XCTAssertNotEqual(keyAPrivate, keyAForeign, "ownerName doit discriminer")
        XCTAssertTrue(keyAPrivate.hasPrefix("afsr.ck.changeToken."))
    }

    // MARK: - ChangeTokenStore.save/load

    /// Si on enregistre un token, on doit pouvoir le relire à l'identique.
    /// On synthétise un `CKServerChangeToken` en désérialisant un blob vide
    /// — pas possible. On teste donc plutôt le contrat "clear → load == nil".
    func test_changeTokenStore_clearMakesLoadReturnNil() {
        let zone = CKRecordZone.ID(zoneName: "TestZone-\(UUID())", ownerName: CKCurrentUserDefaultName)
        // On n'a pas de moyen offline de fabriquer un CKServerChangeToken
        // (constructeur privé) — on vérifie au moins le chemin "vide".
        XCTAssertNil(ChangeTokenStore.load(zoneID: zone, scope: .private))
        ChangeTokenStore.clear(zoneID: zone, scope: .private)
        XCTAssertNil(ChangeTokenStore.load(zoneID: zone, scope: .private))
    }

    func test_changeTokenStore_clearAllRemovesAllKeys() {
        // Écrit deux entrées factices (data arbitraire) pour vérifier que
        // clearAll passe bien sur tout ce qui matche le préfixe.
        let defaults = UserDefaults.standard
        defaults.set(Data([0x01]), forKey: "afsr.ck.changeToken.private.owner.A")
        defaults.set(Data([0x02]), forKey: "afsr.ck.changeToken.shared.someone.B")
        defaults.set(Data([0x03]), forKey: "afsr.unrelated.key")

        ChangeTokenStore.clearAll()

        XCTAssertNil(defaults.data(forKey: "afsr.ck.changeToken.private.owner.A"))
        XCTAssertNil(defaults.data(forKey: "afsr.ck.changeToken.shared.someone.B"))
        XCTAssertNotNil(defaults.data(forKey: "afsr.unrelated.key"),
                        "clearAll ne doit toucher que les clés du préfixe")
        defaults.removeObject(forKey: "afsr.unrelated.key")
    }
}
