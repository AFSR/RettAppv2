import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var profiles: [ChildProfile]
    @Query(sort: \SeizureEvent.startTime, order: .reverse) private var seizures: [SeizureEvent]

    private var currentMonthSeizureCount: Int {
        let cal = Calendar.current
        let now = Date()
        return seizures.filter {
            cal.isDate($0.startTime, equalTo: now, toGranularity: .month)
        }.count
    }

    private var epilepsyEnabled: Bool {
        profiles.first?.hasEpilepsy ?? false
    }

    var body: some View {
        TabView {
            NavigationStack { NewsListView() }
                .tabItem { Label("Actualités", systemImage: "newspaper.fill") }

            if epilepsyEnabled {
                NavigationStack { SeizureTrackerView() }
                    .tabItem { Label("Épilepsie", systemImage: "waveform.path.ecg") }
                    .badge(currentMonthSeizureCount)
            }

            NavigationStack { MedicationListView() }
                .tabItem { Label("Médicaments", systemImage: "pill.fill") }

            NavigationStack { EyeGameView() }
                .tabItem { Label("Jeu Regard", systemImage: "eye.fill") }

            NavigationStack { SettingsView() }
                .tabItem { Label("Réglages", systemImage: "gear") }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
        .environment(AuthManager.previewSignedIn())
}
