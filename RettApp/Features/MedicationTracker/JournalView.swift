import SwiftUI
import SwiftData

/// Onglet principal de l'app — Journal du jour.
/// Combine : bouton urgence crise (si épilepsie), saisie rapide humeur/observations,
/// prises de médicaments planifiées et ponctuelles, crises du jour. Tout est saisi ici.
struct JournalView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]

    @State private var viewModel = MedicationViewModel()
    @State private var showPlan = false
    @State private var showAdHoc = false
    @State private var showDatePicker = false
    @State private var showMoodSheet = false
    @State private var showObservationSheet = false
    @State private var showSeizureTracker = false
    @State private var showSeizureHistory = false
    @State private var showManualSeizureEntry = false

    private var profile: ChildProfile? { profiles.first }
    private var epilepsyEnabled: Bool { profile?.hasEpilepsy ?? false }

    var body: some View {
        ZStack {
            Color.afsrBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Bandeau dédié à la navigation de date — séparé des actions toolbar
                dateNavigationBar
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                JournalContent(
                    selectedDate: viewModel.selectedDate,
                    medications: medications,
                    profile: profile,
                    viewModel: viewModel,
                    emergencyAction: epilepsyEnabled ? { showSeizureTracker = true } : nil,
                    showSeizureHistory: { showSeizureHistory = true }
                )
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdHoc = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Ajouter une prise ponctuelle")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showMoodSheet = true } label: {
                        Label("Saisir une humeur", systemImage: "face.smiling")
                    }
                    Button { showObservationSheet = true } label: {
                        Label("Repas / sommeil du jour", systemImage: "fork.knife")
                    }
                    if epilepsyEnabled {
                        Divider()
                        Button { showManualSeizureEntry = true } label: {
                            Label("Saisir une crise antérieure", systemImage: "calendar.badge.plus")
                        }
                        Button { showSeizureHistory = true } label: {
                            Label("Historique des crises", systemImage: "list.bullet.rectangle.portrait")
                        }
                    }
                    Divider()
                    Button { showPlan = true } label: {
                        Label("Plan médicamenteux", systemImage: "list.bullet.rectangle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showPlan) { NavigationStack { MedicationPlanView() } }
        .sheet(isPresented: $showAdHoc) { AdHocLogSheet() }
        .sheet(isPresented: $showSeizureHistory) {
            NavigationStack { SeizureHistoryView() }
        }
        .sheet(isPresented: $showManualSeizureEntry) {
            ManualSeizureEntrySheet()
        }
        .fullScreenCover(isPresented: $showSeizureTracker) {
            NavigationStack { SeizureTrackerView() }
        }
        .sheet(isPresented: $showMoodSheet) { MoodSheet() }
        .sheet(isPresented: $showObservationSheet) {
            DailyObservationSheet(dayStart: viewModel.selectedDate)
        }
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

    /// Bandeau « ◀ Lundi 26 mai ▶ » — séparé visuellement des actions toolbar.
    private var dateNavigationBar: some View {
        HStack(spacing: 8) {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 36)
            }
            .buttonStyle(.bordered)
            .tint(.afsrPurpleAdaptive)
            .accessibilityLabel("Jour précédent")

            Button {
                showDatePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                    Text(viewModel.selectedDate, format: .dateTime.weekday(.wide).day().month())
                        .font(AFSRFont.headline(15))
                }
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.horizontal, 12)
                .background(Color.afsrPurpleAdaptive.opacity(0.15), in: Capsule())
                .foregroundStyle(.afsrPurpleAdaptive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choisir une date")

            Button { shift(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 36)
            }
            .buttonStyle(.bordered)
            .tint(.afsrPurpleAdaptive)
            .accessibilityLabel("Jour suivant")
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
    /// Action déclenchée par le gros bouton urgence (nil = pas d'épilepsie, bouton caché).
    let emergencyAction: (() -> Void)?
    /// Ouvre l'historique complet des crises.
    let showSeizureHistory: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var logs: [MedicationLog]
    @Query private var moods: [MoodEntry]
    @Query private var observations: [DailyObservation]
    @Query private var seizures: [SeizureEvent]

    @State private var showMood = false
    @State private var showObservation = false

    init(selectedDate: Date, medications: [Medication], profile: ChildProfile?, viewModel: MedicationViewModel,
         emergencyAction: (() -> Void)?, showSeizureHistory: @escaping () -> Void) {
        self.selectedDate = selectedDate
        self.medications = medications
        self.profile = profile
        self.viewModel = viewModel
        self.emergencyAction = emergencyAction
        self.showSeizureHistory = showSeizureHistory

        let day = Calendar.current.startOfDay(for: selectedDate)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        self._logs = Query(
            filter: #Predicate<MedicationLog> { $0.scheduledTime >= day && $0.scheduledTime < nextDay },
            sort: \MedicationLog.scheduledTime
        )
        self._moods = Query(
            filter: #Predicate<MoodEntry> { $0.timestamp >= day && $0.timestamp < nextDay },
            sort: \MoodEntry.timestamp
        )
        self._observations = Query(
            filter: #Predicate<DailyObservation> { $0.dayStart == day }
        )
        self._seizures = Query(
            filter: #Predicate<SeizureEvent> { $0.startTime >= day && $0.startTime < nextDay },
            sort: \SeizureEvent.startTime
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
                if let emergencyAction {
                    AFSREmergencyButton(title: "Démarrer une crise", action: emergencyAction)
                        .padding(.horizontal)
                }
                summaryHeader
                moodObservationCard
                if logs.isEmpty && seizures.isEmpty && moods.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(combinedFeed) { item in
                            JournalFeedRow(item: item, onToggle: { log in toggle(log) }, onDelete: { delete($0) }, onSeizureTap: { showSeizureHistory() })
                        }
                    }
                    .padding(.horizontal)
                }
                Spacer(minLength: 24)
            }
            .padding(.top, 8)
        }
    }

    /// Combine logs médicament, crises et humeurs en un feed chronologique unique.
    private var combinedFeed: [JournalFeedItem] {
        var items: [JournalFeedItem] = []
        items.append(contentsOf: logs.map { JournalFeedItem.medication($0) })
        items.append(contentsOf: seizures.map { JournalFeedItem.seizure($0) })
        items.append(contentsOf: moods.map { JournalFeedItem.mood($0) })
        return items.sorted { $0.time < $1.time }
    }

    private func delete(_ log: MedicationLog) {
        modelContext.delete(log)
        try? modelContext.save()
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

    @ViewBuilder
    private var moodObservationCard: some View {
        let dayObs = observations.first
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "face.smiling")
                    .foregroundStyle(.afsrPurpleAdaptive)
                Text("Humeur & observations")
                    .font(AFSRFont.headline(15))
                Spacer()
            }

            if moods.isEmpty && (dayObs == nil || dayObs?.isPopulated == false) {
                Text("Aucune saisie aujourd'hui")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
            } else {
                if !moods.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(moods) { m in
                            Text(m.level.emoji).font(.system(size: 22))
                        }
                        Spacer()
                        Text(moods.count == 1 ? "1 humeur" : "\(moods.count) humeurs")
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }
                }
                if let obs = dayObs, obs.isPopulated {
                    HStack(spacing: 8) {
                        if let r = obs.averageMealRating {
                            Label(r.label, systemImage: "fork.knife")
                                .font(AFSRFont.caption())
                                .foregroundStyle(.secondary)
                        }
                        if let r = obs.nightSleepRating {
                            Label(r.label, systemImage: "bed.double.fill")
                                .font(AFSRFont.caption())
                                .foregroundStyle(.secondary)
                        }
                        if obs.napDurationMinutes > 0 {
                            Label("\(obs.napDurationMinutes) min", systemImage: "moon.zzz.fill")
                                .font(AFSRFont.caption())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    showMood = true
                } label: {
                    Label("Humeur", systemImage: "plus")
                        .font(AFSRFont.caption())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.afsrPurpleAdaptive.opacity(0.15), in: Capsule())
                        .foregroundStyle(.afsrPurpleAdaptive)
                }
                .buttonStyle(.plain)
                Button {
                    showObservation = true
                } label: {
                    Label(dayObs?.isPopulated == true ? "Modifier obs." : "Repas / sommeil",
                          systemImage: "square.and.pencil")
                        .font(AFSRFont.caption())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.afsrPurpleAdaptive.opacity(0.15), in: Capsule())
                        .foregroundStyle(.afsrPurpleAdaptive)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: AFSRTokens.cornerRadiusSmall))
        .padding(.horizontal)
        .sheet(isPresented: $showMood) { MoodSheet() }
        .sheet(isPresented: $showObservation) {
            DailyObservationSheet(dayStart: selectedDate)
        }
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

// MARK: - Feed item type

private enum JournalFeedItem: Identifiable {
    case medication(MedicationLog)
    case seizure(SeizureEvent)
    case mood(MoodEntry)

    var id: String {
        switch self {
        case .medication(let l): return "med-\(l.id.uuidString)"
        case .seizure(let s): return "seiz-\(s.id.uuidString)"
        case .mood(let m): return "mood-\(m.id.uuidString)"
        }
    }
    var time: Date {
        switch self {
        case .medication(let l): return l.effectiveTime
        case .seizure(let s): return s.startTime
        case .mood(let m): return m.timestamp
        }
    }
}

private struct JournalFeedRow: View {
    let item: JournalFeedItem
    let onToggle: (MedicationLog) -> Void
    let onDelete: (MedicationLog) -> Void
    let onSeizureTap: () -> Void

    var body: some View {
        switch item {
        case .medication(let log):
            JournalEntryRow(log: log,
                            onToggle: { onToggle(log) },
                            onDelete: { onDelete(log) })
        case .seizure(let s):
            SeizureRowCompact(event: s, onTap: onSeizureTap)
        case .mood(let m):
            MoodRowCompact(entry: m)
        }
    }
}

private struct SeizureRowCompact: View {
    let event: SeizureEvent
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 22))
                    .foregroundStyle(.afsrEmergency)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Crise — \(event.seizureType.label)")
                            .font(AFSRFont.headline(15))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    HStack(spacing: 6) {
                        Text(event.startTime, format: .dateTime.hour().minute())
                            .font(AFSRFont.caption())
                        Text("· \(event.formattedDuration)")
                            .font(AFSRFont.caption())
                        if event.trigger != .none {
                            Text("· \(event.trigger.label)")
                                .font(AFSRFont.caption())
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: AFSRTokens.cornerRadiusSmall))
        }
        .buttonStyle(.plain)
    }
}

private struct MoodRowCompact: View {
    let entry: MoodEntry
    var body: some View {
        HStack(spacing: 12) {
            Text(entry.level.emoji)
                .font(.system(size: 26))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.level.label)
                    .font(AFSRFont.headline(15))
                HStack(spacing: 6) {
                    Text(entry.timestamp, format: .dateTime.hour().minute())
                        .font(AFSRFont.caption())
                    if !entry.notes.isEmpty {
                        Text("·").font(AFSRFont.caption())
                        Text(entry.notes)
                            .font(AFSRFont.caption())
                            .italic()
                            .lineLimit(2)
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: AFSRTokens.cornerRadiusSmall))
    }
}

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
    NavigationStack { JournalView() }
        .modelContainer(PreviewData.container)
}
