import SwiftUI
import Charts
import HealthKit

/// Affiche les données Apple Santé partagées par l'enfant (sommeil, rythme
/// cardiaque, activité). Suppose que la fonction « Health Sharing » iCloud Family
/// est déjà configurée — RettApp se contente de demander la lecture et d'agréger
/// les samples accessibles.
struct HealthDataView: View {
    @State private var period: HealthPeriod = .week
    @State private var aggregates: [DailyHealthAggregate] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var hasRequestedPermission = false

    enum HealthPeriod: String, CaseIterable, Identifiable {
        case week, month, threeMonths
        var id: String { rawValue }
        var label: String {
            switch self {
            case .week: return "7 jours"
            case .month: return "30 jours"
            case .threeMonths: return "3 mois"
            }
        }
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .threeMonths: return 90
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                introCard
                periodPicker
                if !HealthKitManager.shared.isAvailable {
                    unavailableCard
                } else if !hasRequestedPermission {
                    permissionPromptCard
                } else if loading {
                    ProgressView("Chargement…")
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if let msg = errorMessage {
                    errorCard(msg)
                } else if aggregates.contains(where: { $0.hasAnyData }) {
                    sleepChart
                    heartRateChart
                    activityChart
                } else {
                    noDataCard
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(Color.afsrBackground.ignoresSafeArea())
        .navigationTitle("Données Santé")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: period) { _, _ in Task { await reload() } }
    }

    // MARK: - Intro

    private var introCard: some View {
        SectionCard(title: "Données partagées par l'enfant", systemImage: "heart.text.square", accent: .afsrPurpleAdaptive) {
            VStack(alignment: .leading, spacing: 8) {
                Text("RettApp peut lire les données Apple Santé partagées par l'iPhone ou l'Apple Watch de votre enfant via le partage familial iCloud.")
                    .font(AFSRFont.body(13))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Pour activer le partage : sur l'iPhone de l'enfant, ouvrez Santé → Partage → Partager avec [vous]. Cochez Sommeil, Rythme cardiaque et Activité.")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var periodPicker: some View {
        Picker("Période", selection: $period) {
            ForEach(HealthPeriod.allCases) { p in
                Text(p.label).tag(p)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Permission states

    private var unavailableCard: some View {
        SectionCard(title: "Indisponible", systemImage: "xmark.octagon.fill", accent: .afsrEmergency) {
            Text("Apple Santé n'est pas disponible sur cet appareil (iPad standard, simulateur sans HealthKit, etc.).")
                .font(AFSRFont.body(13))
                .foregroundStyle(.secondary)
        }
    }

    private var permissionPromptCard: some View {
        SectionCard(title: "Autoriser la lecture", systemImage: "lock.shield", accent: .afsrPurpleAdaptive) {
            VStack(alignment: .leading, spacing: 12) {
                Text("RettApp a besoin de votre permission pour lire les données Santé. Apple affichera une feuille listant chaque type — vous pouvez en autoriser une partie ou la totalité.")
                    .font(AFSRFont.body(13))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await requestPermissionAndLoad() }
                } label: {
                    Label("Demander l'accès", systemImage: "checkmark.shield")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.afsrPurpleAdaptive)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        SectionCard(title: "Erreur", systemImage: "exclamationmark.triangle.fill", accent: .afsrEmergency) {
            Text(message).font(AFSRFont.body(13))
        }
    }

    private var noDataCard: some View {
        SectionCard(title: "Aucune donnée pour cette période", systemImage: "tray", accent: .secondary) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Aucune donnée Apple Santé n'est encore arrivée pour la période sélectionnée.")
                    .font(AFSRFont.body(13))
                Text("Vérifiez que le partage Santé iCloud Family est bien activé sur l'iPhone de l'enfant et que l'Apple Watch est portée régulièrement.")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Charts

    private var sleepChart: some View {
        SectionCard(title: "Sommeil", systemImage: "bed.double.fill", accent: .afsrPurpleAdaptive) {
            let nonNil = aggregates.filter { $0.sleepMinutes != nil }
            if nonNil.isEmpty {
                placeholderText("Pas de samples de sommeil sur la période.")
            } else {
                let avg = average(nonNil.compactMap { $0.sleepMinutes.map(Double.init) })
                Text("Moyenne : \(formatHours(avg)) par nuit")
                    .font(AFSRFont.caption()).foregroundStyle(.secondary)
                Chart {
                    ForEach(aggregates) { a in
                        if let m = a.sleepMinutes {
                            BarMark(
                                x: .value("Jour", a.day, unit: .day),
                                y: .value("Minutes", m)
                            )
                            .foregroundStyle(Color.afsrPurpleAdaptive.opacity(0.85))
                            .cornerRadius(3)
                        }
                    }
                }
                .frame(height: 160)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        if let v = value.as(Int.self) {
                            AxisValueLabel { Text(formatHours(Double(v))).font(.caption2) }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxis { xAxisMarks() }
            }
        }
    }

    private var heartRateChart: some View {
        SectionCard(title: "Rythme cardiaque", systemImage: "heart.fill", accent: .afsrEmergency) {
            let avgs = aggregates.compactMap { agg -> (Date, Double)? in
                if let v = agg.avgHeartRate { return (agg.day, v) }
                return nil
            }
            let restings = aggregates.compactMap { agg -> (Date, Double)? in
                if let v = agg.restingHeartRate { return (agg.day, v) }
                return nil
            }
            if avgs.isEmpty && restings.isEmpty {
                placeholderText("Pas de samples de rythme cardiaque sur la période.")
            } else {
                if let last = avgs.last {
                    Text("Dernière moyenne : \(Int(last.1.rounded())) bpm")
                        .font(AFSRFont.caption()).foregroundStyle(.secondary)
                }
                Chart {
                    ForEach(avgs, id: \.0) { item in
                        LineMark(
                            x: .value("Jour", item.0, unit: .day),
                            y: .value("Moyen", item.1)
                        )
                        .foregroundStyle(Color.afsrEmergency)
                        .interpolationMethod(.monotone)
                        PointMark(
                            x: .value("Jour", item.0, unit: .day),
                            y: .value("Moyen", item.1)
                        )
                        .foregroundStyle(Color.afsrEmergency)
                        .symbolSize(30)
                    }
                    ForEach(restings, id: \.0) { item in
                        LineMark(
                            x: .value("Jour", item.0, unit: .day),
                            y: .value("Repos", item.1)
                        )
                        .foregroundStyle(.gray)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .interpolationMethod(.monotone)
                    }
                }
                .frame(height: 160)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        if let v = value.as(Int.self) {
                            AxisValueLabel { Text("\(v) bpm").font(.caption2) }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxis { xAxisMarks() }
                Text("Trait plein : moyenne. Pointillés : rythme au repos.")
                    .font(AFSRFont.caption()).foregroundStyle(.secondary)
            }
        }
    }

    private var activityChart: some View {
        SectionCard(title: "Activité", systemImage: "figure.walk", accent: .afsrSuccess) {
            let nonNil = aggregates.filter { $0.steps != nil }
            if nonNil.isEmpty {
                placeholderText("Pas de samples d'activité sur la période.")
            } else {
                let totalSteps = nonNil.compactMap(\.steps).reduce(0, +)
                let totalEnergy = aggregates.compactMap(\.activeEnergyKcal).reduce(0, +)
                Text("\(Int(totalSteps)) pas cumulés · \(Int(totalEnergy)) kcal actives")
                    .font(AFSRFont.caption()).foregroundStyle(.secondary)
                Chart {
                    ForEach(aggregates) { a in
                        if let s = a.steps {
                            BarMark(
                                x: .value("Jour", a.day, unit: .day),
                                y: .value("Pas", s)
                            )
                            .foregroundStyle(Color.afsrSuccess.opacity(0.85))
                            .cornerRadius(3)
                        }
                    }
                }
                .frame(height: 140)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                }
                .chartXAxis { xAxisMarks() }
            }
        }
    }

    @AxisContentBuilder
    private func xAxisMarks() -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 5)) { value in
            if let d = value.as(Date.self) {
                AxisValueLabel { Text(d, format: .dateTime.day().month(.abbreviated)) }
            }
            AxisTick()
        }
    }

    private func placeholderText(_ s: String) -> some View {
        Text(s).font(AFSRFont.caption()).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    // MARK: - Loading

    private func requestPermissionAndLoad() async {
        do {
            _ = try await HealthKitManager.shared.requestAuthorizationIfNeeded()
            hasRequestedPermission = true
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        errorMessage = nil
        let cal = Calendar.current
        let end = Date()
        guard let start = cal.date(byAdding: .day, value: -(period.days - 1), to: cal.startOfDay(for: end)) else { return }
        do {
            aggregates = try await HealthKitManager.shared.dailyAggregates(start: start, end: end)
        } catch {
            errorMessage = error.localizedDescription
            aggregates = []
        }
    }

    // MARK: - Helpers

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func formatHours(_ minutes: Double) -> String {
        if minutes < 60 { return String(format: "%.0f min", minutes) }
        let h = minutes / 60.0
        return String(format: "%.1f h", h)
    }
}

#Preview {
    NavigationStack { HealthDataView() }
}
