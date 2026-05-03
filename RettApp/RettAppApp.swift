import SwiftUI
import SwiftData
import CloudKit

@main
struct RettAppApp: App {
    @UIApplicationDelegateAdaptor(RettAppDelegate.self) private var appDelegate
    @State private var authManager = AuthManager()
    @State private var syncService = CloudKitSyncService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ChildProfile.self,
            SeizureEvent.self,
            Medication.self,
            MedicationLog.self,
            MoodEntry.self,
            DailyObservation.self,
            SymptomEvent.self
        ])

        // On utilise un nom de fichier versionné — ça évite tout résidu d'un store
        // antérieur dont le schéma serait incompatible (lightweight migration absente).
        let storeURL = URL.applicationSupportDirectory.appending(path: "rettapp_v5.store")
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
            ("SymptomEvent", SymptomEvent.self)
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
                .environment(authManager)
                .environment(syncService)
                .tint(.afsrPurpleAdaptive)
                .task {
                    await syncService.refreshAccountStatus()
                    await syncService.refreshShareStatus()
                }
                .onReceive(NotificationCenter.default.publisher(for: RettAppDelegate.didReceiveShareMetadata)) { note in
                    guard let metadata = note.object as? CKShare.Metadata else { return }
                    Task { @MainActor in
                        do {
                            try await syncService.acceptShare(metadata)
                            try await syncService.pullChanges(into: sharedModelContainer.mainContext)
                        } catch {
                            syncService.lastErrorMessage = error.localizedDescription
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

struct RootView: View {
    @Environment(AuthManager.self) private var authManager
    @Query private var profiles: [ChildProfile]

    var body: some View {
        Group {
            switch authManager.state {
            case .signedOut:
                SignInView()
            case .signedIn:
                if profiles.isEmpty {
                    ProfileSetupView()
                } else {
                    ContentView()
                }
            case .checking:
                ProgressView("Chargement…")
                    .controlSize(.large)
            }
        }
        .task { await authManager.restoreSession() }
    }
}
