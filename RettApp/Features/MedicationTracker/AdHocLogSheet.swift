import SwiftUI
import SwiftData

/// Sheet de saisie rapide d'une prise ponctuelle (ad-hoc).
/// L'utilisateur peut soit choisir un médicament existant (régulier ou ad-hoc),
/// soit saisir un nom libre pour un médicament non encore enregistré.
struct AdHocLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]

    @State private var mode: Mode = .pickExisting
    @State private var selectedMedID: UUID?
    @State private var freeName: String = ""
    @State private var doseString: String = ""
    @State private var unit: DoseUnit = .mg
    @State private var time: Date = Date()
    @State private var reason: String = ""
    @State private var addToPlan: Bool = false

    enum Mode: String, CaseIterable, Identifiable {
        case pickExisting, freeEntry
        var id: String { rawValue }
        var label: String {
            switch self {
            case .pickExisting: return "Médicament connu"
            case .freeEntry:    return "Nouveau médicament"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Médicament") {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .pickExisting:
                        Picker("Choisir", selection: $selectedMedID) {
                            Text("—").tag(UUID?.none)
                            ForEach(medications) { m in
                                Text("\(m.name) (\(m.doseLabel))").tag(Optional(m.id))
                            }
                        }
                    case .freeEntry:
                        TextField("Nom du médicament", text: $freeName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)

                        // Autocomplétion sur la liste française fréquente
                        let suggestions = CommonFrenchMedications.suggestions(matching: freeName)
                        if !suggestions.isEmpty {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button {
                                    freeName = suggestion.components(separatedBy: " (").first ?? suggestion
                                } label: {
                                    HStack {
                                        Image(systemName: "pills.fill")
                                            .foregroundStyle(.afsrPurpleAdaptive)
                                            .imageScale(.small)
                                        Text(suggestion)
                                            .foregroundStyle(.primary)
                                            .font(AFSRFont.body(14))
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Dose") {
                    HStack {
                        TextField("Quantité", text: $doseString)
                            .keyboardType(.decimalPad)
                        Picker("Unité", selection: $unit) {
                            ForEach(DoseUnit.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Heure de la prise") {
                    DatePicker("Heure", selection: $time, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Raison (optionnel)") {
                    TextField("Ex. fièvre, post-crise, agitation…", text: $reason, axis: .vertical)
                        .lineLimit(1...4)
                }

                if mode == .freeEntry {
                    Section {
                        Toggle("Ajouter ce médicament au plan (à la demande)", isOn: $addToPlan)
                    } footer: {
                        Text("Si activé, ce médicament sera disponible dans les futures saisies ponctuelles.")
                    }
                }
            }
            .navigationTitle("Prise ponctuelle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .bold()
                        .disabled(!canSave)
                }
            }
            .onChange(of: selectedMedID) { _, newValue in
                // Auto-remplit la dose à partir du médicament sélectionné
                if let id = newValue, let m = medications.first(where: { $0.id == id }) {
                    if doseString.isEmpty {
                        doseString = m.doseAmount.truncatingRemainder(dividingBy: 1) == 0
                            ? String(Int(m.doseAmount))
                            : String(format: "%.1f", m.doseAmount)
                        unit = m.doseUnit
                    }
                }
            }
        }
    }

    private var canSave: Bool {
        guard Double(doseString.replacingOccurrences(of: ",", with: ".")) != nil else { return false }
        switch mode {
        case .pickExisting:
            return selectedMedID != nil
        case .freeEntry:
            return !freeName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func save() {
        let amount = Double(doseString.replacingOccurrences(of: ",", with: ".")) ?? 0

        var name = ""
        var medID: UUID

        switch mode {
        case .pickExisting:
            guard let id = selectedMedID,
                  let m = medications.first(where: { $0.id == id }) else { return }
            medID = id
            name = m.name
        case .freeEntry:
            let trimmed = freeName.trimmingCharacters(in: .whitespaces)
            if addToPlan {
                let new = Medication(
                    name: trimmed,
                    doseAmount: amount,
                    doseUnit: unit,
                    scheduledHours: [],
                    kind: .adhoc,
                    isActive: true
                )
                new.childProfile = profiles.first
                modelContext.insert(new)
                medID = new.id
            } else {
                medID = UUID()
            }
            name = trimmed
        }

        let log = MedicationLog(
            medicationId: medID,
            medicationName: name,
            scheduledTime: time,
            takenTime: time,
            taken: true,
            dose: amount,
            doseUnit: unit,
            childProfileId: profiles.first?.id,
            isAdHoc: true,
            adhocReason: reason.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(log)
        try? modelContext.save()
        dismiss()
    }
}
