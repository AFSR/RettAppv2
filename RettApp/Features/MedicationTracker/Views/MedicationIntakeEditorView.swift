import SwiftUI

/// Édite une prise individuelle d'un médicament (heure, dose, jours actifs,
/// notifications). Présentée via NavigationLink depuis `MedicationEditor`.
struct MedicationIntakeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var intake: MedicationIntake
    let unit: DoseUnit

    @State private var doseString: String = ""

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
        .navigationTitle("Prise de \(intake.formattedTime)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: syncDoseString)
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
                    .onChange(of: doseString) { _, newValue in
                        if let v = Double(newValue.replacingOccurrences(of: ",", with: ".")) {
                            intake.dose = v
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
            Toggle(isOn: $intake.notifyEnabled) {
                Label("Rappeler cette prise", systemImage: "bell.badge")
            }
        } footer: {
            Text("Désactivez si cette prise est gérée par un tiers (école, centre, autre parent) et que vous ne voulez pas être notifié sur cet appareil ces jours-là.")
        }
    }

    // MARK: - Helpers

    private func syncDoseString() {
        if intake.dose.truncatingRemainder(dividingBy: 1) == 0 {
            doseString = String(Int(intake.dose))
        } else {
            doseString = String(intake.dose)
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.hour = intake.hour
                c.minute = intake.minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                intake.hour = comps.hour ?? intake.hour
                intake.minute = comps.minute ?? intake.minute
            }
        )
    }

    private var weekdaysBinding: Binding<Set<Int>> {
        Binding(
            get: { intake.weekdays },
            set: { intake.weekdays = $0 }
        )
    }

    private var presetBinding: Binding<WeekdayPreset> {
        Binding(
            get: {
                if intake.isEveryDay { return .everyDay }
                if intake.isWeekdaysOnly { return .weekdaysOnly }
                if intake.isWeekendOnly { return .weekendOnly }
                return .custom
            },
            set: { preset in
                switch preset {
                case .everyDay:     intake.weekdays = MedicationIntake.allWeekdays
                case .weekdaysOnly: intake.weekdays = MedicationIntake.weekdaysOnly
                case .weekendOnly:  intake.weekdays = MedicationIntake.weekendOnly
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
        return symbols[weekday - 1]
    }
}
