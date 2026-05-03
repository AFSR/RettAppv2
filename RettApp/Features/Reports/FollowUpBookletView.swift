import SwiftUI
import SwiftData

/// Écran de configuration + génération du cahier de suivi PDF imprimable.
struct FollowUpBookletView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]

    @State private var includeMedicationGrid = true
    @State private var includeSeizureGrid = true
    @State private var includeMoodGrid = true
    @State private var includeMealsGrid = true
    @State private var includeSleepGrid = false
    @State private var includeFreeNotes = true
    @State private var dayCount = 5
    @State private var periodLabel = ""

    @State private var generating = false
    @State private var lastURL: URL?
    @State private var showShare = false
    @State private var errorMessage: String?
    @State private var archived: [URL] = []
    @State private var toShare: URL?

    var body: some View {
        Form {
            Section("Période") {
                Picker("Nombre de jours", selection: $dayCount) {
                    Text("5 jours (Lun-Ven)").tag(5)
                    Text("7 jours (Lun-Dim)").tag(7)
                }
                TextField("Libellé (ex. Semaine du 27 mai au 2 juin)", text: $periodLabel)
            }

            Section("Sections à inclure") {
                Toggle("Prises de médicaments", isOn: $includeMedicationGrid)
                Toggle("Crises observées", isOn: $includeSeizureGrid)
                Toggle("État général / humeur", isOn: $includeMoodGrid)
                Toggle("Repas et hydratation", isOn: $includeMealsGrid)
                Toggle("Sommeil / siestes", isOn: $includeSleepGrid)
                Toggle("Observations libres", isOn: $includeFreeNotes)
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
                Text("Le cahier est imprimé puis confié à l'équipe de l'école, du centre ou de la halte-garderie. Vous ressaisissez les informations dans l'app le soir.")
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
        .task { refresh(); if periodLabel.isEmpty { periodLabel = defaultPeriodLabel() } }
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
        includeMedicationGrid || includeSeizureGrid || includeMoodGrid
            || includeMealsGrid || includeSleepGrid || includeFreeNotes
    }

    private func defaultPeriodLabel() -> String {
        let cal = Calendar.current
        let today = Date()
        let weekday = cal.component(.weekday, from: today)
        let daysToMonday = (weekday + 5) % 7  // Mon=0, Tue=-1...
        let monday = cal.date(byAdding: .day, value: -daysToMonday, to: today) ?? today
        let endDay = cal.date(byAdding: .day, value: dayCount - 1, to: monday) ?? today
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMMM"
        return "Semaine du \(f.string(from: monday)) au \(f.string(from: endDay))"
    }

    private func generate() async {
        generating = true
        defer { generating = false }
        let opts = FollowUpBookletGenerator.Options(
            coverChildName: profiles.first?.fullName ?? "Enfant",
            coverPeriodLabel: periodLabel.isEmpty ? defaultPeriodLabel() : periodLabel,
            includeMedicationGrid: includeMedicationGrid,
            includeSeizureGrid: includeSeizureGrid,
            includeMoodGrid: includeMoodGrid,
            includeMealsGrid: includeMealsGrid,
            includeSleepGrid: includeSleepGrid,
            includeFreeNotes: includeFreeNotes,
            medications: medications,
            dayCount: dayCount
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
