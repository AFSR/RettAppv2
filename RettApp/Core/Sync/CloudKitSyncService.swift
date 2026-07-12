import Foundation
import CloudKit
import SwiftData
import Observation
import os.log
import UserNotifications

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
    /// Nombre d'écritures locales dans le buffer PendingWriteStore, en attente
    /// d'être poussées vers CloudKit. Alimenté par une notification postée par
    /// le store à chaque mutation → l'UI (bandeau) se rafraîchit sans polling.
    var pendingWriteCount: Int = 0
    /// Métadonnées des autres parents (e-mail / nom Apple ID, statut, droits).
    /// Vide si on n'est pas en partage ou si CloudKit n'a pas encore renvoyé la liste.
    var participants: [ParticipantInfo] = []

    // MARK: - Internals

    private let container: CKContainer
    private(set) var currentShare: CKShare?
    private var ownedZone: CKRecordZone?

    /// Nom du propriétaire stocké côté participant pour pouvoir afficher
    /// « partagé par Marc » même sans `userDiscoverability` activée. Renseigné
    /// par `refreshShareStatus` à partir du champ custom du `CKShare`.
    var ownerDisplayNameFromShare: String?

    /// Journal court des dernières activités distantes (récup à chaque pull
    /// `.shared`). Affiché dans Réglages → Partage pour donner de la
    /// visibilité sur ce que fait l'autre parent. Plafonné à 30 entrées.
    var recentRemoteActivity: [RemoteActivity] = []

    /// Tâche de synchronisation différée (debounce) déclenchée par
    /// `scheduleSync(context:)` après une écriture locale.
    private var pendingSyncTask: Task<Void, Never>?

    /// Sérialise les cycles push+pull — un seul en vol à la fois, les autres
    /// s'enfilent. Empêche les races entre `ensureLogsExist`, dedup, drain.
    private let gate = SyncGate()

    /// Dernière fois qu'on a auto-réparé les subscriptions. Sert de rate-limit
    /// mou (max 1×/heure) pour ne pas hammerer CloudKit à chaque foreground.
    private var lastSubscriptionAuditAt: Date?

    init() {
        self.container = CKContainer(identifier: Self.containerID)
        self.pendingWriteCount = PendingWriteStore.shared.pendingCount
        // Rafraîchit l'observable à chaque mutation du buffer. On garde le
        // token nulle-part : NotificationCenter conserve la subscription vivante
        // aussi longtemps que `self` — le service est un `@State` de l'App donc
        // vit pour toute la session.
        NotificationCenter.default.addObserver(
            forName: PendingWriteStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let count = note.userInfo?["count"] as? Int ?? PendingWriteStore.shared.pendingCount
            Task { @MainActor in
                self?.pendingWriteCount = count
            }
        }
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
        // `.readWrite` : toute personne qui ouvre le lien (AirDrop, Messages,
        // Mail) peut rejoindre. Indispensable pour AirDrop — avec `.none`,
        // CloudKit refuse l'acceptation parce qu'aucune identité (e-mail) n'a
        // été déclarée avant l'envoi, et l'invité ne reçoit qu'un lien mort.
        // La sécurité repose sur la confidentialité du lien (envoi en
        // présentiel via AirDrop, ou destinataire de confiance).
        share.publicPermission = .readWrite
        // Champ custom : nom affichable du propriétaire, lu côté participant
        // pour afficher « Partagé par X » sans dépendre de discoverUserIdentity.
        if let ownerName = await currentUserDisplayName() {
            share["ownerDisplayName"] = ownerName as CKRecordValue
        }

        let saveResult = try await container.privateCloudDatabase.modifyRecords(
            saving: [share], deleting: [],
            savePolicy: .ifServerRecordUnchanged
        )

        // `modifyRecords` ne lève PAS quand un save individuel échoue — il
        // faut inspecter `saveResults` à la main. Sans ça, on récupérait
        // silencieusement la copie locale du share, qui n'a pas d'URL côté
        // serveur — d'où le message « lien de partage n'a pas pu être
        // généré ». On remonte l'erreur réelle avec un contexte parlant
        // (souvent : schéma CloudKit non déployé en production).
        for (_, modResult) in saveResult.saveResults {
            if case .failure(let err) = modResult {
                Self.log.error("share save failed: \(err.localizedDescription)")
                throw SyncError.shareSaveFailed(underlying: err)
            }
        }

        let savedShare: CKShare = {
            for (_, modResult) in saveResult.saveResults {
                if case .success(let saved) = modResult, let s = saved as? CKShare {
                    return s
                }
            }
            return share
        }()

        // Sécurité supplémentaire : si après tout ça l'URL est absente, on
        // refuse de continuer plutôt que de retourner un share inutilisable.
        guard savedShare.url != nil else {
            Self.log.error("share saved but no URL — probable production schema mismatch")
            throw SyncError.shareURLUnavailable
        }

        currentShare = savedShare
        role = .owner
        return (savedShare, container)
    }

    /// Renvoie le couple `(share, container)` à passer à
    /// `UICloudSharingController(share:container:)` quand un partage existe
    /// déjà — c'est l'init canonique pour le mode « gérer les participants »
    /// (ajouter / retirer des invités, copier le lien). Différent du chemin
    /// `prepareShareForController` qui sert au tout premier partage.
    func existingShareForController() -> (CKShare, CKContainer)? {
        guard let share = currentShare else { return nil }
        return (share, container)
    }

    /// API rétrocompatible : renvoie uniquement l'URL pour l'ancien flow
    /// AirDrop-only. Conservée le temps de la transition.
    func setupSharing(childProfile: ChildProfile?) async throws -> URL {
        // Ce chemin n'est plus utilisé par l'UI principale (ProximityShare
        // utilise prepareShareForController). Conservé en filet de sécurité.
        try await ensureSignedIn()
        let zone = try await ensureZone()
        // Important : on ne peut pas écrire `currentShare ?? (try? await …)`
        // parce que l'opérateur `??` utilise un `@autoclosure` non-async,
        // et un `await` dans un autoclosure ne compile pas en Swift 5.9.
        // On résout les deux côtés explicitement.
        let resolved: CKShare?
        if let local = currentShare {
            resolved = local
        } else {
            resolved = try? await fetchZoneShare(database: container.privateCloudDatabase, zoneID: zone.zoneID)
        }
        if let existing = resolved {
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
            //    On itère TOUTES les zones partagées pour supporter le cas où
            //    l'utilisateur est participant de plusieurs enfants (par
            //    exemple un pro qui accompagne plusieurs familles). On garde
            //    le premier share trouvé comme "primaire" pour l'UI de statut,
            //    mais chaque zone est bien pullée par `pullChanges`.
            let sharedZones = try await container.sharedCloudDatabase.allRecordZones()
            if !sharedZones.isEmpty {
                var primaryShare: CKShare?
                for zone in sharedZones {
                    if let share = try? await fetchZoneShare(database: container.sharedCloudDatabase, zoneID: zone.zoneID) {
                        primaryShare = share
                        break
                    }
                }
                if let share = primaryShare {
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
        // Les tokens de changement sont invalidés (la zone n'est plus partagée
        // — pour les futurs partages, on repartira de zéro).
        ChangeTokenStore.clearAll()
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
            // Les tokens de changement de la zone partagée ne sont plus valides
            // une fois qu'on a quitté le partage.
            ChangeTokenStore.clearAll()
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
        if let symptoms = try? context.fetch(FetchDescriptor<SymptomEvent>()) {
            records.append(contentsOf: symptoms.map { $0.toCKRecord(zoneID: zoneID) })
        }
        if let revisions = try? context.fetch(FetchDescriptor<MedicationRevision>()) {
            records.append(contentsOf: revisions.map { $0.toCKRecord(zoneID: zoneID) })
        }

        if records.isEmpty {
            Self.log.info("replicateAll: aucun enregistrement local à pousser")
            lastSyncedAt = Date()
            return
        }

        // Push par batch de 200 (limite raisonnable pour CloudKit). Wrap
        // dans un retry pour absorber les rate-limit et coupures réseau
        // transitoires. `.ifServerRecordUnchanged` : si un record existe déjà
        // avec un tag différent, on récupère `serverRecordChanged` et on merge
        // via LWW plutôt que de blind-writer.
        let batchSize = 200
        var offset = 0
        while offset < records.count {
            let end = min(offset + batchSize, records.count)
            let chunk = Array(records[offset..<end])
            try await pushBatch(chunk, deletes: [], to: database, label: "replicateAll")
            offset = end
        }

        lastSyncedAt = Date()
        Self.log.info("replicateAll OK : \(records.count) records poussés")
        // Le buffer contient probablement des entrées correspondant aux
        // records qu'on vient de push (setup initial du partage) — les
        // vider évite un re-push redondant au premier drain.
        // `.ifServerRecordUnchanged` protégerait, mais on économise un
        // round-trip serveur inutile.
        PendingWriteStore.shared.clear()
    }

    // MARK: - Push incrémental (drain PendingWriteStore)

    /// Push tout ce que le `PendingWriteStore` a accumulé (upserts + deletes)
    /// depuis le dernier drain. Se protège contre les échecs partiels :
    /// - Les entrées non-poussées sont ré-injectées dans le buffer → aucun
    ///   changement n'est perdu, même si l'app crash entre les batches.
    /// - Utilise `.ifServerRecordUnchanged` pour éviter les blind-writes qui
    ///   écraseraient un état serveur plus récent.
    /// - Sur `serverRecordChanged`, résout via `lastModifiedAt` (LWW) —
    ///   voir `pushBatch(...)`.
    ///
    /// Idempotent et safe à rappeler à volonté.
    ///
    /// Contrat CRITIQUE — anti-perte de données :
    /// - On sort le snapshot du buffer AVANT de savoir si on va réussir.
    /// - TOUT chemin de sortie (throw, early return, batch KO) qui n'a PAS
    ///   confirmé le push d'une entrée doit la remettre dans le buffer.
    /// - Le `defer` de fin de fonction est la ceinture de sécurité : quoi
    ///   qu'il arrive dans la fonction, les entries non-marquées "pushées"
    ///   retournent dans le PendingWriteStore.
    func drainPendingWrites(context: ModelContext) async throws {
        try await ensureSignedIn()
        let snapshot = PendingWriteStore.shared.drain()
        guard !snapshot.isEmpty else { return }

        // Toutes les entries commencent dans "unresolved". On les enlève au
        // fur et à mesure que leur push est confirmé. Le defer requeue ce
        // qui reste → aucun exit path (throw, early return) ne perd de données.
        var unresolved = Set(snapshot)
        defer {
            if !unresolved.isEmpty {
                PendingWriteStore.shared.requeue(Array(unresolved))
            }
        }

        let database = appropriateDatabase()
        let zoneIDs = try await resolveZoneIDs()
        guard let zoneID = zoneIDs.first else {
            // Pas de zone dispo → defer requeue tout, on lève une erreur.
            throw SyncError.shareURLUnavailable
        }

        // 1) Séparer upserts / deletes et construire les CKRecord depuis SwiftData.
        //    On garde l'entry originale associée à chaque CKRecord pour pouvoir
        //    la retirer de `unresolved` en cas de succès.
        var upsertRecords: [(entry: PendingWriteStore.Entry, record: CKRecord)] = []
        var deleteRecords: [(entry: PendingWriteStore.Entry, recordID: CKRecord.ID)] = []

        for entry in snapshot {
            switch entry.op {
            case .delete:
                if let recordID = makeRecordID(name: entry.recordName, zoneID: zoneID) {
                    deleteRecords.append((entry, recordID))
                }
                // Nom invalide → on abandonne l'entrée (elle n'est PAS retirée
                // de `unresolved` donc elle sera requeuée — mais elle
                // re-échouera la prochaine fois. C'est un état pathologique).
            case .upsert:
                if let rec = buildCKRecord(for: entry, zoneID: zoneID, context: context) {
                    upsertRecords.append((entry, rec))
                } else {
                    // Modèle disparu de SwiftData entre l'enqueue et le drain
                    // (delete cascadée, dedup, etc.). On marque l'entry résolue :
                    // il n'y a plus rien à pousser pour ce record.
                    unresolved.remove(entry)
                }
            }
        }

        // 2) Push par batches. Un batch entier qui échoue n'invalide QUE
        //    ses propres entries — les autres batches continuent. Les entries
        //    de ce batch restent dans `unresolved` → requeue via defer.
        let batchSize = 200
        var offset = 0
        while offset < upsertRecords.count {
            let end = min(offset + batchSize, upsertRecords.count)
            let chunk = Array(upsertRecords[offset..<end])
            do {
                try await pushBatch(chunk.map(\.record), deletes: [], to: database, label: "drain.upsert")
                // Batch OK → toutes ces entries sont résolues.
                for pair in chunk { unresolved.remove(pair.entry) }
            } catch {
                Self.log.error("drain.upsert batch KO : \(error.localizedDescription)")
                lastErrorMessage = error.localizedDescription
                syncState = .error(error.localizedDescription)
                // Ces entries restent dans unresolved → requeue.
            }
            offset = end
        }

        // Deletes en un seul batch (peu volumineux en pratique).
        if !deleteRecords.isEmpty {
            do {
                try await pushBatch([], deletes: deleteRecords.map(\.recordID), to: database, label: "drain.delete")
                for pair in deleteRecords { unresolved.remove(pair.entry) }
            } catch {
                Self.log.error("drain.delete batch KO : \(error.localizedDescription)")
                lastErrorMessage = error.localizedDescription
                syncState = .error(error.localizedDescription)
            }
        }

        if unresolved.isEmpty, case .error = syncState {
            // Tout est passé — on clear l'erreur qui restait.
            syncState = .idle
            lastErrorMessage = nil
        }
    }

    /// Push un batch avec `.ifServerRecordUnchanged` + recovery LWW sur
    /// `.serverRecordChanged`. Retry les erreurs transitoires (rate-limit,
    /// zoneBusy, réseau) via `CKRetry`.
    ///
    /// Ne throw QUE si le batch entier échoue au niveau réseau. Une erreur
    /// per-record NON-résolvable (permission, quota, invalid data) lève
    /// une `SyncError.perRecordPushFailed` pour que l'appelant requeue le
    /// batch (sinon on perdrait silencieusement des enregistrements).
    private func pushBatch(
        _ records: [CKRecord],
        deletes: [CKRecord.ID],
        to database: CKDatabase,
        label: String
    ) async throws {
        try await CKRetry.run(label: label) {
            let result = try await database.modifyRecords(
                saving: records,
                deleting: deletes,
                savePolicy: .ifServerRecordUnchanged
            )

            // 1) Handle per-record save results — recover LWW on serverRecordChanged.
            var conflictedRecordsToReplay: [CKRecord] = []
            var terminalFailures: [(recordID: CKRecord.ID, error: Error)] = []
            for (recordID, res) in result.saveResults {
                guard case .failure(let err) = res else { continue }
                if let ck = err as? CKError, ck.code == .serverRecordChanged {
                    if let merged = self.mergeForLWW(conflict: ck) {
                        conflictedRecordsToReplay.append(merged)
                    }
                    // Si merge nil (serveur gagne) → notre push est
                    // délibérément abandonné, ce n'est pas une perte.
                } else {
                    terminalFailures.append((recordID, err))
                }
            }

            // 2) Replay conflicted records that WE win according to LWW.
            //    On check les résultats du replay aussi — si un record replayé
            //    conflict encore (autre parent a poussé entre-temps), on le
            //    remet comme échec terminal → appelant requeue.
            if !conflictedRecordsToReplay.isEmpty {
                let replayResult = try await database.modifyRecords(
                    saving: conflictedRecordsToReplay,
                    deleting: [],
                    savePolicy: .ifServerRecordUnchanged
                )
                for (recordID, res) in replayResult.saveResults {
                    if case .failure(let err) = res {
                        terminalFailures.append((recordID, err))
                    }
                }
            }

            // 3) Vérifie aussi les résultats de deletes — un delete échoué
            //    non-idempotent (permission refusée) doit être remonté.
            for (recordID, res) in result.deleteResults {
                if case .failure(let err) = res {
                    // `.unknownItem` sur un delete = record déjà supprimé côté
                    // serveur, c'est un succès idempotent, on ignore.
                    if let ck = err as? CKError, ck.code == .unknownItem { continue }
                    terminalFailures.append((recordID, err))
                }
            }

            if !terminalFailures.isEmpty {
                Self.log.error("[\(label)] \(terminalFailures.count) échec(s) terminal(aux) per-record")
                for (id, err) in terminalFailures {
                    Self.log.error("  - \(id.recordName) : \(err.localizedDescription)")
                }
                throw SyncError.perRecordPushFailed(count: terminalFailures.count)
            }
        }
    }

    /// À partir d'une erreur `.serverRecordChanged`, décide si NOUS gagnons
    /// le LWW. Si oui, retourne le CKRecord serveur (qui porte le bon
    /// changeTag) avec nos valeurs appliquées dessus, prêt à être re-sauvé.
    /// Si le serveur gagne, retourne nil (le pull ultérieur ramènera son état).
    private func mergeForLWW(conflict: CKError) -> CKRecord? {
        guard
            let localRec = conflict.userInfo[CKRecordChangedErrorClientRecordKey] as? CKRecord,
            let serverRec = conflict.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord
        else {
            return nil
        }
        let localTs = localRec[SyncFields.lastModifiedAt] as? Date
        let serverTs = serverRec[SyncFields.lastModifiedAt] as? Date
        if SyncConflictResolver.shouldAcceptIncoming(local: localTs, incoming: serverTs) {
            // Serveur ≥ local → on abandonne notre push.
            return nil
        }
        // Local strictement plus récent → on rejoue avec le tag serveur.
        for key in localRec.allKeys() {
            serverRec[key] = localRec[key]
        }
        return serverRec
    }

    /// Retourne les zones à cibler pour un push (owner : zone privée ; participant :
    /// toutes les zones partagées). Alloué à un seul appel par cycle pour éviter
    /// les allers-retours réseau redondants.
    private func resolveZoneIDs() async throws -> [CKRecordZone.ID] {
        if role == .participant {
            let zones = try await container.sharedCloudDatabase.allRecordZones()
            return zones.map { $0.zoneID }
        } else {
            let zone = try await ensureZone()
            return [zone.zoneID]
        }
    }

    /// Construit un `CKRecord` à partir d'un modèle SwiftData identifié par
    /// `entry`. Retourne nil si le modèle n'existe plus (supprimé entre-temps).
    private func buildCKRecord(for entry: PendingWriteStore.Entry, zoneID: CKRecordZone.ID, context: ModelContext) -> CKRecord? {
        guard let id = UUID(uuidString: entry.recordName) else { return nil }
        switch entry.recordType {
        case CKRecordType.childProfile:
            return (try? context.fetch(FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.id == id })).first)?.toCKRecord(zoneID: zoneID)
        case CKRecordType.medication:
            return (try? context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.id == id })).first)?.toCKRecord(zoneID: zoneID)
        case CKRecordType.medicationLog:
            return (try? context.fetch(FetchDescriptor<MedicationLog>(predicate: #Predicate { $0.id == id })).first)?.toCKRecord(zoneID: zoneID)
        case CKRecordType.seizure:
            return (try? context.fetch(FetchDescriptor<SeizureEvent>(predicate: #Predicate { $0.id == id })).first)?.toCKRecord(zoneID: zoneID)
        case CKRecordType.mood:
            return (try? context.fetch(FetchDescriptor<MoodEntry>(predicate: #Predicate { $0.id == id })).first)?.toCKRecord(zoneID: zoneID)
        case CKRecordType.dailyObservation:
            return (try? context.fetch(FetchDescriptor<DailyObservation>(predicate: #Predicate { $0.id == id })).first)?.toCKRecord(zoneID: zoneID)
        case CKRecordType.symptom:
            return (try? context.fetch(FetchDescriptor<SymptomEvent>(predicate: #Predicate { $0.id == id })).first)?.toCKRecord(zoneID: zoneID)
        case CKRecordType.medicationRevision:
            return (try? context.fetch(FetchDescriptor<MedicationRevision>(predicate: #Predicate { $0.id == id })).first)?.toCKRecord(zoneID: zoneID)
        default:
            return nil
        }
    }

    private func makeRecordID(name: String, zoneID: CKRecordZone.ID) -> CKRecord.ID? {
        // `recordName` peut être n'importe quel string non vide en CloudKit —
        // on n'exige pas un UUID valide ici pour préserver les futurs types.
        guard !name.isEmpty else { return nil }
        return CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    // MARK: - Pull (CloudKit → SwiftData)

    /// Tire les changements depuis CloudKit vers SwiftData.
    ///
    /// **Incrémental** : on persiste un `CKServerChangeToken` par zone dans
    /// `UserDefaults` (cf. `ChangeTokenStore`). Au pull suivant, CloudKit ne
    /// renvoie que les records modifiés *depuis* ce token, ce qui :
    ///   - réduit massivement la bande passante et la latence pour les
    ///     synchronisations répétées,
    ///   - évite le problème d'« écho » (ré-importer ses propres pushes)
    ///     parce que CloudKit n'envoie pas un record que l'appelant a
    ///     lui-même écrit après le token.
    ///
    /// Si le serveur indique qu'un token est expiré (rare — change de zone,
    /// reset du store), on le purge automatiquement et on re-pull depuis le
    /// début (`since: nil`).
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

        // Snapshot des compteurs locaux AVANT le pull, pour calculer le delta
        // par type et :
        //   - alimenter `recentRemoteActivity` (timeline UI dans Réglages),
        //   - émettre une notification locale sur les nouvelles crises.
        let counts = currentCounts(in: context)

        var totalUpserted = 0
        var totalDeleted = 0
        for zoneID in zoneIDs {
            try await pullZone(
                zoneID: zoneID,
                scope: scope,
                database: database,
                context: context,
                upserted: &totalUpserted,
                deleted: &totalDeleted
            )
        }

        try? context.save()
        lastSyncedAt = Date()
        Self.log.info("pullChanges OK : \(totalUpserted) upsertés, \(totalDeleted) supprimés")

        // Dedup post-pull : quand l'autre parent pousse un log planifié dont le
        // recordName (UUID) ne correspond pas au nôtre (cas hérité pré-stableId),
        // le fallback dans `MedicationLog.upsert(from:)` fusionne dans le local.
        // Si pour une raison quelconque un doublon s'est glissé quand même
        // (pull concurrent avec `ensureLogsExist` par exemple), on collapse ici.
        // Les CKRecord des « perdants » sont ensuite supprimés côté serveur.
        do {
            let merged = try MedicationLog.dedupeScheduledLogs(in: context)
            if merged > 0 {
                let losers = MedicationLog.drainDeletedIdsFromDedup()
                if !losers.isEmpty {
                    await deleteLogRecordsInCloudKit(losers)
                }
            }
        } catch {
            Self.log.error("dedup post-pull KO : \(error.localizedDescription)")
        }

        // Détection des changements distants. On limite aux pulls côté
        // participant (scope == .shared) pour ne pas notifier pour ses propres
        // pushes qui reviendraient via l'echo serveur côté propriétaire.
        if scope == .shared {
            let after = currentCounts(in: context)
            let deltas = after.diff(against: counts)
            recordRemoteActivity(deltas)
            // NB: depuis V1.7, on ne déclenche plus de notif locale ici pour
            // les nouvelles crises — c'est `CKQuerySubscription` qui s'en
            // charge directement via APNs (visible même app fermée). Évite
            // le double-notif quand l'app est au foreground au moment du
            // push. Le compteur de timeline `recentRemoteActivity` continue
            // d'être alimenté pour la section Réglages → Activité distante.
        }
    }

    /// Snapshot léger des fetchCounts par type. Utilisé avant/après pull pour
    /// dériver l'activité distante.
    private func currentCounts(in context: ModelContext) -> EntityCounts {
        EntityCounts(
            medications:        (try? context.fetchCount(FetchDescriptor<Medication>())) ?? 0,
            medicationLogs:     (try? context.fetchCount(FetchDescriptor<MedicationLog>())) ?? 0,
            seizures:           (try? context.fetchCount(FetchDescriptor<SeizureEvent>())) ?? 0,
            moods:              (try? context.fetchCount(FetchDescriptor<MoodEntry>())) ?? 0,
            observations:       (try? context.fetchCount(FetchDescriptor<DailyObservation>())) ?? 0,
            symptoms:           (try? context.fetchCount(FetchDescriptor<SymptomEvent>())) ?? 0
        )
    }

    /// Enregistre les deltas positifs dans la timeline `recentRemoteActivity`,
    /// plafonnée à 30 entrées (FIFO). Une seule entrée par type / pull, ce
    /// qui évite de polluer la liste avec une activité massive.
    private func recordRemoteActivity(_ deltas: [RemoteActivity.Entity: Int]) {
        let now = Date()
        var entries: [RemoteActivity] = []
        for (entity, count) in deltas where count > 0 {
            entries.append(RemoteActivity(entity: entity, count: count, timestamp: now))
        }
        guard !entries.isEmpty else { return }
        recentRemoteActivity.insert(contentsOf: entries, at: 0)
        if recentRemoteActivity.count > 30 {
            recentRemoteActivity = Array(recentRemoteActivity.prefix(30))
        }
    }

    /// Émet une notification locale (banner + son) pour signaler `count`
    /// nouvelle(s) crise(s) tout juste apparue(s) côté serveur. Best-effort :
    /// pas de retry, pas de blocage de l'UI si la permission n'est pas
    /// accordée.
    ///
    /// **Désactivé en pratique depuis V1.7** : on s'appuie maintenant sur
    /// `CKQuerySubscription` sur `SeizureEvent` qui déclenche un push APNs
    /// visible directement via iOS, sans transiter par cette fonction.
    /// Conservée comme filet de secours pour un éventuel fallback futur
    /// (rate-limiting APNs, débogage).
    @available(*, deprecated, message: "Replaced by CKQuerySubscription on SeizureEvent — see ensureSubscriptions().")
    private func notifyRemoteSeizures(count: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Nouvelle crise enregistrée"
        if let owner = ownerDisplayNameFromShare, !owner.isEmpty {
            content.body = count == 1
                ? "\(owner) vient d'enregistrer une crise. Ouvrez RettApp pour voir le détail."
                : "\(owner) vient d'enregistrer \(count) crises. Ouvrez RettApp pour voir le détail."
        } else {
            content.body = count == 1
                ? "L'autre parent vient d'enregistrer une crise. Ouvrez RettApp pour voir le détail."
                : "L'autre parent vient d'enregistrer \(count) crises. Ouvrez RettApp pour voir le détail."
        }
        content.sound = .default
        content.categoryIdentifier = "afsr.remote.seizure"
        let id = "afsr.remote.seizure.\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        do {
            try await center.add(request)
            Self.log.info("Notif locale émise pour \(count) crise(s) distantes")
        } catch {
            Self.log.error("notifyRemoteSeizures: \(error.localizedDescription)")
        }
    }

    /// Pull une zone individuelle, en plusieurs passes si `moreComing` est vrai.
    /// Met à jour le `CKServerChangeToken` persistant à la fin de chaque passe
    /// (donc on ne re-télécharge pas tout si une passe ultérieure échoue).
    private func pullZone(
        zoneID: CKRecordZone.ID,
        scope: CKDatabase.Scope,
        database: CKDatabase,
        context: ModelContext,
        upserted: inout Int,
        deleted: inout Int
    ) async throws {
        var sinceToken = ChangeTokenStore.load(zoneID: zoneID, scope: scope)
        var moreComing = true

        while moreComing {
            let result: (
                modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, Error>],
                deletions: [CKDatabase.RecordZoneChange.Deletion],
                changeToken: CKServerChangeToken,
                moreComing: Bool
            )
            do {
                result = try await database.recordZoneChanges(inZoneWith: zoneID, since: sinceToken)
            } catch let error as CKError where error.code == .changeTokenExpired {
                // Le serveur a rejeté notre token (ex. zone réinitialisée) —
                // on repart de zéro pour cette zone.
                Self.log.info("pullZone: token expiré pour \(zoneID.zoneName), reset")
                ChangeTokenStore.clear(zoneID: zoneID, scope: scope)
                sinceToken = nil
                continue
            }

            for (_, modResult) in result.modificationResultsByID {
                switch modResult {
                case .success(let modification):
                    upsert(modification.record, in: context)
                    upserted += 1
                case .failure(let err):
                    Self.log.error("Pull modif: \(err.localizedDescription)")
                }
            }
            for deletion in result.deletions {
                deleteLocal(recordID: deletion.recordID, in: context)
                deleted += 1
            }

            ChangeTokenStore.save(result.changeToken, zoneID: zoneID, scope: scope)
            sinceToken = result.changeToken
            moreComing = result.moreComing
        }
    }

    private func upsert(_ record: CKRecord, in context: ModelContext) {
        switch record.recordType {
        case CKRecordType.childProfile:     ChildProfile.upsert(from: record, in: context)
        case CKRecordType.medication:       Medication.upsert(from: record, in: context)
        case CKRecordType.medicationLog:    MedicationLog.upsert(from: record, in: context)
        case CKRecordType.seizure:          SeizureEvent.upsert(from: record, in: context)
        case CKRecordType.mood:             MoodEntry.upsert(from: record, in: context)
        case CKRecordType.dailyObservation: DailyObservation.upsert(from: record, in: context)
        case CKRecordType.symptom:          SymptomEvent.upsert(from: record, in: context)
        case CKRecordType.medicationRevision: MedicationRevision.upsert(from: record, in: context)
        default: break
        }
    }

    /// Supprime localement le record correspondant à une suppression CloudKit
    /// distante. Exposé en `static internal` pour être appelable depuis les
    /// tests (round-trip de suppression) sans avoir à instancier le service.
    ///
    /// `nonisolated` parce que la classe est `@MainActor` mais cette méthode
    /// n'accède à aucun état d'instance — uniquement au `ModelContext` passé
    /// en paramètre, qui porte sa propre garantie d'isolation. Sans ce
    /// `nonisolated`, les tests (non-MainActor) ne pourraient pas l'appeler
    /// directement.
    nonisolated static func deleteLocal(recordID: CKRecord.ID, in context: ModelContext) {
        guard let id = UUID(uuidString: recordID.recordName) else { return }

        // On essaie chacun des 7 types — c'est le moyen le plus simple sans avoir
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
        if let sym = try? context.fetch(FetchDescriptor<SymptomEvent>(predicate: #Predicate { $0.id == id })).first {
            context.delete(sym); return
        }
        if let rev = try? context.fetch(FetchDescriptor<MedicationRevision>(predicate: #Predicate { $0.id == id })).first {
            context.delete(rev); return
        }
    }

    private func deleteLocal(recordID: CKRecord.ID, in context: ModelContext) {
        Self.deleteLocal(recordID: recordID, in: context)
    }

    /// Supprime côté serveur les CKRecord des logs « perdants » fusionnés par la
    /// dedup post-pull. Sans cette étape, chaque prochain pull ré-injecterait
    /// le doublon dans SwiftData et la boucle continuerait indéfiniment.
    /// Best-effort : les échecs sont loggés sans casser le flux principal, la
    /// dedup finit toujours par converger côté local.
    func deleteLogRecordsInCloudKit(_ ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        let database = appropriateDatabase()
        // On liste toutes les zones dispo pour être robuste au cas participant/owner.
        let zoneIDs: [CKRecordZone.ID]
        if appropriateDatabaseScope() == .private {
            guard let zone = try? await ensureZone() else { return }
            zoneIDs = [zone.zoneID]
        } else {
            zoneIDs = (try? await database.allRecordZones().map { $0.zoneID }) ?? []
        }
        for zoneID in zoneIDs {
            let recordIDs = ids.map { CKRecord.ID(recordName: $0.uuidString, zoneID: zoneID) }
            do {
                _ = try await database.modifyRecords(saving: [], deleting: recordIDs)
                Self.log.info("Supprimé \(recordIDs.count) CKRecord(s) MedicationLog perdants dans \(zoneID.zoneName)")
            } catch {
                Self.log.error("deleteLogRecordsInCloudKit KO (\(zoneID.zoneName)) : \(error.localizedDescription)")
            }
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

    // MARK: - Subscriptions (silent push notifications)

    /// S'assure que les `CKDatabaseSubscription` sont enregistrées pour la
    /// base privée et la base partagée. Quand l'autre parent (ou nous-mêmes
    /// depuis un autre appareil) modifie un record, CloudKit envoie un push
    /// silencieux (`shouldSendContentAvailable = true`) à l'app — l'AppDelegate
    /// intercepte la notif et déclenche un `quickPull` pour rafraîchir
    /// l'écran sans intervention de l'utilisateur.
    ///
    /// Idempotent : la première fois on enregistre, ensuite on no-op (drapeau
    /// dans `UserDefaults`).
    func ensureSubscriptions() async {
        guard accountStatus == .available else { return }

        // On enregistre TOUJOURS de façon idempotente : chaque helper
        // interne fait un `subscription(for:)` et no-op si présente. Le
        // flag UserDefaults servait de shortcut mais il empêchait le
        // ré-enregistrement quand CloudKit purgeait silencieusement les
        // subscriptions (inactivité > ~1 mois, reset de compte iCloud, etc.),
        // donc plus jamais de push silencieux jusqu'au prochain resetSyncState
        // manuel. On préfère un no-op réseau court à un silence total.
        do {
            try await registerDatabaseSubscription(
                database: container.privateCloudDatabase,
                subscriptionID: "afsr.private.changes"
            )
            try await registerDatabaseSubscription(
                database: container.sharedCloudDatabase,
                subscriptionID: "afsr.shared.changes"
            )
            try await registerSeizureAlertSubscription(
                database: container.privateCloudDatabase,
                subscriptionID: "afsr.private.seizure.alert"
            )
            try await registerSeizureAlertSubscription(
                database: container.sharedCloudDatabase,
                subscriptionID: "afsr.shared.seizure.alert"
            )
            UserDefaults.standard.set(true, forKey: Self.subscriptionsRegisteredKey)
            Self.log.info("CKSubscriptions ensured (database + seizure alerts)")
        } catch {
            Self.log.error("ensureSubscriptions error: \(error.localizedDescription)")
        }
    }

    /// Rate-limited : audite les subscriptions au maximum une fois par heure.
    /// À appeler à chaque foreground pour détecter les purges silencieuses
    /// que CloudKit peut faire après une longue inactivité.
    func auditSubscriptionsIfDue() async {
        if let last = lastSubscriptionAuditAt, Date().timeIntervalSince(last) < 3600 {
            return
        }
        lastSubscriptionAuditAt = Date()
        await ensureSubscriptions()
    }

    /// Crée un `CKQuerySubscription` qui se déclenche à chaque création d'un
    /// `SeizureEvent` dans la base donnée. Configurée pour livrer une notif
    /// visible (avec son + badge + alertBody) — le médecin sait qu'une
    /// crise est en cours sans avoir à ouvrir l'app.
    private func registerSeizureAlertSubscription(database: CKDatabase, subscriptionID: String) async throws {
        let id = CKSubscription.ID(subscriptionID)
        do {
            _ = try await database.subscription(for: id)
            return
        } catch let error as CKError where error.code == .unknownItem {
            // tomber dans la création
        }

        let subscription = CKQuerySubscription(
            recordType: CKRecordType.seizure,
            predicate: NSPredicate(value: true),
            subscriptionID: id,
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        info.alertBody = "⚠️ Une crise vient d'être enregistrée par l'autre parent. Ouvrez RettApp pour voir le détail."
        info.soundName = "default"
        info.shouldBadge = true
        // shouldSendContentAvailable réveille aussi l'app pour qu'elle
        // pull immédiatement le record et qu'il apparaisse dans le journal
        // au moment où l'utilisateur tape sur la notif.
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.save(subscription)
    }

    private static let subscriptionsRegisteredKey = "afsr.ck.subscriptionsRegistered.v2"

    private func registerDatabaseSubscription(database: CKDatabase, subscriptionID: String) async throws {
        let id = CKSubscription.ID(subscriptionID)
        // Si déjà existante côté serveur, on ne fait rien.
        do {
            _ = try await database.subscription(for: id)
            return
        } catch let error as CKError where error.code == .unknownItem {
            // tomber dans la création
        }

        let subscription = CKDatabaseSubscription(subscriptionID: id)
        let info = CKSubscription.NotificationInfo()
        // Silent push : pas d'UI, juste un wake-up de l'app pour qu'elle pulle.
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.save(subscription)
    }

    // MARK: - Auto-sync (debounce)

    /// Priorité de planification d'une synchronisation : ajuste le délai de
    /// debounce pour équilibrer fraîcheur côté autre parent vs. coût réseau /
    /// batterie. À utiliser avec `scheduleSync(context:priority:)`.
    enum SyncPriority {
        /// Évènement médical : crise d'épilepsie, prise de médicament marquée
        /// effectuée. Le délai est très court pour que l'autre parent voie
        /// l'info quasi tout de suite.
        case urgent
        /// Édition standard : nouvelle dose, observation quotidienne, etc.
        case normal
        /// Édition lourde rarement consultée immédiatement par l'autre
        /// parent (plan médicamenteux complet, profil enfant).
        case relaxed

        fileprivate var delay: TimeInterval {
            switch self {
            case .urgent:  return 0.5
            case .normal:  return 3.0
            case .relaxed: return 10.0
            }
        }
    }

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
    func scheduleSync(context: ModelContext, priority: SyncPriority = .normal) {
        guard role != .none else { return }
        pendingSyncTask?.cancel()
        let delay = priority.delay
        pendingSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.performCycle(context: context, reason: "scheduleSync(\(priority))")
        }
    }

    /// Push tout ce qui est en attente PUIS pull. Sérialisé via `SyncGate`
    /// pour qu'un seul cycle tourne à la fois — un `scheduleSync` déclenché
    /// pendant qu'un autre finit s'enfile derrière.
    ///
    /// Ne lève JAMAIS : les erreurs sont capturées, remontées dans
    /// `syncState`/`lastErrorMessage` (pour le bandeau UI) et loggées.
    func performCycle(context: ModelContext, reason: String) async {
        guard role != .none, accountStatus == .available else { return }
        do {
            try await gate.run { [self] in
                syncState = .syncing
                defer { if case .syncing = syncState { syncState = .idle } }
                do {
                    try await drainPendingWrites(context: context)
                } catch {
                    Self.log.error("[\(reason)] drain KO : \(error.localizedDescription)")
                    lastErrorMessage = error.localizedDescription
                    syncState = .error(error.localizedDescription)
                }
                do {
                    try await pullChanges(into: context)
                    // Un pull complet réussi = les erreurs précédentes n'ont
                    // plus lieu d'être surfacées à l'utilisateur.
                    if PendingWriteStore.shared.pendingCount == 0 {
                        lastErrorMessage = nil
                        if case .error = syncState { syncState = .idle }
                    }
                } catch {
                    Self.log.error("[\(reason)] pull KO : \(error.localizedDescription)")
                    lastErrorMessage = error.localizedDescription
                    syncState = .error(error.localizedDescription)
                }
            }
        } catch {
            Self.log.error("[\(reason)] gate KO : \(error.localizedDescription)")
        }
    }

    /// Pull immédiat best-effort (appelé typiquement au foreground de l'app).
    /// Silencieux en cas d'erreur — ne perturbe pas l'UI.
    func quickPull(context: ModelContext) async {
        guard role != .none, accountStatus == .available else { return }
        await performCycle(context: context, reason: "quickPull")
    }

    /// Déclenche un cycle immédiat (bouton « Réessayer », UI settings).
    /// Contrairement à `quickPull`, force le drain même si le buffer est vide,
    /// utile pour valider que la connexion CloudKit fonctionne.
    func syncNow(context: ModelContext) async {
        await performCycle(context: context, reason: "manual")
    }

    // MARK: - Hard reset (recovery)

    /// Réinitialisation complète de la couche de synchronisation. À utiliser
    /// quand quelque chose part en biais : tokens corrompus, subscriptions
    /// désynchronisées, données qui ne convergent plus.
    ///
    /// Effet :
    ///   1. Purge tous les `CKServerChangeToken` persistés → prochain pull
    ///      re-télécharge l'intégralité des records.
    ///   2. Re-enregistre les `CKDatabaseSubscription` (silent push) en
    ///      effaçant le drapeau « déjà fait ».
    ///   3. Pousse l'état local puis pull tout, pour repartir sur une base
    ///      commune et complète des deux côtés.
    ///
    /// Ne touche **pas** aux records locaux SwiftData ni au `CKShare` :
    /// l'utilisateur garde ses données et son partage. C'est uniquement la
    /// mécanique de sync qui est remise à zéro.
    func resetSyncState(context: ModelContext) async throws {
        Self.log.info("resetSyncState: purge des tokens + re-souscription + re-sync complète")
        ChangeTokenStore.clearAll()
        UserDefaults.standard.removeObject(forKey: Self.subscriptionsRegisteredKey)
        await ensureSubscriptions()
        try await replicateAll(from: context)
        try await pullChanges(into: context)
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

// MARK: - Remote activity (timeline UI)

/// Une entrée de la timeline d'activité distante affichée dans
/// « Réglages → Partage entre parents ». Représente un événement type :
/// « l'autre parent a ajouté 3 observations » à un instant donné.
struct RemoteActivity: Identifiable, Hashable {
    let id: UUID = UUID()
    let entity: Entity
    let count: Int
    let timestamp: Date

    enum Entity: String, Hashable {
        case medication, medicationLog, seizure, mood, observation, symptom

        var label: String {
            switch self {
            case .medication:    return "médicament"
            case .medicationLog: return "prise de médicament"
            case .seizure:       return "crise"
            case .mood:          return "humeur"
            case .observation:   return "observation"
            case .symptom:       return "symptôme"
            }
        }

        var pluralLabel: String {
            switch self {
            case .medication:    return "médicaments"
            case .medicationLog: return "prises de médicament"
            case .seizure:       return "crises"
            case .mood:          return "humeurs"
            case .observation:   return "observations"
            case .symptom:       return "symptômes"
            }
        }

        var icon: String {
            switch self {
            case .medication, .medicationLog: return "pills.fill"
            case .seizure:                    return "waveform.path.ecg"
            case .mood:                       return "face.smiling"
            case .observation:                return "fork.knife"
            case .symptom:                    return "stethoscope"
            }
        }
    }
}

/// Compteurs par type d'entité utilisés pour calculer un diff après pull.
fileprivate struct EntityCounts {
    let medications: Int
    let medicationLogs: Int
    let seizures: Int
    let moods: Int
    let observations: Int
    let symptoms: Int

    func diff(against base: EntityCounts) -> [RemoteActivity.Entity: Int] {
        [
            .medication:    medications    - base.medications,
            .medicationLog: medicationLogs - base.medicationLogs,
            .seizure:       seizures       - base.seizures,
            .mood:          moods          - base.moods,
            .observation:   observations   - base.observations,
            .symptom:       symptoms       - base.symptoms
        ]
    }
}

// MARK: - Change-token persistence

/// Stockage des `CKServerChangeToken` dans `UserDefaults`, indexés par
/// `(scope, zoneID)`. Les tokens sont sérialisés via `NSKeyedArchiver` —
/// `CKServerChangeToken` adopte `NSSecureCoding`.
///
/// Persistance volontairement légère : pas besoin du Keychain, les tokens
/// ne sont pas des secrets, juste des bookmarks vers la position serveur.
enum ChangeTokenStore {
    private static let keyPrefix = "afsr.ck.changeToken"

    static func key(zoneID: CKRecordZone.ID, scope: CKDatabase.Scope) -> String {
        let scopeStr: String
        switch scope {
        case .private: scopeStr = "private"
        case .shared:  scopeStr = "shared"
        case .public:  scopeStr = "public"
        @unknown default: scopeStr = "unknown"
        }
        return "\(keyPrefix).\(scopeStr).\(zoneID.ownerName).\(zoneID.zoneName)"
    }

    static func save(_ token: CKServerChangeToken, zoneID: CKRecordZone.ID, scope: CKDatabase.Scope) {
        let k = key(zoneID: zoneID, scope: scope)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: k)
        }
    }

    static func load(zoneID: CKRecordZone.ID, scope: CKDatabase.Scope) -> CKServerChangeToken? {
        let k = key(zoneID: zoneID, scope: scope)
        guard let data = UserDefaults.standard.data(forKey: k) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    static func clear(zoneID: CKRecordZone.ID, scope: CKDatabase.Scope) {
        UserDefaults.standard.removeObject(forKey: key(zoneID: zoneID, scope: scope))
    }

    /// Purge toutes les entrées (utilisé à `stopSharing` / `leaveShare`).
    static func clearAll() {
        let defaults = UserDefaults.standard
        for k in defaults.dictionaryRepresentation().keys where k.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: k)
        }
    }
}

// MARK: - Erreurs

enum SyncError: LocalizedError {
    case iCloudUnavailable(CloudKitSyncService.AccountStatus)
    case shareURLUnavailable
    case shareSaveFailed(underlying: Error)
    case perRecordPushFailed(count: Int)

    var errorDescription: String? {
        switch self {
        case .perRecordPushFailed(let count):
            return "Impossible de pousser \(count) enregistrement(s) vers iCloud. Ils seront réessayés à la prochaine synchronisation."
        case .iCloudUnavailable(let status):
            switch status {
            case .noAccount: return "Aucun compte iCloud connecté. Activez iCloud dans Réglages iOS."
            case .restricted: return "iCloud restreint sur cet appareil (contrôle parental)."
            case .unavailable: return "iCloud temporairement indisponible. Réessayez plus tard."
            default: return "iCloud non disponible."
            }
        case .shareURLUnavailable:
            return "L'URL de partage n'a pas pu être générée. Le schéma CloudKit en production n'est probablement pas déployé — vérifiez le CloudKit Dashboard."
        case .shareSaveFailed(let err):
            // Distingue les cas les plus fréquents en production. Tous les
            // autres restent loggés en console pour diagnostic.
            if let ck = err as? CKError {
                switch ck.code {
                case .notAuthenticated:
                    return "Compte iCloud non authentifié. Vérifiez Réglages iOS → [votre nom] → iCloud."
                case .networkUnavailable, .networkFailure:
                    return "Réseau iCloud indisponible. Réessayez en Wi-Fi."
                case .quotaExceeded:
                    return "Espace iCloud insuffisant. Libérez de l'espace dans Réglages iCloud."
                case .permissionFailure:
                    return "Autorisation iCloud refusée pour le conteneur de l'app. Vérifiez Réglages iCloud → RettApp."
                default:
                    return "Le partage CloudKit a échoué (code \(ck.errorCode)). Détail : \(ck.localizedDescription)"
                }
            }
            return "Le partage CloudKit a échoué : \(err.localizedDescription)"
        }
    }
}
