import SwiftUI
import SwiftData

/// Sheet de saisie manuelle d'une crise dans le passé : date + heure de début et de fin,
/// type, déclencheur, notes. Utile pour rattraper l'historique quand le chrono temps réel
/// n'a pas pu être lancé.
struct ManualSeizureEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(CloudKitSyncService.self) private var sync
    @Query private var profiles: [ChildProfile]

    @State private var startDate: Date = {
        let cal = Calendar.current
        return cal.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
    }()
    @State private var durationMode: DurationMode = .endDate
    @State private var endDate: Date = Date()
    @State private var durationMinutes: Int = 1
    @State private var durationSeconds: Int = 0

    @State private var seizureType: SeizureType = .tonicClonic
    @State private var trigger: SeizureTrigger = .none
    @State private var triggerNotes: String = ""
    @State private var notes: String = ""
    @State private var infoType: SeizureType?

    enum DurationMode: String, CaseIterable, Identifiable {
        case endDate, duration
        var id: String { rawValue }
        var label: String {
            switch self {
            case .endDate:  return "Heure de fin"
            case .duration: return "Durée"
            }
        }
    }

    private var computedEnd: Date {
        switch durationMode {
        case .endDate: return endDate
        case .duration:
            let total = TimeInterval(durationMinutes * 60 + durationSeconds)
            return startDate.addingTimeInterval(total)
        }
    }

    private var canSave: Bool {
        let end = computedEnd
        return end > startDate && end <= Date().addingTimeInterval(60)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Début", selection: $startDate, in: ...Date())
                } header: {
                    Text("Quand la crise a-t-elle eu lieu ?")
                } footer: {
                    Text("Les saisies a posteriori vous permettent de rattraper une crise que vous n'avez pas pu chronométrer en direct.")
                }

                Section {
                    Picker("Mode", selection: $durationMode) {
                        ForEach(DurationMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch durationMode {
                    case .endDate:
                        DatePicker("Fin", selection: $endDate, in: startDate...Date().addingTimeInterval(60))
                    case .duration:
                        HStack {
                            Stepper(value: $durationMinutes, in: 0...30) {
                                Text("\(durationMinutes) min")
                                    .monospacedDigit()
                            }
                        }
                        HStack {
                            Stepper(value: $durationSeconds, in: 0...59, step: 5) {
                                Text("\(durationSeconds) s")
                                    .monospacedDigit()
                            }
                        }
                    }
                    Text("Durée totale : \(formatDuration(Int(computedEnd.timeIntervalSince(startDate))))")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(SeizureType.allCases) { t in
                        SeizureTypeChoiceRow(
                            type: t,
                            selected: seizureType == t,
                            onSelect: { seizureType = t },
                            onInfo: { infoType = t }
                        )
                    }
                } header: {
                    Text("Type de crise")
                } footer: {
                    Text("Touchez ⓘ pour une description en langage simple.")
                }

                Section("Déclencheur possible") {
                    Picker("Déclencheur", selection: $trigger) {
                        ForEach(SeizureTrigger.allCases) { t in
                            Text(t.label).tag(t)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if trigger == .other {
                        TextField("Précisez", text: $triggerNotes, axis: .vertical)
                            .lineLimit(1...3)
                    }
                }

                Section("Notes") {
                    TextField("Notes libres (déroulé, sortie de crise…)", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Saisir une crise")
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
            .sheet(item: $infoType) { t in
                ManualSeizureInfoSheet(type: t)
            }
        }
    }

    private func save() {
        let event = SeizureEvent(
            startTime: startDate,
            endTime: computedEnd,
            seizureType: seizureType,
            trigger: trigger,
            triggerNotes: triggerNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            childProfileId: profiles.first?.id
        )
        modelContext.insert(event)
        try? modelContext.saveTouching()
        sync.scheduleSync(context: modelContext, priority: .urgent)
        dismiss()
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds <= 0 { return "—" }
        let m = seconds / 60
        let s = seconds % 60
        if m == 0 { return "\(s) s" }
        if s == 0 { return "\(m) min" }
        return "\(m) min \(s) s"
    }
}

// MARK: - Helpers

private struct SeizureTypeChoiceRow: View {
    let type: SeizureType
    let selected: Bool
    let onSelect: () -> Void
    let onInfo: () -> Void

    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Color.afsrPurpleAdaptive : .secondary)
                        .font(.system(size: 20))
                    Text(type.label).foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.afsrPurpleAdaptive)
                    .font(.system(size: 20))
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct ManualSeizureInfoSheet: View {
    let type: SeizureType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Circle().fill(Color(hex: type.color)).frame(width: 16, height: 16)
                        Text(type.label).font(AFSRFont.title(26))
                    }
                    Text(type.parentDescription)
                        .font(AFSRFont.body())
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }
            .navigationTitle("Type de crise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
