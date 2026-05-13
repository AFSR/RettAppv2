import SwiftUI
import SwiftData

/// Écran dédié à la **configuration** du cahier de suivi : sections incluses,
/// sélection fine des prises de médicaments (chaque dose individuellement, car
/// certaines sont à la maison et d'autres au centre), repas, symptômes Rett.
///
/// Les choix sont persistés dans `BookletConfigStore` (UserDefaults) — on
/// configure une fois, on génère plusieurs fois.
struct BookletConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Medication.createdAt) private var medications: [Medication]

    private let config = BookletConfigStore.shared

    private var activeMedications: [Medication] {
        medications.filter { $0.isActive }
    }

    var body: some View {
        @Bindable var config = BookletConfigStore.shared
        Form {
            Section("Période par défaut") {
                Picker("Nombre de jours", selection: $config.dayCount) {
                    Text("5 jours (Lun-Ven)").tag(5)
                    Text("7 jours (Lun-Dim)").tag(7)
                }
            }

            Section("Sections à inclure") {
                Toggle("Prises de médicaments", isOn: $config.includeMedicationGrid)
                Toggle("Crises observées", isOn: $config.includeSeizureGrid)
                Toggle("État général / humeur", isOn: $config.includeMoodGrid)
                Toggle("Repas et hydratation", isOn: $config.includeMealsGrid)
                Toggle("Sommeil / siestes", isOn: $config.includeSleepGrid)
                Toggle("Symptômes Rett (matin / après-midi)", isOn: $config.includeSymptomsGrid)
                Toggle("Événements particuliers", isOn: $config.includeFreeNotes)
            }

            if config.includeMedicationGrid && !activeMedications.isEmpty {
                medicationsSelection
            }

            if config.includeMealsGrid {
                mealsSelection
            }

            if config.includeSymptomsGrid {
                symptomsSelection
            }
        }
        .navigationTitle("Configuration du cahier")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Médicaments — sélection par PRISE

    private var medicationsSelection: some View {
        @Bindable var config = BookletConfigStore.shared
        return Section {
            Toggle("Inclure toutes les prises", isOn: Binding(
                get: { config.allDosesSelected },
                set: { newValue in
                    config.allDosesSelected = newValue
                    if newValue { config.selectedDoses.removeAll() }
                    else if config.selectedDoses.isEmpty {
                        // Pré-cocher toutes les prises pour démarrer la sélection
                        config.selectedDoses = allDoseKeys()
                    }
                }
            ))
            if !config.allDosesSelected {
                ForEach(activeMedications) { med in
                    medicationDoseGroup(med: med)
                }
            }
        } header: {
            Text("Prises de médicaments à inclure")
        } footer: {
            Text(config.allDosesSelected
                 ? "Toutes les prises planifiées de tous les médicaments actifs apparaîtront dans le cahier."
                 : "Cochez chaque prise individuellement (utile si certaines sont données à la maison et d'autres au centre).")
        }
    }

    @ViewBuilder
    private func medicationDoseGroup(med: Medication) -> some View {
        let intakes = med.intakes
        if intakes.isEmpty {
            HStack {
                Image(systemName: "pills.fill")
                    .foregroundStyle(.secondary)
                Text(med.name).font(AFSRFont.body(14))
                Spacer()
                Text("Aucune prise planifiée").font(AFSRFont.caption()).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "pills.fill")
                        .foregroundStyle(.afsrPurpleAdaptive)
                    Text(med.name).font(AFSRFont.headline(14))
                }
                ForEach(intakes) { intake in
                    let key = DoseKey(medicationID: med.id, hour: intake.hour, minute: intake.minute)
                    Toggle(isOn: doseBinding(key)) {
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 13))
                            Text("Prise de \(intake.formattedTime)")
                                .font(AFSRFont.body(13))
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(MedicationIntake.doseLabel(intake.dose, unit: med.doseUnit))
                                .font(AFSRFont.caption())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(intake.weekdaySummary)
                                .font(AFSRFont.caption())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.afsrPurpleAdaptive)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func doseBinding(_ key: DoseKey) -> Binding<Bool> {
        Binding(
            get: { BookletConfigStore.shared.selectedDoses.contains(key) },
            set: { isOn in
                if isOn { BookletConfigStore.shared.selectedDoses.insert(key) }
                else { BookletConfigStore.shared.selectedDoses.remove(key) }
            }
        )
    }

    private func allDoseKeys() -> Set<DoseKey> {
        var out: Set<DoseKey> = []
        for med in activeMedications {
            for intake in med.intakes {
                out.insert(DoseKey(medicationID: med.id, hour: intake.hour, minute: intake.minute))
            }
        }
        return out
    }

    // MARK: - Repas

    private var mealsSelection: some View {
        @Bindable var config = BookletConfigStore.shared
        return Section {
            ForEach([MealSlot.breakfast, .lunch, .snack, .dinner], id: \.self) { slot in
                Toggle(isOn: Binding(
                    get: { config.selectedMealSlots.contains(slot) },
                    set: { isOn in
                        var current = config.selectedMealSlots
                        if isOn { current.insert(slot) }
                        else { current.remove(slot) }
                        config.selectedMealSlots = current
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

    // MARK: - Symptômes Rett

    private var symptomsSelection: some View {
        @Bindable var config = BookletConfigStore.shared
        return Section {
            Button {
                config.selectedSymptoms = symptomDefaults
            } label: {
                Label("Pré-sélectionner les symptômes courants", systemImage: "checkmark.square")
            }
            ForEach(RettSymptom.allCases) { s in
                Toggle(isOn: Binding(
                    get: { config.selectedSymptoms.contains(s) },
                    set: { isOn in
                        var current = config.selectedSymptoms
                        if isOn { current.insert(s) }
                        else { current.remove(s) }
                        config.selectedSymptoms = current
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
            Text("Pour chaque symptôme coché, une case par demi-journée (matin / après-midi) sera ajoutée.")
        }
    }

    private var symptomDefaults: Set<RettSymptom> {
        [.handStereotypy, .breathingApnea, .bruxism, .agitation, .cryingSpell]
    }
}

#Preview {
    NavigationStack { BookletConfigurationView() }
        .modelContainer(PreviewData.container)
}
