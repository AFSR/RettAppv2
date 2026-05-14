import Foundation
import SwiftData

/// Sexe de l'enfant — utilisé uniquement pour l'accord grammatical des
/// libellés affichés dans l'app (« née » / « né », « elle » / « il »…).
/// `unspecified` permet de garder une formulation neutre.
enum ChildSex: String, Codable, CaseIterable, Identifiable {
    case girl
    case boy
    case unspecified

    var id: String { rawValue }

    var label: String {
        switch self {
        case .girl:        return "Fille"
        case .boy:         return "Garçon"
        case .unspecified: return "Non précisé"
        }
    }

    /// Pronom sujet : « elle » / « il » / « il / elle ».
    var subjectPronoun: String {
        switch self {
        case .girl:        return "elle"
        case .boy:         return "il"
        case .unspecified: return "il / elle"
        }
    }

    /// Suffixe d'accord pour les participes (« née » / « né » / « né(e) »).
    var pastParticipleSuffix: String {
        switch self {
        case .girl:        return "e"
        case .boy:         return ""
        case .unspecified: return "(e)"
        }
    }

    /// Article défini singulier (« la » / « le » / « le/la »).
    var definiteArticle: String {
        switch self {
        case .girl:        return "la"
        case .boy:         return "le"
        case .unspecified: return "le/la"
        }
    }
}

@Model
final class ChildProfile {
    @Attribute(.unique) var id: UUID
    var firstName: String
    /// Nom de famille — utilisé uniquement pour l'identification dans les documents
    /// imprimés (rapport médecin, cahier de suivi). Optionnel : par défaut chaîne vide
    /// pour préserver les profils existants.
    var lastName: String = ""
    var birthDate: Date?
    var hasEpilepsy: Bool
    /// Sexe de l'enfant — pour les accords grammaticaux des libellés.
    /// Valeur par défaut « unspecified » pour préserver les profils existants.
    var sexRaw: String = ChildSex.unspecified.rawValue
    var createdAt: Date
    /// Timestamp client de la dernière modification, mis à jour par
    /// `ModelContext.saveTouching()`. Sert de tie-breaker last-writer-wins
    /// pour la résolution de conflit côté CloudKit Sharing — voir
    /// `SyncTimestamped` et `SyncConflictResolver`.
    var lastModifiedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Medication.childProfile)
    var medications: [Medication] = []

    var sex: ChildSex {
        get { ChildSex(rawValue: sexRaw) ?? .unspecified }
        set { sexRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String = "",
        birthDate: Date? = nil,
        hasEpilepsy: Bool = false,
        sex: ChildSex = .unspecified,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.birthDate = birthDate
        self.hasEpilepsy = hasEpilepsy
        self.sexRaw = sex.rawValue
        self.createdAt = createdAt
    }

    var ageYears: Int? {
        guard let birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    /// Nom complet pour l'identification. Utilise uniquement le prénom si pas de nom.
    var fullName: String {
        let trimmedLast = lastName.trimmingCharacters(in: .whitespaces)
        if trimmedLast.isEmpty { return firstName }
        return "\(firstName) \(trimmedLast)"
    }

    /// Variante courte pour interpoler dans les libellés : prénom si présent,
    /// sinon « votre enfant ».
    var displayName: String {
        let trimmed = firstName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "votre enfant" : trimmed
    }
}

extension ChildProfile: SyncTimestamped {}
