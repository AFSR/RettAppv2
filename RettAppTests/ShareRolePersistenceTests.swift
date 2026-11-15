import XCTest
@testable import RettApp

/// Le rôle de partage survit-il au lancement suivant ?
///
/// Il ne survivait pas, et c'est ce qui rendait le partage invisible au parent
/// invité. À chaque ouverture, `role` repartait de `.none` : l'écran annonçait
/// « Aucun partage actif » jusqu'à ce qu'une requête réseau aboutisse, et comme
/// `performCycle` commence par `guard role != .none`, **rien ne se
/// synchronisait pendant ce temps**. Hors ligne, jamais.
///
/// Ces tests portent sur la valeur brute et sa relecture, et non sur le service
/// lui-même : l'instancier ouvrirait un conteneur CloudKit, ce qu'un test hors
/// ligne ne doit pas faire.
final class ShareRolePersistenceTests: XCTestCase {

    /// La clé réelle du réglage. Si elle change, ce test doit changer aussi —
    /// et c'est voulu : la renommer sans y penser ferait perdre leur rôle à
    /// toutes les familles déjà installées, d'un coup.
    private let cle = "afsr.sync.role"

    private var valeurInitiale: String?

    override func setUp() {
        super.setUp()
        valeurInitiale = UserDefaults.standard.string(forKey: cle)
    }

    override func tearDown() {
        if let valeurInitiale {
            UserDefaults.standard.set(valeurInitiale, forKey: cle)
        } else {
            UserDefaults.standard.removeObject(forKey: cle)
        }
        super.tearDown()
    }

    func test_chaqueRoleAUneValeurBruteStable() {
        // Les valeurs brutes partent dans les réglages de l'appareil. Les
        // changer ferait relire un rôle faux, ou aucun.
        XCTAssertEqual(CloudKitSyncService.ShareRole.none.rawValue, "none")
        XCTAssertEqual(CloudKitSyncService.ShareRole.owner.rawValue, "owner")
        XCTAssertEqual(CloudKitSyncService.ShareRole.participant.rawValue, "participant")
    }

    func test_leRoleSeRelitDepuisLesReglages() {
        UserDefaults.standard.set("participant", forKey: cle)

        let relu = CloudKitSyncService.ShareRole(
            rawValue: UserDefaults.standard.string(forKey: cle) ?? ""
        )

        XCTAssertEqual(relu, .participant,
                       "C'est cette relecture qui fait qu'un parent invité voit son partage à l'ouverture.")
    }

    /// Une valeur absente — première installation — ou abîmée ne doit pas
    /// faire croire à un partage qui n'existe pas. Le repli est `.none`, et
    /// `refreshShareStatus()` tranchera.
    func test_uneValeurAbsenteOuAbimeeRetombeSurAucunPartage() {
        UserDefaults.standard.removeObject(forKey: cle)
        XCTAssertNil(CloudKitSyncService.ShareRole(
            rawValue: UserDefaults.standard.string(forKey: cle) ?? ""
        ))

        UserDefaults.standard.set("propriétaire", forKey: cle)
        XCTAssertNil(CloudKitSyncService.ShareRole(
            rawValue: UserDefaults.standard.string(forKey: cle) ?? ""
        ), "Un rôle inconnu ne doit pas être deviné.")
    }
}
