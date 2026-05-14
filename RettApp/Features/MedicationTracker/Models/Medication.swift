import Foundation
import SwiftData

enum DoseUnit: String, Codable, CaseIterable, Identifiable {
    case mg, ml, tablet
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mg: return "mg"
        case .ml: return "ml"
        case .tablet: return "cp"
        }
    }
}

/// Type de médicament : régulier (planifié) ou ponctuel (à la demande, sans horaires).
enum MedicationKind: String, Codable, CaseIterable, Identifiable {
    case regular   // pris selon des horaires planifiés
    case adhoc     // pris en cas de besoin (Rivotril en cas de crise, antipyrétique sur fièvre, etc.)
    var id: String { rawValue }
    var label: String {
        switch self {
        case .regular: return "Récurrent"
        case .adhoc:   return "À la demande"
        }
    }
}

@Model
final class Medication {
    @Attribute(.unique) var id: UUID
    var name: String
    var doseAmount: Double
    var doseUnitRaw: String

    /// Heures planifiées (encodées en JSON pour éviter un model SwiftData imbriqué).
    /// Conservé pour compatibilité ascendante : chaque écriture sur `intakes`
    /// synchronise ce champ avec la liste des heures.
    private var scheduledHoursData: Data

    /// Prises planifiées détaillées (heure + dose + jours + notifications).
    /// Ajouté en V1.6.0. Si vide pour un médicament créé avant cette version,
    /// le getter `intakes` reconstruit la liste à partir de `scheduledHours`.
    private var intakesData: Data = Data()

    var isActive: Bool
    @Relationship var childProfile: ChildProfile?
    var createdAt: Date
    /// Tie-breaker last-writer-wins pour la synchro CloudKit (cf. SyncTimestamped).
    var lastModifiedAt: Date = Date()

    /// Type : régulier ou ponctuel. Ajouté en V1.3.0 — par défaut « régulier »
    /// pour préserver le comportement des médicaments existants.
    var kindRaw: String = MedicationKind.regular.rawValue

    /// Interrupteur principal de notifications pour ce médicament. Quand il
    /// est désactivé, aucun rappel n'est planifié quels que soient les
    /// réglages individuels des prises. Quand il est activé, chaque prise
    /// peut affiner via `intake.notifyEnabled`.
    var notifyEnabled: Bool = true

    var doseUnit: DoseUnit {
        get { DoseUnit(rawValue: doseUnitRaw) ?? .mg }
        set { doseUnitRaw = newValue.rawValue }
    }

    var kind: MedicationKind {
        get { MedicationKind(rawValue: kindRaw) ?? .regular }
        set { kindRaw = newValue.rawValue }
    }

    var scheduledHours: [HourMinute] {
        get { (try? JSONDecoder().decode([HourMinute].self, from: scheduledHoursData)) ?? [] }
        set { scheduledHoursData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// Prises planifiées : autoritaire pour le calcul des logs et notifications.
    /// Pour un médicament créé avant V1.6.0, le getter reconstruit la liste à
    /// partir de `scheduledHours` (tous les jours, dose = `doseAmount`,
    /// notifications = `notifyEnabled`).
    var intakes: [MedicationIntake] {
        get {
            if let decoded = try? JSONDecoder().decode([MedicationIntake].self, from: intakesData),
               !decoded.isEmpty {
                return decoded.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
            }
            return scheduledHours.map { hm in
                MedicationIntake(
                    hour: hm.hour,
                    minute: hm.minute,
                    dose: doseAmount,
                    weekdays: MedicationIntake.allWeekdays,
                    notifyEnabled: true
                )
            }
        }
        set {
            let sorted = newValue.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
            intakesData = (try? JSONEncoder().encode(sorted)) ?? Data()
            // Garde `scheduledHours` en miroir pour les vues / exports qui
            // n'ont pas encore migré vers `intakes`.
            scheduledHours = sorted.map { HourMinute(hour: $0.hour, minute: $0.minute) }
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        doseAmount: Double,
        doseUnit: DoseUnit,
        scheduledHours: [HourMinute],
        kind: MedicationKind = .regular,
        isActive: Bool = true,
        notifyEnabled: Bool = true,
        createdAt: Date = Date(),
        intakes: [MedicationIntake]? = nil
    ) {
        self.id = id
        self.name = name
        self.doseAmount = doseAmount
        self.doseUnitRaw = doseUnit.rawValue
        let resolvedHours = scheduledHours
        self.scheduledHoursData = (try? JSONEncoder().encode(resolvedHours)) ?? Data()
        self.kindRaw = kind.rawValue
        self.isActive = isActive
        self.notifyEnabled = notifyEnabled
        self.createdAt = createdAt
        let resolvedIntakes = intakes ?? resolvedHours.map { hm in
            MedicationIntake(
                hour: hm.hour, minute: hm.minute,
                dose: doseAmount, weekdays: MedicationIntake.allWeekdays,
                notifyEnabled: true
            )
        }
        let sortedIntakes = resolvedIntakes.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        self.intakesData = (try? JSONEncoder().encode(sortedIntakes)) ?? Data()
    }

    var doseLabel: String {
        let numberFormat: String = doseAmount.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(doseAmount))
            : String(format: "%.1f", doseAmount)
        return "\(numberFormat) \(doseUnit.label)"
    }
}

extension Medication: SyncTimestamped {}
