import Foundation
import SwiftData

/// Données de prévisualisation. N'est pas entouré de `#if DEBUG` : les macros
/// `#Preview { }` SwiftUI sont compilées en Release aussi — si PreviewData
/// n'est pas visible, l'Archive échoue. Coût zéro en production : les `let`
/// statiques sont lazy, donc les stores en mémoire ne sont créés que si
/// quelqu'un référence `PreviewData.container` (ce qui n'arrive jamais hors
/// canvas Xcode).
enum PreviewData {
    static let container: ModelContainer = {
        let schema = Schema([
            ChildProfile.self,
            SeizureEvent.self,
            Medication.self,
            MedicationLog.self,
            MoodEntry.self,
            DailyObservation.self,
            SymptomEvent.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(for: schema, configurations: [config])

        // Utilise un ModelContext dédié (non main-actor) pour peupler depuis
        // un static let init (qui n'est pas isolé au main actor).
        let context = ModelContext(container)

        let child = ChildProfile(
            firstName: "Léa",
            birthDate: Calendar.current.date(byAdding: .year, value: -8, to: Date()),
            hasEpilepsy: true
        )
        context.insert(child)

        let keppra = Medication(
            name: "Keppra",
            doseAmount: 500,
            doseUnit: .mg,
            scheduledHours: [HourMinute(hour: 8, minute: 0), HourMinute(hour: 20, minute: 0)],
            isActive: true
        )
        keppra.childProfile = child
        context.insert(keppra)

        let now = Date()
        let seizure = SeizureEvent(
            startTime: now.addingTimeInterval(-3600 * 5),
            endTime: now.addingTimeInterval(-3600 * 5 + 154),
            seizureType: .tonicClonic,
            trigger: .fever,
            notes: "Forte fièvre la veille."
        )
        seizure.childProfileId = child.id
        context.insert(seizure)

        try? context.save()
        return container
    }()

    static let emptyContainer: ModelContainer = {
        let schema = Schema([
            ChildProfile.self,
            SeizureEvent.self,
            Medication.self,
            MedicationLog.self,
            MoodEntry.self,
            DailyObservation.self,
            SymptomEvent.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: [config])
    }()
}

