import Foundation

/// Distingue une retouche d'un changement de traitement.
///
/// Corriger une faute de frappe ou couper un rappel ne change rien à ce que
/// reçoit l'enfant : on modifie sur place. Changer la dose ou les horaires,
/// si. Écrire la nouvelle valeur par-dessus l'ancienne efface ce qui permet
/// de comparer « avant » et « après » — c'est-à-dire de voir si un dosage
/// accompagne une évolution des crises ou des symptômes (`JournalFactors`).
///
/// Pour un changement de traitement, l'éditeur propose donc d'arrêter le
/// plan en cours et d'en créer un nouveau, chacun horodaté. Rien n'est
/// imposé : modifier sur place reste possible, et le choix est dit.
///
/// Type de valeurs, sans SwiftData : testable sans simulateur.
enum MedicationPlanChange {

    /// Ce qui définit ce que reçoit l'enfant, sans l'identité des prises
    /// (leurs `id` changent à chaque ouverture de l'éditeur) ni leur rappel
    /// (qui ne change pas le traitement).
    struct Values: Equatable {
        var doseAmount: Double
        var unit: DoseUnit
        var kind: MedicationKind
        var isActive: Bool
        var intakes: [MedicationIntake]

        fileprivate var schedule: [[Int]] {
            intakes
                .map { [$0.hour, $0.minute, Int(($0.dose * 1000).rounded()), $0.weekdaysRaw] }
                .sorted { $0.lexicographicallyPrecedes($1) }
        }
    }

    /// Vrai quand l'enregistrement change le traitement d'un médicament
    /// récurrent en cours. Un médicament à la demande, déjà arrêté, ou qu'on
    /// arrête dans le même geste, se modifie sur place : il n'y a pas de
    /// plan en cours à clore.
    static func requiresNewPlan(from old: Values, to new: Values) -> Bool {
        guard old.kind == .regular, new.kind == .regular else { return false }
        guard old.isActive, new.isActive else { return false }
        return !changes(from: old, to: new).isEmpty
    }

    /// Ce qui change, en une ligne par point, pour que la famille voie
    /// exactement ce qu'elle s'apprête à enregistrer.
    static func changes(from old: Values, to new: Values) -> [String] {
        var lines: [String] = []
        if old.doseAmount != new.doseAmount || old.unit != new.unit {
            lines.append("Dose : \(format(old.doseAmount)) \(old.unit.label) → \(format(new.doseAmount)) \(new.unit.label)")
        }
        if old.schedule != new.schedule {
            lines.append("Horaires ou doses des prises modifiés")
        }
        return lines
    }

    private static func format(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }

    /// Clé qui réunit les plans successifs d'un même médicament : « Keppra »
    /// arrêté puis « keppra » recréé est un seul traitement dans l'analyse.
    static func seriesKey(forName name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension MedicationPlanChange.Values {
    init(_ m: Medication) {
        self.init(doseAmount: m.doseAmount, unit: m.doseUnit, kind: m.kind,
                  isActive: m.isActive, intakes: m.intakes)
    }
}
