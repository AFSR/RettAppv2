import SwiftUI

/// Édite une prise individuelle d'un médicament (heure, dose, jours actifs,
/// notifications). Présentée via NavigationLink depuis `MedicationEditor`.
///
/// **Pattern transactionnel** : la vue tient un `@State draft` local et
/// commit explicitement vers le tableau parent au tap « OK ». Évite les
/// fragilités du binding `intakes[idx] = copy` qui ne propage pas toujours
/// vers le `@State` parent en iOS 17 (cause du bug 2025-11 « la
/// modification des prises est sans effet »).
struct MedicationIntakeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let intakeId: UUID
    @Binding var intakes: [MedicationIntake]
    let unit: DoseUnit

    @State private var draft: MedicationIntake
    @State private var doseString: String
    @FocusState private var doseFieldFocused: Bool

    init(intakeId: UUID, intakes: Binding<[MedicationIntake]>, unit: DoseUnit) {
        self.intakeId = intakeId
        self._intakes = intakes
        self.unit = unit
        let initial = intakes.wrappedValue.first(where: { $0.id == intakeId })
            ?? MedicationIntake(hour: 8, minute: 0, dose: 0)
        self._draft = State(initialValue: initial)
        let formatted: String
        if initial.dose.truncatingRemainder(dividingBy: 1) == 0 {
            formatted = String(Int(initial.dose))
        } else {
            formatted = String(initial.dose)
        }
        self._doseString = State(initialValue: formatted)
    }

    enum WeekdayPreset: String, CaseIterable, Identifiable, Hashable {
        case everyDay, weekdaysOnly, weekendOnly, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .everyDay: return "Tous les jours"
            case .weekdaysOnly: return "Semaine"
            case .weekendOnly: return "Week-end"
            case .custom: return "Personnalisé"
            }
        }
    }

    var body: some View {
        Form {
            timeSection
            doseSection
            weekdaysSection
            notifySection
        }
        .navigationTitle("Prise de \(draft.formattedTime)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { doseFieldFocused = false }.bold()
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("OK") {
                    doseFieldFocused = false
                    commit()
                    dismiss()
                }
                .bold()
            }
        }
    }

    // MARK: - Commit

    /// Écrit le draft local dans le tableau parent. On reconstruit le tableau
    /// puis on réassigne en entier — c'est ce qui garantit la propagation du
    /// `@Binding<[…]>` vers le `@State` parent. La version « intakes[idx] = … »
    /// se comportait silencieusement comme un no-op dans certains cas iOS 17.
    private func commit() {
        guard let idx = intakes.firstIndex(where: { $0.id == intakeId }) else { return }
        var newArray = intakes
        newArray[idx] = draft
        intakes = newArray
    }

    // MARK: - Sections

    @ViewBuilder
    private var timeSection: some View {
        Section {
            DatePicker(
                "Heure de prise",
                selection: timeBinding,
                displayedComponents: .hourAndMinute
            )
        } header: {
            Text("Heure")
        }
    }

    @ViewBuilder
    private var doseSection: some View {
        Section {
            HStack {
                TextField("Quantité", text: $doseString)
                    .keyboardType(.decimalPad)
                    .focused($doseFieldFocused)
                    .onChange(of: doseString) { _, newValue in
                        if let v = Double(newValue.replacingOccurrences(of: ",", with: ".")) {
                            draft.dose = v
                        }
                    }
                Text(unit.label).foregroundStyle(.secondary)
            }
        } header: {
            Text("Dose")
        } footer: {
            Text("Permet d'adapter la dose à chaque prise (ex. 5 mg le matin, 10 mg le soir).")
        }
    }

    @ViewBuilder
    private var weekdaysSection: some View {
        Section {
            Picker("Préréglage", selection: presetBinding) {
                ForEach(WeekdayPreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            WeekdayChipPicker(selection: weekdaysBinding)
                .padding(.vertical, 4)
        } header: {
            Text("Jours actifs")
        } footer: {
            Text("Sélectionnez les jours où cette prise doit être effectuée. Pour une dose différente le week-end, créez une seconde prise.")
        }
    }

    @ViewBuilder
    private var notifySection: some View {
        Section {
            Toggle(isOn: $draft.notifyEnabled) {
                Label("Rappeler cette prise", systemImage: "bell.badge")
            }
        } footer: {
            Text("Désactivez si cette prise est gérée par un tiers (école, centre, autre parent) et que vous ne voulez pas être notifié sur cet appareil ces jours-là.")
        }
    }

    // MARK: - Bindings sur le draft

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.hour = draft.hour
                c.minute = draft.minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                draft.hour = comps.hour ?? draft.hour
                draft.minute = comps.minute ?? draft.minute
            }
        )
    }

    private var weekdaysBinding: Binding<Set<Int>> {
        Binding(
            get: { draft.weekdays },
            set: { draft.weekdays = $0 }
        )
    }

    private var presetBinding: Binding<WeekdayPreset> {
        Binding(
            get: {
                if draft.isEveryDay { return .everyDay }
                if draft.isWeekdaysOnly { return .weekdaysOnly }
                if draft.isWeekendOnly { return .weekendOnly }
                return .custom
            },
            set: { preset in
                switch preset {
                case .everyDay:     draft.weekdays = MedicationIntake.allWeekdays
                case .weekdaysOnly: draft.weekdays = MedicationIntake.weekdaysOnly
                case .weekendOnly:  draft.weekdays = MedicationIntake.weekendOnly
                case .custom:       break
                }
            }
        )
    }
}

/// Sélecteur compact L M M J V S D (lundi → dimanche).
struct WeekdayChipPicker: View {
    @Binding var selection: Set<Int>

    private let order: [(weekday: Int, label: String)] = [
        (2, "L"), (3, "M"), (4, "M"), (5, "J"), (6, "V"), (7, "S"), (1, "D")
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(order, id: \.weekday) { item in
                chip(for: item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func chip(for item: (weekday: Int, label: String)) -> some View {
        let isSelected = selection.contains(item.weekday)
        Button {
            toggle(weekday: item.weekday, isSelected: isSelected)
        } label: {
            Text(item.label)
                .font(AFSRFont.headline(13))
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(isSelected ? Color.afsrPurpleAdaptive : Color(uiColor: .systemGray5))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(weekdayName(item.weekday))
        .accessibilityValue(isSelected ? "actif" : "inactif")
    }

    private func toggle(weekday: Int, isSelected: Bool) {
        if isSelected {
            if selection.count > 1 { selection.remove(weekday) }
        } else {
            selection.insert(weekday)
        }
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let idx = weekday - 1
        guard symbols.indices.contains(idx) else { return "" }
        return symbols[idx]
    }
}
