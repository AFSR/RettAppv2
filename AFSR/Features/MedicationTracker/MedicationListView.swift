import SwiftUI
import SwiftData

struct MedicationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]

    @State private var viewModel = MedicationViewModel()
    @State private var showPlan = false
    @State private var showDatePicker = false

    private var profile: ChildProfile? { profiles.first }

    var body: some View {
        ZStack {
            Color.afsrBackground.ignoresSafeArea()

            if medications.isEmpty {
                EmptyStateView(
                    title: "Aucun médicament",
                    message: "Configurez le plan médicamenteux pour voir les prises du jour.",
                    systemImage: "pill",
                    actionTitle: "Configurer le plan"
                ) { showPlan = true }
            } else {
                MedicationDayListContent(
                    selectedDate: viewModel.selectedDate,
                    medications: medications,
                    profile: profile,
                    viewModel: viewModel
                )
            }
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
                HStack {
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    Menu {
                        Button { showPlan = true } label: { Label("Plan médicamenteux", systemImage: "list.bullet.rectangle") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showPlan) { NavigationStack { MedicationPlanView() } }
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
        if let name = profile?.firstName, !name.isEmpty {
            return "Médicaments — \(name)"
        }
        return "Médicaments"
    }

    private func shift(_ days: Int) {
        let cal = Calendar.current
        if let newDate = cal.date(byAdding: .day, value: days, to: viewModel.selectedDate) {
            viewModel.selectedDate = cal.startOfDay(for: newDate)
        }
    }
}

private struct MedicationDayListContent: View {
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

    private var grouped: [(HourMinute.DayPeriod, [MedicationLog])] {
        let dict = Dictionary(grouping: logs) { log -> HourMinute.DayPeriod in
            HourMinute(date: log.scheduledTime).period
        }
        let order: [HourMinute.DayPeriod] = [.morning, .noon, .evening, .other]
        return order.compactMap { period in
            guard let items = dict[period], !items.isEmpty else { return nil }
            return (period, items)
        }
    }

    var body: some View {
        if logs.isEmpty {
            EmptyStateView(
                title: "Aucune prise prévue",
                message: "Aucun médicament planifié pour cette journée.",
                systemImage: "calendar"
            )
        } else {
            List {
                ForEach(grouped, id: \.0) { period, items in
                    Section(period.label) {
                        ForEach(items) { log in
                            MedicationLogRow(log: log) {
                                viewModel.togglePrise(log, in: modelContext)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.afsrBackground)
        }
    }
}

private struct MedicationLogRow: View {
    @Bindable var log: MedicationLog
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(log.medicationName)
                    .font(AFSRFont.headline(17))
                HStack(spacing: 8) {
                    Text(log.scheduledTime, format: .dateTime.hour().minute())
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                    Text("· \(log.dose.shortString) \(log.doseUnit.label)")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                    if log.isLate {
                        Text("En retard")
                            .font(AFSRFont.caption())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.afsrWarning.opacity(0.25), in: Capsule())
                            .foregroundStyle(.afsrWarning)
                    }
                    if log.taken, let takenTime = log.takenTime {
                        Text("✓ \(takenTime.formatted(.dateTime.hour().minute()))")
                            .font(AFSRFont.caption())
                            .foregroundStyle(.afsrSuccess)
                    }
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { log.taken },
                set: { _ in toggle() }
            ))
            .labelsHidden()
            .tint(.afsrSuccess)
            .accessibilityLabel(log.taken ? "Pris" : "Non pris")
        }
        .padding(.vertical, 4)
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
