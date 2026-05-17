import SwiftUI
import SwiftData

/// Configuration du plan médicamenteux (CRUD).
struct MedicationPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CloudKitSyncService.self) private var sync
    @Query private var profiles: [ChildProfile]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]

    /// Combine création et édition dans une seule source de vérité pour la
    /// feuille modale. Avant : deux `@State` séparés (`editing` + `showEditor`)
    /// — SwiftUI évaluait parfois le `body` du sheet AVANT que `editing` ait
    /// fini de propager, faisant que le premier tap ouvrait l'éditeur en mode
    /// création au lieu d'édition, créant un médicament fantôme à chaque
    /// tentative (cf. issue utilisateur 2025-11 : « la première fois qu'on
    /// clique sur un medicament du plan, cela ouvre un nouveau medicament »).
    @State private var editorSheet: EditorSheet?
    @State private var importSummary: MedicationImporter.ImportResult?
    /// Date d'observation rétroactive — nil = mode édition courant. Quand
    /// non-nil, le plan affiche l'état tel qu'il était à cette date (lecture
    /// seule), reconstruit via `MedicationRevision.latest(...)`.
    @State private var historicalDate: Date?
    @State private var showDatePicker: Bool = false

    enum EditorSheet: Identifiable {
        case create
        case edit(Medication)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let m): return m.id.uuidString
            }
        }
    }

    private var profile: ChildProfile? { profiles.first }

    var body: some View {
        List {
            if historicalDate != nil {
                historicalBanner
            }
            Section {
                ForEach(planEntries) { entry in
                    planRow(entry)
                }
                .onDelete(perform: historicalDate == nil ? delete : nil)
            } footer: {
                Text(historicalDate == nil
                     ? "Les notifications sont recréées automatiquement après modification."
                     : "Plan en mode historique : lecture seule. Pour modifier, revenez d'abord au plan actuel.")
            }

            if historicalDate == nil {
                Section {
                    Button {
                        editorSheet = .create
                    } label: {
                        Label("Ajouter un médicament", systemImage: "plus.circle.fill")
                    }
                }
            }
        }
        .navigationTitle(historicalDate == nil ? "Plan médicamenteux" : "Plan au passé")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fermer") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if historicalDate == nil {
                        Button {
                            showDatePicker = true
                        } label: {
                            Label("Afficher le plan à une date passée", systemImage: "clock.arrow.circlepath")
                        }
                    } else {
                        Button {
                            historicalDate = nil
                        } label: {
                            Label("Revenir au plan actuel", systemImage: "arrow.uturn.backward")
                        }
                    }
                    Divider()
                    Button {
                        // Placeholder pour ouvrir le menu CSV existant
                    } label: {
                        Label("Import / Export CSV", systemImage: "doc.text")
                    }
                    .hidden() // visuellement remplacé par le menu CSV séparé ci-dessous
                } label: {
                    Image(systemName: historicalDate == nil ? "ellipsis.circle" : "clock.fill")
                }
            }
            // Le menu CSV reste un bouton à part (il porte sa propre UI de
            // file picker et de sheet de partage) — on ne le mélange pas dans
            // le Menu principal.
            ToolbarItem(placement: .topBarTrailing) {
                if historicalDate == nil {
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
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(
                initial: historicalDate ?? Date(),
                onCancel: { showDatePicker = false },
                onApply: { date in
                    historicalDate = date
                    showDatePicker = false
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(item: $editorSheet) { item in
            NavigationStack {
                switch item {
                case .create:
                    MedicationEditor(medication: nil) { result in
                        Task { await save(result, editing: nil) }
                    }
                case .edit(let med):
                    MedicationEditor(
                        medication: med,
                        onSave: { result in
                            Task { await save(result, editing: med) }
                        },
                        onDelete: {
                            deleteMedication(med)
                        }
                    )
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

    // MARK: - Plan entries (current vs historical)

    /// Représentation unifiée d'une ligne du plan, alimentée soit par le
    /// `Medication` courant, soit par sa dernière `MedicationRevision`
    /// antérieure à la date historique sélectionnée.
    private struct PlanEntry: Identifiable {
        let id: UUID
        let name: String
        let kind: MedicationKind
        let doseAmount: Double
        let doseUnit: DoseUnit
        let intakes: [MedicationIntake]
        let isActive: Bool
        let notifyEnabled: Bool
        /// Référence au `Medication` éditable. nil en mode historique.
        let editable: Medication?
    }

    /// Liste à afficher : médicaments courants OU snapshots historiques
    /// reconstitués via `MedicationRevision.latest(...)` selon `historicalDate`.
    private var planEntries: [PlanEntry] {
        guard let date = historicalDate else {
            return medications.map { med in
                PlanEntry(
                    id: med.id,
                    name: med.name,
                    kind: med.kind,
                    doseAmount: med.doseAmount,
                    doseUnit: med.doseUnit,
                    intakes: med.intakes,
                    isActive: med.isActive,
                    notifyEnabled: med.notifyEnabled,
                    editable: med
                )
            }
        }
        // Mode historique : on exclut les médocs créés APRÈS `date`, et pour
        // chacun on cherche la dernière révision antérieure à `date`.
        return medications.compactMap { med in
            guard med.createdAt <= date else { return nil }
            let rev = MedicationRevision.latest(medicationId: med.id, before: date, in: modelContext)
            return PlanEntry(
                id: med.id,
                name: rev?.name ?? med.name,
                kind: rev?.kind ?? med.kind,
                doseAmount: rev?.doseAmount ?? med.doseAmount,
                doseUnit: rev?.doseUnit ?? med.doseUnit,
                intakes: rev?.intakes ?? med.intakes,
                isActive: rev?.isActive ?? med.isActive,
                notifyEnabled: rev?.notifyEnabled ?? med.notifyEnabled,
                editable: nil
            )
        }
    }

    @ViewBuilder
    private func planRow(_ entry: PlanEntry) -> some View {
        let content = VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.name)
                    .font(AFSRFont.headline(17))
                    .foregroundStyle(.primary)
                if entry.kind == .adhoc {
                    Text("Ponctuel")
                        .font(AFSRFont.caption())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.afsrPurpleAdaptive.opacity(0.15), in: Capsule())
                        .foregroundStyle(.afsrPurpleAdaptive)
                }
                Spacer()
                if entry.kind == .regular && !entry.notifyEnabled {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Notifications désactivées")
                }
                if !entry.isActive {
                    Text("Inactif")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                }
            }
            Text(rowSubtitleForEntry(entry))
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
        }
        if let med = entry.editable {
            Button { editorSheet = .edit(med) } label: { content }
        } else {
            content // lecture seule en mode historique
        }
    }

    private func rowSubtitleForEntry(_ e: PlanEntry) -> String {
        switch e.kind {
        case .adhoc:
            let dose = MedicationIntake.doseLabel(e.doseAmount, unit: e.doseUnit)
            return "\(dose) · à la demande"
        case .regular:
            if e.intakes.isEmpty {
                return MedicationIntake.doseLabel(e.doseAmount, unit: e.doseUnit)
            }
            let uniformDose = Set(e.intakes.map(\.dose)).count == 1
            let uniformDays = Set(e.intakes.map(\.weekdaysRaw)).count == 1
            if uniformDose && uniformDays {
                let suffix = e.intakes.first?.isEveryDay == false
                    ? " · \(e.intakes.first?.weekdaySummary ?? "")"
                    : ""
                let times = e.intakes.map(\.formattedTime).joined(separator: ", ")
                return "\(MedicationIntake.doseLabel(e.doseAmount, unit: e.doseUnit)) — \(times)\(suffix)"
            }
            return e.intakes.map { intake in
                let dose = MedicationIntake.doseLabel(intake.dose, unit: e.doseUnit)
                return "\(intake.formattedTime) \(dose) (\(intake.weekdaySummary))"
            }.joined(separator: " · ")
        }
    }

    @ViewBuilder
    private var historicalBanner: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.afsrPurpleAdaptive)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan reconstitué")
                        .font(AFSRFont.headline(14))
                    if let date = historicalDate {
                        Text(date, format: .dateTime.day().month(.wide).year().hour().minute())
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Plan actuel") {
                    historicalDate = nil
                }
                .font(AFSRFont.caption())
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.afsrPurpleAdaptive.opacity(0.08))
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
        try? modelContext.saveTouching()
        sync.scheduleSync(context: modelContext)
        Task {
            await MedicationViewModel().rescheduleAllNotifications(
                medications: medications,
                childFirstName: profile?.firstName ?? ""
            )
        }
    }

    /// Suppression depuis le bouton « Supprimer ce médicament » à l'intérieur
    /// de l'éditeur. Même comportement que swipe-to-delete : on retire le
    /// `Medication` (les `MedicationLog` orphelins restent dans le journal
    /// pour conserver l'historique tel quel) et on resynchronise.
    private func deleteMedication(_ med: Medication) {
        modelContext.delete(med)
        try? modelContext.saveTouching()
        sync.scheduleSync(context: modelContext)
        Task {
            await MedicationViewModel().rescheduleAllNotifications(
                medications: medications,
                childFirstName: profile?.firstName ?? ""
            )
        }
    }

    private func save(_ r: MedicationEditor.SaveResult, editing: Medication?) async {
        let hours = r.intakes.map { HourMinute(hour: $0.hour, minute: $0.minute) }
        let target: Medication
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
            target = editing
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
            target = med
        }
        // Versioning : on capture l'état post-modification dans une révision
        // horodatée. Cette révision sert ensuite à reconstituer le plan tel
        // qu'il était à une date donnée (cf. MedicationRevision.latest).
        MedicationRevision.capture(of: target, in: modelContext)
        try? modelContext.saveTouching()
        sync.scheduleSync(context: modelContext)
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
    var onDelete: (() -> Void)? = nil

    @State private var name: String = ""
    @State private var defaultDoseText: String = ""
    @State private var unit: DoseUnit = .mg
    @State private var intakes: [MedicationIntake] = [
        MedicationIntake(hour: 8, minute: 0, dose: 0)
    ]
    @State private var kind: MedicationKind = .regular
    @State private var active: Bool = true
    @State private var notifyEnabled: Bool = true
    @State private var showDeleteConfirm: Bool = false
    @FocusState private var defaultDoseFocused: Bool

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
                    ForEach(MedicationCatalog.suggestions(matching: name, limit: 6)) { suggestion in
                        Button {
                            name = suggestion.shortName
                        } label: {
                            HStack {
                                Image(systemName: "pills.fill")
                                    .foregroundStyle(.afsrPurpleAdaptive)
                                    .font(.system(size: 13))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(suggestion.shortName)
                                        .font(AFSRFont.body(14))
                                    if let active = suggestion.activeIngredient, !active.isEmpty {
                                        Text(active)
                                            .font(AFSRFont.caption())
                                            .foregroundStyle(.secondary)
                                    }
                                }
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
                        .focused($defaultDoseFocused)
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

            // Bouton explicite de suppression, visible uniquement en mode
            // édition. Le swipe-to-delete dans la liste reste disponible
            // depuis le plan, mais l'utilisateur attend aussi une option
            // claire à l'intérieur du formulaire.
            if let med = medication {
                Section {
                    NavigationLink {
                        MedicationRevisionHistoryView(medicationId: med.id, medicationName: med.name)
                    } label: {
                        Label("Historique des modifications", systemImage: "clock.arrow.circlepath")
                    }
                } footer: {
                    Text("Liste chronologique de toutes les modifications de dosage, horaires et activation depuis la création de ce médicament dans le plan.")
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Supprimer ce médicament", systemImage: "trash")
                    }
                } footer: {
                    Text("Supprime le médicament du plan ainsi que toutes ses prises planifiées et leur historique de validation.")
                }
            }
        }
        .navigationTitle(medication == nil ? "Nouveau médicament" : "Modifier")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    defaultDoseFocused = false
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
            // Touche « OK » au-dessus du clavier décimal (sinon l'utilisateur
            // ne peut pas sortir du champ Dose sans cliquer en-dehors).
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { defaultDoseFocused = false }.bold()
            }
        }
        .onAppear { loadFromMedication() }
        .confirmationDialog(
            "Supprimer ce médicament ?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Cette action est irréversible. Le médicament et son historique de prises seront effacés.")
        }
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

// MARK: - Historical date picker

/// Petite feuille pour choisir la date à laquelle reconstituer le plan
/// médicamenteux. Plafonnée à `Date()` parce qu'on ne reconstitue pas le
/// futur (les révisions sont créées au présent).
private struct DatePickerSheet: View {
    let initial: Date
    let onCancel: () -> Void
    let onApply: (Date) -> Void

    @State private var selected: Date

    init(initial: Date, onCancel: @escaping () -> Void, onApply: @escaping (Date) -> Void) {
        self.initial = initial
        self.onCancel = onCancel
        self.onApply = onApply
        _selected = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Date d'observation",
                        selection: $selected,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                } footer: {
                    Text("Le plan affichera l'état tel qu'il était à cette date — utile pour préparer une consultation médicale ou comparer un dosage actuel à un dosage passé.")
                }
            }
            .navigationTitle("Plan à une date passée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Afficher") { onApply(selected) }.bold()
                }
            }
        }
    }
}

#Preview {
    NavigationStack { MedicationPlanView() }
        .modelContainer(PreviewData.container)
}
