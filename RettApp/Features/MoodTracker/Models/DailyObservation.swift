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

/// Synthèse qualitative et quantitative quotidienne — repas, hydratation, sommeil.
/// Une seule entrée par jour (clé : `dayStart`).
@Model
final class DailyObservation {
    @Attribute(.unique) var id: UUID
    /// Début de la journée (00:00:00) — sert de clé d'unicité par jour.
    var dayStart: Date

    /// 1-5. 0 = non renseigné.
    var mealRatingRaw: Int = 0
    var mealNotes: String = ""

    var hydrationRatingRaw: Int = 0
    var hydrationNotes: String = ""

    var nightSleepRatingRaw: Int = 0
    var nightSleepNotes: String = ""

    /// Durée de la sieste en minutes. 0 = pas de sieste.
    var napDurationMinutes: Int = 0
    var napNotes: String = ""

    var generalNotes: String = ""

    var childProfileId: UUID?

    init(
        id: UUID = UUID(),
        dayStart: Date,
        mealRating: QualityRating? = nil,
        mealNotes: String = "",
        hydrationRating: QualityRating? = nil,
        hydrationNotes: String = "",
        nightSleepRating: QualityRating? = nil,
        nightSleepNotes: String = "",
        napDurationMinutes: Int = 0,
        napNotes: String = "",
        generalNotes: String = "",
        childProfileId: UUID? = nil
    ) {
        self.id = id
        self.dayStart = dayStart
        self.mealRatingRaw = mealRating?.rawValue ?? 0
        self.mealNotes = mealNotes
        self.hydrationRatingRaw = hydrationRating?.rawValue ?? 0
        self.hydrationNotes = hydrationNotes
        self.nightSleepRatingRaw = nightSleepRating?.rawValue ?? 0
        self.nightSleepNotes = nightSleepNotes
        self.napDurationMinutes = napDurationMinutes
        self.napNotes = napNotes
        self.generalNotes = generalNotes
        self.childProfileId = childProfileId
    }

    var mealRating: QualityRating? {
        get { QualityRating(rawValue: mealRatingRaw) }
        set { mealRatingRaw = newValue?.rawValue ?? 0 }
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
        mealRatingRaw > 0 || hydrationRatingRaw > 0 || nightSleepRatingRaw > 0
            || napDurationMinutes > 0 || !generalNotes.isEmpty
            || !mealNotes.isEmpty || !hydrationNotes.isEmpty
            || !nightSleepNotes.isEmpty || !napNotes.isEmpty
    }
}
