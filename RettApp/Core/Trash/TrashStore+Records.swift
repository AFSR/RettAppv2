import Foundation
import SwiftData

/// Dépôts en corbeille par type d'enregistrement.
///
/// Chaque méthode fabrique une sauvegarde ne contenant que l'élément
/// supprimé, puis la confie à `TrashStore`. Les champs sont recopiés avec la
/// même correspondance que l'export complet, pour qu'une restauration passe
/// par le chemin d'import déjà durci plutôt que par un second, parallèle, qui
/// finirait par diverger.
///
/// À appeler **avant** `context.delete(...)` : après, l'objet n'est plus
/// lisible.
extension TrashStore {

    /// Sauvegarde vide, à remplir d'un seul élément.
    static func emptyBackup() -> CombinedBackup {
        CombinedBackup(
            version: CombinedBackup.currentVersion,
            exportedAt: Date(),
            child: nil,
            medications: [],
            medicationLogs: [],
            seizures: [],
            moods: [],
            observations: [],
            symptoms: [],
            revisions: [],
            children: nil
        )
    }

    // MARK: - Crises

    static func record(seizure s: SeizureEvent) {
        var payload = emptyBackup()
        payload.seizures = [
            CombinedBackup.SeizureBackup(
                id: s.id, startTime: s.startTime, endTime: s.endTime,
                seizureTypeRaw: s.seizureTypeRaw, triggerRaw: s.triggerRaw,
                triggerNotes: s.triggerNotes, notes: s.notes,
                childProfileId: s.childProfileId,
                lastModifiedAt: s.lastModifiedAt, authorName: s.authorName
            )
        ]

        let quand = s.startTime.formatted(date: .abbreviated, time: .shortened)
        record(
            recordName: s.id.uuidString,
            recordType: CKRecordType.seizure,
            summary: "Crise — \(s.seizureType.label), \(quand)",
            payload: payload
        )
    }

    // MARK: - Médicaments

    /// Le médicament seul : ses prises déjà cochées sont des faits médicaux
    /// qui restent en base, et les prises à venir non cochées sont nettoyées
    /// séparément par `MedicationLog.purgeObsoleteScheduledLogs`. Restaurer le
    /// médicament rétablit donc le plan sans ressusciter d'historique.
    static func record(medication m: Medication) {
        var payload = emptyBackup()
        payload.medications = [
            CombinedBackup.MedicationBackup(
                id: m.id, name: m.name, doseAmount: m.doseAmount,
                doseUnitRaw: m.doseUnitRaw, kindRaw: m.kindRaw,
                isActive: m.isActive, notifyEnabled: m.notifyEnabled,
                createdAt: m.createdAt, intakes: m.intakes,
                childProfileId: m.childProfile?.id,
                lastModifiedAt: m.lastModifiedAt
            )
        ]

        record(
            recordName: m.id.uuidString,
            recordType: CKRecordType.medication,
            summary: "Médicament — \(m.name) \(m.doseLabel)",
            payload: payload
        )
    }

    // MARK: - Prises

    /// Une prise supprimée depuis le journal.
    ///
    /// Elle passait auparavant par un `context.delete` nu : la suppression
    /// n'était pas opposable, l'appareil de l'autre parent la repoussait au
    /// cycle suivant, et la prise revenait d'entre les morts chez celui qui
    /// l'avait retirée.
    static func record(log l: MedicationLog) {
        var payload = emptyBackup()
        payload.medicationLogs = [
            CombinedBackup.LogBackup(
                id: l.id, medicationId: l.medicationId,
                medicationName: l.medicationName,
                scheduledTime: l.scheduledTime, takenTime: l.takenTime,
                taken: l.taken, dose: l.dose, doseUnitRaw: l.doseUnitRaw,
                childProfileId: l.childProfileId,
                isAdHoc: l.isAdHoc, adhocReason: l.adhocReason,
                lastModifiedAt: l.lastModifiedAt, authorName: l.authorName
            )
        ]

        let quand = l.effectiveTime.formatted(date: .abbreviated, time: .shortened)
        record(
            recordName: l.id.uuidString,
            recordType: CKRecordType.medicationLog,
            summary: "Prise — \(l.medicationName), \(quand)",
            payload: payload
        )
    }

    // MARK: - Humeur

    static func record(mood m: MoodEntry) {
        var payload = emptyBackup()
        payload.moods = [
            CombinedBackup.MoodBackup(
                id: m.id, timestamp: m.timestamp, levelRaw: m.levelRaw,
                notes: m.notes, childProfileId: m.childProfileId,
                lastModifiedAt: m.lastModifiedAt, authorName: m.authorName
            )
        ]

        let quand = m.timestamp.formatted(date: .abbreviated, time: .shortened)
        record(
            recordName: m.id.uuidString,
            recordType: CKRecordType.mood,
            summary: "Humeur — \(m.level.label), \(quand)",
            payload: payload
        )
    }

    // MARK: - Symptômes

    static func record(symptom s: SymptomEvent) {
        var payload = emptyBackup()
        payload.symptoms = [
            CombinedBackup.SymptomBackup(
                id: s.id, timestamp: s.timestamp,
                symptomTypeRaw: s.symptomTypeRaw, intensityRaw: s.intensityRaw,
                durationMinutes: s.durationMinutes, notes: s.notes,
                childProfileId: s.childProfileId,
                lastModifiedAt: s.lastModifiedAt, authorName: s.authorName
            )
        ]

        let quand = s.timestamp.formatted(date: .abbreviated, time: .shortened)
        record(
            recordName: s.id.uuidString,
            recordType: CKRecordType.symptom,
            summary: "Symptôme — \(s.symptomType.label), \(quand)",
            payload: payload
        )
    }
}
