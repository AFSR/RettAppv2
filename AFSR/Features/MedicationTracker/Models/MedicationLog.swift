import Foundation
import SwiftData

@Model
final class MedicationLog {
    @Attribute(.unique) var id: UUID
    var medicationId: UUID
    var medicationName: String
    var scheduledTime: Date
    var takenTime: Date?
    var taken: Bool
    var dose: Double
    var doseUnitRaw: String
    var childProfileId: UUID?
    var exportedToHealthKit: Bool

    var doseUnit: DoseUnit {
        get { DoseUnit(rawValue: doseUnitRaw) ?? .mg }
        set { doseUnitRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        medicationId: UUID,
        medicationName: String,
        scheduledTime: Date,
        takenTime: Date? = nil,
        taken: Bool = false,
        dose: Double,
        doseUnit: DoseUnit,
        childProfileId: UUID? = nil,
        exportedToHealthKit: Bool = false
    ) {
        self.id = id
        self.medicationId = medicationId
        self.medicationName = medicationName
        self.scheduledTime = scheduledTime
        self.takenTime = takenTime
        self.taken = taken
        self.dose = dose
        self.doseUnitRaw = doseUnit.rawValue
        self.childProfileId = childProfileId
        self.exportedToHealthKit = exportedToHealthKit
    }

    var isLate: Bool {
        guard !taken else { return false }
        return Date().timeIntervalSince(scheduledTime) > 30 * 60
    }
}
