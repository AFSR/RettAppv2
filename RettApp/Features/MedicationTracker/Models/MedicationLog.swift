import Foundation
import SwiftData
import CryptoKit

@Model
final class MedicationLog {
    @Attribute(.unique) var id: UUID
    var medicationId: UUID
    var medicationName: String
    var scheduledTime: Date
    var takenTime: Date?
    var taken: Bool
    var dose: Double
    var doseUnitRaw: String
    var childProfileId: UUID?
    var exportedToHealthKit: Bool

    /// Marqueur pour les prises ponctuelles (saisies à la volée), par opposition
    /// aux prises planifiées issues d'un Medication récurrent.
    /// Default false → préserve les logs existants.
    var isAdHoc: Bool = false
    /// Raison libre pour les prises ponctuelles (« fièvre », « post-crise », etc.).
    var adhocReason: String = ""
    /// Tie-breaker last-writer-wins pour la synchro CloudKit (cf. SyncTimestamped).
    var lastModifiedAt: Date = Date()

    var doseUnit: DoseUnit {
        get { DoseUnit(rawValue: doseUnitRaw) ?? .mg }
        set { doseUnitRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        medicationId: UUID,
        medicationName: String,
        scheduledTime: Date,
        takenTime: Date? = nil,
        taken: Bool = false,
        dose: Double,
        doseUnit: DoseUnit,
        childProfileId: UUID? = nil,
        exportedToHealthKit: Bool = false,
        isAdHoc: Bool = false,
        adhocReason: String = ""
    ) {
        self.id = id
        self.medicationId = medicationId
        self.medicationName = medicationName
        self.scheduledTime = scheduledTime
        self.takenTime = takenTime
        self.taken = taken
        self.dose = dose
        self.doseUnitRaw = doseUnit.rawValue
        self.childProfileId = childProfileId
        self.exportedToHealthKit = exportedToHealthKit
        self.isAdHoc = isAdHoc
        self.adhocReason = adhocReason
    }

    var isLate: Bool {
        guard !taken && !isAdHoc else { return false }
        return Date().timeIntervalSince(scheduledTime) > 30 * 60
    }

    /// Heure pertinente : `takenTime` pour ad-hoc / pris, `scheduledTime` sinon.
    var effectiveTime: Date {
        takenTime ?? scheduledTime
    }

    /// UUID déterministe pour une prise programmée d'après `(medicationId, scheduledTime)`.
    /// Les deux parents génèrent donc le MÊME identifiant pour une même dose planifiée →
    /// CloudKit fait un upsert au lieu de créer un doublon. Utilisé UNIQUEMENT pour les
    /// prises auto-générées par le plan ; les prises ad-hoc gardent un UUID aléatoire.
    static func stableId(medicationId: UUID, scheduledTime: Date) -> UUID {
        let unix = Int(scheduledTime.timeIntervalSince1970)
        let seed = "afsr.medlog.v1|\(medicationId.uuidString)|\(unix)"
        var digest = Array(Insecure.MD5.hash(data: Data(seed.utf8)))
        // Version 5 (name-based), variante RFC 4122 : conforme au format UUID.
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        let bytes: uuid_t = (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        )
        return UUID(uuid: bytes)
    }
}

extension MedicationLog: SyncTimestamped, UUIDIdentified {
    static var syncRecordType: String { CKRecordType.medicationLog }
}

// MARK: - Dedup

extension MedicationLog {
    /// UUIDs des « perdants » supprimés par le dernier passage de dedup —
    /// utile pour supprimer les CKRecord correspondants dans CloudKit et
    /// éviter qu'ils ne réapparaissent au prochain pull.
    private static let deletedIdsBufferKey = "afsr.medlog.dedup.deletedIds.v1"

    /// Version « premier lancement » : appelée depuis `RettAppApp.task`, elle
    /// est aussi idempotente pour être ré-appelée à volonté après un pull.
    /// L'ancien flag one-shot est retiré : les doublons peuvent réapparaître à
    /// tout moment via un pull CloudKit d'un log hérité (UUID aléatoire), donc
    /// on veut pouvoir re-collapser.
    static func dedupeScheduledLogsIfNeeded(in context: ModelContext) {
        do {
            try dedupeScheduledLogs(in: context)
        } catch {
            print("⚠️ dedupeScheduledLogs a échoué : \(error.localizedDescription)")
        }
    }

    /// Collapse les prises planifiées qui partagent `(medicationId, scheduledTime)`
    /// en gardant celle qui compte le plus (prise > récente > id lexicographique).
    /// Retourne le nombre de logs fusionnés.
    @discardableResult
    static func dedupeScheduledLogs(in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<MedicationLog>(
            predicate: #Predicate { $0.isAdHoc == false }
        )
        let all = try context.fetch(descriptor)
        // Groupe par (medicationId, scheduledTime tronqué à la seconde).
        var groups: [String: [MedicationLog]] = [:]
        for log in all {
            let key = "\(log.medicationId.uuidString)|\(Int(log.scheduledTime.timeIntervalSince1970))"
            groups[key, default: []].append(log)
        }
        var merged = 0
        var deletedIds: [String] = []
        for (_, logs) in groups where logs.count > 1 {
            // On garde le survivant : priorité à « pris », puis au plus récent
            // (lastModifiedAt), puis au plus vieux id (déterministe).
            let survivor = logs.max { lhs, rhs in
                if lhs.taken != rhs.taken { return !lhs.taken && rhs.taken }
                if lhs.lastModifiedAt != rhs.lastModifiedAt { return lhs.lastModifiedAt < rhs.lastModifiedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }!
            for log in logs where log !== survivor {
                deletedIds.append(log.id.uuidString)
                context.delete(log)
                merged += 1
            }
        }
        if merged > 0 {
            // saveTouching enqueue automatiquement les deletes dans
            // PendingWriteStore → le prochain drain les propage à CloudKit.
            try context.saveTouching()
            appendDeletedIdsBuffer(deletedIds)
            print("ℹ️ MedicationLog dedup : \(merged) doublon(s) fusionné(s)")
        }
        return merged
    }

    /// Récupère et vide la liste des UUIDs supprimés par les derniers passages
    /// de dedup, pour que le service de sync les supprime aussi côté CloudKit.
    static func drainDeletedIdsFromDedup() -> [UUID] {
        let defaults = UserDefaults.standard
        let raw = (defaults.stringArray(forKey: deletedIdsBufferKey) ?? [])
        defaults.removeObject(forKey: deletedIdsBufferKey)
        return raw.compactMap(UUID.init(uuidString:))
    }

    private static func appendDeletedIdsBuffer(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let defaults = UserDefaults.standard
        var current = defaults.stringArray(forKey: deletedIdsBufferKey) ?? []
        current.append(contentsOf: ids)
        defaults.set(current, forKey: deletedIdsBufferKey)
    }
}
