import Foundation
import SwiftData

/// Modèles qui veulent participer à la résolution explicite de conflit
/// last-writer-wins via CloudKit Sharing. Chaque write local doit toucher
/// `lastModifiedAt` (idéalement via `ModelContext.saveTouching()`) ; le
/// timestamp est répliqué dans le CKRecord et comparé côté pull pour
/// arbitrer entre l'état local et l'état distant.
protocol SyncTimestamped: AnyObject {
    var lastModifiedAt: Date { get set }
}

extension ModelContext {
    /// Variante de `save()` qui met à jour `lastModifiedAt = Date()` sur tous
    /// les modèles `SyncTimestamped` insérés ou modifiés depuis le dernier
    /// save, avant de persister. C'est le point central de la résolution de
    /// conflit : sans cet appel, les CKRecord poussés vers iCloud auraient
    /// un timestamp obsolète et perdraient les arbitrages contre l'état
    /// distant.
    ///
    /// À utiliser à la place de `try? modelContext.save()` partout où une
    /// écriture doit propager via CloudKit Sharing.
    func saveTouching() throws {
        let now = Date()
        for model in insertedModelsArray + changedModelsArray {
            if let timestamped = model as? any SyncTimestamped {
                timestamped.lastModifiedAt = now
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
