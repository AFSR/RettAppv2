import SwiftUI
import SwiftData

/// Écran de configuration + génération du cahier de suivi PDF imprimable.
/// Format A4 paysage, conçu pour être imprimé et confié à l'équipe encadrante
/// (école, IME, IMP, centre).
struct FollowUpBookletView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]

    @State private var includeMedicationGrid = true
    @State private var includeSeizureGrid = true
    @State private var includeMoodGrid = true
    @State private var includeMealsGrid = true
    @State private var includeSleepGrid = false
    @State private var includeSymptomsGrid = false
    @State private var includeFreeNotes = true
    @State private var dayCount = 5
    @State private var periodLabel = ""

    @State private var selectedMedicationIDs: Set<UUID> = []
    @State private var selectedMealSlots: Set<MealSlot> = [.breakfast, .lunch, .snack, .dinner]
    @State private var selectedSymptoms: Set<RettSymptom> = []
    /// Si true, tous les médicaments actifs sont sélectionnés (équivalent à
    /// `selectedMedicationIDs = Set(medications.filter{$0.isActive}.map(\.id))`).
    @State private var allMedicationsSelected = true

    @State private var generating = false
    @State private var lastURL: URL?
    @State private var showShare = false
    @State private var errorMessage: String?
    @State private var archived: [URL] = []
    @State private var toShare: URL?

    private var activeMedications: [Medication] {
        medications.filter { $0.isActive }
    }

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
                Toggle("Symptômes Rett (matin / après-midi)", isOn: $includeSymptomsGrid)
                Toggle("Observations libres", isOn: $includeFreeNotes)
            }

            if includeMedicationGrid && !activeMedications.isEmpty {
                Section {
                    Toggle("Inclure tous les médicaments", isOn: Binding(
                        get: { allMedicationsSelected },
                        set: { newValue in
                            allMedicationsSelected = newValue
                            if newValue { selectedMedicationIDs.removeAll() }
                            else if selectedMedicationIDs.isEmpty {
                                // pré-cocher tout pour démarrer la sélection
                                selectedMedicationIDs = Set(activeMedications.map(\.id))
                            }
                        }
                    ))
                    if !allMedicationsSelected {
                        ForEach(activeMedications) { med in
                            Toggle(isOn: Binding(
                                get: { selectedMedicationIDs.contains(med.id) },
                                set: { isOn in
                                    if isOn { selectedMedicationIDs.insert(med.id) }
                                    else { selectedMedicationIDs.remove(med.id) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(med.name).font(AFSRFont.body(14))
                                    Text("\(med.doseLabel) · \(med.scheduledHours.map(\.formatted).joined(separator: " · "))")
                                        .font(AFSRFont.caption())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Médicaments à suivre")
                } footer: {
                    Text(allMedicationsSelected
                         ? "Tous les médicaments actifs apparaîtront dans la grille du cahier."
                         : "Seuls les médicaments cochés apparaîtront dans la grille.")
                }
            }

            if includeMealsGrid {
                Section {
                    ForEach([MealSlot.breakfast, .lunch, .snack, .dinner], id: \.self) { slot in
                        Toggle(isOn: Binding(
                            get: { selectedMealSlots.contains(slot) },
                            set: { isOn in
                                if isOn { selectedMealSlots.insert(slot) }
                                else { selectedMealSlots.remove(slot) }
                            }
                        )) {
                            Label(slot.label, systemImage: slot.icon)
                        }
                    }
                } header: {
                    Text("Repas à suivre")
                } footer: {
                    Text("Une ligne par repas coché + une ligne hydratation seront ajoutées au cahier.")
                }
            }

            if includeSymptomsGrid {
                Section {
                    if selectedSymptoms.isEmpty {
                        Button {
                            selectedSymptoms = symptomDefaults
                        } label: {
                            Label("Sélectionner les symptômes courants", systemImage: "checkmark.square")
                        }
                    } else {
                        Button {
                            selectedSymptoms.removeAll()
                        } label: {
                            Label("Tout désélectionner", systemImage: "square")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(RettSymptom.allCases) { s in
                        Toggle(isOn: Binding(
                            get: { selectedSymptoms.contains(s) },
                            set: { isOn in
                                if isOn { selectedSymptoms.insert(s) }
                                else { selectedSymptoms.remove(s) }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Image(systemName: s.icon).foregroundStyle(.afsrPurpleAdaptive)
                                Text(s.label).font(AFSRFont.body(13))
                            }
                        }
                    }
                } header: {
                    Text("Symptômes Rett à suivre")
                } footer: {
                    Text("Pour chaque symptôme coché, l'équipe pourra cocher une case par demi-journée (matin / après-midi).")
                }
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
                Text("Le cahier est imprimé puis confié à l'équipe encadrante (école, IME, IMP, centre). Vous ressaisissez les informations dans l'app le soir.")
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
            if selectedSymptoms.isEmpty { selectedSymptoms = symptomDefaults }
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

    /// Symptômes les plus pertinents à suivre par l'équipe encadrante par défaut.
    private var symptomDefaults: Set<RettSymptom> {
        [.handStereotypy, .breathingApnea, .bruxism, .agitation, .cryingSpell]
    }

    private var atLeastOneSectionSelected: Bool {
        includeMedicationGrid || includeSeizureGrid || includeMoodGrid
            || includeMealsGrid || includeSleepGrid || includeSymptomsGrid || includeFreeNotes
    }

    private func defaultPeriodLabel() -> String {
        let cal = Calendar.current
        let today = Date()
        let weekday = cal.component(.weekday, from: today)
        let daysToMonday = (weekday + 5) % 7
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
            includeSymptomsGrid: includeSymptomsGrid,
            includeFreeNotes: includeFreeNotes,
            medications: medications,
            selectedMedicationIDs: allMedicationsSelected ? [] : selectedMedicationIDs,
            selectedMealSlots: selectedMealSlots,
            selectedSymptoms: selectedSymptoms,
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
