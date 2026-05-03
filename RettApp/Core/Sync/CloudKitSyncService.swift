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
    /// Métadonnées des autres parents (e-mail / nom Apple ID, statut, droits).
    /// Vide si on n'est pas en partage ou si CloudKit n'a pas encore renvoyé la liste.
    var participants: [ParticipantInfo] = []

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

    /// Récupère le statut de partage actuel (si on est propriétaire ou participant)
    /// **et** la liste des participants associés au share. Les identités proviennent
    /// directement de CloudKit (Apple ID + e-mail si l'utilisateur a accepté de
    /// les exposer côté Réglages iCloud).
    func refreshShareStatus() async {
        do {
            // 1) Tenter le côté propriétaire : la zone existe-t-elle déjà dans la
            //    privateCloudDatabase ? On NE crée PAS la zone ici (à la différence
            //    de `ensureZone`) — sinon on l'amorce involontairement chez un
            //    participant qui n'en a aucune et on perd la détection du rôle.
            let zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
            do {
                _ = try await container.privateCloudDatabase.recordZone(for: zoneID)
                let shareRecordID = CKRecord.ID(
                    recordName: "share-\(zoneID.zoneName)", zoneID: zoneID
                )
                do {
                    let record = try await container.privateCloudDatabase.record(for: shareRecordID)
                    if let share = record as? CKShare {
                        currentShare = share
                        role = .owner
                        let infos = share.participants.map { p in
                        ParticipantInfo(from: p, isOwnerSlot: p.userIdentity.userRecordID == share.owner.userIdentity.userRecordID)
                    }
                        participants = infos
                        // exclut le propriétaire de la "shape" affichée
                        participantCount = max(0, infos.filter { !$0.isOwner }.count)
                        return
                    }
                } catch let error as CKError where error.code == .unknownItem {
                    // pas de share owned
                }
            } catch let error as CKError where error.code == .zoneNotFound {
                // Pas de zone côté privé — on bascule en check participant.
            }

            // 2) Côté participant : zone(s) présente(s) dans la sharedCloudDatabase ?
            let sharedZones = try await container.sharedCloudDatabase.allRecordZones()
            if let firstZone = sharedZones.first {
                role = .participant
                // Tenter de retrouver le CKShare pour exposer les autres participants
                // (en particulier le propriétaire — c'est le plus utile à voir
                //  pour un parent invité).
                if let share = try? await fetchSharedZoneShare(zoneID: firstZone.zoneID) {
                    currentShare = share
                    let infos = share.participants.map { p in
                        ParticipantInfo(from: p, isOwnerSlot: p.userIdentity.userRecordID == share.owner.userIdentity.userRecordID)
                    }
                    participants = infos
                    participantCount = max(0, infos.filter { !$0.isOwner }.count)
                } else {
                    participants = []
                    participantCount = 0
                }
                return
            }
            // 3) Aucun partage en cours
            role = .none
            participants = []
            participantCount = 0
            currentShare = nil
        } catch {
            Self.log.error("refreshShareStatus error: \(error.localizedDescription)")
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Cherche le CKShare attaché à une zone partagée (côté participant).
    /// Le share apparaît comme un record de type `cloudkit.share` lors d'un
    /// fetch des changements de zone.
    private func fetchSharedZoneShare(zoneID: CKRecordZone.ID) async throws -> CKShare? {
        let result = try await container.sharedCloudDatabase.recordZoneChanges(inZoneWith: zoneID, since: nil)
        for (_, modResult) in result.modificationResultsByID {
            if case .success(let mod) = modResult, let share = mod.record as? CKShare {
                return share
            }
        }
        return nil
    }

    /// Le propriétaire arrête le partage (supprime le CKShare).
    /// Effet : tous les invités perdent l'accès immédiatement.
    func stopSharing() async throws {
        guard role == .owner, let share = currentShare else { return }
        syncState = .syncing
        defer { syncState = .idle }
        try await container.privateCloudDatabase.deleteRecord(withID: share.recordID)
        currentShare = nil
        role = .none
        participantCount = 0
        participants = []
        await refreshShareStatus()
    }

    /// Un participant (non propriétaire) quitte un partage en cours.
    ///
    /// La V1 ne faisait que `deleteRecordZone(withID:)` sur la sharedCloudDatabase,
    /// ce qui n'est pas fiable : selon les versions d'iOS, l'opération peut
    /// renvoyer une erreur `.permissionFailure` (un participant n'est pas
    /// propriétaire de la zone) ou réussir localement sans révoquer le share côté
    /// serveur. La méthode officielle est de **supprimer le record CKShare lui-même**
    /// depuis la sharedCloudDatabase — CloudKit interprète ça comme « retire-moi
    /// du partage » et propage la révocation au propriétaire et aux autres invités.
    func leaveShare() async throws {
        guard role == .participant else { return }
        syncState = .syncing
        defer { syncState = .idle }

        let zones = try await container.sharedCloudDatabase.allRecordZones()
        guard !zones.isEmpty else {
            // Plus rien à quitter — on remet l'état à zéro et on sort.
            currentShare = nil
            role = .none
            participantCount = 0
            participants = []
            return
        }

        var leftSomething = false
        for zone in zones {
            // 1) Supprimer le CKShare → c'est ce qui retire le participant du partage.
            if let share = try? await fetchSharedZoneShare(zoneID: zone.zoneID) {
                do {
                    _ = try await container.sharedCloudDatabase.modifyRecords(
                        saving: [], deleting: [share.recordID]
                    )
                    leftSomething = true
                } catch {
                    Self.log.error("leaveShare: échec deleteRecord(share) — \(error.localizedDescription)")
                }
            }
            // 2) Supprimer la zone partagée localement (au cas où le share n'a pas été
            //    trouvé, ou pour s'assurer que la cache locale est purgée).
            do {
                try await container.sharedCloudDatabase.deleteRecordZone(withID: zone.zoneID)
                leftSomething = true
            } catch let err as CKError where err.code == .zoneNotFound {
                // déjà parti, on ignore
            } catch {
                Self.log.error("leaveShare: échec deleteRecordZone — \(error.localizedDescription)")
            }
        }

        currentShare = nil
        role = .none
        participantCount = 0
        participants = []
        // Re-vérifie l'état pour que l'UI reflète la réalité (au cas où une partie
        // des opérations aurait échoué silencieusement).
        await refreshShareStatus()
        if !leftSomething {
            throw SyncError.shareURLUnavailable
        }
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
    /// Utilise `recordZoneChanges` (token-based) plutôt que `CKQuery`, qui exigeait
    /// que `recordName` soit déclaré « queryable » dans le schema CloudKit Console.
    func pullChanges(into context: ModelContext) async throws {
        try await ensureSignedIn()
        syncState = .syncing
        defer { syncState = .idle }

        let database = appropriateDatabase()
        let scope = appropriateDatabaseScope()

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

        var totalUpserted = 0
        var totalDeleted = 0
        for zoneID in zoneIDs {
            // recordZoneChanges (since: nil) ramène TOUTES les modifications.
            // Pas besoin que les fields soient queryable — c'est un fetch par token, pas une query.
            let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: nil)

            for (_, modResult) in result.modificationResultsByID {
                switch modResult {
                case .success(let modification):
                    upsert(modification.record, in: context)
                    totalUpserted += 1
                case .failure(let err):
                    Self.log.error("Pull modif: \(err.localizedDescription)")
                }
            }

            // Suppressions distantes : on supprime localement aussi
            for deletion in result.deletions {
                deleteLocal(recordID: deletion.recordID, in: context)
                totalDeleted += 1
            }
        }

        try? context.save()
        lastSyncedAt = Date()
        Self.log.info("pullChanges OK : \(totalUpserted) upsertés, \(totalDeleted) supprimés")
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

    /// Supprime localement le record correspondant à une suppression CloudKit distante.
    private func deleteLocal(recordID: CKRecord.ID, in context: ModelContext) {
        guard let id = UUID(uuidString: recordID.recordName) else { return }

        // On essaie chacun des 6 types — c'est le moyen le plus simple sans avoir
        // le recordType (Apple ne le donne pas dans CKDatabase.RecordZoneChange.Deletion).
        if let p = try? context.fetch(FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.id == id })).first {
            context.delete(p); return
        }
        if let m = try? context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.id == id })).first {
            context.delete(m); return
        }
        if let l = try? context.fetch(FetchDescriptor<MedicationLog>(predicate: #Predicate { $0.id == id })).first {
            context.delete(l); return
        }
        if let s = try? context.fetch(FetchDescriptor<SeizureEvent>(predicate: #Predicate { $0.id == id })).first {
            context.delete(s); return
        }
        if let m = try? context.fetch(FetchDescriptor<MoodEntry>(predicate: #Predicate { $0.id == id })).first {
            context.delete(m); return
        }
        if let o = try? context.fetch(FetchDescriptor<DailyObservation>(predicate: #Predicate { $0.id == id })).first {
            context.delete(o); return
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

// MARK: - Participant info

/// Vue publique d'un participant CloudKit. Encapsule `CKShare.Participant` pour
/// que la couche UI n'ait pas à manipuler PassKit / CloudKit directement.
///
/// CloudKit n'expose les e-mails / numéros de téléphone que si l'utilisateur a
/// **opté pour leur découvrabilité** dans Réglages iOS → [son nom] → Contacts
/// → Permettre aux autres de me trouver. Sans cela, on n'a que l'identifiant
/// interne (`userRecordID`) et éventuellement le nom complet.
struct ParticipantInfo: Identifiable, Hashable {
    let id: String   // userRecordID.recordName
    let displayName: String?
    let email: String?
    let phone: String?
    let isOwner: Bool
    let isCurrentUser: Bool
    let acceptanceLabel: String
    let permissionLabel: String

    init(from p: CKShare.Participant, isOwnerSlot: Bool) {
        self.id = p.userIdentity.userRecordID?.recordName ?? UUID().uuidString
        let comps = p.userIdentity.nameComponents
        if let comps {
            let f = PersonNameComponentsFormatter()
            f.style = .default
            let s = f.string(from: comps)
            self.displayName = s.isEmpty ? nil : s
        } else {
            self.displayName = nil
        }
        self.email = p.userIdentity.lookupInfo?.emailAddress
        self.phone = p.userIdentity.lookupInfo?.phoneNumber
        self.isOwner = isOwnerSlot || p.role == .owner
        self.isCurrentUser = (p.userIdentity.userRecordID == CKRecord.ID(recordName: CKCurrentUserDefaultName))

        switch p.acceptanceStatus {
        case .accepted:    self.acceptanceLabel = "Invitation acceptée"
        case .pending:     self.acceptanceLabel = "Invitation envoyée — en attente"
        case .removed:     self.acceptanceLabel = "Retiré du partage"
        case .unknown:     self.acceptanceLabel = "Statut inconnu"
        @unknown default:  self.acceptanceLabel = "Statut inconnu"
        }
        switch p.permission {
        case .readOnly:    self.permissionLabel = "Lecture seule"
        case .readWrite:   self.permissionLabel = "Lecture / écriture"
        case .none:        self.permissionLabel = "Aucun droit"
        case .unknown:     self.permissionLabel = "Droits inconnus"
        @unknown default:  self.permissionLabel = "Droits inconnus"
        }
    }

    /// Étiquette « la plus parlante » pour l'utilisateur final : on préfère le nom,
    /// puis l'e-mail, puis le téléphone, puis la mention « Apple ID anonyme ».
    var bestLabel: String {
        if let n = displayName, !n.isEmpty { return n }
        if let e = email, !e.isEmpty { return e }
        if let p = phone, !p.isEmpty { return p }
        return "Apple ID anonyme"
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
