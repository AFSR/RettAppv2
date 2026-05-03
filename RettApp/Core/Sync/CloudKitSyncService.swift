import Foundation
import CloudKit
import SwiftData
import Observation
import os.log

/// Orchestre la synchronisation entre les deux parents via CloudKit Sharing.
///
/// Architecture :
/// - Une zone CKRecordZone unique « FamilyData » contient tous les records partagés
/// - Le parent **propriétaire** crée la zone dans sa privateCloudDatabase puis crée un
///   `CKShare` sur la zone. L'URL du share est envoyée au second parent (Messages, Mail).
/// - Le parent **invité** accepte le share via `RettAppSceneDelegate` (callback système),
///   la zone apparaît dans sa sharedCloudDatabase, identique en lecture/écriture.
/// - `replicateAll()` pousse tout SwiftData → CloudKit (utilisé au moment du partage initial)
/// - `pullChanges()` ramène tout CloudKit → SwiftData (utilisé après acceptation et au refresh manuel)
///
/// Limites V1 :
/// - Sync manuelle (bouton "Synchroniser maintenant") — pas encore de
///   `CKDatabaseSubscription` pour notifs push instantanées
/// - Résolution de conflits last-writer-wins (basée sur le timestamp serveur CloudKit)
@Observable
@MainActor
final class CloudKitSyncService {

    static let containerID = "iCloud.fr.afsr.RettApp"
    static let zoneName = "FamilyData"

    private static let log = Logger(subsystem: "fr.afsr.RettApp", category: "Sync")

    enum AccountStatus: Equatable {
        case unknown
        case available
        case noAccount
        case restricted
        case unavailable
    }

    enum ShareRole: Equatable {
        case none
        case owner
        case participant
    }

    enum SyncState: Equatable {
        case idle
        case syncing
        case error(String)
    }

    // MARK: - Observable state

    var accountStatus: AccountStatus = .unknown
    var syncState: SyncState = .idle
    var role: ShareRole = .none
    var lastSyncedAt: Date?
    var participantCount: Int = 0
    var lastErrorMessage: String?

    // MARK: - Internals

    private let container: CKContainer
    private(set) var currentShare: CKShare?
    private var ownedZone: CKRecordZone?

    /// Token de changements pour les pulls incrémentaux (par database scope).
    private var changeTokenPrivate: CKServerChangeToken?
    private var changeTokenShared: CKServerChangeToken?

    init() {
        self.container = CKContainer(identifier: Self.containerID)
    }

    // MARK: - Account

    func refreshAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                accountStatus = .available
            case .noAccount:
                accountStatus = .noAccount
            case .restricted:
                accountStatus = .restricted
            case .couldNotDetermine, .temporarilyUnavailable:
                accountStatus = .unavailable
            @unknown default:
                accountStatus = .unavailable
            }
        } catch {
            accountStatus = .unavailable
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Zone setup

    /// S'assure que la zone partagée existe (créée à la demande, idempotent).
    @discardableResult
    private func ensureZone() async throws -> CKRecordZone {
        if let ownedZone { return ownedZone }
        let zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        // Tentative de fetch d'abord
        do {
            let zone = try await container.privateCloudDatabase.recordZone(for: zoneID)
            ownedZone = zone
            return zone
        } catch let error as CKError where error.code == .zoneNotFound {
            // Création
            let zone = CKRecordZone(zoneID: zoneID)
            let saved = try await container.privateCloudDatabase.save(zone)
            ownedZone = saved
            return saved
        }
    }

    // MARK: - Share creation (côté propriétaire)

    /// Crée (ou récupère) un CKShare sur la zone et retourne l'URL d'invitation.
    /// L'URL est à envoyer au second parent par Messages, Mail ou AirDrop.
    func setupSharing(childProfile: ChildProfile?) async throws -> URL {
        try await ensureSignedIn()
        syncState = .syncing
        defer {
            if case .syncing = syncState { syncState = .idle }
        }

        let zone = try await ensureZone()

        // Si on a déjà un share local, on le retourne. Sinon, on essaie de fetch ou crée.
        if let share = currentShare, let url = share.url {
            return url
        }

        let shareRecordID = CKRecord.ID(
            recordName: "share-\(zone.zoneID.zoneName)",
            zoneID: zone.zoneID
        )

        // Tentative de fetch
        do {
            let record = try await container.privateCloudDatabase.record(for: shareRecordID)
            if let existing = record as? CKShare {
                currentShare = existing
                role = .owner
                if let url = existing.url { return url }
            }
        } catch let error as CKError where error.code == .unknownItem {
            // pas de share existant, on crée
        }

        let share = CKShare(recordZoneID: zone.zoneID)
        share[CKShare.SystemFieldKey.title] = "Suivi RettApp — \(childProfile?.fullName ?? "enfant")" as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "fr.afsr.RettApp.familyShare" as CKRecordValue
        // L'URL grants accès à toute personne avec le lien — sécurité repose sur
        // la transmission AirDrop en présentiel uniquement (cf. ProximityShareSheet
        // côté UI, qui exclut tous les canaux à distance).
        share.publicPermission = .readWrite

        _ = try await container.privateCloudDatabase.modifyRecords(
            saving: [share], deleting: [],
            savePolicy: .ifServerRecordUnchanged
        )

        currentShare = share
        role = .owner

        guard let url = share.url else {
            throw SyncError.shareURLUnavailable
        }
        return url
    }

    /// Récupère le statut de partage actuel (si on est propriétaire ou participant).
    func refreshShareStatus() async {
        do {
            let zone = try await ensureZone()
            let shareRecordID = CKRecord.ID(
                recordName: "share-\(zone.zoneID.zoneName)",
                zoneID: zone.zoneID
            )
            do {
                let record = try await container.privateCloudDatabase.record(for: shareRecordID)
                if let share = record as? CKShare {
                    currentShare = share
                    role = .owner
                    participantCount = max(0, share.participants.count - 1) // exclut le propriétaire
                    return
                }
            } catch let error as CKError where error.code == .unknownItem {
                // pas de share owned
            }

            // Vérifier si on est participant : zone dans sharedCloudDatabase
            let sharedZones = try await container.sharedCloudDatabase.allRecordZones()
            if !sharedZones.isEmpty {
                role = .participant
                return
            }
            role = .none
        } catch {
            Self.log.error("refreshShareStatus error: \(error.localizedDescription)")
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Le propriétaire arrête le partage (supprime le CKShare).
    func stopSharing() async throws {
        guard role == .owner, let share = currentShare else { return }
        syncState = .syncing
        defer { syncState = .idle }
        try await container.privateCloudDatabase.deleteRecord(withID: share.recordID)
        currentShare = nil
        role = .none
        participantCount = 0
    }

    // MARK: - Replication push (CloudKit ←  SwiftData)

    /// Pousse tous les enregistrements SwiftData vers la zone partagée.
    /// Utilisé après création du share, ou pour resynchroniser totalement.
    func replicateAll(from context: ModelContext) async throws {
        try await ensureSignedIn()
        syncState = .syncing
        defer { syncState = .idle }

        let database = appropriateDatabase()
        let zoneID: CKRecordZone.ID
        if role == .participant {
            // L'invité écrit dans la zone partagée déjà existante de l'autre côté
            let zones = try await container.sharedCloudDatabase.allRecordZones()
            guard let zone = zones.first else {
                throw SyncError.shareURLUnavailable
            }
            zoneID = zone.zoneID
        } else {
            let zone = try await ensureZone()
            zoneID = zone.zoneID
        }

        var records: [CKRecord] = []

        if let profiles = try? context.fetch(FetchDescriptor<ChildProfile>()) {
            records.append(contentsOf: profiles.map { $0.toCKRecord(zoneID: zoneID) })
        }
        if let meds = try? context.fetch(FetchDescriptor<Medication>()) {
            records.append(contentsOf: meds.map { $0.toCKRecord(zoneID: zoneID) })
        }
        if let logs = try? context.fetch(FetchDescriptor<MedicationLog>()) {
            records.append(contentsOf: logs.map { $0.toCKRecord(zoneID: zoneID) })
        }
        if let seizures = try? context.fetch(FetchDescriptor<SeizureEvent>()) {
            records.append(contentsOf: seizures.map { $0.toCKRecord(zoneID: zoneID) })
        }
        if let moods = try? context.fetch(FetchDescriptor<MoodEntry>()) {
            records.append(contentsOf: moods.map { $0.toCKRecord(zoneID: zoneID) })
        }
        if let obs = try? context.fetch(FetchDescriptor<DailyObservation>()) {
            records.append(contentsOf: obs.map { $0.toCKRecord(zoneID: zoneID) })
        }

        if records.isEmpty {
            Self.log.info("replicateAll: aucun enregistrement local à pousser")
            lastSyncedAt = Date()
            return
        }

        // Push par batch de 200 (limite raisonnable pour CloudKit)
        let batchSize = 200
        var offset = 0
        while offset < records.count {
            let end = min(offset + batchSize, records.count)
            let chunk = Array(records[offset..<end])
            _ = try await database.modifyRecords(
                saving: chunk, deleting: [],
                savePolicy: .changedKeys
            )
            offset = end
        }

        lastSyncedAt = Date()
        Self.log.info("replicateAll OK : \(records.count) records poussés")
    }

    // MARK: - Pull (CloudKit → SwiftData)

    /// Tire tous les changements depuis CloudKit vers SwiftData.
    func pullChanges(into context: ModelContext) async throws {
        try await ensureSignedIn()
        syncState = .syncing
        defer { syncState = .idle }

        // Owner : pull privé. Participant : pull shared.
        let database = appropriateDatabase()
        let scope = appropriateDatabaseScope()

        // Liste des zones à fetcher
        let zoneIDs: [CKRecordZone.ID]
        if scope == .private {
            let zone = try await ensureZone()
            zoneIDs = [zone.zoneID]
        } else {
            let zones = try await database.allRecordZones()
            zoneIDs = zones.map { $0.zoneID }
        }

        if zoneIDs.isEmpty {
            Self.log.info("pullChanges: aucune zone à puller")
            return
        }

        // Pull complet par zone (V1 — pas encore d'incrémental token-based).
        // CloudKit demande un recordType précis par query → on itère sur les 6 types.
        var totalUpserted = 0
        for zoneID in zoneIDs {
            for type in CKRecordType.all {
                let q = CKQuery(recordType: type, predicate: NSPredicate(value: true))
                let (matchResults, _) = try await database.records(
                    matching: q, inZoneWith: zoneID,
                    desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults
                )
                for (_, result) in matchResults {
                    switch result {
                    case .success(let record):
                        upsert(record, in: context)
                        totalUpserted += 1
                    case .failure(let err):
                        Self.log.error("Pull \(type): \(err.localizedDescription)")
                    }
                }
            }
        }

        try? context.save()
        lastSyncedAt = Date()
        Self.log.info("pullChanges OK : \(totalUpserted) records upsertés")
    }

    private func upsert(_ record: CKRecord, in context: ModelContext) {
        switch record.recordType {
        case CKRecordType.childProfile:     ChildProfile.upsert(from: record, in: context)
        case CKRecordType.medication:       Medication.upsert(from: record, in: context)
        case CKRecordType.medicationLog:    MedicationLog.upsert(from: record, in: context)
        case CKRecordType.seizure:          SeizureEvent.upsert(from: record, in: context)
        case CKRecordType.mood:             MoodEntry.upsert(from: record, in: context)
        case CKRecordType.dailyObservation: DailyObservation.upsert(from: record, in: context)
        default: break
        }
    }

    // MARK: - Acceptance

    /// Accepte une invitation reçue (via UICloudShare metadata).
    func acceptShare(_ metadata: CKShare.Metadata) async throws {
        syncState = .syncing
        defer { syncState = .idle }
        try await container.accept(metadata)
        role = .participant
        Self.log.info("Share accepté (rootRecordID=\(metadata.rootRecordID.recordName))")
    }

    // MARK: - Helpers

    private func ensureSignedIn() async throws {
        if accountStatus == .unknown {
            await refreshAccountStatus()
        }
        guard accountStatus == .available else {
            throw SyncError.iCloudUnavailable(accountStatus)
        }
    }

    private func appropriateDatabase() -> CKDatabase {
        role == .participant ? container.sharedCloudDatabase : container.privateCloudDatabase
    }

    private func appropriateDatabaseScope() -> CKDatabase.Scope {
        role == .participant ? .shared : .private
    }
}

// MARK: - Erreurs

enum SyncError: LocalizedError {
    case iCloudUnavailable(CloudKitSyncService.AccountStatus)
    case shareURLUnavailable

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable(let status):
            switch status {
            case .noAccount: return "Aucun compte iCloud connecté. Activez iCloud dans Réglages iOS."
            case .restricted: return "iCloud restreint sur cet appareil (contrôle parental)."
            case .unavailable: return "iCloud temporairement indisponible. Réessayez plus tard."
            default: return "iCloud non disponible."
            }
        case .shareURLUnavailable: return "L'URL de partage n'a pas pu être générée."
        }
    }
}
