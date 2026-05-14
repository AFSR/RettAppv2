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

    /// Marqueur pour les prises ponctuelles (saisies à la volée), par opposition
    /// aux prises planifiées issues d'un Medication récurrent.
    /// Default false → préserve les logs existants.
    var isAdHoc: Bool = false
    /// Raison libre pour les prises ponctuelles (« fièvre », « post-crise », etc.).
    var adhocReason: String = ""
    /// Tie-breaker last-writer-wins pour la synchro CloudKit (cf. SyncTimestamped).
    var lastModifiedAt: Date = Date()

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
        exportedToHealthKit: Bool = false,
        isAdHoc: Bool = false,
        adhocReason: String = ""
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
        self.isAdHoc = isAdHoc
        self.adhocReason = adhocReason
    }

    var isLate: Bool {
        guard !taken && !isAdHoc else { return false }
        return Date().timeIntervalSince(scheduledTime) > 30 * 60
    }

    /// Heure pertinente : `takenTime` pour ad-hoc / pris, `scheduledTime` sinon.
    var effectiveTime: Date {
        takenTime ?? scheduledTime
    }
}

extension MedicationLog: SyncTimestamped {}
