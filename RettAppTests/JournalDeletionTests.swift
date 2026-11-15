import XCTest
@testable import RettApp

/// Supprimer depuis le journal, et la règle qui s'y applique.
///
/// Une suppression doit rester **opposable** : sans pierre tombale, l'appareil
/// de l'autre parent repousse l'enregistrement au cycle suivant et l'entrée
/// revient d'entre les morts chez celui qui l'avait retirée. Elle revient aussi
/// quand on restaure un instantané de sécurité antérieur à la suppression.
///
/// Les prises de médicaments étaient supprimées par un `context.delete` nu
/// jusqu'en novembre 2026 : la seule suppression offerte par le journal était
/// précisément celle qui ne laissait aucune trace.
@MainActor
final class JournalDeletionTests: XCTestCase {

    /// Les entrées déposées pendant un test, retirées à la fin — le magasin
    /// est un fichier partagé par toute la suite.
    private var deposees: [UUID] = []

    override func tearDown() {
        for id in deposees { TrashStore.forget(id: id) }
        deposees = []
        super.tearDown()
    }

    /// Retrouve l'entrée déposée pour un enregistrement, et la note pour le
    /// nettoyage.
    private func entree(pour recordName: String) -> TrashStore.Item? {
        let trouvee = TrashStore.items().first { $0.recordName == recordName }
        if let trouvee { deposees.append(trouvee.id) }
        return trouvee
    }

    private func prise(nom: String = "Keppra") -> MedicationLog {
        MedicationLog(
            medicationId: UUID(),
            medicationName: nom,
            scheduledTime: Date(),
            dose: 250,
            doseUnit: .mg
        )
    }

    // MARK: - Chaque type du fil laisse une trace

    func test_unePriseSupprimeeLaisseUnePierreTombale() throws {
        let log = prise()

        TrashStore.record(log: log)

        let entree = try XCTUnwrap(entree(pour: log.id.uuidString))
        XCTAssertEqual(entree.recordType, CKRecordType.medicationLog)
        XCTAssertTrue(
            entree.summary.contains("Keppra"),
            "La corbeille doit dire ce qu'elle garde, sinon on ne sait pas quoi restaurer."
        )
    }

    func test_uneHumeurSupprimeeLaisseUnePierreTombale() throws {
        let humeur = MoodEntry(level: .good)

        TrashStore.record(mood: humeur)

        let entree = try XCTUnwrap(entree(pour: humeur.id.uuidString))
        XCTAssertEqual(entree.recordType, CKRecordType.mood)
    }

    func test_unSymptomeSupprimeLaisseUnePierreTombale() throws {
        let symptome = SymptomEvent(symptomType: .handStereotypy)

        TrashStore.record(symptom: symptome)

        let entree = try XCTUnwrap(entree(pour: symptome.id.uuidString))
        XCTAssertEqual(entree.recordType, CKRecordType.symptom)
    }

    // MARK: - Ce que la pierre tombale protège

    /// Le point de toute l'affaire : la suppression l'emporte sur une copie
    /// plus ancienne qui reviendrait de l'autre appareil, ou d'une sauvegarde.
    func test_uneCopiePlusAncienneNePeutPasDefaireLaSuppression() throws {
        let log = prise()
        let avant = Date().addingTimeInterval(-3600)

        TrashStore.record(log: log)
        _ = entree(pour: log.id.uuidString)   // pour le nettoyage

        XCTAssertTrue(
            TrashStore.wasDeleted(recordName: log.id.uuidString, after: avant),
            "Une version d'avant la suppression ne doit pas la défaire."
        )
    }

    /// Mais une saisie postérieure est une intention plus récente que la
    /// suppression : elle doit passer, sinon on perdrait une vraie saisie.
    func test_uneSaisiePosterieureNEstPasBloquee() throws {
        let humeur = MoodEntry(level: .neutral)

        TrashStore.record(mood: humeur)
        _ = entree(pour: humeur.id.uuidString)

        XCTAssertFalse(
            TrashStore.wasDeleted(
                recordName: humeur.id.uuidString,
                after: Date().addingTimeInterval(3600)
            )
        )
    }

    /// La suppression doit atteindre l'autre parent : sans écriture en
    /// attente, elle resterait locale et l'entrée resurgirait chez lui.
    func test_laSuppressionEstMiseEnFilePourLAutreParent() throws {
        let avant = PendingWriteStore.shared.pendingCount

        let symptome = SymptomEvent(symptomType: .handStereotypy)
        TrashStore.record(symptom: symptome)
        _ = entree(pour: symptome.id.uuidString)

        XCTAssertGreaterThan(PendingWriteStore.shared.pendingCount, avant)
    }
}
