import XCTest
@testable import RettApp

/// Le suivi des selles et des urines, et les trois endroits où il peut se
/// défaire en silence.
///
/// 1. « Aucune selle » et « non renseigné » doivent rester distincts. Les
///    confondre ferait apparaître une constipation qui n'a jamais été
///    constatée — ou, pire, la ferait disparaître.
/// 2. Les cases du cahier imprimé et les valeurs enregistrées sont reliées par
///    un simple indice. Rien dans le compilateur ne garde cet alignement.
/// 3. Le schéma du cahier voyage dans un QR code imprimé : une lettre de
///    section doit survivre à l'aller-retour, et les cahiers déjà imprimés
///    doivent rester lisibles.
final class EliminationTrackingTests: XCTestCase {

    // MARK: - Zéro n'est pas rien

    func test_aucuneSelleEtNonRenseigneNeSeConfondentPas() {
        let jour = DailyObservation(dayStart: Date())

        // Rien n'a été noté.
        XCTAssertNil(jour.stoolCount)
        XCTAssertNil(jour.stoolCountLabel)
        XCTAssertFalse(jour.hasElimination)

        // Zéro selle est une observation, et c'est celle qui compte.
        jour.stoolCount = 0
        XCTAssertEqual(jour.stoolCount, 0)
        XCTAssertEqual(jour.stoolCountLabel, "Aucune")
        XCTAssertTrue(jour.hasElimination)
        XCTAssertTrue(jour.isPopulated, "Un jour sans selle est un jour renseigné.")
    }

    func test_leNombreEstPlafonneEtLeDitDansSonLibelle() {
        let jour = DailyObservation(dayStart: Date())

        jour.stoolCount = 2
        XCTAssertEqual(jour.stoolCountLabel, "2")

        // Au-delà du plafond, on ne compte plus : la grille du cahier n'a pas
        // la place, et le médecin n'en tire rien de plus.
        jour.stoolCount = 9
        XCTAssertEqual(jour.stoolCount, DailyObservation.stoolCountCap)
        XCTAssertEqual(jour.stoolCountLabel, "3 et plus")

        // Un nombre négatif n'existe pas ; il ne doit surtout pas être relu
        // comme le marqueur « non renseigné ».
        jour.stoolCount = -4
        XCTAssertEqual(jour.stoolCount, 0)
    }

    func test_remettreANilEffaceSansLaisserUnZero() {
        let jour = DailyObservation(dayStart: Date())
        jour.stoolCount = 3
        jour.stoolCount = nil
        XCTAssertNil(jour.stoolCount)
        XCTAssertFalse(jour.hasElimination)
    }

    // MARK: - Les cases du cahier et les valeurs enregistrées

    /// L'insertion lit l'indice de la case cochée et en déduit la valeur.
    /// Ces correspondances sont tenues par la position, pas par le type :
    /// inverser deux libellés dans le générateur ferait enregistrer « liquides »
    /// là où le cahier dit « dures », sans la moindre erreur.
    func test_lOrdreDesCasesImprimeesSuitLOrdreDesValeurs() {
        XCTAssertEqual(StoolAspect(rawValue: 0 + 1), .hard)
        XCTAssertEqual(StoolAspect(rawValue: 1 + 1), .normal)
        XCTAssertEqual(StoolAspect(rawValue: 2 + 1), .soft)
        XCTAssertEqual(StoolAspect(rawValue: 3 + 1), .liquid)
        XCTAssertEqual(StoolAspect.allCases.count, 4, "La grille imprimée a quatre cases.")

        // Les urines vont du plus faible au plus abondant : c'est le côté
        // « aucune » qui alerte, et il se lit en premier sur le papier.
        XCTAssertEqual(UrineOutput(rawValue: 0 + 1), .none)
        XCTAssertEqual(UrineOutput(rawValue: 1 + 1), .low)
        XCTAssertEqual(UrineOutput(rawValue: 2 + 1), .normal)
        XCTAssertEqual(UrineOutput(rawValue: 3 + 1), .high)
        XCTAssertEqual(UrineOutput.allCases.count, 4)
    }

    func test_leNombreDeCasesDuCahierCouvreLePlafond() {
        // Quatre cases imprimées : 0, 1, 2, « 3 et plus ».
        XCTAssertEqual(DailyObservation.stoolCountCap + 1, 4)
    }

    // MARK: - Le schéma du cahier

    func test_laLettreDeSectionFaitLAllerRetour() {
        XCTAssertEqual(BookletSchema.Section.elimination.letter, "T")
        XCTAssertEqual(BookletSchema.Section(letter: "T"), .elimination)
    }

    func test_lesLettresDeSectionRestentUniques() {
        let sections: [BookletSchema.Section] = [
            .medication, .seizure, .mood, .meals, .hydration, .sleep, .elimination, .symptoms, .events
        ]
        let lettres = sections.map(\.letter)
        XCTAssertEqual(Set(lettres).count, lettres.count,
                       "Deux sections partageant une lettre feraient lire la mauvaise grille au scan.")
    }

    /// Un cahier imprimé avant cette version ne porte pas la lettre T. Il doit
    /// rester lisible : le schéma se décrit lui-même, et la section absente ne
    /// déplace donc rien.
    func test_unCahierImprimeAvantResteLisible() {
        let ancien = BookletSchema(
            v: 1, start: "2026-11-09", days: 5, incl: "MSDLHP",
            meds: [], mealSlots: "BLD", symptoms: []
        )
        XCTAssertFalse(ancien.includedSections.contains(.elimination))
        XCTAssertTrue(ancien.includedSections.contains(.sleep))
    }

    func test_leSchemaSurvitAuPassageParLeQR() throws {
        let schema = BookletSchema(
            v: 1, start: "2026-11-16", days: 7, incl: "MSDLHPTY",
            meds: ["Keppra 250 mg @ 08:00"], mealSlots: "BLSD", symptoms: ["bruxism"]
        )
        let encode = try XCTUnwrap(schema.encodedJSON())
        let relu = try XCTUnwrap(BookletSchema.decode(encode))
        XCTAssertEqual(relu, schema)
        XCTAssertTrue(relu.includedSections.contains(.elimination))
    }
}
