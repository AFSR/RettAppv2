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

extension MedicationLog: SyncTimestamped {}

// MARK: - Dedup migration

extension MedicationLog {
    private static let dedupFlagKey = "afsr.medlog.stableIdDedupDone.v1"

    /// Migration one-shot : les versions antérieures créaient les prises planifiées
    /// avec un UUID aléatoire côté chaque parent, ce qui produisait des doublons
    /// via CloudKit. On collapse ici les prises qui partagent
    /// `(medicationId, scheduledTime, isAdHoc=false)` en gardant la plus significative
    /// (« prise » l'emporte, puis la plus récemment modifiée), puis on la ré-idente
    /// avec l'UUID déterministe pour converger avec l'autre parent au prochain sync.
    static func dedupeScheduledLogsIfNeeded(in context: ModelContext) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: dedupFlagKey) { return }
        do {
            try dedupeScheduledLogs(in: context)
            defaults.set(true, forKey: dedupFlagKey)
        } catch {
            print("⚠️ dedupeScheduledLogs a échoué : \(error.localizedDescription)")
        }
    }

    static func dedupeScheduledLogs(in context: ModelContext) throws {
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
        for (_, logs) in groups where logs.count > 1 {
            // On garde le survivant : priorité à « pris », puis au plus récent
            // (lastModifiedAt), puis au plus vieux id (déterministe).
            let survivor = logs.max { lhs, rhs in
                if lhs.taken != rhs.taken { return !lhs.taken && rhs.taken }
                if lhs.lastModifiedAt != rhs.lastModifiedAt { return lhs.lastModifiedAt < rhs.lastModifiedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }!
            for log in logs where log !== survivor {
                context.delete(log)
                merged += 1
            }
        }
        if merged > 0 {
            try context.save()
            print("ℹ️ MedicationLog dedup : \(merged) doublon(s) fusionné(s)")
        }
    }
}
