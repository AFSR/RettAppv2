import Foundation
import SwiftData

#if DEBUG
enum PreviewData {
    static let container: ModelContainer = {
        let schema = Schema([
            ChildProfile.self,
            SeizureEvent.self,
            Medication.self,
            MedicationLog.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])

        let child = ChildProfile(
            firstName: "Léa",
            birthDate: Calendar.current.date(byAdding: .year, value: -8, to: Date()),
            hasEpilepsy: true
        )
        container.mainContext.insert(child)

        let keppra = Medication(
            name: "Keppra",
            doseAmount: 500,
            doseUnit: .mg,
            scheduledHours: [HourMinute(hour: 8, minute: 0), HourMinute(hour: 20, minute: 0)],
            isActive: true
        )
        keppra.childProfile = child
        container.mainContext.insert(keppra)

        let now = Date()
        let seizure = SeizureEvent(
            startTime: now.addingTimeInterval(-3600 * 5),
            endTime: now.addingTimeInterval(-3600 * 5 + 154),
            seizureType: .tonicClonic,
            trigger: .fever,
            notes: "Forte fièvre la veille."
        )
        seizure.childProfileId = child.id
        container.mainContext.insert(seizure)

        return container
    }()

    static let emptyContainer: ModelContainer = {
        let schema = Schema([
            ChildProfile.self,
            SeizureEvent.self,
            Medication.self,
            MedicationLog.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()
}
#endif
