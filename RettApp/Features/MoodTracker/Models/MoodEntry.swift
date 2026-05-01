import Foundation
import SwiftData

/// Niveau d'humeur sur une échelle 5 points (compatible analyse statistique).
/// Les valeurs numériques permettent les corrélations (Pearson) avec d'autres signaux.
enum MoodLevel: Int, Codable, CaseIterable, Identifiable {
    case veryDifficult = 1
    case worried       = 2
    case neutral       = 3
    case good          = 4
    case veryGood      = 5

    var id: Int { rawValue }
    var emoji: String {
        switch self {
        case .veryDifficult: return "😢"
        case .worried:       return "😟"
        case .neutral:       return "😐"
        case .good:          return "🙂"
        case .veryGood:      return "😀"
        }
    }
    var label: String {
        switch self {
        case .veryDifficult: return "Très difficile"
        case .worried:       return "Inquiétant"
        case .neutral:       return "Neutre"
        case .good:          return "Bien"
        case .veryGood:      return "Très bien"
        }
    }
}

/// Saisie ponctuelle de l'humeur. Plusieurs entrées possibles par jour.
@Model
final class MoodEntry {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var levelRaw: Int
    var notes: String
    var childProfileId: UUID?

    var level: MoodLevel {
        get { MoodLevel(rawValue: levelRaw) ?? .neutral }
        set { levelRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: MoodLevel,
        notes: String = "",
        childProfileId: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.levelRaw = level.rawValue
        self.notes = notes
        self.childProfileId = childProfileId
    }
}
