import XCTest
@testable import RettApp

/// L'auteur de chaque entrée du journal.
///
/// Le fil mêle ce que notent les deux parents, et rien ne disait qui avait
/// écrit quoi : le parent invité ouvrait un journal rempli d'entrées
/// identiques aux siennes. L'auteur est un **prénom recopié à la saisie**, et
/// non une référence vers un compte — l'entrée doit rester lisible si le
/// partage s'arrête, et rien ici ne doit dépendre de CloudKit.
///
/// Deux choses se cassent silencieusement si on n'y prend garde : une entrée
/// ancienne, sans auteur, se mettrait à en porter un ; et ses propres entrées
/// se mettraient à afficher son propre prénom, ce qui n'apprend rien.
final class EntryAuthorTests: XCTestCase {

    private var prenomInitial: String!

    override func setUp() {
        super.setUp()
        prenomInitial = ParentIdentity.current
    }

    override func tearDown() {
        ParentIdentity.current = prenomInitial
        super.tearDown()
    }

    // MARK: - Le prénom lui-même

    func test_leChampVideNeDesigneAucunAuteur() {
        ParentIdentity.current = "   "
        XCTAssertNil(ParentIdentity.currentOrNil,
                     "Des espaces ne font pas un prénom.")

        ParentIdentity.current = "Marie"
        XCTAssertEqual(ParentIdentity.currentOrNil, "Marie")
    }

    func test_leBlancAutourDuPrenomEstRetireALaSaisie() {
        ParentIdentity.current = "  Marie  "
        XCTAssertEqual(ParentIdentity.current, "Marie")
    }

    // MARK: - Qui est « un autre »

    func test_mesPropresEntreesNeSontPasAttribuees() {
        ParentIdentity.current = "Marie"
        XCTAssertFalse(ParentIdentity.estUnAutre("Marie"))
        // Deux appareils d'une même famille peuvent avoir saisi la casse ou
        // les accents différemment. Afficher « Marie » sur ses propres entrées
        // serait déroutant.
        XCTAssertFalse(ParentIdentity.estUnAutre("marie"))
        XCTAssertFalse(ParentIdentity.estUnAutre("  MARIE "))
    }

    func test_uneEntreeSansAuteurNEnRecoitPas() {
        ParentIdentity.current = "Marie"
        XCTAssertFalse(ParentIdentity.estUnAutre(""),
                       "Les entrées d'avant novembre 2026 n'ont pas d'auteur : on n'en invente pas.")
        XCTAssertFalse(ParentIdentity.estUnAutre("   "))
    }

    func test_lAutreParentEstReconnu() {
        ParentIdentity.current = "Marie"
        XCTAssertTrue(ParentIdentity.estUnAutre("Julien"))
    }

    /// Le cas du parent qui n'a pas renseigné son prénom : tout ce qui porte
    /// un auteur vient forcément de quelqu'un d'autre.
    func test_sansPrenomALaSaisieToutAuteurEstUnAutre() {
        ParentIdentity.current = ""
        XCTAssertTrue(ParentIdentity.estUnAutre("Julien"))
        XCTAssertFalse(ParentIdentity.estUnAutre(""))
    }

    // MARK: - L'estampille à la création

    /// Le prénom est la valeur par défaut de l'initialiseur, et non quelque
    /// chose qu'on pense à poser sur chaque site de création — il y en a sept
    /// par type, importateurs compris, et en oublier un donnerait des entrées
    /// anonymes sans que rien ne le signale.
    func test_uneEntreeNeuveEstSigneeSansQuOnLeDemande() {
        ParentIdentity.current = "Marie"

        XCTAssertEqual(MoodEntry(level: .good).authorName, "Marie")
        XCTAssertEqual(SymptomEvent(symptomType: .handStereotypy).authorName, "Marie")
        XCTAssertEqual(SeizureEvent(startTime: Date(), endTime: Date()).authorName, "Marie")
        XCTAssertEqual(
            MedicationLog(
                medicationId: UUID(), medicationName: "Keppra",
                scheduledTime: Date(), dose: 250, doseUnit: .mg
            ).authorName,
            "Marie"
        )
    }

    /// Un enregistrement reconstruit depuis CloudKit ou depuis une sauvegarde
    /// doit garder SON auteur, et non recevoir celui de l'appareil qui le
    /// relit. L'initialiseur accepte donc une valeur explicite.
    func test_unAuteurExpliciteLEmporteSurCeluiDeLAppareil() {
        ParentIdentity.current = "Marie"
        let humeur = MoodEntry(level: .good, authorName: "Julien")
        XCTAssertEqual(humeur.authorName, "Julien")
    }
}
