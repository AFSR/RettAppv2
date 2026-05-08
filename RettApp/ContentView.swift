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
            if FeatureFlags.newsEnabled {
                NavigationStack { NewsListView() }
                    .tabItem { Label("Actualités", systemImage: "newspaper.fill") }
            }

            NavigationStack { JournalView() }
                .tabItem { Label("Journal", systemImage: "book.pages.fill") }
                .badge(epilepsyEnabled ? currentMonthSeizureCount : 0)

            if epilepsyEnabled {
                NavigationStack { DashboardView() }
                    .tabItem { Label("Bilan", systemImage: "chart.bar.xaxis") }
            }

            NavigationStack { SettingsView() }
                .tabItem { Label("Réglages", systemImage: "gear") }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
