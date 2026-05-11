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
    private var scheduledHoursData: Data

    var isActive: Bool
    @Relationship var childProfile: ChildProfile?
    var createdAt: Date

    /// Type : régulier ou ponctuel. Ajouté en V1.3.0 — par défaut « régulier »
    /// pour préserver le comportement des médicaments existants.
    var kindRaw: String = MedicationKind.regular.rawValue

    /// Active ou désactive les notifications pour ce médicament. Utile quand
    /// la prise est gérée par un tiers (école, centre, autre parent) et que
    /// le parent local ne veut pas être notifié.
    /// Default true pour préserver le comportement des médicaments existants.
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

    init(
        id: UUID = UUID(),
        name: String,
        doseAmount: Double,
        doseUnit: DoseUnit,
        scheduledHours: [HourMinute],
        kind: MedicationKind = .regular,
        isActive: Bool = true,
        notifyEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.doseAmount = doseAmount
        self.doseUnitRaw = doseUnit.rawValue
        self.scheduledHoursData = (try? JSONEncoder().encode(scheduledHours)) ?? Data()
        self.kindRaw = kind.rawValue
        self.isActive = isActive
        self.notifyEnabled = notifyEnabled
        self.createdAt = createdAt
    }

    var doseLabel: String {
        let numberFormat: String = doseAmount.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(doseAmount))
            : String(format: "%.1f", doseAmount)
        return "\(numberFormat) \(doseUnit.label)"
    }
}
