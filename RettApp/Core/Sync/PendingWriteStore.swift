import Foundation
import os.log

/// Buffer persistant sur disque des écritures locales en attente de push vers
/// CloudKit. Existe pour garantir qu'AUCUNE modification faite localement n'est
/// perdue, même si :
///
/// - le device est hors ligne au moment de la modification,
/// - CloudKit renvoie un rate-limit temporaire,
/// - l'app crashe entre le save SwiftData et le push CloudKit,
/// - l'utilisateur tue l'app en background pendant le debounce.
///
/// Modèle logique :
/// - `upsert(recordType, recordName)` : l'entité identifiée doit être ré-encodée
///   depuis SwiftData et pushée vers CloudKit au prochain drain.
/// - `delete(recordType, recordName)` : le CKRecord doit être supprimé serveur-side.
/// - `drain()` retire et retourne un snapshot atomiquement — l'appelant doit
///   `requeue()` en cas d'échec pour ne rien perdre.
///
/// Sérialisation : JSON dans `Application Support/pending_writes.json`. On
/// n'utilise pas UserDefaults parce que le volume peut atteindre plusieurs
/// centaines d'entrées (batch initial de replicate, plans complets) et que
/// UserDefaults n'est pas dimensionné pour ça.
///
/// Thread-safety : accès en interne via `DispatchQueue` sérielle.
final class PendingWriteStore {
    enum Op: String, Codable {
        case upsert
        case delete
    }

    struct Entry: Codable, Hashable {
        let recordType: String
        let recordName: String
        let op: Op
    }

    /// Notification postée à chaque changement de contenu — les vues d'UI
    /// (bandeau de statut) s'y abonnent pour rafraîchir leur compteur en
    /// temps réel sans polling.
    static let didChangeNotification = Notification.Name("afsr.pendingWrites.didChange")

    static let shared = PendingWriteStore()

    private static let log = Logger(subsystem: "fr.afsr.RettApp", category: "PendingWrites")

    /// Un `Set` ordonné plutôt qu'un array : dédupliquer plusieurs modifications
    /// rapprochées d'un même record en O(1). L'ordre est peu important — le
    /// serveur reçoit le dernier état après fetch SwiftData, pas les intermédiaires.
    private var entries: Set<Entry> = []
    private let queue = DispatchQueue(label: "afsr.pending-writes", qos: .userInitiated)
    private let fileURL: URL

    private init() {
        // ApplicationSupportDirectory persiste entre installations et n'est pas
        // exposé à iTunes/Files — approprié pour un buffer de sync.
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("pending_writes.json")
        self.entries = loadFromDisk()
        Self.log.info("PendingWriteStore chargé avec \(self.entries.count) entrée(s)")
    }

    // MARK: - Public

    /// Ajoute une écriture au buffer. Idempotent — un upsert répété sur le même
    /// (type, name) est un no-op. Un upsert qui suit un delete du même record
    /// annule le delete (l'entité a été recréée localement).
    func markUpsert(recordType: String, recordName: String) {
        queue.sync {
            entries.remove(Entry(recordType: recordType, recordName: recordName, op: .delete))
            entries.insert(Entry(recordType: recordType, recordName: recordName, op: .upsert))
            persist()
        }
    }

    /// Marque un record à supprimer côté serveur. Annule tout upsert en attente
    /// pour le même record.
    func markDelete(recordType: String, recordName: String) {
        queue.sync {
            entries.remove(Entry(recordType: recordType, recordName: recordName, op: .upsert))
            entries.insert(Entry(recordType: recordType, recordName: recordName, op: .delete))
            persist()
        }
    }

    /// Récupère et retire un snapshot du buffer. Si le push échoue, l'appelant
    /// DOIT rappeler `requeue(_:)` pour ne rien perdre.
    func drain() -> [Entry] {
        queue.sync {
            let snapshot = Array(entries)
            entries.removeAll()
            persist()
            return snapshot
        }
    }

    /// Réinjecte les entrées qu'un cycle de push n'a pas réussi à écouler.
    func requeue(_ items: [Entry]) {
        guard !items.isEmpty else { return }
        queue.sync {
            for item in items {
                entries.insert(item)
            }
            persist()
        }
    }

    /// Nombre d'entrées en attente — pour badge UI / diagnostic.
    var pendingCount: Int {
        queue.sync { entries.count }
    }

    /// Purge totale — à réserver aux cas de recovery (share quitté, reset).
    func clear() {
        queue.sync {
            entries.removeAll()
            persist()
        }
    }

    // MARK: - Persistance

    private func loadFromDisk() -> Set<Entry> {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return Set(decoded)
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(Array(entries))
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            Self.log.error("persist KO : \(error.localizedDescription)")
        }
        // Notifie les UI observers depuis la file principale pour être safe
        // vis-à-vis de SwiftUI.
        let count = entries.count
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.didChangeNotification,
                object: nil,
                userInfo: ["count": count]
            )
        }
    }
}
