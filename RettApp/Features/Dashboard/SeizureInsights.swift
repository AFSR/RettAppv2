import Foundation

/// Ce que les données disent au parent, en français.
///
/// Le Bilan montrait quatre graphiques et trois compteurs : beaucoup de
/// chiffres, et au parent de conclure. La décision 3 a tranché — le Bilan est
/// pour le parent, réduit, mais il garde l'estimation des corrélations pour
/// le guider. Le travail porte donc sur la lisibilité, pas sur le calcul :
/// les corrélations existent déjà, elles sont calculées pour le rapport
/// médecin par `MedicalReportAnalysis`. Elles n'étaient simplement jamais
/// montrées dans l'application.
///
/// Ce type les traduit en phrases. Il ne calcule rien de neuf : il choisit
/// quoi dire, et avec quelles précautions.
enum SeizureInsights {

    /// Une observation présentable au parent.
    struct Insight: Identifiable, Hashable {
        let id = UUID()
        /// Phrase principale, au présent, sans jargon.
        let sentence: String
        /// Nuance obligatoire : sur combien de jours, et avec quelle force.
        let caveat: String
        let systemImage: String
    }

    /// Nombre de jours en dessous duquel on ne dit rien.
    ///
    /// Une corrélation sur cinq jours n'est pas une tendance, c'est du
    /// hasard. Mieux vaut un écran qui dit « pas encore assez de données »
    /// qu'une phrase qui inquiète une famille sur un bruit statistique.
    static let minimumDays = 14

    /// Au plus deux observations. Au-delà, le parent relit un rapport, ce
    /// qu'on cherchait justement à lui éviter.
    static let maximumShown = 2

    /// Traduit les corrélations en observations lisibles.
    ///
    /// Les corrélations négligeables et faibles sont écartées : les montrer
    /// reviendrait à présenter du bruit comme un signal. Seules les
    /// corrélations modérées et fortes sont dites, et toujours avec le
    /// nombre de jours observés — c'est ce qui permet au parent de juger
    /// par lui-même.
    static func from(
        correlations: [MedicalReportAnalysis.Correlation],
        daysObserved: Int
    ) -> [Insight] {
        guard daysObserved >= minimumDays else { return [] }

        return correlations
            .filter { $0.strength == .moderate || $0.strength == .strong }
            .filter { $0.n >= minimumDays }
            .sorted { abs($0.r) > abs($1.r) }
            .prefix(maximumShown)
            .map { correlation in
                Insight(
                    sentence: sentence(for: correlation),
                    caveat: "Tendance \(correlation.strength.label), observée sur \(correlation.n) jours. "
                        + "Une tendance n'est pas une cause.",
                    systemImage: correlation.r >= 0 ? "arrow.up.right" : "arrow.down.right"
                )
            }
    }

    /// Phrase orientée « ce qui se passe les jours où », plutôt que « le
    /// coefficient vaut ». Un parent n'a pas à traduire un r de Pearson.
    private static func sentence(for c: MedicalReportAnalysis.Correlation) -> String {
        let plus = c.r >= 0 ? "plus" : "moins"
        return "Les jours où « \(c.signal) » est plus élevé, il y a \(plus) de crises."
    }
}
