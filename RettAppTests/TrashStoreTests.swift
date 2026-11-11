import XCTest
@testable import RettApp

/// La corbeille a deux promesses, et la seconde est la plus importante :
/// rendre une suppression réversible trente jours, et empêcher qu'une
/// restauration d'instantané ressuscite ce qui a été supprimé depuis.
///
/// Ces tests portent sur la logique de rétention et sur la garde
/// anti-résurrection. Ils écrivent dans le vrai fichier de corbeille de
/// l'environnement de test, donc chacun nettoie derrière lui.
final class TrashStoreTests: XCTestCase {

    private var deposees: [UUID] = []

    override func tearDown() {
        for id in deposees { TrashStore.forget(id: id) }
        deposees = []
        super.tearDown()
    }

    @discardableResult
    private func deposer(
        recordName: String = UUID().uuidString,
        deletedAt: Date = Date()
    ) -> String {
        TrashStore.record(
            recordName: recordName,
            recordType: CKRecordType.seizure,
            summary: "Crise de test",
            payload: TrashStore.emptyBackup(),
            deletedAt: deletedAt
        )
        if let item = TrashStore.items().first(where: { $0.recordName == recordName }) {
            deposees.append(item.id)
        }
        return recordName
    }

    // MARK: - Garde anti-résurrection

    /// Le cas qui motive tout : une sauvegarde prise AVANT la suppression ne
    /// doit pas réinsérer l'enregistrement.
    func test_suppressionPosterieureALaSauvegarde_bloqueLaReinsertion() {
        let sauvegarde = Date().addingTimeInterval(-3600)
        let id = deposer(deletedAt: Date())

        XCTAssertTrue(TrashStore.wasDeleted(recordName: id, after: sauvegarde))
        XCTAssertTrue(TrashStore.recordNamesDeleted(after: sauvegarde).contains(id))
    }

    /// Le contre-exemple, tout aussi important : une suppression ANTÉRIEURE à
    /// la sauvegarde ne dit rien. L'enregistrement a pu être recréé depuis, et
    /// le bloquer ferait perdre une donnée au lieu d'en protéger une.
    func test_suppressionAnterieureALaSauvegarde_neBloquePas() {
        let id = deposer(deletedAt: Date().addingTimeInterval(-7200))
        let sauvegarde = Date().addingTimeInterval(-3600)

        XCTAssertFalse(TrashStore.wasDeleted(recordName: id, after: sauvegarde))
        XCTAssertFalse(TrashStore.recordNamesDeleted(after: sauvegarde).contains(id))
    }

    func test_identifiantInconnu_neBloqueRien() {
        XCTAssertFalse(
            TrashStore.wasDeleted(recordName: UUID().uuidString, after: Date().addingTimeInterval(-86_400))
        )
    }

    // MARK: - Rétention

    func test_uneEntreeRecenteEstListee() {
        let id = deposer()
        XCTAssertTrue(TrashStore.items().contains { $0.recordName == id })
    }

    func test_uneEntreeExpireeNEstPlusListee() {
        let vieux = Date().addingTimeInterval(-(TrashStore.retention + 60))
        let id = deposer(deletedAt: vieux)

        XCTAssertFalse(
            TrashStore.items().contains { $0.recordName == id },
            "au-delà de trente jours, l'entrée ne doit plus apparaître"
        )
    }

    /// RÉGRESSION : une entrée expirée ne doit plus protéger contre une
    /// réinsertion, sinon une suppression vieille d'un an bloquerait à jamais
    /// la restauration d'une sauvegarde plus ancienne encore.
    func test_purgeRendLaReinsertionPossible() {
        let vieux = Date().addingTimeInterval(-(TrashStore.retention + 60))
        let id = deposer(deletedAt: vieux)
        let sauvegardeEncorePlusVieille = vieux.addingTimeInterval(-3600)

        XCTAssertTrue(TrashStore.wasDeleted(recordName: id, after: sauvegardeEncorePlusVieille))

        TrashStore.purgeExpired()

        XCTAssertFalse(
            TrashStore.wasDeleted(recordName: id, after: sauvegardeEncorePlusVieille),
            "une entrée purgée ne doit plus bloquer quoi que ce soit"
        )
    }

    // MARK: - Unicité

    /// Supprimer deux fois le même enregistrement — supprimé, restauré,
    /// resupprimé — ne doit pas donner deux lignes dans la corbeille.
    func test_deuxSuppressionsDuMemeEnregistrement_neDonnentQuUneEntree() {
        let id = UUID().uuidString
        deposer(recordName: id, deletedAt: Date().addingTimeInterval(-60))
        deposer(recordName: id, deletedAt: Date())

        XCTAssertEqual(TrashStore.items().filter { $0.recordName == id }.count, 1)
    }

    // MARK: - Oubli

    func test_forget_retireLEntreeEtLaProtection() {
        let id = deposer()
        let avant = Date().addingTimeInterval(-3600)
        XCTAssertTrue(TrashStore.wasDeleted(recordName: id, after: avant))

        let item = try? XCTUnwrap(TrashStore.items().first { $0.recordName == id })
        TrashStore.forget(id: item!.id)

        XCTAssertFalse(TrashStore.wasDeleted(recordName: id, after: avant))
    }
}
