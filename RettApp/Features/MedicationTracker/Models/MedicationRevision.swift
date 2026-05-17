import Foundation
import SwiftData

/// Snapshot horodaté d'un `Medication`. À chaque modification du plan, on
/// insère une nouvelle révision avec `effectiveFrom = Date()` — l'état du
/// `Medication` courant reste la valeur la plus récente (pour l'accès rapide),
/// mais on peut reconstituer l'état historique à n'importe quelle date passée
/// en cherchant la dernière révision où `effectiveFrom <= date` pour le
/// `medicationId` donné.
///
/// Utilité :
/// - Bilan rétrospectif : afficher le plan tel qu'il était il y a 3 mois.
/// - Audit médical : conserver la trace des changements de dosage.
/// - Préservation de l'historique : modifier un dosage n'efface plus les
///   anciennes valeurs associées aux `MedicationLog` antérieurs (lesquels
///   stockent déjà leur propre dose/unité au moment de la prise — la
///   révision sert pour les vues qui reconstruisent un plan complet à
///   une date).
@Model
final class MedicationRevision {
    @Attribute(.unique) var id: UUID
    var medicationId: UUID
    var effectiveFrom: Date

    // Snapshot complet des champs éditables.
    var name: String
    var doseAmount: Double
    var doseUnitRaw: String
    private var intakesData: Data
    var kindRaw: String
    var isActive: Bool
    var notifyEnabled: Bool

    /// Tie-breaker last-writer-wins pour la synchro CloudKit (cf. SyncTimestamped).
    var lastModifiedAt: Date = Date()

    var doseUnit: DoseUnit {
        get { DoseUnit(rawValue: doseUnitRaw) ?? .mg }
        set { doseUnitRaw = newValue.rawValue }
    }

    var kind: MedicationKind {
        get { MedicationKind(rawValue: kindRaw) ?? .regular }
        set { kindRaw = newValue.rawValue }
    }

    var intakes: [MedicationIntake] {
        get { (try? JSONDecoder().decode([MedicationIntake].self, from: intakesData)) ?? [] }
        set { intakesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(
        id: UUID = UUID(),
        medicationId: UUID,
        effectiveFrom: Date = Date(),
        name: String,
        doseAmount: Double,
        doseUnit: DoseUnit,
        intakes: [MedicationIntake],
        kind: MedicationKind,
        isActive: Bool,
        notifyEnabled: Bool
    ) {
        self.id = id
        self.medicationId = medicationId
        self.effectiveFrom = effectiveFrom
        self.name = name
        self.doseAmount = doseAmount
        self.doseUnitRaw = doseUnit.rawValue
        self.intakesData = (try? JSONEncoder().encode(intakes)) ?? Data()
        self.kindRaw = kind.rawValue
        self.isActive = isActive
        self.notifyEnabled = notifyEnabled
    }

    /// Récupère la révision la plus récente d'un médicament dont la date
    /// d'effet est antérieure ou égale à `date`. Renvoie nil si aucune
    /// révision n'existe pour ce médicament — l'appelant retombe alors sur
    /// l'état courant du `Medication`.
    static func latest(
        medicationId: UUID,
        before date: Date,
        in context: ModelContext
    ) -> MedicationRevision? {
        let descriptor = FetchDescriptor<MedicationRevision>(
            predicate: #Predicate { rev in
                rev.medicationId == medicationId && rev.effectiveFrom <= date
            },
            sortBy: [SortDescriptor(\.effectiveFrom, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// Insère une révision capturant l'état actuel du médicament passé. À
    /// appeler depuis la couche de sauvegarde du plan (`MedicationEditor`)
    /// **avant** d'écraser les champs avec les nouvelles valeurs, ou
    /// **après** pour capturer l'état post-modification — au choix selon la
    /// sémantique souhaitée. RettApp utilise « après » : l'état affiché à
    /// une date d est l'état tel qu'il était APRÈS la dernière modification
    /// effectuée avant d.
    static func capture(
        of medication: Medication,
        at date: Date = Date(),
        in context: ModelContext
    ) {
        let rev = MedicationRevision(
            medicationId: medication.id,
            effectiveFrom: date,
            name: medication.name,
            doseAmount: medication.doseAmount,
            doseUnit: medication.doseUnit,
            intakes: medication.intakes,
            kind: medication.kind,
            isActive: medication.isActive,
            notifyEnabled: medication.notifyEnabled
        )
        context.insert(rev)
    }

    /// Backfill au démarrage : pour chaque `Medication` sans aucune
    /// révision, insère une révision initiale datée du `createdAt` du
    /// médicament. Idempotent — on peut le rappeler à chaque lancement
    /// sans risque.
    static func backfillIfNeeded(in context: ModelContext) {
        let medications = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        var insertedCount = 0
        for med in medications {
            let medID = med.id
            let descriptor = FetchDescriptor<MedicationRevision>(
                predicate: #Predicate { $0.medicationId == medID }
            )
            let existing = (try? context.fetchCount(descriptor)) ?? 0
            if existing == 0 {
                capture(of: med, at: med.createdAt, in: context)
                insertedCount += 1
            }
        }
        if insertedCount > 0 {
            try? context.save()
        }
    }
}

extension MedicationRevision: SyncTimestamped {}
