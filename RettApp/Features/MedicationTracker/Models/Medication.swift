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

    var doseUnit: DoseUnit {
        get { DoseUnit(rawValue: doseUnitRaw) ?? .mg }
        set { doseUnitRaw = newValue.rawValue }
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
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.doseAmount = doseAmount
        self.doseUnitRaw = doseUnit.rawValue
        self.scheduledHoursData = (try? JSONEncoder().encode(scheduledHours)) ?? Data()
        self.isActive = isActive
        self.createdAt = createdAt
    }

    var doseLabel: String {
        let numberFormat: String = doseAmount.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(doseAmount))
            : String(format: "%.1f", doseAmount)
        return "\(numberFormat) \(doseUnit.label)"
    }
}
