import SwiftUI
import SwiftData

/// Écran principal du cahier de suivi : génération + archive.
/// La configuration (sections, médicaments par prise, repas, symptômes…) est
/// déportée dans `BookletConfigurationView` accessible via NavigationLink.
/// Cette page reste compacte : période, libellé, bouton générer, archive.
struct FollowUpBookletView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]

    @State private var periodLabel = ""
    @State private var generating = false
    @State private var lastURL: URL?
    @State private var showShare = false
    @State private var errorMessage: String?
    @State private var archived: [URL] = []
    @State private var toShare: URL?

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    BookletConfigurationView()
                } label: {
                    Label("Configurer le cahier", systemImage: "slider.horizontal.3")
                }
            } footer: {
                Text("Sections incluses, prises de médicaments à suivre par horaire, repas, symptômes Rett, événements particuliers…")
            }

            Section("Libellé de la période") {
                TextField("ex. Semaine du 27 mai au 2 juin", text: $periodLabel)
            }

            Section {
                Button {
                    Task { await generate() }
                } label: {
                    HStack {
                        if generating { ProgressView().controlSize(.small) }
                        Text(generating ? "Génération…" : "Générer le cahier PDF")
                    }
                }
                .disabled(generating || !atLeastOneSectionSelected)
            } footer: {
                Text("Une seule page A4 portrait, 100 % cases à cocher (fréquence, intensité, quantité pré-définies). Imprimé puis confié à l'équipe encadrante (école, IME, IMP, centre).")
            }

            if !archived.isEmpty {
                Section("Cahiers archivés") {
                    ForEach(archived, id: \.self) { url in
                        ArchivedFileRow(url: url) {
                            toShare = url
                        } onDelete: {
                            try? FollowUpBookletGenerator.deleteBooklet(url)
                            refresh()
                        }
                    }
                }
            }
        }
        .navigationTitle("Cahier de suivi")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refresh()
            if periodLabel.isEmpty { periodLabel = defaultPeriodLabel() }
        }
        .sheet(isPresented: $showShare) {
            if let u = lastURL { ShareSheet(items: [u]) }
        }
        .sheet(item: Binding(
            get: { toShare.map { ShareItem(url: $0) } },
            set: { toShare = $0?.url }
        )) { item in
            ShareSheet(items: [item.url])
        }
        .alert("Erreur", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var atLeastOneSectionSelected: Bool {
        let c = BookletConfigStore.shared
        return c.includeMedicationGrid || c.includeSeizureGrid || c.includeMoodGrid
            || c.includeMealsGrid || c.includeSleepGrid || c.includeSymptomsGrid || c.includeFreeNotes
    }

    private func defaultPeriodLabel() -> String {
        let monday = currentMonday()
        let cal = Calendar.current
        let endDay = cal.date(byAdding: .day, value: BookletConfigStore.shared.dayCount - 1, to: monday) ?? monday
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMMM"
        return "Semaine du \(f.string(from: monday)) au \(f.string(from: endDay))"
    }

    private func currentMonday() -> Date {
        let cal = Calendar.current
        let today = Date()
        let weekday = cal.component(.weekday, from: today)
        let daysToMonday = (weekday + 5) % 7
        return cal.date(byAdding: .day, value: -daysToMonday, to: today) ?? today
    }

    private func generate() async {
        generating = true
        defer { generating = false }
        let config = BookletConfigStore.shared
        let opts = FollowUpBookletGenerator.Options(
            coverChildName: profiles.first?.fullName ?? "Enfant",
            coverPeriodLabel: periodLabel.isEmpty ? defaultPeriodLabel() : periodLabel,
            weekStart: currentMonday(),
            includeMedicationGrid: config.includeMedicationGrid,
            includeSeizureGrid: config.includeSeizureGrid,
            includeMoodGrid: config.includeMoodGrid,
            includeMealsGrid: config.includeMealsGrid,
            includeSleepGrid: config.includeSleepGrid,
            includeSymptomsGrid: config.includeSymptomsGrid,
            includeFreeNotes: config.includeFreeNotes,
            medications: medications,
            allDosesSelected: config.allDosesSelected,
            selectedDoses: config.selectedDoses,
            selectedMealSlots: config.selectedMealSlots,
            selectedSymptoms: config.selectedSymptoms,
            dayCount: config.dayCount
        )
        do {
            let url = try FollowUpBookletGenerator.generate(opts)
            lastURL = url
            showShare = true
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refresh() {
        archived = FollowUpBookletGenerator.archivedBooklets()
    }
}

private struct ArchivedFileRow: View {
    let url: URL
    let onShare: () -> Void
    let onDelete: () -> Void

    @State private var showConfirm = false

    private var creationDate: Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    }

    var body: some View {
        HStack {
            Image(systemName: "doc.fill")
                .foregroundStyle(.afsrPurpleAdaptive)
                .font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(AFSRFont.body(14))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(creationDate, format: .dateTime.day().month().year().hour().minute())
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { onShare() } label: { Image(systemName: "square.and.arrow.up") }
                .buttonStyle(.borderless)
            Button { showConfirm = true } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
        }
        .confirmationDialog("Supprimer ce cahier ?", isPresented: $showConfirm) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) { }
        }
    }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}
