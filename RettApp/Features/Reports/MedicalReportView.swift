import SwiftUI
import SwiftData

/// Écran de génération + archivage des rapports médicaux PDF.
struct MedicalReportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [ChildProfile]
    @Query(sort: \SeizureEvent.startTime) private var allSeizures: [SeizureEvent]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]
    @Query(sort: \MedicationLog.scheduledTime) private var allLogs: [MedicationLog]
    @Query(sort: \MoodEntry.timestamp) private var allMoods: [MoodEntry]
    @Query(sort: \DailyObservation.dayStart) private var allObservations: [DailyObservation]

    @State private var preset: PeriodPreset = .lastMonth
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()
    @State private var parentNotes: String = ""

    @State private var generating = false
    @State private var lastGeneratedURL: URL?
    @State private var showShare = false
    @State private var errorMessage: String?
    @State private var archivedReports: [URL] = []
    @State private var reportToShare: URL?

    enum PeriodPreset: String, CaseIterable, Identifiable {
        case lastWeek, lastMonth, last3Months, last6Months, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .lastWeek: return "7 derniers jours"
            case .lastMonth: return "30 derniers jours"
            case .last3Months: return "3 derniers mois"
            case .last6Months: return "6 derniers mois"
            case .custom: return "Période personnalisée"
            }
        }
    }

    var body: some View {
        Form {
            Section("Période couverte") {
                Picker("Période", selection: $preset) {
                    ForEach(PeriodPreset.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                if preset == .custom {
                    DatePicker("Du", selection: $customStart, in: ...Date(), displayedComponents: .date)
                    DatePicker("Au", selection: $customEnd, in: customStart...Date(), displayedComponents: .date)
                }
            }

            Section("Observations à inclure") {
                TextField("Notes pour le médecin (optionnel)", text: $parentNotes, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section {
                Button {
                    Task { await generate() }
                } label: {
                    HStack {
                        if generating { ProgressView().controlSize(.small) }
                        Text(generating ? "Génération…" : "Générer le rapport PDF")
                    }
                }
                .disabled(generating)
            } footer: {
                Text("Le rapport est archivé dans l'application et peut être partagé par e-mail, AirDrop ou Messages avec le médecin.")
            }

            if !archivedReports.isEmpty {
                Section("Rapports archivés") {
                    ForEach(archivedReports, id: \.self) { url in
                        ArchivedReportRow(url: url) {
                            reportToShare = url
                        } onDelete: {
                            try? MedicalReportGenerator.deleteReport(url)
                            refreshArchive()
                        }
                    }
                }
            }
        }
        .navigationTitle("Rapport médecin")
        .navigationBarTitleDisplayMode(.inline)
        .task { refreshArchive() }
        .sheet(isPresented: $showShare) {
            if let url = lastGeneratedURL { ShareSheet(items: [url]) }
        }
        .sheet(item: Binding(
            get: { reportToShare.map { ShareItem(url: $0) } },
            set: { reportToShare = $0?.url }
        )) { item in
            ShareSheet(items: [item.url])
        }
        .alert("Erreur", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Génération

    private func generate() async {
        generating = true
        defer { generating = false }
        let (start, end) = currentPeriod()
        let seizuresInPeriod = allSeizures.filter { $0.startTime >= start && $0.startTime <= end }
        let logsInPeriod = allLogs.filter { $0.scheduledTime >= start && $0.scheduledTime <= end }
        let moodsInPeriod = allMoods.filter { $0.timestamp >= start && $0.timestamp <= end }
        let observationsInPeriod = allObservations.filter { $0.dayStart >= start && $0.dayStart <= end }
        let input = MedicalReportGenerator.Input(
            child: profiles.first,
            periodStart: start,
            periodEnd: end,
            seizures: seizuresInPeriod,
            medications: medications,
            logs: logsInPeriod,
            moods: moodsInPeriod,
            observations: observationsInPeriod,
            parentNotes: parentNotes
        )
        do {
            let url = try MedicalReportGenerator.generate(input)
            lastGeneratedURL = url
            showShare = true
            refreshArchive()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func currentPeriod() -> (Date, Date) {
        let cal = Calendar.current
        let now = Date()
        switch preset {
        case .lastWeek:
            return (cal.date(byAdding: .day, value: -7, to: now) ?? now, now)
        case .lastMonth:
            return (cal.date(byAdding: .day, value: -30, to: now) ?? now, now)
        case .last3Months:
            return (cal.date(byAdding: .month, value: -3, to: now) ?? now, now)
        case .last6Months:
            return (cal.date(byAdding: .month, value: -6, to: now) ?? now, now)
        case .custom:
            return (cal.startOfDay(for: customStart), cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: customEnd)) ?? customEnd)
        }
    }

    private func refreshArchive() {
        archivedReports = MedicalReportGenerator.archivedReports()
    }
}

// MARK: - Row

private struct ArchivedReportRow: View {
    let url: URL
    let onShare: () -> Void
    let onDelete: () -> Void

    @State private var showConfirm = false

    private var creationDate: Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    }

    var body: some View {
        HStack {
            Image(systemName: "doc.fill")
                .foregroundStyle(.afsrPurpleAdaptive)
                .font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(AFSRFont.body(14))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(creationDate, format: .dateTime.day().month().year().hour().minute())
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { onShare() } label: { Image(systemName: "square.and.arrow.up") }
                .buttonStyle(.borderless)
            Button { showConfirm = true } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
        }
        .confirmationDialog("Supprimer ce rapport ?", isPresented: $showConfirm) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) { }
        }
    }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}
