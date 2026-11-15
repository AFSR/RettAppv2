import XCTest
@testable import RettApp

/// Le diagnostic de synchronisation ne doit porter **aucun lien d'accès**.
///
/// L'URL d'un `CKShare` n'est pas une référence, c'est la clé : le partage est
/// en `publicPermission = .readWrite`, donc quiconque l'ouvre rejoint le
/// partage et lit tout le suivi médical de l'enfant. La sécurité du partage
/// entre parents repose entièrement sur le fait que ce lien ne circule que par
/// AirDrop, les deux téléphones côte à côte — c'est ce qu'affirme la politique
/// de confidentialité publiée sur afsr.fr.
///
/// Or l'écran de diagnostic affichait les deux URL en clair et sélectionnables,
/// et son bouton « Copier » les mettait dans le presse-papiers « pour le coller
/// dans un email de support ». L'app demandait donc aux familles d'envoyer à
/// l'association une clé de leur dossier, par le canal exact que la règle
/// AirDrop existe pour fermer.
///
/// Ces tests gardent la correction. Ils échouent si quelqu'un remet une URL
/// dans l'instantané, y compris sans le vouloir.
@MainActor
final class SharingDiagnosticPrivacyTests: XCTestCase {

    /// Un instantané représentatif : tout est renseigné, pour qu'aucun champ
    /// ne passe au travers faute d'avoir une valeur.
    private func instantane(erreur: String? = nil) -> CloudKitSyncService.DiagnosticSnapshot {
        CloudKitSyncService.DiagnosticSnapshot(
            role: "propriétaire",
            accountStatus: "disponible",
            privateZoneExists: true,
            privateZoneShareExists: true,
            privateZoneShareHasURL: true,
            sharedZonesCount: 1,
            sharedZones: ["FamilyData / propriétaire A"],
            sharedZoneShareExists: true,
            currentShareHasURL: true,
            pendingWriteCount: 3,
            lastSyncedAt: "2026-11-15T09:30:00Z",
            lastErrorMessage: erreur,
            subscriptionsRegistered: true
        )
    }

    /// Le test qui compte : on parcourt l'instantané par réflexion, de sorte
    /// qu'un champ AJOUTÉ plus tard soit examiné lui aussi. Un test qui
    /// nommerait les champs un par un ne verrait pas le prochain.
    func test_aucunChampDuDiagnosticNePorteDeLien() {
        for champ in Mirror(reflecting: instantane()).children {
            let texte = String(describing: champ.value).lowercased()
            XCTAssertFalse(
                texte.contains("http"),
                "Le champ « \(champ.label ?? "?") » porte une adresse web. "
                + "Un lien de partage est une clé d'accès au dossier de l'enfant : "
                + "il ne sort de l'appareil que par AirDrop."
            )
            XCTAssertFalse(
                texte.contains("icloud.com"),
                "Le champ « \(champ.label ?? "?") » porte une adresse iCloud."
            )
        }
    }

    /// L'état du lien reste lisible — c'est ce que le diagnostic avait à dire.
    /// Un partage peut exister sans que le serveur ait émis son URL : c'est le
    /// bug de la copie locale récupérée à la place de l'enregistrement serveur,
    /// et on doit pouvoir le constater sans voir l'adresse.
    func test_lEtatDuLienResteLisibleSansLeLien() {
        let snap = instantane()
        XCTAssertTrue(snap.privateZoneShareExists)
        XCTAssertTrue(snap.privateZoneShareHasURL)
        XCTAssertTrue(snap.currentShareHasURL)
    }

    /// Le message d'erreur vient de CloudKit et part tel quel dans le rapport
    /// de support. C'est le seul texte libre du système qui quitte l'appareil.
    func test_uneErreurQuiCiteraitLeLienEstFiltree() throws {
        let resultat = try XCTUnwrap(SharingDiagnosticView.anonymise(
            "Échec sur https://www.icloud.com/share/0abc123 — réessayez"
        ))
        XCTAssertFalse(resultat.contains("https://"))
        XCTAssertFalse(resultat.contains("0abc123"))
        XCTAssertTrue(resultat.contains("[lien retiré]"))
        // Le reste du message survit : il sert au diagnostic.
        XCTAssertTrue(resultat.contains("Échec"))
        XCTAssertTrue(resultat.contains("réessayez"))
    }

    /// Un identifiant d'enregistrement ou de zone ne donne pas accès aux
    /// données, mais il désigne un enregistrement précis d'une famille
    /// précise. Le rapport est fait pour être envoyé : il n'a pas à le porter.
    func test_unIdentifiantEstRetireLuiAussi() throws {
        let resultat = try XCTUnwrap(SharingDiagnosticView.anonymise(
            "Zone 3F2B4A1C-9D8E-4C7B-A1F0-5E6D7C8B9A01 introuvable"
        ))
        XCTAssertFalse(resultat.contains("3F2B4A1C"))
        XCTAssertTrue(resultat.contains("[identifiant retiré]"))
        XCTAssertTrue(resultat.contains("introuvable"))
    }

    /// Les zones partagées sont désignées par un rang, pas par le compte
    /// iCloud de leur propriétaire : deux zones du même parent portent la même
    /// lettre, et personne n'est nommé.
    func test_lesZonesPartageesNeNommentPersonne() {
        for zone in instantane().sharedZones {
            XCTAssertTrue(zone.contains("propriétaire "), "La zone « \(zone) » devrait désigner un rang.")
            XCTAssertFalse(zone.contains("_"), "Un identifiant CloudKit commence par « _ ».")
        }
    }

    func test_uneErreurOrdinaireNEstPasAbimee() {
        let message = "Network unavailable, retry later"
        XCTAssertEqual(SharingDiagnosticView.anonymise(message), message)
        XCTAssertNil(SharingDiagnosticView.anonymise(nil))
    }
}
