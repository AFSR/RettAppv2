import Foundation
import SwiftData

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
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Medication.childProfile)
    var medications: [Medication] = []

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String = "",
        birthDate: Date? = nil,
        hasEpilepsy: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.birthDate = birthDate
        self.hasEpilepsy = hasEpilepsy
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
}
