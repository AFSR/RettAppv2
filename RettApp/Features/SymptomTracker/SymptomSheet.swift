import SwiftUI
import SwiftData

/// Sheet de saisie d'un symptôme observé du syndrome de Rett.
struct SymptomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(CloudKitSyncService.self) private var sync
    @Query private var profiles: [ChildProfile]

    @State private var symptomType: RettSymptom = .handStereotypy
    @State private var timestamp: Date = Date()
    @State private var intensity: Int = 0
    @State private var durationMinutes: Int = 0
    @State private var notes: String = ""
    @State private var infoSymptom: RettSymptom?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(RettSymptom.allCases) { s in
                        SymptomChoiceRow(
                            symptom: s,
                            selected: symptomType == s,
                            onSelect: { symptomType = s },
                            onInfo: { infoSymptom = s }
                        )
                    }
                } header: {
                    Text("Symptôme observé")
                } footer: {
                    Text("Touchez ⓘ pour une description.")
                }

                Section("Quand ?") {
                    DatePicker("Heure d'observation", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                }

                Section {
                    HStack {
                        Text("Intensité")
                        Spacer()
                        Stepper(value: $intensity, in: 0...5) {
                            Text(intensity == 0 ? "Non renseignée" : "\(intensity) / 5")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Durée")
                        Spacer()
                        Stepper(value: $durationMinutes, in: 0...240, step: 5) {
                            Text(durationMinutes == 0 ? "Ponctuelle" : "\(durationMinutes) min")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Détails (optionnels)")
                } footer: {
                    Text("L'intensité (1 = très faible, 5 = très intense) et la durée aideront le médecin à mieux comprendre la fréquence et la gravité.")
                }

                Section("Notes") {
                    TextField("Détails, déclencheur possible…", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle("Symptôme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }.bold()
                }
            }
            .sheet(item: $infoSymptom) { s in SymptomInfoSheet(symptom: s) }
        }
    }

    private func save() {
        let event = SymptomEvent(
            timestamp: timestamp,
            symptomType: symptomType,
            intensity: intensity,
            durationMinutes: durationMinutes,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            childProfileId: profiles.first?.id
        )
        modelContext.insert(event)
        try? modelContext.saveTouching()
        sync.scheduleSync(context: modelContext)
        dismiss()
    }
}

private struct SymptomChoiceRow: View {
    let symptom: RettSymptom
    let selected: Bool
    let onSelect: () -> Void
    let onInfo: () -> Void

    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Color.afsrPurpleAdaptive : .secondary)
                        .font(.system(size: 18))
                    Image(systemName: symptom.icon)
                        .foregroundStyle(.afsrPurpleAdaptive)
                        .font(.system(size: 16))
                        .frame(width: 22)
                    Text(symptom.label).foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.afsrPurpleAdaptive)
                    .font(.system(size: 18))
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct SymptomInfoSheet: View {
    let symptom: RettSymptom
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: symptom.icon)
                            .font(.system(size: 28))
                            .foregroundStyle(.afsrPurpleAdaptive)
                        Text(symptom.label).font(AFSRFont.title(22))
                    }
                    Text(symptom.parentDescription)
                        .font(AFSRFont.body())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Cette description est destinée aux parents et aidants. Elle ne remplace pas l'avis du médecin.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Symptôme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
