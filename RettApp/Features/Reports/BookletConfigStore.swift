import Foundation
import Observation

/// Identifiant d'une prise spécifique (médicament + horaire planifié).
/// Permet à l'utilisateur de cocher chaque prise séparément dans la config
/// du cahier de suivi (certaines prises sont à la maison, d'autres au centre).
struct DoseKey: Hashable, Codable {
    let medicationID: UUID
    let hour: Int
    let minute: Int

    var formattedTime: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

/// Préférences persistantes pour la génération du cahier de suivi.
/// L'utilisateur configure une fois ; chaque génération réutilise le même
/// jeu de préférences. Stocké dans UserDefaults.
@Observable
@MainActor
final class BookletConfigStore {
    static let shared = BookletConfigStore()

    private let key = "RettApp.bookletConfig.v1"

    var dayCount: Int { didSet { persist() } }

    var includeMedicationGrid: Bool { didSet { persist() } }
    var includeSeizureGrid: Bool { didSet { persist() } }
    var includeMoodGrid: Bool { didSet { persist() } }
    var includeMealsGrid: Bool { didSet { persist() } }
    var includeSleepGrid: Bool { didSet { persist() } }
    var includeSymptomsGrid: Bool { didSet { persist() } }
    var includeFreeNotes: Bool { didSet { persist() } }

    /// Toutes les prises actives sont incluses si ce set est vide
    /// (back-compat — premier lancement).
    var selectedDoses: Set<DoseKey> { didSet { persist() } }
    /// Si true, on ignore selectedDoses et on prend toutes les prises actives.
    var allDosesSelected: Bool { didSet { persist() } }

    var selectedMealSlotsRaw: [String] { didSet { persist() } }
    var selectedSymptomsRaw: [String] { didSet { persist() } }

    var selectedMealSlots: Set<MealSlot> {
        get { Set(selectedMealSlotsRaw.compactMap { MealSlot(rawValue: $0) }) }
        set { selectedMealSlotsRaw = Array(newValue.map(\.rawValue)) }
    }
    var selectedSymptoms: Set<RettSymptom> {
        get { Set(selectedSymptomsRaw.compactMap { RettSymptom(rawValue: $0) }) }
        set { selectedSymptomsRaw = Array(newValue.map(\.rawValue)) }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.persistedKey),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {
            self.dayCount = decoded.dayCount
            self.includeMedicationGrid = decoded.includeMedicationGrid
            self.includeSeizureGrid = decoded.includeSeizureGrid
            self.includeMoodGrid = decoded.includeMoodGrid
            self.includeMealsGrid = decoded.includeMealsGrid
            self.includeSleepGrid = decoded.includeSleepGrid
            self.includeSymptomsGrid = decoded.includeSymptomsGrid
            self.includeFreeNotes = decoded.includeFreeNotes
            self.selectedDoses = decoded.selectedDoses
            self.allDosesSelected = decoded.allDosesSelected
            self.selectedMealSlotsRaw = decoded.selectedMealSlotsRaw
            self.selectedSymptomsRaw = decoded.selectedSymptomsRaw
        } else {
            self.dayCount = 5
            self.includeMedicationGrid = true
            self.includeSeizureGrid = true
            self.includeMoodGrid = true
            self.includeMealsGrid = true
            self.includeSleepGrid = false
            self.includeSymptomsGrid = false
            self.includeFreeNotes = true
            self.selectedDoses = []
            self.allDosesSelected = true
            self.selectedMealSlotsRaw = [MealSlot.breakfast.rawValue, MealSlot.lunch.rawValue,
                                          MealSlot.snack.rawValue, MealSlot.dinner.rawValue]
            self.selectedSymptomsRaw = []
        }
    }

    private static let persistedKey = "RettApp.bookletConfig.v1"

    private struct Persisted: Codable {
        var dayCount: Int
        var includeMedicationGrid: Bool
        var includeSeizureGrid: Bool
        var includeMoodGrid: Bool
        var includeMealsGrid: Bool
        var includeSleepGrid: Bool
        var includeSymptomsGrid: Bool
        var includeFreeNotes: Bool
        var selectedDoses: Set<DoseKey>
        var allDosesSelected: Bool
        var selectedMealSlotsRaw: [String]
        var selectedSymptomsRaw: [String]
    }

    private func persist() {
        let snapshot = Persisted(
            dayCount: dayCount,
            includeMedicationGrid: includeMedicationGrid,
            includeSeizureGrid: includeSeizureGrid,
            includeMoodGrid: includeMoodGrid,
            includeMealsGrid: includeMealsGrid,
            includeSleepGrid: includeSleepGrid,
            includeSymptomsGrid: includeSymptomsGrid,
            includeFreeNotes: includeFreeNotes,
            selectedDoses: selectedDoses,
            allDosesSelected: allDosesSelected,
            selectedMealSlotsRaw: selectedMealSlotsRaw,
            selectedSymptomsRaw: selectedSymptomsRaw
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.persistedKey)
        }
    }
}
