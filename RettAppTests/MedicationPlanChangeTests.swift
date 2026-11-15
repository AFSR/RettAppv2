import XCTest
@testable import RettApp

/// Quand l'application propose d'arrêter un plan et d'en créer un nouveau.
///
/// Trop de propositions et la famille cliquera sans lire ; trop peu et un
/// dosage sera écrasé sans trace. Ces tests gardent la frontière.
final class MedicationPlanChangeTests: XCTestCase {

    private func values(
        dose: Double = 250, unit: DoseUnit = .mg, kind: MedicationKind = .regular,
        active: Bool = true, intakes: [MedicationIntake]? = nil
    ) -> MedicationPlanChange.Values {
        .init(doseAmount: dose, unit: unit, kind: kind, isActive: active,
              intakes: intakes ?? [MedicationIntake(hour: 8, minute: 0, dose: dose)])
    }

    func test_changementDeDose_proposeUnNouveauPlan() {
        let old = values(dose: 250)
        let new = values(dose: 500, intakes: [MedicationIntake(hour: 8, minute: 0, dose: 500)])
        XCTAssertTrue(MedicationPlanChange.requiresNewPlan(from: old, to: new))
        XCTAssertEqual(MedicationPlanChange.changes(from: old, to: new).first, "Dose : 250 mg → 500 mg")
    }

    func test_changementD_horaire_proposeUnNouveauPlan() {
        let old = values()
        let new = values(intakes: [MedicationIntake(hour: 9, minute: 30, dose: 250)])
        XCTAssertTrue(MedicationPlanChange.requiresNewPlan(from: old, to: new))
    }

    func test_ordreDesPrises_nEstPasUnChangement() {
        let a = MedicationIntake(hour: 8, minute: 0, dose: 250)
        let b = MedicationIntake(hour: 20, minute: 0, dose: 250)
        XCTAssertFalse(MedicationPlanChange.requiresNewPlan(
            from: values(intakes: [a, b]), to: values(intakes: [b, a])))
    }

    func test_identiteEtRappelDesPrises_neCompteNiCommeUnChangement() {
        // L'éditeur recrée les prises avec de nouveaux `id`, et le rappel
        // ne change pas ce que reçoit l'enfant.
        var rappelCoupe = MedicationIntake(hour: 8, minute: 0, dose: 250)
        rappelCoupe.notifyEnabled = false
        XCTAssertFalse(MedicationPlanChange.requiresNewPlan(
            from: values(), to: values(intakes: [rappelCoupe])))
    }

    func test_aLaDemande_seModifieSurPlace() {
        XCTAssertFalse(MedicationPlanChange.requiresNewPlan(
            from: values(dose: 5, kind: .adhoc, intakes: []),
            to: values(dose: 10, kind: .adhoc, intakes: [])))
    }

    func test_arretDansLeMemeGeste_seModifieSurPlace() {
        XCTAssertFalse(MedicationPlanChange.requiresNewPlan(
            from: values(dose: 250), to: values(dose: 500, active: false)))
    }

    func test_planDejaArrete_seModifieSurPlace() {
        XCTAssertFalse(MedicationPlanChange.requiresNewPlan(
            from: values(dose: 250, active: false), to: values(dose: 500)))
    }
}
