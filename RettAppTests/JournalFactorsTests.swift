import XCTest
@testable import RettApp

/// Ce que l'analyse des facteurs accepte de dire.
///
/// On y teste moins le calcul que les garde-fous : l'écran croise des
/// centaines de paires, et sans seuils il afficherait du hasard à une famille.
final class JournalFactorsTests: XCTestCase {

    private let sleepCycle: [Double] = [1, 4, 2, 5, 3, 2, 5, 1, 4, 3, 5, 2, 1, 4, 3]

    private func days(
        count: Int = 30,
        factor: (Int) -> Double? = { [1, 4, 2, 5, 3, 2, 5, 1, 4, 3, 5, 2, 1, 4, 3][$0 % 15] },
        seizures: (Int) -> Int
    ) -> [JournalFactors.Day] {
        (0..<count).map { i in
            var d = JournalFactors.Day(start: Date(timeIntervalSince1970: Double(i) * 86_400))
            if let v = factor(i) { d.factors[.sleepQuality] = v }
            d.seizureCount = seizures(i)
            return d
        }
    }

    func test_lienNet_estTrouve_etDitPlusDeCrisQuandLeSommeilEstBas() {
        let data = days { i in 6 - Int(self.sleepCycle[i % 15]) }
        let f = JournalFactors.findings(in: data)
        XCTAssertEqual(f.first?.factor, .sleepQuality)
        XCTAssertEqual(f.first?.outcome, .seizures)
        XCTAssertTrue(f.first?.sentence.contains("est plus bas, il y a plus de crises") == true,
                      f.first?.sentence ?? "aucun constat")
    }

    func test_pasAssezDeJours_rienNEstDit() {
        let data = days(count: 10) { i in 6 - Int(self.sleepCycle[i % 15]) }
        XCTAssertTrue(JournalFactors.findings(in: data).isEmpty)
    }

    func test_facteurConstant_rienNEstDit() {
        let data = days(factor: { _ in 3 }) { i in i % 3 }
        XCTAssertTrue(JournalFactors.findings(in: data).isEmpty)
    }

    func test_unSeulJourDeCrise_rienNEstDit() {
        // Un épisode isolé ne fait pas une tendance, même s'il tombe un
        // jour de mauvais sommeil.
        let data = days { $0 == 0 ? 5 : 0 }
        XCTAssertTrue(JournalFactors.findings(in: data).isEmpty)
    }

    func test_facteurNonRenseigne_neCompteNiCommeZeroNiCommeJour() {
        // Une journée sans saisie est écartée : 10 saisies sur 30 jours
        // ne suffisent pas, et les 20 autres ne comptent pas pour zéro.
        let data = days(factor: { $0 < 10 ? self.sleepCycle[$0 % 15] : nil }) { i in 6 - Int(self.sleepCycle[i % 15]) }
        XCTAssertTrue(JournalFactors.findings(in: data).isEmpty)
    }

    func test_effetDuLendemain_estRetrouveAvecLaVeille() {
        // Les crises du jour i suivent le sommeil du jour i-1.
        let data = days { i in i == 0 ? 0 : 6 - Int(self.sleepCycle[(i - 1) % 15]) }
        let f = JournalFactors.findings(in: data)
        XCTAssertEqual(f.first?.lag, .previousDay)
        XCTAssertTrue(f.first?.sentence.hasPrefix("Le lendemain") == true)
    }

    func test_pasPlusDeCinqConstats() {
        XCTAssertLessThanOrEqual(JournalFactors.maximumShown, 5)
    }

    func test_pValue_decroitAvecLeNombreDeJours() {
        XCTAssertLessThan(JournalFactors.pValue(r: 0.5, n: 60), JournalFactors.pValue(r: 0.5, n: 15))
    }

    // MARK: - Plan médicamenteux

    private let keppra = JournalFactors.MedicationRef(name: "Keppra")

    /// 30 jours : la dose passe de 250 à 500 au 16e jour.
    private func daysWithDoseChange(seizures: (Int) -> Int) -> [JournalFactors.Day] {
        (0..<30).map { i in
            var d = JournalFactors.Day(start: Date(timeIntervalSince1970: Double(i) * 86_400))
            d.factors[.medicationDose(keppra)] = i < 15 ? 250 : 500
            d.seizureCount = seizures(i)
            return d
        }
    }

    func test_changementDeDose_estRelieAuxCrises_etRenvoieAuMedecin() {
        // Crises : 3 ou 4 avant la hausse, 0 ou 1 après, en alternance.
        let data = daysWithDoseChange { i in i < 15 ? 3 + i % 2 : i % 2 }
        let f = JournalFactors.findings(in: data)
        XCTAssertEqual(f.first?.factor, .medicationDose(keppra))
        XCTAssertTrue(f.first?.sentence.contains("la dose quotidienne de Keppra est plus bas, il y a plus de crises") == true,
                      f.first?.sentence ?? "aucun constat")
        XCTAssertTrue(f.first?.caveat.contains("avis du médecin") == true,
                      "un constat sur un traitement doit renvoyer au médecin")
    }

    func test_doseConstante_neDitRien() {
        let data = (0..<30).map { i -> JournalFactors.Day in
            var d = JournalFactors.Day(start: Date(timeIntervalSince1970: Double(i) * 86_400))
            d.factors[.medicationDose(keppra)] = 250
            d.seizureCount = i % 3
            return d
        }
        XCTAssertTrue(JournalFactors.findings(in: data).isEmpty,
                      "sans variation de dose, il n'y a rien à corréler")
    }

    func test_planArreteEtRecree_resteUnSeulTraitement() {
        // « Keppra » arrêté puis « keppra » recréé : même série.
        let recree = JournalFactors.MedicationRef(name: "  keppra ")
        XCTAssertEqual(JournalFactors.Factor.medicationDose(keppra), .medicationDose(recree))
        let accent = JournalFactors.MedicationRef(name: "Lévétiracétam")
        XCTAssertEqual(accent, JournalFactors.MedicationRef(name: "levetiracetam"))
    }
}
