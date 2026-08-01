import SwiftUI
import SwiftData
import CloudKit

@main
struct RettAppApp: App {
    @UIApplicationDelegateAdaptor(RettAppDelegate.self) private var appDelegate
    @State private var syncService = CloudKitSyncService()
    @State private var updateService = UpdateAvailabilityService()
    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ChildProfile.self,
            SeizureEvent.self,
            Medication.self,
            MedicationLog.self,
            MoodEntry.self,
            DailyObservation.self,
            SymptomEvent.self,
            MedicationRevision.self
        ])

        // On utilise un nom de fichier versionné — ça évite tout résidu d'un store
        // antérieur dont le schéma serait incompatible (lightweight migration absente).
        let storeURL = URL.applicationSupportDirectory.appending(path: "rettapp_v7.store")
        // IMPORTANT : `cloudKitDatabase: .none` désactive la sync auto SwiftData ↔ CloudKit.
        // Sans cela, comme on a déclaré l'entitlement iCloud (pour le partage entre parents),
        // SwiftData tenterait d'activer son intégration CloudKit native — qui exige que
        // TOUS les attributs soient optionnels et que les @Attribute(.unique) disparaissent.
        // Notre partage entre parents est géré manuellement via CloudKitSyncService, pas
        // par SwiftData ; le store local doit donc rester strict.
        let config = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        // 1) Tentative normale
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            logSwiftDataError("init #1 (disque, store v4)", error)
        }

        // 2) Recovery : efface le store v4 et retente
        let wal = storeURL.appendingPathExtension("wal")
        let shm = storeURL.appendingPathExtension("shm")
        for url in [storeURL, wal, shm] {
            try? FileManager.default.removeItem(at: url)
        }
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            logSwiftDataError("init #2 (disque après wipe)", error)
        }

        // 3) In-memory — l'app reste fonctionnelle pour la session
        let memConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [memConfig])
        } catch {
            logSwiftDataError("init #3 (in-memory)", error)
        }

        // 4) Diagnostic ultime : trouve le model qui pose problème en testant un par un
        let models: [(String, any PersistentModel.Type)] = [
            ("ChildProfile", ChildProfile.self),
            ("SeizureEvent", SeizureEvent.self),
            ("Medication", Medication.self),
            ("MedicationLog", MedicationLog.self),
            ("MoodEntry", MoodEntry.self),
            ("DailyObservation", DailyObservation.self),
            ("SymptomEvent", SymptomEvent.self),
            ("MedicationRevision", MedicationRevision.self)
        ]
        for (name, model) in models {
            let s = Schema([model])
            let c = ModelConfiguration(
                schema: s,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            do {
                _ = try ModelContainer(for: s, configurations: [c])
                print("✅ Schema OK (in-memory) : \(name)")
            } catch {
                print("❌ Schema KO (in-memory) : \(name) — \(error)")
            }
        }

        fatalError("Aucune init ModelContainer n'a réussi. Voir les logs ci-dessus.")
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(syncService)
                .environment(updateService)
                .tint(.afsrPurpleAdaptive)
                .task {
                    // Watchdog : quoi qu'il arrive (offline, iCloud lent), on
                    // débloque l'onboarding après 8 s pour ne jamais bloquer
                    // un premier lancement sans réseau.
                    let watchdog = Task { [syncService] in
                        try? await Task.sleep(nanoseconds: 8_000_000_000)
                        syncService.initialCloudCheckDone = true
                    }
                    defer {
                        watchdog.cancel()
                        syncService.initialCloudCheckDone = true
                    }

                    await syncService.refreshAccountStatus()
                    await syncService.refreshShareStatus()
                    // Enregistre les CKDatabaseSubscription pour recevoir des
                    // pushes silencieux quand l'autre parent modifie un record.
                    // `auditSubscriptionsIfDue()` prend en compte le rate-limit
                    // mou (1×/h) et ré-enregistre ce que CloudKit aurait purgé.
                    await syncService.auditSubscriptionsIfDue()
                    // Backfill des révisions de plan médicamenteux pour les
                    // utilisateurs qui passent depuis une version antérieure
                    // à cette feature. Idempotent.
                    MedicationRevision.backfillIfNeeded(in: sharedModelContainer.mainContext)
                    // Migration one-shot : collapse les logs planifiés en doublon
                    // (UUID aléatoire par parent avant fix de la sync). Prend
                    // effet une seule fois puis reste no-op.
                    MedicationLog.dedupeScheduledLogsIfNeeded(in: sharedModelContainer.mainContext)
                    // Draine tout ce qui est resté dans le buffer d'écriture
                    // depuis la dernière session (offline, crash, kill app…).
                    await syncService.performCycle(context: sharedModelContainer.mainContext, reason: "launch")
                    // Le pull de lancement est fini : RootView peut décider
                    // (onboarding vs données restaurées) sans attendre le reste.
                    syncService.initialCloudCheckDone = true
                    // Bandeau de mise à jour App Store. Cache 24 h, silencieux
                    // en cas d'échec réseau — jamais bloquant.
                    await updateService.checkForUpdate()
                }
                .onReceive(NotificationCenter.default.publisher(for: RettAppDelegate.cloudKitRemoteChange)) { _ in
                    Task { @MainActor in
                        await syncService.performCycle(context: sharedModelContainer.mainContext, reason: "silent-push")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: RettAppDelegate.didReceiveShareMetadata)) { note in
                    guard let metadata = note.object as? CKShare.Metadata else { return }
                    Task { @MainActor in
                        do {
                            try await syncService.acceptShare(metadata)
                            try await syncService.pullChanges(into: sharedModelContainer.mainContext)
                            await syncService.refreshShareStatus()
                        } catch {
                            syncService.lastErrorMessage = error.localizedDescription
                        }
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // Pull silencieux à chaque retour au foreground pour que
                    // les changements de l'autre parent apparaissent sans
                    // intervention manuelle.
                    if newPhase == .active {
                        Task { @MainActor in
                            await syncService.refreshAccountStatus()
                            await syncService.refreshShareStatus()
                            await syncService.auditSubscriptionsIfDue()
                            await syncService.performCycle(context: sharedModelContainer.mainContext, reason: "foreground")
                            await updateService.checkForUpdate()
                        }
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

private func logSwiftDataError(_ stage: String, _ error: Error) {
    print("⚠️ ModelContainer \(stage) — \(type(of: error))")
    print("   description : \(error)")
    print("   localized   : \(error.localizedDescription)")
    let ns = error as NSError
    print("   domain      : \(ns.domain)")
    print("   code        : \(ns.code)")
    if !ns.userInfo.isEmpty {
        for (key, value) in ns.userInfo {
            print("   userInfo[\(key)] = \(value)")
        }
    }
}

/// Vue racine : montre l'onboarding tant qu'aucun profil enfant n'existe,
/// puis l'écran principal. Aucune authentification utilisateur — toutes les
/// données restent locales (SwiftData) ou dans l'iCloud personnel de
/// l'utilisateur (CloudKit Sharing). Le compte iCloud du device sert
/// d'identité ; pas besoin de Sign in with Apple.
///
/// **Garde anti-doublon multi-appareil** : sur un appareil fraîchement
/// installé, on attend la fin du premier check iCloud (`initialCloudCheckDone`,
/// watchdog 8 s) avant de proposer l'onboarding. Si un suivi existe déjà sur
/// le compte (2ᵉ iPhone/iPad du même parent, ou partage accepté), le pull le
/// ramène pendant cette attente et l'app ouvre directement l'écran principal
/// — au lieu de faire re-saisir profil + plan et de créer des doublons.
struct RootView: View {
    @Query private var profiles: [ChildProfile]
    @Environment(CloudKitSyncService.self) private var sync

    var body: some View {
        if !profiles.isEmpty {
            ContentView()
        } else if sync.initialCloudCheckDone {
            ProfileSetupView()
        } else {
            CloudRestoreCheckView()
        }
    }
}

/// Écran d'attente affiché quelques secondes au premier lancement, le temps
/// de vérifier si un suivi existe déjà sur iCloud (2ᵉ appareil, partage).
private struct CloudRestoreCheckView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Recherche d'un suivi existant…")
                .font(.headline)
            Text("Si vous avez déjà utilisé RettApp sur un autre appareil ou accepté un partage, vos données vont apparaître automatiquement.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.afsrBackground.ignoresSafeArea())
    }
}
