import CloudKit
import Foundation

/// Circulation des suppressions entre parents.
///
/// ## Le problème que ça règle
///
/// Supprimer un enregistrement le retire de CloudKit, et l'autre appareil
/// reçoit la suppression. Mais rien ne dit *qu'il a été supprimé* : si cet
/// appareil repousse ensuite sa copie — parce qu'il était hors ligne, parce
/// qu'une écriture en attente datait d'avant, parce qu'une restauration l'a
/// réinséré — l'enregistrement renaît, et le parent qui l'avait retiré le
/// voit revenir.
///
/// Une pierre tombale est la réponse : un enregistrement durable qui dit
/// « l'identifiant X a été supprimé à telle heure ». Elle circule comme
/// n'importe quelle donnée, et transforme la suppression en une écriture
/// horodatée comme les autres. La règle devient alors la même que pour le
/// reste : **le plus récent gagne**. Une pierre tombale postérieure à la
/// dernière modification d'un enregistrement entrant le refuse ; une
/// modification postérieure à la pierre tombale la périme.
///
/// ## Nommage
///
/// `tomb_<identifiant supprimé>` : déterministe, donc deux appareils qui
/// suppriment le même enregistrement écrivent la même pierre tombale au lieu
/// d'en créer deux. Le préfixe évite de réutiliser le nom de l'enregistrement
/// défunt, ce qui mélangerait les deux dans les journaux et les outils.
extension TrashStore {

    static let recordNamePrefix = "tomb_"

    static func cloudRecordName(forTarget target: String) -> String {
        recordNamePrefix + target
    }

    /// Identifiant visé par une pierre tombale, ou `nil` si le nom n'en est
    /// pas une.
    static func target(fromCloudRecordName name: String) -> String? {
        guard name.hasPrefix(recordNamePrefix) else { return nil }
        return String(name.dropFirst(recordNamePrefix.count))
    }

    private enum Field {
        static let targetRecordName = "targetRecordName"
        static let targetRecordType = "targetRecordType"
        static let deletedAt = "deletedAt"
    }

    // MARK: - Vers CloudKit

    /// Construit la pierre tombale à pousser pour un enregistrement supprimé.
    /// `nil` si la corbeille ne connaît pas cet identifiant — l'entrée de
    /// poussée est alors sans objet et sera abandonnée.
    static func makeCloudRecord(forTarget target: String, zoneID: CKRecordZone.ID) -> CKRecord? {
        guard let item = (items().first { $0.recordName == target }) else { return nil }

        let id = CKRecord.ID(recordName: cloudRecordName(forTarget: target), zoneID: zoneID)
        let record = CKRecord(recordType: CKRecordType.tombstone, recordID: id)
        record[Field.targetRecordName] = target as CKRecordValue
        record[Field.targetRecordType] = item.recordType as CKRecordValue
        record[Field.deletedAt] = item.deletedAt as CKRecordValue
        // Le champ commun de résolution de conflit, pour que la pierre
        // tombale se compare aux autres enregistrements avec la même règle.
        record[SyncFields.lastModifiedAt] = item.deletedAt as CKRecordValue
        return record
    }

    // MARK: - Depuis CloudKit

    /// Enregistre localement une pierre tombale reçue de l'autre parent.
    ///
    /// On la dépose dans la corbeille comme si la suppression avait eu lieu
    /// ici : elle y est visible, récupérable, et surtout elle protège cet
    /// appareil contre une réinsertion. La charge utile est vide — le contenu
    /// supprimé n'a pas voyagé, seule la suppression l'a fait — donc une
    /// restauration depuis cet appareil ne rétablit rien ; c'est pourquoi
    /// l'écran de corbeille n'offre pas la restauration de ces entrées-là.
    static func applyCloudRecord(_ ck: CKRecord) {
        guard ck.recordType == CKRecordType.tombstone,
              let target = ck[Field.targetRecordName] as? String,
              let deletedAt = ck[Field.deletedAt] as? Date
        else { return }

        let type = (ck[Field.targetRecordType] as? String) ?? "?"

        // Déjà connue et au moins aussi récente : rien à faire. Sans ce
        // garde-fou, chaque pull réécrirait le fichier et reposterait une
        // notification de changement.
        if let connue = (items().first { $0.recordName == target }), connue.deletedAt >= deletedAt {
            return
        }

        record(
            recordName: target,
            recordType: type,
            summary: summaryForRemote(type: type, deletedAt: deletedAt),
            payload: emptyBackup(),
            deletedAt: deletedAt,
            restorable: false
        )
    }

    /// Un enregistrement entrant doit-il être refusé parce qu'il a été
    /// supprimé plus récemment qu'il n'a été modifié ?
    ///
    /// C'est la même règle que partout ailleurs — le plus récent gagne —
    /// appliquée à la suppression. Un enregistrement modifié APRÈS la
    /// suppression la périme et doit passer : quelqu'un l'a délibérément
    /// recréé ou restauré.
    static func shouldRejectIncoming(recordName: String, lastModifiedAt: Date?) -> Bool {
        guard let item = (items().first { $0.recordName == recordName }) else { return false }
        guard let lastModifiedAt else {
            // Pas d'horodatage : on ne peut pas dater la modification, donc on
            // ne peut pas affirmer qu'elle est postérieure. La suppression,
            // elle, est datée — elle gagne.
            return true
        }
        return item.deletedAt > lastModifiedAt
    }

    private static func summaryForRemote(type: String, deletedAt: Date) -> String {
        let quoi: String
        switch type {
        case CKRecordType.seizure:           quoi = "Crise"
        case CKRecordType.medication:        quoi = "Médicament"
        case CKRecordType.medicationLog:     quoi = "Prise"
        case CKRecordType.mood:              quoi = "Humeur"
        case CKRecordType.symptom:           quoi = "Symptôme"
        case CKRecordType.dailyObservation:  quoi = "Observation du jour"
        case CKRecordType.childProfile:      quoi = "Profil"
        default:                             quoi = "Élément"
        }
        return "\(quoi) supprimé par l'autre parent"
    }
}
