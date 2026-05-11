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
                                if med.kind == .adhoc {
                                    Text("Ponctuel")
                                        .font(AFSRFont.caption())
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.afsrPurpleAdaptive.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.afsrPurpleAdaptive)
                                }
                                Spacer()
                                if med.kind == .regular && !med.notifyEnabled {
                                    Image(systemName: "bell.slash.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Notifications désactivées")
                                }
                                if !med.isActive {
                                    Text("Inactif")
                                        .font(AFSRFont.caption())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(rowSubtitle(for: med))
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
                MedicationEditor(medication: editing) { name, dose, unit, hours, kind, active, notifyEnabled in
                    Task { await save(name: name, dose: dose, unit: unit, hours: hours, kind: kind, active: active, notifyEnabled: notifyEnabled) }
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

    private func rowSubtitle(for med: Medication) -> String {
        switch med.kind {
        case .adhoc:
            return "\(med.doseLabel) · à la demande"
        case .regular:
            let hours = med.scheduledHours.map(\.formatted).joined(separator: ", ")
            return hours.isEmpty ? med.doseLabel : "\(med.doseLabel) — \(hours)"
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

    private func save(name: String, dose: Double, unit: DoseUnit, hours: [HourMinute], kind: MedicationKind, active: Bool, notifyEnabled: Bool) async {
        if let editing {
            editing.name = name
            editing.doseAmount = dose
            editing.doseUnit = unit
            editing.scheduledHours = hours
            editing.kind = kind
            editing.isActive = active
            editing.notifyEnabled = notifyEnabled
        } else {
            let med = Medication(name: name, doseAmount: dose, doseUnit: unit, scheduledHours: hours, kind: kind, isActive: active, notifyEnabled: notifyEnabled)
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
    let onSave: (String, Double, DoseUnit, [HourMinute], MedicationKind, Bool, Bool) -> Void

    @State private var name: String = ""
    @State private var dose: String = ""
    @State private var unit: DoseUnit = .mg
    @State private var times: [HourMinute] = [HourMinute(hour: 8, minute: 0)]
    @State private var kind: MedicationKind = .regular
    @State private var active: Bool = true
    @State private var notifyEnabled: Bool = true

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(MedicationKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(kind == .regular
                     ? "Récurrent : pris à des horaires fixes, génère des rappels automatiques."
                     : "À la demande : pris en cas de besoin (Rivotril en cas de crise, antipyrétique sur fièvre…). Aucune notification.")
            }

            Section("Nom") {
                TextField("Ex. Keppra, Doliprane, Mélatonine…", text: $name)
                    .autocorrectionDisabled()
                if !name.isEmpty {
                    ForEach(CommonFrenchMedications.suggestions(matching: name, limit: 6), id: \.self) { suggestion in
                        Button {
                            if let parenIdx = suggestion.firstIndex(of: "(") {
                                name = String(suggestion[..<parenIdx]).trimmingCharacters(in: .whitespaces)
                            } else {
                                name = suggestion
                            }
                        } label: {
                            HStack {
                                Image(systemName: "pills.fill")
                                    .foregroundStyle(.afsrPurpleAdaptive)
                                    .font(.system(size: 13))
                                Text(suggestion)
                                    .font(AFSRFont.body(14))
                                Spacer()
                            }
                        }
                    }
                }
            }

            Section("Dose habituelle") {
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

            if kind == .regular {
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
            }

            Section {
                Toggle("Actif", isOn: $active)
            } footer: {
                Text("Un médicament inactif n'apparaît plus dans la vue du jour et n'envoie plus de notifications.")
            }

            if kind == .regular {
                Section {
                    Toggle(isOn: $notifyEnabled) {
                        Label("Notifier ce médicament", systemImage: "bell.badge")
                    }
                } footer: {
                    Text("Désactivez si la prise est gérée par un tiers (école, centre, autre parent) et que vous ne voulez pas recevoir de rappel sur cet appareil.")
                }
            }
        }
        .navigationTitle(medication == nil ? "Nouveau médicament" : "Modifier")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    let amount = Double(dose.replacingOccurrences(of: ",", with: ".")) ?? 0
                    let finalTimes = kind == .regular ? times : []
                    onSave(name.trimmingCharacters(in: .whitespaces), amount, unit, finalTimes, kind, active, notifyEnabled)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || Double(dose.replacingOccurrences(of: ",", with: ".")) == nil
                          || (kind == .regular && times.isEmpty))
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
                kind = medication.kind
                active = medication.isActive
                notifyEnabled = medication.notifyEnabled
            }
        }
    }
}

#Preview {
    NavigationStack { MedicationPlanView() }
        .modelContainer(PreviewData.container)
}
