import SwiftUI
import SwiftData

/// Onglet principal de l'app — Journal du jour.
/// Combine : bouton urgence crise (si épilepsie), saisie rapide humeur/observations,
/// prises de médicaments planifiées et ponctuelles, crises du jour. Tout est saisi ici.
struct JournalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CloudKitSyncService.self) private var sync
    @Query private var profiles: [ChildProfile]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]

    @State private var viewModel = MedicationViewModel()
    @State private var seizureTracker = SeizureTrackerViewModel()
    @State private var showPlan = false
    @State private var showAdHoc = false
    @State private var showDatePicker = false
    @State private var showMoodSheet = false
    @State private var showObservationSheet = false
    @State private var showSymptomSheet = false
    @State private var showSeizureQualification = false
    @State private var showSeizureHistory = false
    @State private var showManualSeizureEntry = false
    @State private var showBookletImport = false

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

                // Bannière chronomètre quand une crise est en cours d'enregistrement.
                // Le déclenchement se fait directement depuis le bouton « Démarrer
                // une crise » du Journal — plus de plein-écran intermédiaire.
                if case .recording = seizureTracker.phase {
                    seizureRecordingBanner
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                }

                JournalContent(
                    selectedDate: viewModel.selectedDate,
                    medications: medications,
                    profile: profile,
                    viewModel: viewModel,
                    seizureInProgress: { if case .recording = seizureTracker.phase { return true } else { return false } }(),
                    emergencyAction: epilepsyEnabled ? { startSeizureTimer() } : nil,
                    showSeizureHistory: { showSeizureHistory = true }
                )
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Deux boutons, deux intentions, et c'est tout le sens de la
            // réorganisation. Avant, le « + » ne faisait qu'une chose — une
            // prise ponctuelle — tandis que le menu « … » mélangeait la
            // saisie du jour, une action rare et de la navigation. Un parent
            // qui veut noter une humeur appuie sur « + », puisque c'est le
            // geste universel pour ajouter, et ne trouvait rien.
            //
            // Désormais : « + » = je note quelque chose aujourd'hui.
            // « … » = j'ouvre autre chose.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Ordre de fréquence réelle : une prise ponctuelle et une
                    // humeur se saisissent tous les jours, une crise
                    // antérieure une fois de temps en temps.
                    Button { showAdHoc = true } label: {
                        Label("Prise ponctuelle", systemImage: "pills.fill")
                    }
                    Button { showMoodSheet = true } label: {
                        Label("Humeur", systemImage: "face.smiling")
                    }
                    Button { showSymptomSheet = true } label: {
                        Label("Symptôme", systemImage: "stethoscope")
                    }
                    Button { showObservationSheet = true } label: {
                        Label("Repas et sommeil", systemImage: "fork.knife")
                    }
                    if epilepsyEnabled {
                        Divider()
                        Button { showManualSeizureEntry = true } label: {
                            Label("Crise antérieure", systemImage: "calendar.badge.plus")
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Noter quelque chose")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showPlan = true } label: {
                        Label("Plan médicamenteux", systemImage: "list.bullet.rectangle")
                    }
                    if epilepsyEnabled {
                        Button { showSeizureHistory = true } label: {
                            Label("Historique des crises", systemImage: "list.bullet.rectangle.portrait")
                        }
                    }
                    Divider()
                    // Action rare : une fois par semaine au mieux, quand le
                    // cahier revient de l'école. Elle n'a rien à faire parmi
                    // les gestes quotidiens.
                    Button { showBookletImport = true } label: {
                        Label("Scanner le cahier de suivi", systemImage: "doc.text.viewfinder")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Ouvrir")
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
        .sheet(isPresented: $showSeizureQualification, onDismiss: {
            // Si l'utilisateur ferme la sheet sans valider, on annule la crise
            // (rien n'est sauvegardé). C'est volontaire : pas de demi-saisie.
            if case .qualifying = seizureTracker.phase {
                seizureTracker.cancelQualification()
            }
        }) {
            if case .qualifying(let start, let end) = seizureTracker.phase {
                SeizureQualificationSheet(
                    start: start,
                    end: end
                ) { type, trigger, triggerNotes, notes in
                    Task {
                        await seizureTracker.save(
                            context: modelContext,
                            type: type,
                            trigger: trigger,
                            triggerNotes: triggerNotes,
                            notes: notes,
                            childProfile: profile,
                            healthKit: HealthKitManager.shared
                        )
                        // Crise = événement médical prioritaire — sync immédiate
                        // vers l'autre parent (délai debounce urgent = 0.5s).
                        sync.scheduleSync(context: modelContext, priority: .urgent)
                        showSeizureQualification = false
                    }
                }
                .interactiveDismissDisabled()
            }
        }
        .onChange(of: seizureTracker.phase) { _, newValue in
            if case .qualifying = newValue { showSeizureQualification = true }
        }
        .sheet(isPresented: $showMoodSheet) { MoodSheet() }
        .sheet(isPresented: $showSymptomSheet) { SymptomSheet() }
        .sheet(isPresented: $showObservationSheet) {
            DailyObservationSheet(dayStart: viewModel.selectedDate)
        }
        .sheet(isPresented: $showBookletImport) {
            BookletImportSheet()
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                VStack(spacing: 0) {
                    // `labelsHidden` : le titre de la feuille dit déjà « Choisir
                    // une date », le label du DatePicker ferait doublon et
                    // volerait de la hauteur au calendrier.
                    DatePicker("Date", selection: $viewModel.selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(.horizontal)
                    Spacer(minLength: 0)
                }
                .navigationTitle("Choisir une date")
                // Titre inline : le format large consommait ~96 pt de hauteur,
                // ce qui rognait le calendrier.
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Aujourd'hui") {
                            viewModel.selectedDate = Calendar.current.startOfDay(for: Date())
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { showDatePicker = false }
                    }
                }
            }
            // Hauteur explicite : le calendrier `.graphical` mesure ~400 pt.
            // Avec le détent `.medium` (moitié d'écran) il était comprimé et
            // rogné. On dimensionne la feuille pour qu'il tienne entier, tout
            // en gardant `.large` pour les grands réglages d'accessibilité.
            .presentationDetents([.height(520), .large])
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
    /// Bannière compacte affichée au-dessus du journal pendant l'enregistrement
    /// d'une crise : durée en cours + bouton « Terminer ». Remplace l'ancien
    /// plein-écran SeizureTrackerView.
    private var seizureRecordingBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.afsrEmergency.opacity(0.25))
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(Color.afsrEmergency)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Crise en cours")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.afsrEmergency)
                Text(seizureTracker.formattedCurrentDuration())
                    .font(AFSRFont.headline(20))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            Spacer()
            Button {
                seizureTracker.stop()
            } label: {
                Label("Terminer", systemImage: "checkmark.circle.fill")
                    .font(AFSRFont.headline(14))
            }
            .buttonStyle(.borderedProminent)
            .tint(.afsrSuccess)
            .controlSize(.regular)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.afsrEmergency.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.afsrEmergency.opacity(0.4), lineWidth: 0.5)
        )
    }

    private func startSeizureTimer() {
        guard case .idle = seizureTracker.phase else { return }
        seizureTracker.start()
    }

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
    @Environment(CloudKitSyncService.self) private var sync
    let selectedDate: Date
    let medications: [Medication]
    let profile: ChildProfile?
    let viewModel: MedicationViewModel
    /// True si une crise est en cours d'enregistrement (la bannière prend
    /// la place du bouton « Démarrer une crise »).
    let seizureInProgress: Bool
    /// Action déclenchée par le gros bouton urgence (nil = pas d'épilepsie, bouton caché).
    let emergencyAction: (() -> Void)?
    /// Ouvre l'historique complet des crises.
    let showSeizureHistory: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var logs: [MedicationLog]
    @Query private var moods: [MoodEntry]
    @Query private var observations: [DailyObservation]
    @State private var editingTakenTimeFor: MedicationLog?
    @Query private var seizures: [SeizureEvent]
    @Query private var symptoms: [SymptomEvent]

    @State private var showMood = false
    @State private var showObservation = false

    init(selectedDate: Date, medications: [Medication], profile: ChildProfile?, viewModel: MedicationViewModel,
         seizureInProgress: Bool,
         emergencyAction: (() -> Void)?, showSeizureHistory: @escaping () -> Void) {
        self.selectedDate = selectedDate
        self.medications = medications
        self.profile = profile
        self.viewModel = viewModel
        self.seizureInProgress = seizureInProgress
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
        self._symptoms = Query(
            filter: #Predicate<SymptomEvent> { $0.timestamp >= day && $0.timestamp < nextDay },
            sort: \SymptomEvent.timestamp
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
                // Bouton « Démarrer une crise » uniquement quand aucune crise
                // n'est en cours (sinon la bannière du JournalView prend le relais).
                if let emergencyAction, !seizureInProgress {
                    AFSREmergencyButton(title: "Démarrer une crise", action: emergencyAction)
                        .padding(.horizontal)
                }
                summaryHeader
                moodObservationCard
                if logs.isEmpty && seizures.isEmpty && moods.isEmpty {
                    emptyState
                } else {
                    HStack {
                        Text("Fil de la journée")
                            .font(AFSRFont.headline(17))
                        Spacer()
                        Text(combinedFeed.count == 1 ? "1 entrée" : "\(combinedFeed.count) entrées")
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    LazyVStack(spacing: 10) {
                        ForEach(combinedFeed) { item in
                            JournalFeedRow(
                                item: item,
                                onToggle: { log in toggle(log) },
                                onDelete: { delete($0) },
                                onEditTakenTime: { editingTakenTimeFor = $0 },
                                onSeizureTap: { showSeizureHistory() }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                Spacer(minLength: 24)
            }
            .padding(.top, 8)
        }
        .sheet(item: $editingTakenTimeFor) { log in
            MedicationTakenTimeSheet(log: log) {
                try? modelContext.saveTouching()
                sync.scheduleSync(context: modelContext, priority: .urgent)
            }
            .presentationDetents([.medium])
        }
    }

    /// Combine logs médicament, crises, humeurs et symptômes en un feed chronologique unique.
    private var combinedFeed: [JournalFeedItem] {
        var items: [JournalFeedItem] = []
        items.append(contentsOf: logs.map { JournalFeedItem.medication($0) })
        items.append(contentsOf: seizures.map { JournalFeedItem.seizure($0) })
        items.append(contentsOf: moods.map { JournalFeedItem.mood($0) })
        items.append(contentsOf: symptoms.map { JournalFeedItem.symptom($0) })
        return items.sorted { $0.time < $1.time }
    }

    private func delete(_ log: MedicationLog) {
        modelContext.delete(log)
        try? modelContext.saveTouching()
        sync.scheduleSync(context: modelContext, priority: .urgent)
    }

    private var summaryHeader: some View {
        let s = stats
        let lateLogs = logs.filter { $0.isLate }.count
        return HStack(spacing: 10) {
            StatPill(value: "\(s.taken)/\(s.planned)", label: "Pris", color: .afsrSuccess,
                     systemImage: "checkmark",
                     progress: s.planned > 0 ? Double(s.taken) / Double(s.planned) : 0)
            StatPill(value: "\(s.adHoc)", label: "Ponctuels", color: .afsrPurpleAdaptive,
                     systemImage: "pin.fill")
            if lateLogs > 0 {
                StatPill(value: "\(lateLogs)", label: "En retard", color: .afsrWarning,
                         systemImage: "clock.fill")
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var moodObservationCard: some View {
        let dayObs = observations.first
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AFSRIconBadge(systemImage: "face.smiling", color: .afsrSuccess, size: 28)
                Text("Humeur & observations")
                    .font(AFSRFont.headline(16))
                Spacer()
            }

            if moods.isEmpty && (dayObs == nil || dayObs?.isPopulated == false) {
                Text("Rien de noté pour ce jour. Ajoutez une humeur, les repas ou le sommeil.")
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
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.afsrPurpleAdaptive.opacity(0.15), in: Capsule())
                        .foregroundStyle(.afsrPurpleAdaptive)
                }
                .buttonStyle(AFSRPressableStyle())
                Button {
                    showObservation = true
                } label: {
                    Label(dayObs?.isPopulated == true ? "Modifier obs." : "Repas / sommeil",
                          systemImage: "square.and.pencil")
                        .font(AFSRFont.caption())
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.afsrPurpleAdaptive.opacity(0.15), in: Capsule())
                        .foregroundStyle(.afsrPurpleAdaptive)
                }
                .buttonStyle(AFSRPressableStyle())
                Spacer()
            }
        }
        .padding(14)
        .afsrSurface()
        .padding(.horizontal)
        .sheet(isPresented: $showMood) { MoodSheet() }
        .sheet(isPresented: $showObservation) {
            DailyObservationSheet(dayStart: selectedDate)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.afsrPurpleAdaptive.opacity(0.08))
                    .frame(width: 104, height: 104)
                Circle()
                    .fill(Color.afsrPurpleAdaptive.opacity(0.14))
                    .frame(width: 76, height: 76)
                Image(systemName: "pills.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.afsrPurpleAdaptive)
            }
            .accessibilityHidden(true)
            Text("Aucune prise pour cette journée")
                .font(AFSRFont.headline(16))
            Text("Touchez ➕ pour noter une prise, une humeur ou un symptôme. Le plan médicamenteux se règle depuis le menu ···.")
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 28)
    }

    private func toggle(_ log: MedicationLog) {
        log.taken.toggle()
        log.takenTime = log.taken ? Date() : nil
        try? modelContext.saveTouching()
        sync.scheduleSync(context: modelContext, priority: .urgent)
    }
}

// MARK: - Row du journal

// MARK: - Feed item type

private enum JournalFeedItem: Identifiable {
    case medication(MedicationLog)
    case seizure(SeizureEvent)
    case mood(MoodEntry)
    case symptom(SymptomEvent)

    var id: String {
        switch self {
        case .medication(let l): return "med-\(l.id.uuidString)"
        case .seizure(let s): return "seiz-\(s.id.uuidString)"
        case .mood(let m): return "mood-\(m.id.uuidString)"
        case .symptom(let s): return "symp-\(s.id.uuidString)"
        }
    }
    var time: Date {
        switch self {
        case .medication(let l): return l.effectiveTime
        case .seizure(let s): return s.startTime
        case .mood(let m): return m.timestamp
        case .symptom(let s): return s.timestamp
        }
    }
}

private struct JournalFeedRow: View {
    let item: JournalFeedItem
    let onToggle: (MedicationLog) -> Void
    let onDelete: (MedicationLog) -> Void
    let onEditTakenTime: (MedicationLog) -> Void
    let onSeizureTap: () -> Void

    var body: some View {
        switch item {
        case .medication(let log):
            JournalEntryRow(log: log,
                            onToggle: { onToggle(log) },
                            onDelete: { onDelete(log) },
                            onEditTakenTime: { onEditTakenTime(log) })
        case .seizure(let s):
            SeizureRowCompact(event: s, onTap: onSeizureTap)
        case .mood(let m):
            MoodRowCompact(entry: m)
        case .symptom(let s):
            SymptomRowCompact(event: s)
        }
    }
}

private struct SymptomRowCompact: View {
    let event: SymptomEvent
    var body: some View {
        HStack(spacing: 12) {
            AFSRSoftIconBadge(systemImage: event.symptomType.icon, color: .afsrPurpleAdaptive)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.symptomType.label)
                    .font(AFSRFont.headline(15))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(event.timestamp, format: .dateTime.hour().minute())
                        .font(AFSRFont.caption())
                    if event.intensityRaw > 0 {
                        Text("· intensité \(event.intensityRaw)/5")
                            .font(AFSRFont.caption())
                    }
                    if event.durationMinutes > 0 {
                        Text("· \(event.durationMinutes) min")
                            .font(AFSRFont.caption())
                    }
                }
                .foregroundStyle(.secondary)
                if !event.notes.isEmpty {
                    Text(event.notes)
                        .font(AFSRFont.caption())
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(12)
        .afsrSurface()
    }
}

private struct SeizureRowCompact: View {
    let event: SeizureEvent
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AFSRSoftIconBadge(systemImage: "waveform.path.ecg", color: .afsrEmergency)
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
            .afsrSurface()
        }
        .buttonStyle(.plain)
    }
}

private struct MoodRowCompact: View {
    let entry: MoodEntry
    var body: some View {
        HStack(spacing: 12) {
            Text(entry.level.emoji)
                .font(.system(size: 24))
                .frame(width: 40, height: 40)
                .background(Color.afsrSuccess.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .afsrSurface()
    }
}

private struct JournalEntryRow: View {
    @Bindable var log: MedicationLog
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEditTakenTime: () -> Void

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
            AFSRSoftIconBadge(systemImage: statusIcon, color: statusColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(log.medicationName)
                        .font(AFSRFont.headline(16))
                        .lineLimit(1)
                        .foregroundStyle(!log.isAdHoc && log.taken ? Color.secondary : Color.primary)
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
        .afsrSurface()
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: AFSRTokens.cornerRadiusSmall + 4, style: .continuous))
        .contextMenu {
            if !log.isAdHoc {
                Button {
                    onEditTakenTime()
                } label: {
                    Label(log.taken ? "Modifier l'heure de prise" : "Marquer pris à une autre heure…",
                          systemImage: "clock.arrow.circlepath")
                }
            }
        }
    }
}

private struct StatPill: View {
    let value: String
    let label: String
    let color: Color
    var systemImage: String = "circle.fill"
    /// Progression 0…1 affichée en anneau autour de l'icône (nil = pas d'anneau).
    var progress: Double? = nil

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 4)
                if let progress {
                    Circle()
                        .trim(from: 0, to: max(0, min(1, progress)))
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.4), value: progress)
                }
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(AFSRFont.headline(18))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(label)
                    .font(AFSRFont.caption(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .afsrSurface()
        .accessibilityElement(children: .combine)
    }
}

private extension Double {
    var shortString: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(format: "%.1f", self)
    }
}

// MARK: - Edit "taken time" sheet

/// Petite feuille pour corriger l'heure à laquelle un médicament a été donné.
/// Utile quand on note la prise en différé dans la journée — par exemple le
/// matin on a donné Keppra à 8h mais on coche seulement le soir : il faut
/// pouvoir saisir 8h, pas l'heure actuelle.
///
/// Pré-rempli :
/// - `takenTime` existant s'il y en a un,
/// - sinon `scheduledTime` (cas le plus fréquent : on coche tardivement la
///   prise prévue ce matin, le plus probable est qu'elle a été donnée à
///   l'heure planifiée).
private struct MedicationTakenTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var log: MedicationLog
    /// Appelé après modification pour que le parent puisse persister + sync.
    let onSave: () -> Void

    @State private var pickedTime: Date
    @State private var markAsTaken: Bool

    init(log: MedicationLog, onSave: @escaping () -> Void) {
        self.log = log
        self.onSave = onSave
        _pickedTime = State(initialValue: log.takenTime ?? log.scheduledTime)
        _markAsTaken = State(initialValue: log.taken || log.takenTime == nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "pills.fill")
                            .foregroundStyle(.afsrPurpleAdaptive)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.medicationName)
                                .font(AFSRFont.headline(15))
                            Text("Prévu à \(log.scheduledTime, format: .dateTime.hour().minute())")
                                .font(AFSRFont.caption())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Prise effectuée", isOn: $markAsTaken)
                    if markAsTaken {
                        DatePicker(
                            "Heure de prise réelle",
                            selection: $pickedTime,
                            displayedComponents: [.hourAndMinute, .date]
                        )
                    }
                } footer: {
                    Text("Si la prise a été faite plus tôt (ou plus tard) que l'heure prévue, ajustez ici. Vous pouvez aussi cocher une prise oubliée a posteriori, ou la décocher si elle a été indiquée par erreur.")
                }
            }
            .navigationTitle("Heure de prise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if markAsTaken {
                            log.taken = true
                            log.takenTime = pickedTime
                        } else {
                            log.taken = false
                            log.takenTime = nil
                        }
                        onSave()
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}

#Preview {
    NavigationStack { JournalView() }
        .modelContainer(PreviewData.container)
}
