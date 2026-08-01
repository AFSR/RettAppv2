import Foundation
import SwiftData

/// Modèles qui participent à la synchronisation CloudKit.
///
/// - `lastModifiedAt` : timestamp last-writer-wins pour arbitrer les conflits
///   entre local et distant côté pull.
/// - `syncRecordName` / `syncRecordType` : identifient le CKRecord côté serveur.
///   Utilisés par `saveTouching()` pour alimenter automatiquement le
///   `PendingWriteStore` — plus besoin d'appeler `sync.markUpsert(...)` à la
///   main sur chaque site d'écriture.
protocol SyncTimestamped: AnyObject {
    var lastModifiedAt: Date { get set }
    /// Identifiant CKRecord — par convention `id.uuidString` pour tous nos modèles.
    var syncRecordName: String { get }
    /// Type CKRecord — utilise les constantes de `CKRecordType`.
    static var syncRecordType: String { get }
}

/// Modèles qui exposent un `id: UUID` (tous nos modèles synchronisés le font).
/// Fournit une conformance par défaut à `syncRecordName`.
protocol UUIDIdentified {
    var id: UUID { get }
}
extension SyncTimestamped where Self: UUIDIdentified {
    var syncRecordName: String { id.uuidString }
}

extension ModelContext {
    /// Save qui :
    /// 1. Stampe `lastModifiedAt = now` sur tous les `SyncTimestamped` insérés/modifiés
    ///    (base du LWW côté pull).
    /// 2. Enregistre dans `PendingWriteStore` un upsert pour chaque
    ///    inséré/modifié et un delete pour chaque supprimé (base du push
    ///    fiable côté drain — survit crash/offline).
    /// 3. Persiste réellement via `save()`.
    ///
    /// **À utiliser à la place de `try? save()` partout** où l'écriture doit
    /// propager via CloudKit Sharing. Si on oublie, la modif reste locale et
    /// ne remontera pas chez l'autre parent.
    /// - Parameter stampingTimestamps: `true` (défaut) pour les écritures
    ///   utilisateur normales — le LWW doit refléter « modifié maintenant ».
    ///   `false` pour les restaurations/imports qui doivent conserver les
    ///   timestamps d'origine : les données restaurées sont bien re-poussées,
    ///   mais si CloudKit détient une version plus récente, elle gagne —
    ///   restaurer un vieux fichier ne fait pas régresser l'autre parent.
    func saveTouching(stampingTimestamps: Bool = true) throws {
        let now = Date()

        // 1) Snapshot des modèles concernés AVANT save (les arrays sont
        //    vidés une fois le save appliqué).
        let inserted = insertedModelsArray
        let changed = changedModelsArray
        let deleted = deletedModelsArray

        // 2) Timestamp LWW sur les upserts.
        if stampingTimestamps {
            for model in inserted + changed {
                if let t = model as? any SyncTimestamped {
                    t.lastModifiedAt = now
                }
            }
        }

        // 3) Capture des clés (type, recordName) AVANT save — accéder aux
        //    propriétés d'un modèle supprimé après le save peut fauter.
        let upsertKeys: [(String, String)] = (inserted + changed).compactMap { model in
            (model as? any SyncTimestamped).map { (type(of: $0).syncRecordType, $0.syncRecordName) }
        }
        let deleteKeys: [(String, String)] = deleted.compactMap { model in
            (model as? any SyncTimestamped).map { (type(of: $0).syncRecordType, $0.syncRecordName) }
        }

        // 4) Persister D'ABORD. L'enqueue vient APRÈS le save réussi :
        //    si on enfilait avant et que save() échouait, le drain pousserait
        //    quand même les suppressions vers CloudKit (donc chez l'autre
        //    parent) pour des records encore vivants localement — et le pull
        //    suivant détruirait la copie locale. Ordre inverse = un échec de
        //    save laisse le monde intact (les entrées seront ré-enfilées au
        //    prochain saveTouching réussi).
        try save()

        // 5) Enqueue dans le buffer persistant. On ne push pas ici : c'est le
        //    job du service de sync (drain + retry + back-off + LWW).
        for (recordType, recordName) in upsertKeys {
            PendingWriteStore.shared.markUpsert(recordType: recordType, recordName: recordName)
        }
        for (recordType, recordName) in deleteKeys {
            PendingWriteStore.shared.markDelete(recordType: recordType, recordName: recordName)
        }
    }
}

/// Résout un conflit entre un état local et un état distant via leurs
/// timestamps `lastModifiedAt`. Retourne `true` si l'incoming doit écraser
/// le local. Pure fonction → facilement testable sans CloudKit ni SwiftData.
///
/// - Note : les égalités strictes (même milliseconde) penchent par défaut
///   pour l'incoming, ce qui correspond à un push depuis l'autre parent
///   très peu après une écriture locale — c'est sûr (les deux côtés
///   convergent vers la même valeur).
enum SyncConflictResolver {
    static func shouldAcceptIncoming(local: Date?, incoming: Date?) -> Bool {
        switch (local, incoming) {
        case (nil, _): return true                    // pas d'état local : on accepte
        case (_, nil): return false                   // remote sans timestamp : on garde local
        case (let l?, let r?): return r >= l          // remote ≥ local → on accepte
        }
    }
}
