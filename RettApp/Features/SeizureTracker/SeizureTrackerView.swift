import SwiftUI
import SwiftData

struct SeizureTrackerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SeizureEvent.startTime, order: .reverse) private var seizures: [SeizureEvent]
    @Query private var profiles: [ChildProfile]

    @State private var viewModel = SeizureTrackerViewModel()
    @State private var pulse = false
    @State private var showHistory = false
    @State private var showQualification = false

    private var profile: ChildProfile? { profiles.first }
    private var lastSeizure: SeizureEvent? { seizures.first }

    var body: some View {
        ZStack {
            backgroundPulse
            VStack(spacing: 24) {
                if case .recording = viewModel.phase {
                    recordingUI
                } else {
                    idleUI
                }
            }
            .padding(AFSRTokens.spacingLarge)
        }
        .navigationTitle("Suivi épilepsie")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showHistory = true
                } label: {
                    Label("Historique", systemImage: "list.bullet.rectangle")
                }
                .accessibilityLabel("Historique des crises")
            }
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack { SeizureHistoryView() }
        }
        .sheet(isPresented: $showQualification, onDismiss: {
            if case .qualifying = viewModel.phase {
                viewModel.cancelQualification()
            }
        }) {
            if case .qualifying(let start, let end) = viewModel.phase {
                SeizureQualificationSheet(
                    start: start,
                    end: end
                ) { type, trigger, triggerNotes, notes in
                    Task {
                        await viewModel.save(
                            context: modelContext,
                            type: type,
                            trigger: trigger,
                            triggerNotes: triggerNotes,
                            notes: notes,
                            childProfile: profile,
                            healthKit: HealthKitManager.shared
                        )
                        showQualification = false
                    }
                }
                .interactiveDismissDisabled()
            }
        }
        .onChange(of: viewModel.phase) { _, newValue in
            if case .qualifying = newValue { showQualification = true }
        }
    }

    // MARK: - Subviews

    private var backgroundPulse: some View {
        Group {
            if case .recording = viewModel.phase {
                Color.afsrEmergency
                    .opacity(pulse ? 0.35 : 0.12)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
                    .onDisappear { pulse = false }
            } else {
                Color.afsrBackground.ignoresSafeArea()
            }
        }
    }

    private var idleUI: some View {
        VStack(spacing: AFSRTokens.spacingLarge) {
            Spacer()

            AFSREmergencyButton(title: "Démarrer une crise") {
                viewModel.start()
            }
            .accessibilityHint("Démarre un chronomètre pour enregistrer la durée d'une crise.")

            if let last = lastSeizure {
                SectionCard(title: "Dernière crise", systemImage: "clock.arrow.circlepath") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(last.startTime, format: .dateTime.day().month().year().hour().minute())
                                .font(AFSRFont.body())
                            Text(last.formattedDuration + " · " + last.seizureType.label)
                                .font(AFSRFont.caption())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            } else {
                Text("Aucune crise enregistrée pour le moment.")
                    .font(AFSRFont.body())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            statsCard

            Spacer()
        }
    }

    private var recordingUI: some View {
        VStack(spacing: AFSRTokens.spacingLarge) {
            Spacer()
            Text("Crise en cours")
                .font(AFSRFont.headline(22))
                .foregroundStyle(.white)
            Text(viewModel.formattedCurrentDuration())
                .font(AFSRFont.timer())
                .foregroundStyle(.white)
                .accessibilityLabel("Durée : \(Int(viewModel.currentDuration)) secondes")

            Spacer()

            AFSRPrimaryButton(title: "Terminer la crise", icon: "checkmark.circle.fill", color: .afsrSuccess) {
                viewModel.stop()
            }
            .padding(.bottom, AFSRTokens.spacingLarge)
        }
    }

    private var statsCard: some View {
        let monthCount = monthlyCount()
        let avg = averageDurationMinutes()
        return SectionCard(title: "Ce mois", systemImage: "chart.bar.fill") {
            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("\(monthCount)")
                        .font(AFSRFont.title(32))
                    Text(monthCount <= 1 ? "crise" : "crises")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 48)
                VStack(alignment: .leading) {
                    Text(avg == nil ? "—" : String(format: "%.1f min", avg!))
                        .font(AFSRFont.title(32))
                    Text("durée moyenne")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private func monthlyCount() -> Int {
        let cal = Calendar.current
        let now = Date()
        return seizures.filter { cal.isDate($0.startTime, equalTo: now, toGranularity: .month) }.count
    }

    private func averageDurationMinutes() -> Double? {
        let cal = Calendar.current
        let now = Date()
        let month = seizures.filter { cal.isDate($0.startTime, equalTo: now, toGranularity: .month) }
        guard !month.isEmpty else { return nil }
        let total = month.map { $0.durationSeconds }.reduce(0, +)
        return Double(total) / Double(month.count) / 60.0
    }
}

// MARK: - Qualification sheet

struct SeizureQualificationSheet: View {
    let start: Date
    let end: Date
    let onSave: (SeizureType, SeizureTrigger, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var type: SeizureType = .tonicClonic
    @State private var trigger: SeizureTrigger = .none
    @State private var triggerNotes: String = ""
    @State private var notes: String = ""
    @State private var infoType: SeizureType?

    var body: some View {
        NavigationStack {
            Form {
                Section("Durée") {
                    Text(SeizureEvent.formatDuration(Int(end.timeIntervalSince(start))))
                        .font(AFSRFont.headline())
                }

                Section {
                    ForEach(SeizureType.allCases) { t in
                        SeizureTypeRow(
                            type: t,
                            selected: type == t,
                            onSelect: { type = t },
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
                    TextField("Notes libres", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Qualifier la crise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        onSave(type, trigger, triggerNotes, notes)
                    }
                    .bold()
                }
            }
            .sheet(item: $infoType) { t in
                SeizureTypeInfoSheet(type: t)
            }
        }
    }
}

// MARK: - Type row + info sheet

private struct SeizureTypeRow: View {
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
                    Text(type.label)
                        .foregroundStyle(.primary)
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
            .accessibilityLabel("Description : \(type.label)")
        }
    }
}

private struct SeizureTypeInfoSheet: View {
    let type: SeizureType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: type.color))
                            .frame(width: 16, height: 16)
                        Text(type.label)
                            .font(AFSRFont.title(26))
                    }
                    Text(type.parentDescription)
                        .font(AFSRFont.body())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Cette description est volontairement simplifiée pour les parents. Elle ne remplace pas l'avis de votre neurologue.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
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

#Preview("Idle") {
    NavigationStack { SeizureTrackerView() }
        .modelContainer(PreviewData.container)
}
