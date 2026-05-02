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
            DailyObservation.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Impossible d'initialiser le ModelContainer : \(error)")
        }
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
