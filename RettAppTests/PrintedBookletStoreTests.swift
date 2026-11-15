import XCTest
@testable import RettApp

/// L'historique des cahiers imprimés.
///
/// Il existe pour une raison précise : jusqu'ici le `BookletSchema` d'une page
/// n'était écrit qu'à un seul endroit, le QR imprimé dessus. Un QR illisible,
/// et une semaine entière remplie à la main par l'école devenait
/// inexploitable. Ces tests gardent les trois propriétés dont dépend ce repli.
///
/// Comme `TrashStoreTests`, ils écrivent dans le vrai fichier de
/// l'environnement de test : chacun nettoie derrière lui.
final class PrintedBookletStoreTests: XCTestCase {

    private var deposes: [UUID] = []

    override func tearDown() {
        for id in deposes { PrintedBookletStore.forget(id: id) }
        deposes = []
        super.tearDown()
    }

    private func schema(
        start: String = "2026-11-09",
        days: Int = 5,
        meds: [String] = ["Keppra 250 mg @ 08:00"]
    ) -> BookletSchema {
        BookletSchema(
            v: 1, start: start, days: days, incl: "MSDLHPTYE",
            meds: meds, mealSlots: "BLSD", symptoms: ["handStereotypy"]
        )
    }

    @discardableResult
    private func deposer(_ s: BookletSchema, printedAt: Date = Date()) -> UUID {
        let id = PrintedBookletStore.record(s, printedAt: printedAt)
        deposes.append(id)
        return id
    }

    // MARK: - Ce qu'on imprime, on le retrouve

    func test_unCahierImprimeEstRetrouve() {
        let s = schema(start: "2026-11-09")
        deposer(s)

        let trouve = PrintedBookletStore.items().first { $0.schema == s }
        XCTAssertNotNil(trouve, "Sans cette entrée, le repli n'a rien à proposer.")
        XCTAssertEqual(trouve?.schema.start, "2026-11-09")
    }

    // MARK: - Pas de doublon pour la même feuille

    func test_reimprimerLaMemePageNeCreePasUneSecondeEntree() {
        let s = schema(start: "2026-11-16")
        deposer(s)
        deposer(s)

        let correspondances = PrintedBookletStore.items().filter { $0.schema == s }
        XCTAssertEqual(correspondances.count, 1,
                       "Deux entrées identiques obligeraient le parent à choisir entre deux feuilles indiscernables.")
    }

    /// Deux impressions de la **même semaine** avec des rubriques différentes
    /// sont deux feuilles différentes. Là, le choix a un sens, et les fondre
    /// ferait lire la page avec la mauvaise grille.
    func test_deuxVersionsDeLaMemeSemaineRestentDistinctes() {
        let cinqJours = schema(start: "2026-11-23", days: 5)
        let septJours = schema(start: "2026-11-23", days: 7)
        deposer(cinqJours)
        deposer(septJours)

        let correspondances = PrintedBookletStore.items()
            .filter { $0.schema.start == "2026-11-23" }
        XCTAssertEqual(correspondances.count, 2)
    }

    // MARK: - Rétention

    func test_unCahierTropAncienNEstPlusPropose() {
        let vieux = schema(start: "2025-01-06")
        let bienAvantLaLimite = Date()
            .addingTimeInterval(-PrintedBookletStore.retention - 86_400)
        deposer(vieux, printedAt: bienAvantLaLimite)

        XCTAssertNil(PrintedBookletStore.items().first { $0.schema == vieux },
                     "Passé six mois, la liste deviendrait trop longue pour qu'on y reconnaisse la bonne feuille.")
    }

    func test_lePlusRecentEstEnTete() {
        let ancien = schema(start: "2026-10-05")
        let recent = schema(start: "2026-11-02")
        deposer(ancien, printedAt: Date().addingTimeInterval(-7 * 86_400))
        deposer(recent, printedAt: Date())

        let items = PrintedBookletStore.items()
        let rangAncien = items.firstIndex { $0.schema == ancien }
        let rangRecent = items.firstIndex { $0.schema == recent }
        XCTAssertNotNil(rangAncien)
        XCTAssertNotNil(rangRecent)
        XCTAssertLessThan(rangRecent!, rangAncien!,
                          "Le cahier qu'on vient d'imprimer est celui qu'on scanne.")
    }

    // MARK: - Le libellé est celui de la page

    /// Le parent reconnaît sa feuille au titre imprimé dessus, pas à une date
    /// technique. Le format doit rester celui de `defaultPeriodLabel()`.
    func test_leLibelleReprendLeTitreImprime() {
        let item = PrintedBookletStore.Item(schema: schema(start: "2026-11-09", days: 5))
        XCTAssertEqual(item.libelle, "Semaine du 9 novembre au 13 novembre")
    }
}
