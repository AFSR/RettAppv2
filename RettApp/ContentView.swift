import SwiftUI
import SwiftData

struct ContentView: View {
    /// Usage de cette session. Décide des onglets : en découverte, ce qui ne
    /// sert pas n'apparaît pas — pas d'onglet vide ni de menu grisé.
    let usage: AppUsage

    @Query private var profiles: [ChildProfile]
    @Query(sort: \SeizureEvent.startTime, order: .reverse) private var seizures: [SeizureEvent]
    @Environment(UpdateAvailabilityService.self) private var updateService

    init(usage: AppUsage = .suivi) {
        self.usage = usage
    }

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
            // Les actualités s'adressent aux deux usages : c'est la moitié de
            // la proposition pour qui découvre, et un lien avec l'association
            // pour les familles.
            if FeatureFlags.newsEnabled {
                NavigationStack { NewsListView() }
                    .tabItem { Label("Actualités", systemImage: "newspaper.fill") }
            }

            if usage == .suivi {
                NavigationStack { JournalView() }
                    .tabItem { Label("Journal", systemImage: "book.pages.fill") }
                    .badge(epilepsyEnabled ? currentMonthSeizureCount : 0)

                if epilepsyEnabled {
                    NavigationStack { DashboardView() }
                        .tabItem { Label("Bilan", systemImage: "chart.bar.xaxis") }
                }
            } else {
                NavigationStack { DiscoveryHomeView() }
                    .tabItem { Label("AFSR", systemImage: "heart.circle.fill") }
            }

            // Les lieux Rett friendly : un annuaire public, utile à tous.
            NavigationStack { PlacesView() }
                .tabItem { Label("Lieux", systemImage: "map.fill") }

            // Onglet réservé aux personnes connectées à leur compte AFSR.
            if MemberSession.shared.isSignedIn {
                NavigationStack { MemberAreaView() }
                    .tabItem { Label("Adhérent", systemImage: "person.crop.circle.fill") }
            }

            NavigationStack { SettingsView(usage: usage) }
                .tabItem { Label("Réglages", systemImage: "gear") }
        }
        // Bandeaux en overlay : au-dessus du TabView, sans pousser le contenu
        // vers le bas, animés pour ne pas surgir sèchement. On empile
        // (erreur/pending) EN HAUT (plus critique) puis update dessous.
        .safeAreaInset(edge: .top) {
            VStack(spacing: 6) {
                // Le bandeau de synchronisation ne concerne que le suivi :
                // en découverte, rien n'est synchronisé entre parents, donc
                // afficher un état de synchro n'aurait aucun sens.
                if usage == .suivi {
                    SyncStatusBanner()
                }
                if let info = updateService.availableUpdate {
                    UpdateAvailabilityBanner(info: info) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            updateService.dismissCurrentBanner()
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: updateService.availableUpdate)
    }
}

#Preview("Usage suivi") {
    ContentView(usage: .suivi)
        .modelContainer(PreviewData.container)
        .environment(UpdateAvailabilityService())
        .environment(UsageModeStore.shared)
}

#Preview("Usage découverte") {
    ContentView(usage: .decouverte)
        .modelContainer(PreviewData.container)
        .environment(UpdateAvailabilityService())
        .environment(UsageModeStore.shared)
}
