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
    func saveTouching() throws {
        let now = Date()

        // 1) Snapshot des modèles concernés AVANT save (deletedModelsArray
        //    disparaît une fois le save appliqué).
        let inserted = insertedModelsArray
        let changed = changedModelsArray
        let deleted = deletedModelsArray

        // 2) Timestamp LWW sur les upserts.
        for model in inserted + changed {
            if let t = model as? any SyncTimestamped {
                t.lastModifiedAt = now
            }
        }

        // 3) Enqueue dans le buffer persistant. On ne push pas ici : c'est le
        //    job du service de sync (drain + retry + back-off + LWW).
        for model in inserted + changed {
            if let t = model as? any SyncTimestamped {
                PendingWriteStore.shared.markUpsert(
                    recordType: type(of: t).syncRecordType,
                    recordName: t.syncRecordName
                )
            }
        }
        for model in deleted {
            if let t = model as? any SyncTimestamped {
                PendingWriteStore.shared.markDelete(
                    recordType: type(of: t).syncRecordType,
                    recordName: t.syncRecordName
                )
            }
        }

        try save()
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
