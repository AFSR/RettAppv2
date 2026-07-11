import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var profiles: [ChildProfile]
    @Query(sort: \SeizureEvent.startTime, order: .reverse) private var seizures: [SeizureEvent]
    @Environment(UpdateAvailabilityService.self) private var updateService

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
        // Bandeau de mise à jour en overlay : reste au-dessus du TabView, sans
        // pousser le contenu vers le bas, et animé pour ne pas surgir sèchement.
        .safeAreaInset(edge: .top) {
            if let info = updateService.availableUpdate {
                UpdateAvailabilityBanner(info: info) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        updateService.dismissCurrentBanner()
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: updateService.availableUpdate)
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
        .environment(UpdateAvailabilityService())
}
