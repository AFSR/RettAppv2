import Foundation
import SwiftData

/// Échelle qualitative 1-5 utilisée pour repas / hydratation / sommeil.
enum QualityRating: Int, Codable, CaseIterable, Identifiable {
    case veryPoor = 1
    case poor     = 2
    case ok       = 3
    case good     = 4
    case excellent = 5

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .veryPoor:  return "Très faible"
        case .poor:      return "Faible"
        case .ok:        return "Correct"
        case .good:      return "Bon"
        case .excellent: return "Excellent"
        }
    }
    var symbol: String {
        switch self {
        case .veryPoor:  return "1"
        case .poor:      return "2"
        case .ok:        return "3"
        case .good:      return "4"
        case .excellent: return "5"
        }
    }
}

/// Moments de repas distincts dans la journée.
enum MealSlot: String, CaseIterable, Identifiable {
    case breakfast, lunch, snack, dinner
    var id: String { rawValue }
    var label: String {
        switch self {
        case .breakfast: return "Petit-déjeuner"
        case .lunch:     return "Déjeuner"
        case .snack:     return "Goûter"
        case .dinner:    return "Dîner"
        }
    }
    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch:     return "sun.max.fill"
        case .snack:     return "cup.and.saucer.fill"
        case .dinner:    return "moon.stars.fill"
        }
    }
}

/// Synthèse qualitative et quantitative quotidienne — repas, hydratation, sommeil.
/// Une seule entrée par jour (clé : `dayStart`).
@Model
final class DailyObservation {
    @Attribute(.unique) var id: UUID
    /// Début de la journée (00:00:00) — sert de clé d'unicité par jour.
    var dayStart: Date

    // ── Legacy (V1 — note unique pour tous les repas).
    // Conservés pour ne pas casser les données existantes ; la moyenne des 4
    // ratings spécifiques en a la priorité quand présentes.
    var mealRatingRaw: Int = 0
    var mealNotes: String = ""

    // ── Repas par moment (V1.4)
    var breakfastRatingRaw: Int = 0
    var breakfastNotes: String = ""
    var lunchRatingRaw: Int = 0
    var lunchNotes: String = ""
    var snackRatingRaw: Int = 0
    var snackNotes: String = ""
    var dinnerRatingRaw: Int = 0
    var dinnerNotes: String = ""

    var hydrationRatingRaw: Int = 0
    var hydrationNotes: String = ""

    var nightSleepRatingRaw: Int = 0
    /// Durée du sommeil de nuit en minutes. 0 = non renseigné. (Ajouté V1.4)
    var nightSleepDurationMinutes: Int = 0
    var nightSleepNotes: String = ""

    /// Durée de la sieste en minutes. 0 = pas de sieste.
    var napDurationMinutes: Int = 0
    var napNotes: String = ""

    var generalNotes: String = ""

    var childProfileId: UUID?

    init(
        id: UUID = UUID(),
        dayStart: Date,
        breakfastRating: QualityRating? = nil, breakfastNotes: String = "",
        lunchRating: QualityRating? = nil, lunchNotes: String = "",
        snackRating: QualityRating? = nil, snackNotes: String = "",
        dinnerRating: QualityRating? = nil, dinnerNotes: String = "",
        hydrationRating: QualityRating? = nil,
        hydrationNotes: String = "",
        nightSleepRating: QualityRating? = nil,
        nightSleepDurationMinutes: Int = 0,
        nightSleepNotes: String = "",
        napDurationMinutes: Int = 0,
        napNotes: String = "",
        generalNotes: String = "",
        childProfileId: UUID? = nil
    ) {
        self.id = id
        self.dayStart = dayStart
        self.breakfastRatingRaw = breakfastRating?.rawValue ?? 0
        self.breakfastNotes = breakfastNotes
        self.lunchRatingRaw = lunchRating?.rawValue ?? 0
        self.lunchNotes = lunchNotes
        self.snackRatingRaw = snackRating?.rawValue ?? 0
        self.snackNotes = snackNotes
        self.dinnerRatingRaw = dinnerRating?.rawValue ?? 0
        self.dinnerNotes = dinnerNotes
        self.hydrationRatingRaw = hydrationRating?.rawValue ?? 0
        self.hydrationNotes = hydrationNotes
        self.nightSleepRatingRaw = nightSleepRating?.rawValue ?? 0
        self.nightSleepDurationMinutes = nightSleepDurationMinutes
        self.nightSleepNotes = nightSleepNotes
        self.napDurationMinutes = napDurationMinutes
        self.napNotes = napNotes
        self.generalNotes = generalNotes
        self.childProfileId = childProfileId
    }

    // MARK: - Per-meal accessors

    func mealRating(for slot: MealSlot) -> QualityRating? {
        switch slot {
        case .breakfast: return QualityRating(rawValue: breakfastRatingRaw)
        case .lunch:     return QualityRating(rawValue: lunchRatingRaw)
        case .snack:     return QualityRating(rawValue: snackRatingRaw)
        case .dinner:    return QualityRating(rawValue: dinnerRatingRaw)
        }
    }
    func setMealRating(_ rating: QualityRating?, for slot: MealSlot) {
        let v = rating?.rawValue ?? 0
        switch slot {
        case .breakfast: breakfastRatingRaw = v
        case .lunch:     lunchRatingRaw = v
        case .snack:     snackRatingRaw = v
        case .dinner:    dinnerRatingRaw = v
        }
    }
    func mealNotes(for slot: MealSlot) -> String {
        switch slot {
        case .breakfast: return breakfastNotes
        case .lunch:     return lunchNotes
        case .snack:     return snackNotes
        case .dinner:    return dinnerNotes
        }
    }
    func setMealNotes(_ notes: String, for slot: MealSlot) {
        switch slot {
        case .breakfast: breakfastNotes = notes
        case .lunch:     lunchNotes = notes
        case .snack:     snackNotes = notes
        case .dinner:    dinnerNotes = notes
        }
    }

    // MARK: - Aggregated

    /// Moyenne des 4 ratings de repas (sans les zéros). Fallback sur le legacy
    /// `mealRatingRaw` si rien de spécifique n'est renseigné.
    var averageMealRatingRaw: Int {
        let raws = [breakfastRatingRaw, lunchRatingRaw, snackRatingRaw, dinnerRatingRaw].filter { $0 > 0 }
        if raws.isEmpty { return mealRatingRaw }
        let avg = Double(raws.reduce(0, +)) / Double(raws.count)
        return Int(avg.rounded())
    }
    var averageMealRating: QualityRating? {
        QualityRating(rawValue: averageMealRatingRaw)
    }

    var hydrationRating: QualityRating? {
        get { QualityRating(rawValue: hydrationRatingRaw) }
        set { hydrationRatingRaw = newValue?.rawValue ?? 0 }
    }
    var nightSleepRating: QualityRating? {
        get { QualityRating(rawValue: nightSleepRatingRaw) }
        set { nightSleepRatingRaw = newValue?.rawValue ?? 0 }
    }

    /// True si au moins un champ a été renseigné.
    var isPopulated: Bool {
        averageMealRatingRaw > 0
            || hydrationRatingRaw > 0
            || nightSleepRatingRaw > 0
            || nightSleepDurationMinutes > 0
            || napDurationMinutes > 0
            || !generalNotes.isEmpty
            || !mealNotes.isEmpty
            || !hydrationNotes.isEmpty
            || !nightSleepNotes.isEmpty
            || !napNotes.isEmpty
            || !breakfastNotes.isEmpty || !lunchNotes.isEmpty
            || !snackNotes.isEmpty || !dinnerNotes.isEmpty
    }
}
