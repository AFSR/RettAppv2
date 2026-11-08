import XCTest
@testable import RettApp

/// Ce que le Bilan dit au parent.
///
/// L'enjeu n'est pas le calcul — il existait déjà pour le rapport médecin —
/// mais ce qu'on accepte de montrer. Une phrase du type « les jours où
/// l'humeur est basse, il y a plus de crises » affichée sur trois jours
/// d'observation inquiéterait une famille sur du bruit statistique. Ces
/// tests gardent les seuils.
final class SeizureInsightsTests: XCTestCase {

    private func correlation(_ signal: String, r: Double, n: Int) -> MedicalReportAnalysis.Correlation {
        MedicalReportAnalysis.Correlation(signal: signal, r: r, n: n)
    }

    // MARK: - Seuils

    func test_pasAssezDeJoursObserves_aucuneObservation() {
        let fortes = [correlation("Humeur moyenne", r: 0.8, n: 60)]
        XCTAssertTrue(
            SeizureInsights.from(correlations: fortes, daysObserved: 5).isEmpty,
            "cinq jours ne font pas une tendance, même avec un coefficient élevé"
        )
    }

    func test_correlationFaible_nEstPasMontree() {
        let faibles = [correlation("Sommeil", r: 0.25, n: 60)]
        XCTAssertTrue(
            SeizureInsights.from(correlations: faibles, daysObserved: 60).isEmpty,
            "montrer une tendance faible, c'est présenter du bruit comme un signal"
        )
    }

    /// Le nombre de jours de la corrélation elle-même compte, pas seulement
    /// celui de la période : un signal peut n'être renseigné que rarement.
    func test_correlationSurTropPeuDeJoursCommuns_nEstPasMontree() {
        let peu = [correlation("Hydratation", r: 0.9, n: 4)]
        XCTAssertTrue(SeizureInsights.from(correlations: peu, daysObserved: 90).isEmpty)
    }

    // MARK: - Ce qui est montré

    func test_correlationForte_estMontreeAvecSesReserves() throws {
        let fortes = [correlation("Humeur moyenne", r: 0.72, n: 45)]
        let observations = SeizureInsights.from(correlations: fortes, daysObserved: 45)

        let premiere = try XCTUnwrap(observations.first)
        XCTAssertTrue(premiere.sentence.contains("Humeur moyenne"))
        XCTAssertTrue(premiere.sentence.contains("plus de crises"), "r positif = plus de crises")
        XCTAssertTrue(premiere.caveat.contains("45 jours"))
        XCTAssertTrue(
            premiere.caveat.contains("n'est pas une cause"),
            "une corrélation présentée sans cette réserve se lit comme une cause"
        )
    }

    func test_correlationNegative_ditMoinsDeCrises() throws {
        let negative = [correlation("Sommeil de nuit", r: -0.65, n: 30)]
        let premiere = try XCTUnwrap(SeizureInsights.from(correlations: negative, daysObserved: 30).first)
        XCTAssertTrue(premiere.sentence.contains("moins de crises"))
    }

    /// Au-delà de deux, le parent relit un rapport — ce qu'on cherchait à lui
    /// éviter. Et les plus fortes passent devant.
    func test_auPlusDeuxObservations_lesPlusFortesDAbord() throws {
        let toutes = [
            correlation("Signal faible", r: 0.45, n: 40),
            correlation("Signal fort", r: -0.88, n: 40),
            correlation("Signal moyen", r: 0.60, n: 40),
        ]
        let observations = SeizureInsights.from(correlations: toutes, daysObserved: 40)

        XCTAssertEqual(observations.count, 2)
        XCTAssertTrue(observations[0].sentence.contains("Signal fort"))
        XCTAssertTrue(observations[1].sentence.contains("Signal moyen"))
    }

    func test_aucuneCorrelation_aucuneObservation() {
        XCTAssertTrue(SeizureInsights.from(correlations: [], daysObserved: 90).isEmpty)
    }
}
