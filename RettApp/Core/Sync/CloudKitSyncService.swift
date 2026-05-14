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

    /// Nom du propriétaire stocké côté participant pour pouvoir afficher
    /// « partagé par Marc » même sans `userDiscoverability` activée. Renseigné
    /// par `refreshShareStatus` à partir du champ custom du `CKShare`.
    var ownerDisplayNameFromShare: String?

    /// Tâche de synchronisation différée (debounce) déclenchée par
    /// `scheduleSync(context:)` après une écriture locale.
    private var pendingSyncTask: Task<Void, Never>?

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

    /// Prépare un `CKShare` zone-wide prêt à être présenté à
    /// `UICloudSharingController`. La méthode :
    ///   1. s'assure que la zone existe et que les records locaux sont poussés
    ///      (sinon le participant accepte un partage vide),
    ///   2. cherche un share existant sur cette zone (via scan des records
    ///      de la zone — un zone-share a le recordName auto-généré
    ///      `cloudkit.zoneshare`, c'est pour ça que la V1 ne le retrouvait
    ///      jamais en construisant un recordID manuel),
    ///   3. en crée un nouveau sinon, avec le titre et le nom du propriétaire
    ///      stockés dans des champs custom pour être lisibles côté participant
    ///      sans dépendre de `discoverUserIdentity`.
    func prepareShareForController(childProfile: ChildProfile?, context: ModelContext) async throws -> (CKShare, CKContainer) {
        try await ensureSignedIn()
        syncState = .syncing
        defer {
            if case .syncing = syncState { syncState = .idle }
        }

        // (1) Pousse l'existant pour que l'invité voie tout au moment d'accepter.
        //    Important : avant d'attacher le share, sinon les records ajoutés
        //    plus tard ne propagent pas tout de suite.
        try? await replicateAll(from: context)

        let zone = try await ensureZone()

        // (2) Cherche un share existant dans la zone
        if let existing = try? await fetchZoneShare(database: container.privateCloudDatabase, zoneID: zone.zoneID) {
            currentShare = existing
            role = .owner
            return (existing, container)
        }

        // (3) Crée un nouveau share zone-wide
        let share = CKShare(recordZoneID: zone.zoneID)
        share[CKShare.SystemFieldKey.title] = "Suivi RettApp — \(childProfile?.fullName ?? "enfant")" as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "fr.afsr.RettApp.familyShare" as CKRecordValue
        share.publicPermission = .none // forcer l'invitation explicite (plus sûr)
        // Champ custom : nom affichable du propriétaire, lu côté participant
        // pour afficher « Partagé par X » sans dépendre de discoverUserIdentity.
        if let ownerName = await currentUserDisplayName() {
            share["ownerDisplayName"] = ownerName as CKRecordValue
        }

        let saveResult = try await container.privateCloudDatabase.modifyRecords(
            saving: [share], deleting: [],
            savePolicy: .ifServerRecordUnchanged
        )

        // Récupère le share sauvegardé (avec recordChangeTag à jour) plutôt
        // que la copie locale, pour que UICloudSharingController ne re-tente
        // pas de le créer.
        let savedShare: CKShare = {
            for (_, modResult) in saveResult.saveResults {
                if case .success(let saved) = modResult, let s = saved as? CKShare {
                    return s
                }
            }
            return share
        }()

        currentShare = savedShare
        role = .owner
        return (savedShare, container)
    }

    /// API rétrocompatible : renvoie uniquement l'URL pour l'ancien flow
    /// AirDrop-only. Conservée le temps de la transition.
    func setupSharing(childProfile: ChildProfile?) async throws -> URL {
        // Ce chemin n'est plus utilisé par l'UI principale (CloudShareSheet
        // utilise prepareShareForController). Conservé en filet de sécurité.
        try await ensureSignedIn()
        let zone = try await ensureZone()
        if let existing = currentShare ?? (try? await fetchZoneShare(database: container.privateCloudDatabase, zoneID: zone.zoneID)) {
            currentShare = existing
            role = .owner
            if let url = existing.url { return url }
        }
        throw SyncError.shareURLUnavailable
    }

    /// Cherche un `CKShare` dans une zone donnée en scannant les
    /// modifications via `recordZoneChanges`. Fonctionne aussi bien pour les
    /// shares per-record que zone-wide — c'est l'API officielle Apple pour
    /// retrouver le share associé à une zone, qu'on en soit propriétaire ou
    /// participant.
    private func fetchZoneShare(database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> CKShare? {
        let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: nil)
        for (_, modResult) in result.modificationResultsByID {
            if case .success(let mod) = modResult, let share = mod.record as? CKShare {
                return share
            }
        }
        return nil
    }

    /// Récupère le nom complet de l'utilisateur iCloud courant via
    /// `discoverUserIdentity`. Nécessite `requestApplicationPermission(.userDiscoverability)`
    /// accordée + l'utilisateur a activé « Trouvable par e-mail » dans ses
    /// Réglages iCloud. Retourne nil sinon — l'appelant prévoit un fallback.
    private func currentUserDisplayName() async -> String? {
        do {
            let userRecordID = try await container.userRecordID()
            let identity = try await discoverIdentity(userRecordID: userRecordID)
            if let comps = identity?.nameComponents {
                let formatter = PersonNameComponentsFormatter()
                let s = formatter.string(from: comps)
                return s.isEmpty ? nil : s
            }
        } catch {
            Self.log.error("currentUserDisplayName: \(error.localizedDescription)")
        }
        return nil
    }

    /// Récupère le statut de partage actuel (si on est propriétaire ou participant)
    /// **et** la liste des participants associés au share. Les identités
    /// viennent en priorité du champ custom `ownerDisplayName` stocké dans le
    /// CKShare ; à défaut, `discoverUserIdentity` (qui nécessite que l'autre
    /// utilisateur ait activé la découvrabilité — souvent désactivée).
    func refreshShareStatus() async {
        do {
            // 1) Côté propriétaire — zone privée existante ?
            let zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
            do {
                _ = try await container.privateCloudDatabase.recordZone(for: zoneID)
                if let share = try? await fetchZoneShare(database: container.privateCloudDatabase, zoneID: zoneID) {
                    await applyOwnedShare(share)
                    return
                }
            } catch let error as CKError where error.code == .zoneNotFound {
                // Pas de zone côté privé — on bascule en check participant.
            }

            // 2) Côté participant — zone(s) présente(s) dans la sharedCloudDatabase ?
            let sharedZones = try await container.sharedCloudDatabase.allRecordZones()
            if let firstZone = sharedZones.first {
                if let share = try? await fetchZoneShare(database: container.sharedCloudDatabase, zoneID: firstZone.zoneID) {
                    await applyParticipantShare(share)
                } else {
                    role = .participant
                    participants = []
                    participantCount = 0
                    ownerDisplayNameFromShare = nil
                }
                return
            }

            // 3) Aucun partage en cours
            role = .none
            participants = []
            participantCount = 0
            currentShare = nil
            ownerDisplayNameFromShare = nil
        } catch {
            Self.log.error("refreshShareStatus error: \(error.localizedDescription)")
            lastErrorMessage = error.localizedDescription
        }
    }

    private func applyOwnedShare(_ share: CKShare) async {
        currentShare = share
        role = .owner
        let infos = share.participants.map { p in
            ParticipantInfo(from: p, isOwnerSlot: p.userIdentity.userRecordID == share.owner.userIdentity.userRecordID)
        }
        participants = infos
        participantCount = max(0, infos.filter { !$0.isOwner && $0.acceptanceStatus != .removed }.count)
        ownerDisplayNameFromShare = share["ownerDisplayName"] as? String
        let enriched = await enrichParticipants(from: share, currentList: infos)
        participants = enriched
    }

    private func applyParticipantShare(_ share: CKShare) async {
        currentShare = share
        role = .participant
        let infos = share.participants.map { p in
            ParticipantInfo(from: p, isOwnerSlot: p.userIdentity.userRecordID == share.owner.userIdentity.userRecordID)
        }
        participants = infos
        participantCount = max(0, infos.filter { !$0.isOwner && $0.acceptanceStatus != .removed }.count)
        ownerDisplayNameFromShare = share["ownerDisplayName"] as? String
        let enriched = await enrichParticipants(from: share, currentList: infos)
        participants = enriched
    }

    /// Demande à l'utilisateur l'autorisation de découvrir l'identité des autres
    /// participants (Apple ID, e-mail). Sans cette permission, CloudKit nous
    /// renvoie des participants anonymes même quand les autres parents ont
    /// activé la découvrabilité de leur côté.
    func requestParticipantsDiscoverability() async {
        do {
            let status = try await container.requestApplicationPermission(.userDiscoverability)
            Self.log.info("Discoverability permission: \(String(describing: status))")
        } catch {
            Self.log.error("Discoverability request failed: \(error.localizedDescription)")
        }
    }

    /// Enrichit la liste des participants avec leur identité visible (e-mail,
    /// nom complet) en interrogeant CloudKit. Nécessite que :
    ///   - chaque parent ait activé la découvrabilité côté Réglages iOS,
    ///   - cette app ait obtenu la permission `.userDiscoverability` (cf.
    ///     `requestParticipantsDiscoverability()`).
    private func enrichParticipants(from share: CKShare, currentList: [ParticipantInfo]) async -> [ParticipantInfo] {
        var enriched: [ParticipantInfo] = []
        for (i, p) in share.participants.enumerated() {
            let base = currentList.indices.contains(i)
                ? currentList[i]
                : ParticipantInfo(from: p, isOwnerSlot: p.userIdentity.userRecordID == share.owner.userIdentity.userRecordID)
            // Si on a déjà email/nom, on garde — sinon on tente la découverte.
            if base.email != nil || base.displayName != nil {
                enriched.append(base)
                continue
            }
            guard let userRecordID = p.userIdentity.userRecordID else {
                enriched.append(base)
                continue
            }
            do {
                let identity = try await discoverIdentity(userRecordID: userRecordID)
                enriched.append(ParticipantInfo(
                    from: p,
                    isOwnerSlot: p.userIdentity.userRecordID == share.owner.userIdentity.userRecordID,
                    overrideIdentity: identity
                ))
            } catch {
                Self.log.error("discoverUserIdentity failed: \(error.localizedDescription)")
                enriched.append(base)
            }
        }
        return enriched
    }

    /// Wrapper de `discoverUserIdentity(withUserRecordID:completionHandler:)` en
    /// async/await. L'API ObjC originale n'a pas de variante async auto-bridgée
    /// dans le SDK iOS 17 — il faut explicitement wrapper avec
    /// `withCheckedThrowingContinuation` pour utiliser `try await`.
    private func discoverIdentity(userRecordID: CKRecord.ID) async throws -> CKUserIdentity? {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CKUserIdentity?, Error>) in
            container.discoverUserIdentity(withUserRecordID: userRecordID) { identity, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: identity) }
            }
        }
    }

    /// Retire un participant spécifique du share (action propriétaire). Le
    /// participant perd l'accès immédiatement, mais le partage reste en place
    /// pour les autres invités. Si c'est le dernier invité, le share reste
    /// actif (vide) — utiliser `stopSharing()` pour tout supprimer.
    func removeParticipant(_ info: ParticipantInfo) async throws {
        guard role == .owner, let share = currentShare else { return }
        guard let participant = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == info.id
        }) else { return }
        guard !info.isOwner else { return } // on ne peut pas se retirer soi-même
        syncState = .syncing
        defer { syncState = .idle }

        share.removeParticipant(participant)
        _ = try await container.privateCloudDatabase.modifyRecords(
            saving: [share], deleting: [],
            savePolicy: .ifServerRecordUnchanged
        )
        await refreshShareStatus()
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
    /// Apple a deux mécanismes documentés :
    ///   1. Supprimer la zone partagée via `deleteRecordZone(withID:)` sur la
    ///      sharedCloudDatabase. **C'EST LE CHEMIN QUI ÉCHOUE** avec
    ///      « zone delete not allowed » sur iOS récents : la zone reste la
    ///      propriété du parent qui partage.
    ///   2. Supprimer le record `CKShare` lui-même via `modifyRecords(deleting:)`.
    ///      C'est l'API canonique pour « retire-moi du partage ». CloudKit
    ///      propage la révocation au propriétaire.
    ///
    /// On utilise (2) exclusivement et on inspecte le résultat per-record (la
    /// version async/await de `modifyRecords` ne lève PAS pour les erreurs
    /// per-record — on doit lire `deleteResults`).
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

        var deletedAtLeastOne = false
        var lastError: Error?
        for zone in zones {
            // 1) Récupérer le CKShare via le fetch des changements de zone.
            //    La version async/await de recordZoneChanges peut elle-même
            //    échouer (réseau, etc.) — on isole.
            let share: CKShare?
            do {
                share = try await fetchZoneShare(database: container.sharedCloudDatabase, zoneID: zone.zoneID)
            } catch {
                Self.log.error("leaveShare: fetchZoneShare a échoué — \(error.localizedDescription)")
                lastError = error
                continue
            }
            guard let share else { continue }

            // 2) modifyRecords(deleting:) en supprimant le share lui-même.
            //    On inspecte les résultats per-record (la version async/await
            //    ne lève PAS pour les erreurs partielles).
            do {
                let result = try await container.sharedCloudDatabase.modifyRecords(
                    saving: [], deleting: [share.recordID]
                )
                if let outcome = result.deleteResults[share.recordID] {
                    switch outcome {
                    case .success:
                        deletedAtLeastOne = true
                    case .failure(let err):
                        Self.log.error("leaveShare: deleteResults indique échec — \(err.localizedDescription)")
                        lastError = err
                    }
                }
            } catch {
                Self.log.error("leaveShare: modifyRecords a échoué — \(error.localizedDescription)")
                lastError = error
            }
        }

        if deletedAtLeastOne {
            currentShare = nil
            role = .none
            participantCount = 0
            participants = []
            // Re-vérifie l'état pour que l'UI reflète la réalité côté serveur.
            await refreshShareStatus()
        } else if let err = lastError {
            throw err
        } else {
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

    // MARK: - Auto-sync (debounce)

    /// Planifie un push + pull différé après une écriture locale. Plusieurs
    /// appels rapprochés sont coalescés : seul le dernier provoque un cycle
    /// de synchronisation, `delay` secondes après le dernier appel.
    ///
    /// À utiliser depuis les vues qui sauvent des données importantes
    /// (médicaments, crises, observations) pour que l'autre parent voie les
    /// changements la prochaine fois qu'il ouvre l'app — sans avoir à
    /// déclencher la synchronisation manuelle.
    ///
    /// No-op si l'utilisateur n'est pas en mode partage.
    func scheduleSync(context: ModelContext, delay: TimeInterval = 3.0) {
        guard role != .none else { return }
        pendingSyncTask?.cancel()
        pendingSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            do {
                try await self.replicateAll(from: context)
                try await self.pullChanges(into: context)
            } catch {
                Self.log.error("scheduleSync error: \(error.localizedDescription)")
            }
        }
    }

    /// Pull immédiat best-effort (appelé typiquement au foreground de l'app).
    /// Silencieux en cas d'erreur — ne perturbe pas l'UI.
    func quickPull(context: ModelContext) async {
        guard role != .none, accountStatus == .available else { return }
        do {
            try await pullChanges(into: context)
        } catch {
            Self.log.error("quickPull error: \(error.localizedDescription)")
        }
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
    let acceptanceStatus: CKShare.ParticipantAcceptanceStatus
    let acceptanceLabel: String
    let permissionLabel: String

    init(from p: CKShare.Participant, isOwnerSlot: Bool, overrideIdentity: CKUserIdentity? = nil) {
        self.acceptanceStatus = p.acceptanceStatus
        self.id = p.userIdentity.userRecordID?.recordName ?? UUID().uuidString
        // Priorité : overrideIdentity (récupéré via discoverUserIdentity) > userIdentity
        //            de p (souvent vide pour les shares à publicPermission ouvert).
        let identity = overrideIdentity ?? p.userIdentity
        if let comps = identity.nameComponents {
            let f = PersonNameComponentsFormatter()
            f.style = .default
            let s = f.string(from: comps)
            self.displayName = s.isEmpty ? nil : s
        } else {
            self.displayName = nil
        }
        self.email = identity.lookupInfo?.emailAddress
        self.phone = identity.lookupInfo?.phoneNumber
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
