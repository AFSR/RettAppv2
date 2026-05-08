import SwiftUI
import Charts
import HealthKit

/// Données Apple Santé.
///
/// **Deux modes** selon `DeviceRoleStore.shared.role` :
///
/// - **Mode parent** (défaut) : RettApp lit les données partagées par l'iPhone
///   ou l'Apple Watch de l'enfant via le partage familial iCloud (Health
///   Sharing). Aucun choix de type ici — Apple gère la liste des types
///   partagés au niveau OS sur l'iPhone de l'enfant.
///
/// - **Mode enfant** : RettApp est installée directement sur l'iPhone de
///   l'enfant. Le parent / aidant choisit explicitement quels types lire
///   (hydratation, repas, sommeil de nuit, sieste, rythme cardiaque,
///   activité). Les autres types ne sont pas requêtés.
struct HealthDataView: View {
    @State private var period: HealthPeriod = .week
    @State private var aggregates: [DailyHealthAggregate] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var hasRequestedPermission = false

    private let roleStore = DeviceRoleStore.shared

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
                healthKitBadge
                introCard
                if roleStore.role == .child {
                    childSelectionCard
                }
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
                } else if hasNoSelection {
                    noSelectionCard
                } else if aggregates.contains(where: { $0.hasAnyData }) {
                    chartsForCurrentSelection
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
        .onChange(of: roleStore.childHealthSelection) { _, _ in
            if hasRequestedPermission { Task { await reload() } }
        }
    }

    // MARK: - Selection helpers

    private var effectiveSelection: ChildHealthSelection {
        // En mode parent on tire tout — Apple filtre à la source ce qui est partagé.
        roleStore.role == .parent ? .defaults : roleStore.childHealthSelection
    }

    private var hasNoSelection: Bool {
        roleStore.role == .child && !roleStore.childHealthSelection.anySelected
    }

    @ViewBuilder
    private var chartsForCurrentSelection: some View {
        let sel = effectiveSelection
        if sel.nightSleep || sel.naps { sleepChart }
        if sel.heartRate { heartRateChart }
        if sel.activity { activityChart }
        if sel.hydration { hydrationChart }
        if sel.meals { mealsChart }
    }

    // MARK: - Intro

    /// Bandeau prominent indiquant clairement que cette fonctionnalité utilise
    /// l'API HealthKit d'Apple. Exigé par la Guideline 2.5.1 d'Apple : les
    /// fonctionnalités utilisant HealthKit doivent être identifiées de façon
    /// claire et transparente dans l'UI.
    private var healthKitBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.36, blue: 0.36),
                                 Color(red: 0.95, green: 0.21, blue: 0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("Utilise l'app Santé d'Apple")
                    .font(AFSRFont.headline(15))
                Text("via le framework HealthKit — données lues localement sur votre appareil")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                if let url = URL(string: "x-apple-health://") { UIApplication.shared.open(url) }
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .foregroundStyle(.afsrPurpleAdaptive)
            }
            .accessibilityLabel("Ouvrir l'app Santé")
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var introCard: some View {
        SectionCard(
            title: roleStore.role == .child
                ? "Cet iPhone est utilisé par l'enfant"
                : "Données partagées par l'enfant",
            systemImage: roleStore.role == .child ? "figure.child" : "heart.text.square",
            accent: .afsrPurpleAdaptive
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if roleStore.role == .child {
                    Text("RettApp peut lire les données Apple Santé de cet appareil et les transmettre aux parents qui ont accepté l'invitation de partage.")
                        .font(AFSRFont.body(13))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Cochez ci-dessous les types de données à inclure. Vous pouvez tout désactiver si vous préférez seulement la saisie manuelle dans le journal.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("RettApp lit les données Apple Santé partagées par l'iPhone ou l'Apple Watch de votre enfant via le partage familial iCloud.")
                        .font(AFSRFont.body(13))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pour activer le partage : sur l'iPhone de l'enfant, ouvrez Santé → Partage → Partager avec [vous]. Vous pouvez aussi installer RettApp directement sur l'iPhone de l'enfant et basculer son mode dans Réglages → Profil enfant.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Child selection card

    private var childSelectionCard: some View {
        @Bindable var store = DeviceRoleStore.shared
        return SectionCard(
            title: "Types de données à lire (mode enfant)",
            systemImage: "checkmark.square",
            accent: .afsrPurpleAdaptive
        ) {
            VStack(alignment: .leading, spacing: 4) {
                healthTypeToggle(
                    "Hydratation",
                    detail: "Quantité d'eau bue (Santé → Hydratation).",
                    icon: "drop.fill",
                    color: .blue,
                    isOn: $store.childHealthSelection.hydration
                )
                healthTypeToggle(
                    "Repas",
                    detail: "Calories alimentaires + nb de repas saisis dans Santé.",
                    icon: "fork.knife",
                    color: .orange,
                    isOn: $store.childHealthSelection.meals
                )
                healthTypeToggle(
                    "Sommeil de nuit",
                    detail: "Sessions de sommeil démarrées entre 19 h et 7 h.",
                    icon: "moon.stars.fill",
                    color: .indigo,
                    isOn: $store.childHealthSelection.nightSleep
                )
                healthTypeToggle(
                    "Sieste",
                    detail: "Sessions de sommeil démarrées entre 7 h et 19 h.",
                    icon: "bed.double.fill",
                    color: .purple,
                    isOn: $store.childHealthSelection.naps
                )
                healthTypeToggle(
                    "Rythme cardiaque",
                    detail: "Moyenne quotidienne et rythme au repos.",
                    icon: "heart.fill",
                    color: .afsrEmergency,
                    isOn: $store.childHealthSelection.heartRate
                )
                healthTypeToggle(
                    "Activité",
                    detail: "Pas et énergie active dépensée.",
                    icon: "figure.walk",
                    color: .afsrSuccess,
                    isOn: $store.childHealthSelection.activity
                )
            }
        }
    }

    private func healthTypeToggle(
        _ title: String, detail: String, icon: String, color: Color, isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AFSRFont.body(14))
                    Text(detail).font(AFSRFont.caption()).foregroundStyle(.secondary)
                }
            }
        }
        .tint(.afsrPurpleAdaptive)
        .padding(.vertical, 4)
    }

    private var periodPicker: some View {
        Picker("Période", selection: $period) {
            ForEach(HealthPeriod.allCases) { p in
                Text(p.label).tag(p)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Empty / permission states

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
                Text("Vérifiez que les types sélectionnés sont bien renseignés dans Santé (et que le partage iCloud est activé en mode parent).")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noSelectionCard: some View {
        SectionCard(title: "Rien à afficher", systemImage: "square.dashed", accent: .secondary) {
            Text("Cochez au moins un type de données dans la section ci-dessus pour afficher des graphiques.")
                .font(AFSRFont.body(13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Charts

    private var sleepChart: some View {
        SectionCard(title: "Sommeil", systemImage: "bed.double.fill", accent: .afsrPurpleAdaptive) {
            let sel = effectiveSelection
            let nightSeries = sel.nightSleep
                ? aggregates.compactMap { agg -> (Date, Int)? in
                    if let m = agg.sleepMinutes { return (agg.day, m) }
                    return nil
                  }
                : []
            let napSeries = sel.naps
                ? aggregates.compactMap { agg -> (Date, Int)? in
                    if let m = agg.napMinutes { return (agg.day, m) }
                    return nil
                  }
                : []
            if nightSeries.isEmpty && napSeries.isEmpty {
                placeholderText("Pas de samples de sommeil sur la période.")
            } else {
                if !nightSeries.isEmpty {
                    let avg = average(nightSeries.map { Double($0.1) })
                    Text("Nuit — moyenne : \(formatHours(avg))")
                        .font(AFSRFont.caption()).foregroundStyle(.secondary)
                }
                if !napSeries.isEmpty {
                    let avg = average(napSeries.map { Double($0.1) })
                    Text("Sieste — moyenne : \(formatHours(avg))")
                        .font(AFSRFont.caption()).foregroundStyle(.secondary)
                }
                Chart {
                    ForEach(nightSeries, id: \.0) { item in
                        BarMark(
                            x: .value("Jour", item.0, unit: .day),
                            y: .value("Minutes", item.1)
                        )
                        .foregroundStyle(by: .value("Type", "Nuit"))
                    }
                    ForEach(napSeries, id: \.0) { item in
                        BarMark(
                            x: .value("Jour", item.0, unit: .day),
                            y: .value("Minutes", item.1)
                        )
                        .foregroundStyle(by: .value("Type", "Sieste"))
                    }
                }
                .chartForegroundStyleScale([
                    "Nuit": Color.indigo,
                    "Sieste": Color.purple
                ])
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

    private var hydrationChart: some View {
        SectionCard(title: "Hydratation", systemImage: "drop.fill", accent: .blue) {
            let series = aggregates.compactMap { agg -> (Date, Double)? in
                if let v = agg.hydrationMl, v > 0 { return (agg.day, v) }
                return nil
            }
            if series.isEmpty {
                placeholderText("Aucune saisie d'hydratation dans Santé sur la période.")
            } else {
                let avg = average(series.map { $0.1 })
                Text("Moyenne : \(Int(avg)) ml / jour")
                    .font(AFSRFont.caption()).foregroundStyle(.secondary)
                Chart {
                    ForEach(series, id: \.0) { item in
                        BarMark(
                            x: .value("Jour", item.0, unit: .day),
                            y: .value("ml", item.1)
                        )
                        .foregroundStyle(.blue.opacity(0.85))
                        .cornerRadius(3)
                    }
                }
                .frame(height: 140)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        if let v = value.as(Int.self) {
                            AxisValueLabel { Text("\(v) ml").font(.caption2) }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxis { xAxisMarks() }
            }
        }
    }

    private var mealsChart: some View {
        SectionCard(title: "Repas", systemImage: "fork.knife", accent: .orange) {
            let kcal = aggregates.compactMap { agg -> (Date, Double)? in
                if let v = agg.mealKcal, v > 0 { return (agg.day, v) }
                return nil
            }
            let counts = aggregates.compactMap { agg -> (Date, Int)? in
                if let c = agg.mealCount, c > 0 { return (agg.day, c) }
                return nil
            }
            if kcal.isEmpty && counts.isEmpty {
                placeholderText("Aucun repas saisi dans Santé sur la période.")
            } else {
                if !kcal.isEmpty {
                    let avg = average(kcal.map { $0.1 })
                    Text("Moyenne énergétique : \(Int(avg)) kcal / jour")
                        .font(AFSRFont.caption()).foregroundStyle(.secondary)
                }
                if !counts.isEmpty {
                    let avgCount = average(counts.map { Double($0.1) })
                    Text(String(format: "Moyenne : %.1f repas / jour", avgCount))
                        .font(AFSRFont.caption()).foregroundStyle(.secondary)
                }
                Chart {
                    ForEach(kcal, id: \.0) { item in
                        BarMark(
                            x: .value("Jour", item.0, unit: .day),
                            y: .value("kcal", item.1)
                        )
                        .foregroundStyle(.orange.opacity(0.85))
                        .cornerRadius(3)
                    }
                }
                .frame(height: 140)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        if let v = value.as(Int.self) {
                            AxisValueLabel { Text("\(v) kcal").font(.caption2) }
                        }
                        AxisGridLine()
                    }
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
            aggregates = try await HealthKitManager.shared.dailyAggregates(
                start: start, end: end, selection: effectiveSelection
            )
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
