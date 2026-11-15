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
    /// Tie-breaker last-writer-wins pour la synchro CloudKit (cf. SyncTimestamped).

    /// Le prénom du parent qui a noté cette entrée.
    ///
    /// Vide quand personne ne l'a renseigné, et pour tout ce qui a été saisi
    /// avant novembre 2026 : l'app n'affiche alors rien plutôt que d'inventer
    /// un auteur. C'est aussi le cas quand on suit seul — l'auteur n'a de sens
    /// qu'à deux.
    ///
    /// Un prénom recopié à la saisie, et non une référence vers un compte :
    /// l'entrée doit rester lisible si le partage s'arrête, et rien ici ne
    /// doit dépendre de CloudKit.
    var authorName: String = ""

    var lastModifiedAt: Date = Date()

    var level: MoodLevel {
        get { MoodLevel(rawValue: levelRaw) ?? .neutral }
        set { levelRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: MoodLevel,
        notes: String = "",
        childProfileId: UUID? = nil,
        authorName: String = ParentIdentity.current
    ) {
        self.id = id
        self.timestamp = timestamp
        self.levelRaw = level.rawValue
        self.notes = notes
        self.childProfileId = childProfileId
        self.authorName = authorName
    }
}

extension MoodEntry: SyncTimestamped, UUIDIdentified {
    static var syncRecordType: String { CKRecordType.mood }
}
