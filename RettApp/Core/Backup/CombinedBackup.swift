import Foundation
import SwiftData

/// Structure JSON unique contenant l'ensemble des données RettApp d'un
/// enfant. Sert à :
/// - Exporter une sauvegarde complète (un seul fichier au lieu de N CSV).
/// - Réimporter depuis cette sauvegarde sur un autre appareil ou après
///   réinstallation.
/// - Migrer depuis un autre outil de suivi qui produirait ce format.
///
/// Version 1 — tous les `@Model` synchronisés CloudKit (cf. CKRecordType.all)
/// sauf les `SyncTimestamped` qui sont automatiquement re-touchés à l'import.
struct CombinedBackup: Codable {
    /// Numéro de version du schéma. Permet de gérer les évolutions futures
    /// (ajout d'un type de record) en gardant la rétro-compatibilité.
    let version: Int
    /// Date de génération du fichier — pour traçabilité utilisateur.
    let exportedAt: Date

    var child: ChildBackup?
    var medications: [MedicationBackup]
    var medicationLogs: [LogBackup]
    var seizures: [SeizureBackup]
    var moods: [MoodBackup]
    var observations: [ObservationBackup]
    var symptoms: [SymptomBackup]
    var revisions: [RevisionBackup]

    static let currentVersion: Int = 1

    // MARK: - Backup sub-structs (mirror du modèle SwiftData)

    struct ChildBackup: Codable {
        let id: UUID
        let firstName: String
        let lastName: String
        let birthDate: Date?
        let hasEpilepsy: Bool
        let sexRaw: String
        let createdAt: Date
    }

    struct MedicationBackup: Codable {
        let id: UUID
        let name: String
        let doseAmount: Double
        let doseUnitRaw: String
        let kindRaw: String
        let isActive: Bool
        let notifyEnabled: Bool
        let createdAt: Date
        let intakes: [MedicationIntake]
        let childProfileId: UUID?
    }

    struct LogBackup: Codable {
        let id: UUID
        let medicationId: UUID
        let medicationName: String
        let scheduledTime: Date
        let takenTime: Date?
        let taken: Bool
        let dose: Double
        let doseUnitRaw: String
        let childProfileId: UUID?
        let isAdHoc: Bool
        let adhocReason: String
    }

    struct SeizureBackup: Codable {
        let id: UUID
        let startTime: Date
        let endTime: Date
        let seizureTypeRaw: String
        let triggerRaw: String
        let triggerNotes: String
        let notes: String
        let childProfileId: UUID?
    }

    struct MoodBackup: Codable {
        let id: UUID
        let timestamp: Date
        let levelRaw: Int
        let notes: String
        let childProfileId: UUID?
    }

    struct ObservationBackup: Codable {
        let id: UUID
        let dayStart: Date
        let breakfastRatingRaw: Int
        let breakfastNotes: String
        let lunchRatingRaw: Int
        let lunchNotes: String
        let snackRatingRaw: Int
        let snackNotes: String
        let dinnerRatingRaw: Int
        let dinnerNotes: String
        let hydrationRatingRaw: Int
        let hydrationNotes: String
        let nightSleepRatingRaw: Int
        let nightSleepDurationMinutes: Int
        let nightSleepNotes: String
        let napDurationMinutes: Int
        let napNotes: String
        let generalNotes: String
        let childProfileId: UUID?
    }

    struct SymptomBackup: Codable {
        let id: UUID
        let timestamp: Date
        let symptomTypeRaw: String
        let intensityRaw: Int
        let durationMinutes: Int
        let notes: String
        let childProfileId: UUID?
    }

    struct RevisionBackup: Codable {
        let id: UUID
        let medicationId: UUID
        let effectiveFrom: Date
        let name: String
        let doseAmount: Double
        let doseUnitRaw: String
        let kindRaw: String
        let isActive: Bool
        let notifyEnabled: Bool
        let intakes: [MedicationIntake]
    }
}
