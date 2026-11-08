import XCTest
@testable import RettApp

/// Démarrage rapide d'un plan médicamenteux.
///
/// Le plan est volontairement fin — dose par prise, jours actifs, rappel
/// individuel — mais cette finesse ne doit pas se payer pour le cas
/// ordinaire : même dose, tous les jours, deux ou trois fois.
final class MedicationRhythmTests: XCTestCase {

    // MARK: - Heures proposées

    func test_rythmesCourants_suiventLesRepas() {
        XCTAssertEqual(MedicationRhythm.hours(forCountPerDay: 1).map(\.hour), [8])
        XCTAssertEqual(MedicationRhythm.hours(forCountPerDay: 2).map(\.hour), [8, 20])
        XCTAssertEqual(MedicationRhythm.hours(forCountPerDay: 3).map(\.hour), [8, 12, 20])
        XCTAssertEqual(MedicationRhythm.hours(forCountPerDay: 4).map(\.hour), [8, 12, 16, 20])
    }

    func test_heuresToujoursCroissantes() {
        for count in 1...8 {
            let heures = MedicationRhythm.hours(forCountPerDay: count).map { $0.hour * 60 + $0.minute }
            XCTAssertEqual(heures, heures.sorted(), "rythme \(count) : les prises doivent être dans l'ordre")
            XCTAssertEqual(Set(heures).count, heures.count, "rythme \(count) : pas deux prises à la même heure")
        }
    }

    /// Au-delà de quatre, on répartit entre 8 h et 20 h. Le résultat doit
    /// rester dans la journée et tomber sur des minutes présentables.
    func test_rythmeInhabituel_resteDansLaJournee() {
        for count in 5...8 {
            let heures = MedicationRhythm.hours(forCountPerDay: count)
            XCTAssertEqual(heures.count, count)
            for h in heures {
                XCTAssertGreaterThanOrEqual(h.hour, 8)
                XCTAssertLessThanOrEqual(h.hour, 20)
                XCTAssertEqual(h.minute % 5, 0, "une heure proposée ne doit pas tomber sur 13 h 43")
                XCTAssertTrue((0..<60).contains(h.minute))
            }
        }
    }

    func test_rythmeNul_neProposeRien() {
        XCTAssertTrue(MedicationRhythm.hours(forCountPerDay: 0).isEmpty)
        XCTAssertTrue(MedicationRhythm.intakes(countPerDay: 0, dose: 5).isEmpty)
    }

    // MARK: - Prises générées

    func test_prisesGenerees_reprennentLaDoseEtTousLesJours() {
        let prises = MedicationRhythm.intakes(countPerDay: 3, dose: 7.5)

        XCTAssertEqual(prises.count, 3)
        for p in prises {
            XCTAssertEqual(p.dose, 7.5)
            XCTAssertEqual(p.weekdays, MedicationIntake.allWeekdays, "par défaut, tous les jours")
            XCTAssertTrue(p.notifyEnabled)
        }
    }

    func test_prisesGenerees_ontDesIdentifiantsDistincts() {
        let prises = MedicationRhythm.intakes(countPerDay: 4, dose: 1)
        XCTAssertEqual(Set(prises.map(\.id)).count, 4,
                       "deux prises partageant un identifiant se confondraient dans l'éditeur")
    }

    func test_libelleAuSingulierPourUneSeulePrise() {
        XCTAssertEqual(MedicationRhythm.label(forCountPerDay: 1), "1 fois par jour")
        XCTAssertEqual(MedicationRhythm.label(forCountPerDay: 3), "3 fois par jour")
    }
}
