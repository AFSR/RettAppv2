import SwiftUI
import SwiftData

/// Configuration du plan médicamenteux (CRUD).
struct MedicationPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [ChildProfile]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]

    @State private var showEditor = false
    @State private var editing: Medication?
    @State private var importSummary: MedicationImporter.ImportResult?

    private var profile: ChildProfile? { profiles.first }

    var body: some View {
        List {
            Section {
                ForEach(medications) { med in
                    Button {
                        editing = med
                        showEditor = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(med.name)
                                    .font(AFSRFont.headline(17))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if !med.isActive {
                                    Text("Inactif")
                                        .font(AFSRFont.caption())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("\(med.doseLabel) — \(med.scheduledHours.map(\.formatted).joined(separator: ", "))")
                                .font(AFSRFont.caption())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: delete)
            } footer: {
                Text("Les notifications sont recréées automatiquement après modification.")
            }

            Section {
                Button {
                    editing = nil
                    showEditor = true
                } label: {
                    Label("Ajouter un médicament", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("Plan médicamenteux")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fermer") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                CSVImportMenu(
                    buildTemplate: { try MedicationImporter.writeTemplate() },
                    onImportedContent: { content in
                        let result = MedicationImporter.importCSV(
                            contents: content,
                            childProfile: profile,
                            context: modelContext
                        )
                        importSummary = result
                        // Replanifie les notifications après l'import
                        Task {
                            let vm = MedicationViewModel()
                            await vm.requestNotificationPermissionIfNeeded()
                            await vm.rescheduleAllNotifications(
                                medications: medications,
                                childFirstName: profile?.firstName ?? ""
                            )
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                MedicationEditor(medication: editing) { name, dose, unit, hours, active in
                    Task { await save(name: name, dose: dose, unit: unit, hours: hours, active: active) }
                }
            }
        }
        .alert("Import terminé", isPresented: Binding(
            get: { importSummary != nil },
            set: { if !$0 { importSummary = nil } }
        ), presenting: importSummary) { _ in
            Button("OK") { importSummary = nil }
        } message: { result in
            var msg = "Importés : \(result.imported)\nIgnorés : \(result.skipped)"
            if !result.errors.isEmpty {
                msg += "\n\n" + result.errors.prefix(5).joined(separator: "\n")
                if result.errors.count > 5 {
                    msg += "\n… et \(result.errors.count - 5) autres"
                }
            }
            return Text(msg)
        }
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets {
            modelContext.delete(medications[i])
        }
        try? modelContext.save()
        Task {
            await MedicationViewModel().rescheduleAllNotifications(
                medications: medications,
                childFirstName: profile?.firstName ?? ""
            )
        }
    }

    private func save(name: String, dose: Double, unit: DoseUnit, hours: [HourMinute], active: Bool) async {
        if let editing {
            editing.name = name
            editing.doseAmount = dose
            editing.doseUnit = unit
            editing.scheduledHours = hours
            editing.isActive = active
        } else {
            let med = Medication(name: name, doseAmount: dose, doseUnit: unit, scheduledHours: hours, isActive: active)
            med.childProfile = profile
            modelContext.insert(med)
        }
        try? modelContext.save()
        let vm = MedicationViewModel()
        await vm.requestNotificationPermissionIfNeeded()
        await vm.rescheduleAllNotifications(medications: medications, childFirstName: profile?.firstName ?? "")
    }
}

// MARK: - Editor

struct MedicationEditor: View {
    @Environment(\.dismiss) private var dismiss
    let medication: Medication?
    let onSave: (String, Double, DoseUnit, [HourMinute], Bool) -> Void

    @State private var name: String = ""
    @State private var dose: String = ""
    @State private var unit: DoseUnit = .mg
    @State private var times: [HourMinute] = [HourMinute(hour: 8, minute: 0)]
    @State private var active: Bool = true

    private static let commonNames = [
        "Dépakine", "Keppra", "Lamictal", "Rivotril", "Valium", "Urbanyl",
        "Sabril", "Topamax", "Tegretol", "Diacomit", "Ospolot"
    ]

    var body: some View {
        Form {
            Section("Nom") {
                TextField("Ex. Keppra", text: $name)
                    .autocorrectionDisabled()
                if !name.isEmpty {
                    ForEach(Self.commonNames.filter {
                        $0.localizedCaseInsensitiveContains(name) && $0.lowercased() != name.lowercased()
                    }, id: \.self) { suggestion in
                        Button(suggestion) { name = suggestion }
                    }
                }
            }

            Section("Dose") {
                HStack {
                    TextField("Quantité", text: $dose)
                        .keyboardType(.decimalPad)
                    Picker("Unité", selection: $unit) {
                        ForEach(DoseUnit.allCases) { u in
                            Text(u.label).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section("Heures de prise") {
                ForEach($times) { $t in
                    DatePicker("Heure", selection: Binding(
                        get: { t.asDate },
                        set: { t = HourMinute(date: $0) }
                    ), displayedComponents: .hourAndMinute)
                }
                .onDelete { idx in times.remove(atOffsets: idx) }
                Button {
                    times.append(HourMinute(hour: 12, minute: 0))
                } label: {
                    Label("Ajouter une heure", systemImage: "plus")
                }
            }

            Section {
                Toggle("Actif", isOn: $active)
            } footer: {
                Text("Un médicament inactif n'apparaît plus dans la vue du jour et n'envoie plus de notifications.")
            }
        }
        .navigationTitle(medication == nil ? "Nouveau médicament" : "Modifier")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    let amount = Double(dose.replacingOccurrences(of: ",", with: ".")) ?? 0
                    onSave(name.trimmingCharacters(in: .whitespaces), amount, unit, times, active)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || Double(dose.replacingOccurrences(of: ",", with: ".")) == nil
                          || times.isEmpty)
                .bold()
            }
        }
        .onAppear {
            if let medication {
                name = medication.name
                dose = medication.doseAmount.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(medication.doseAmount))
                    : String(medication.doseAmount)
                unit = medication.doseUnit
                times = medication.scheduledHours
                active = medication.isActive
            }
        }
    }
}

#Preview {
    NavigationStack { MedicationPlanView() }
        .modelContainer(PreviewData.container)
}
