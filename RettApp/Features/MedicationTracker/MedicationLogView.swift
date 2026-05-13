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
                MedicationEditor(medication: editing) { result in
                    Task { await save(result) }
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
            let intakes = med.intakes
            if intakes.isEmpty { return med.doseLabel }
            let uniformDose = Set(intakes.map(\.dose)).count == 1
            let uniformDays = Set(intakes.map(\.weekdaysRaw)).count == 1
            if uniformDose && uniformDays {
                let suffix = intakes.first?.isEveryDay == false
                    ? " · \(intakes.first?.weekdaySummary ?? "")"
                    : ""
                let times = intakes.map(\.formattedTime).joined(separator: ", ")
                return "\(med.doseLabel) — \(times)\(suffix)"
            }
            // Plan plus complexe : résume chaque prise
            return intakes.map { intake in
                let dose = MedicationIntake.doseLabel(intake.dose, unit: med.doseUnit)
                return "\(intake.formattedTime) \(dose) (\(intake.weekdaySummary))"
            }.joined(separator: " · ")
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

    private func save(_ r: MedicationEditor.SaveResult) async {
        let hours = r.intakes.map { HourMinute(hour: $0.hour, minute: $0.minute) }
        if let editing {
            editing.name = r.name
            editing.doseAmount = r.defaultDose
            editing.doseUnit = r.unit
            editing.kind = r.kind
            editing.isActive = r.active
            editing.notifyEnabled = r.notifyEnabled
            // Important : on écrit `intakes` après les autres champs car le
            // setter synchronise `scheduledHours` à partir de la liste finale.
            editing.intakes = r.intakes
        } else {
            let med = Medication(
                name: r.name,
                doseAmount: r.defaultDose,
                doseUnit: r.unit,
                scheduledHours: hours,
                kind: r.kind,
                isActive: r.active,
                notifyEnabled: r.notifyEnabled,
                intakes: r.intakes
            )
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
    let onSave: (SaveResult) -> Void

    @State private var name: String = ""
    @State private var defaultDoseText: String = ""
    @State private var unit: DoseUnit = .mg
    @State private var intakes: [MedicationIntake] = [
        MedicationIntake(hour: 8, minute: 0, dose: 0)
    ]
    @State private var kind: MedicationKind = .regular
    @State private var active: Bool = true
    @State private var notifyEnabled: Bool = true

    struct SaveResult {
        let name: String
        let defaultDose: Double
        let unit: DoseUnit
        let intakes: [MedicationIntake]
        let kind: MedicationKind
        let active: Bool
        let notifyEnabled: Bool
    }

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

            Section {
                HStack {
                    TextField("Quantité", text: $defaultDoseText)
                        .keyboardType(.decimalPad)
                    Picker("Unité", selection: $unit) {
                        ForEach(DoseUnit.allCases) { u in
                            Text(u.label).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Dose habituelle")
            } footer: {
                Text(kind == .regular
                     ? "Dose utilisée par défaut quand vous ajoutez une nouvelle prise. Chaque prise peut ensuite être ajustée individuellement."
                     : "Dose habituelle pour ce médicament ponctuel.")
            }

            if kind == .regular {
                Section {
                    ForEach(intakes) { intake in
                        NavigationLink {
                            MedicationIntakeEditorView(intakeId: intake.id, intakes: $intakes, unit: unit)
                        } label: {
                            intakeRow(intake)
                        }
                    }
                    .onDelete { offsets in
                        if intakes.count > offsets.count { intakes.remove(atOffsets: offsets) }
                    }

                    Button {
                        addIntake()
                    } label: {
                        Label("Ajouter une prise", systemImage: "plus")
                    }
                } header: {
                    Text("Prises")
                } footer: {
                    Text("Chaque prise a sa propre heure, sa dose, ses jours actifs et son rappel. Créez deux prises pour différencier semaine et week-end, par exemple.")
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
                    Text("Interrupteur principal. Vous pouvez aussi désactiver individuellement chaque prise (utile pour les jours pris en charge par l'école ou l'autre parent).")
                }
            }
        }
        .navigationTitle(medication == nil ? "Nouveau médicament" : "Modifier")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    let amount = Double(defaultDoseText.replacingOccurrences(of: ",", with: ".")) ?? 0
                    let finalIntakes = kind == .regular ? intakes : []
                    onSave(SaveResult(
                        name: name.trimmingCharacters(in: .whitespaces),
                        defaultDose: amount,
                        unit: unit,
                        intakes: finalIntakes,
                        kind: kind,
                        active: active,
                        notifyEnabled: notifyEnabled
                    ))
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || Double(defaultDoseText.replacingOccurrences(of: ",", with: ".")) == nil
                          || (kind == .regular && intakes.isEmpty))
                .bold()
            }
        }
        .onAppear { loadFromMedication() }
    }

    @ViewBuilder
    private func intakeRow(_ intake: MedicationIntake) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock")
                .foregroundStyle(.afsrPurpleAdaptive)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(intake.formattedTime)
                        .font(AFSRFont.headline(15))
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(MedicationIntake.doseLabel(intake.dose, unit: unit))
                        .font(AFSRFont.body(14))
                        .foregroundStyle(.secondary)
                    if !intake.notifyEnabled {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(intake.weekdaySummary)
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addIntake() {
        let amount = Double(defaultDoseText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let last = intakes.last
        let new = MedicationIntake(
            hour: last?.hour ?? 12,
            minute: last?.minute ?? 0,
            dose: last?.dose ?? amount,
            weekdays: last?.weekdays ?? MedicationIntake.allWeekdays,
            notifyEnabled: true
        )
        intakes.append(new)
    }

    private func loadFromMedication() {
        guard let medication else { return }
        name = medication.name
        unit = medication.doseUnit
        defaultDoseText = medication.doseAmount.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(medication.doseAmount))
            : String(medication.doseAmount)
        kind = medication.kind
        active = medication.isActive
        notifyEnabled = medication.notifyEnabled
        let existing = medication.intakes
        intakes = existing.isEmpty
            ? [MedicationIntake(hour: 8, minute: 0, dose: medication.doseAmount)]
            : existing
    }
}

#Preview {
    NavigationStack { MedicationPlanView() }
        .modelContainer(PreviewData.container)
}
