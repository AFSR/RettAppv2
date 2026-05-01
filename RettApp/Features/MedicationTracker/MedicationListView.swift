import SwiftUI
import SwiftData

/// Journal chronologique des médicaments du jour : prises planifiées (récurrentes)
/// et prises ponctuelles (ad-hoc) mélangées et triées par heure.
struct MedicationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]

    @State private var viewModel = MedicationViewModel()
    @State private var showPlan = false
    @State private var showAdHoc = false
    @State private var showDatePicker = false

    private var profile: ChildProfile? { profiles.first }

    var body: some View {
        ZStack {
            Color.afsrBackground.ignoresSafeArea()

            JournalContent(
                selectedDate: viewModel.selectedDate,
                medications: medications,
                profile: profile,
                viewModel: viewModel
            )
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            }
            ToolbarItem(placement: .principal) {
                Button {
                    showDatePicker = true
                } label: {
                    Text(viewModel.selectedDate, format: .dateTime.weekday(.wide).day().month())
                        .font(AFSRFont.headline(16))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    Button {
                        showAdHoc = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.afsrPurpleAdaptive)
                    }
                    .accessibilityLabel("Ajouter une prise ponctuelle")
                    Menu {
                        Button { showPlan = true } label: {
                            Label("Plan médicamenteux", systemImage: "list.bullet.rectangle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showPlan) { NavigationStack { MedicationPlanView() } }
        .sheet(isPresented: $showAdHoc) { AdHocLogSheet() }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker("Date", selection: $viewModel.selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Choisir une date")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("OK") { showDatePicker = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .task(id: medications.map(\.id)) {
            viewModel.ensureLogsExist(for: viewModel.selectedDate, medications: medications, profile: profile, in: modelContext)
            await viewModel.requestNotificationPermissionIfNeeded()
            await viewModel.rescheduleAllNotifications(medications: medications, childFirstName: profile?.firstName ?? "")
        }
        .onChange(of: viewModel.selectedDate) { _, newDate in
            viewModel.ensureLogsExist(for: newDate, medications: medications, profile: profile, in: modelContext)
        }
    }

    private var title: String {
        if let n = profile?.firstName, !n.isEmpty {
            return "Journal — \(n)"
        }
        return "Journal médicaments"
    }

    private func shift(_ days: Int) {
        let cal = Calendar.current
        if let newDate = cal.date(byAdding: .day, value: days, to: viewModel.selectedDate) {
            viewModel.selectedDate = cal.startOfDay(for: newDate)
        }
    }
}

// MARK: - Contenu du journal

private struct JournalContent: View {
    let selectedDate: Date
    let medications: [Medication]
    let profile: ChildProfile?
    let viewModel: MedicationViewModel

    @Environment(\.modelContext) private var modelContext
    @Query private var logs: [MedicationLog]

    init(selectedDate: Date, medications: [Medication], profile: ChildProfile?, viewModel: MedicationViewModel) {
        self.selectedDate = selectedDate
        self.medications = medications
        self.profile = profile
        self.viewModel = viewModel

        let day = Calendar.current.startOfDay(for: selectedDate)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        self._logs = Query(
            filter: #Predicate<MedicationLog> { $0.scheduledTime >= day && $0.scheduledTime < nextDay },
            sort: \MedicationLog.scheduledTime
        )
    }

    private var sortedLogs: [MedicationLog] {
        logs.sorted { $0.effectiveTime < $1.effectiveTime }
    }

    private var stats: (planned: Int, taken: Int, adHoc: Int) {
        let planned = logs.filter { !$0.isAdHoc }.count
        let taken = logs.filter { !$0.isAdHoc && $0.taken }.count
        let adHoc = logs.filter { $0.isAdHoc }.count
        return (planned, taken, adHoc)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryHeader
                if logs.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(sortedLogs) { log in
                            JournalEntryRow(log: log) {
                                toggle(log)
                            } onDelete: {
                                modelContext.delete(log)
                                try? modelContext.save()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                Spacer(minLength: 24)
            }
            .padding(.top, 8)
        }
    }

    private var summaryHeader: some View {
        let s = stats
        let lateLogs = logs.filter { $0.isLate }.count
        return HStack(spacing: 10) {
            StatPill(value: "\(s.taken)/\(s.planned)", label: "Pris", color: .afsrSuccess)
            StatPill(value: "\(s.adHoc)", label: "Ponctuels", color: .afsrPurpleAdaptive)
            if lateLogs > 0 {
                StatPill(value: "\(lateLogs)", label: "En retard", color: .afsrWarning)
            }
        }
        .padding(.horizontal)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "pills")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("Aucune prise pour cette journée")
                .font(AFSRFont.headline(15))
            Text("Ajoutez une prise ponctuelle avec le bouton ➕ ou configurez le plan médicamenteux.")
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 40)
    }

    private func toggle(_ log: MedicationLog) {
        log.taken.toggle()
        log.takenTime = log.taken ? Date() : nil
        try? modelContext.save()
    }
}

// MARK: - Row du journal

private struct JournalEntryRow: View {
    @Bindable var log: MedicationLog
    let onToggle: () -> Void
    let onDelete: () -> Void

    private var statusColor: Color {
        if log.isAdHoc { return .afsrPurpleAdaptive }
        if log.taken { return .afsrSuccess }
        if log.isLate { return .afsrWarning }
        return Color(.systemGray3)
    }

    private var statusIcon: String {
        if log.isAdHoc { return "pin.fill" }
        if log.taken { return "checkmark.circle.fill" }
        if log.isLate { return "clock.badge.exclamationmark.fill" }
        return "circle"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 24))
                .foregroundStyle(statusColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(log.medicationName)
                        .font(AFSRFont.headline(16))
                        .lineLimit(1)
                    if log.isAdHoc {
                        Text("Ponctuel")
                            .font(AFSRFont.caption())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.afsrPurpleAdaptive.opacity(0.15), in: Capsule())
                            .foregroundStyle(.afsrPurpleAdaptive)
                    }
                }
                HStack(spacing: 8) {
                    Text(log.effectiveTime, format: .dateTime.hour().minute())
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                    Text("· \(log.dose.shortString) \(log.doseUnit.label)")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                    if !log.isAdHoc, log.taken, let t = log.takenTime,
                       Calendar.current.compare(t, to: log.scheduledTime, toGranularity: .minute) != .orderedSame {
                        Text("(prévu \(log.scheduledTime, format: .dateTime.hour().minute()))")
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }
                }
                if log.isAdHoc, !log.adhocReason.isEmpty {
                    Text(log.adhocReason)
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(2)
                }
            }
            Spacer()

            if !log.isAdHoc {
                Toggle("", isOn: Binding(
                    get: { log.taken },
                    set: { _ in onToggle() }
                ))
                .labelsHidden()
                .tint(.afsrSuccess)
                .accessibilityLabel(log.taken ? "Pris" : "Non pris")
            } else {
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: AFSRTokens.cornerRadiusSmall))
    }
}

private struct StatPill: View {
    let value: String
    let label: String
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AFSRFont.headline(18))
                .foregroundStyle(color)
            Text(label)
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: AFSRTokens.cornerRadiusSmall))
    }
}

private extension Double {
    var shortString: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(format: "%.1f", self)
    }
}

#Preview {
    NavigationStack { MedicationListView() }
        .modelContainer(PreviewData.container)
}
