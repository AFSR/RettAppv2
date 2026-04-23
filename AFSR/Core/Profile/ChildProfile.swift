import Foundation
import SwiftData

@Model
final class ChildProfile {
    @Attribute(.unique) var id: UUID
    var firstName: String
    var birthDate: Date?
    var hasEpilepsy: Bool
    var createdAt: Date
    var appleUserID: String?

    @Relationship(deleteRule: .cascade, inverse: \Medication.childProfile)
    var medications: [Medication] = []

    init(
        id: UUID = UUID(),
        firstName: String,
        birthDate: Date? = nil,
        hasEpilepsy: Bool = false,
        appleUserID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.firstName = firstName
        self.birthDate = birthDate
        self.hasEpilepsy = hasEpilepsy
        self.appleUserID = appleUserID
        self.createdAt = createdAt
    }

    var ageYears: Int? {
        guard let birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }
}
