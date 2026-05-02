import SwiftUI
import SwiftData

@main
struct RettAppApp: App {
    @State private var authManager = AuthManager()

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
                .tint(.afsrPurpleAdaptive)
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
