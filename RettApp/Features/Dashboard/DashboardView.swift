import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query(sort: \SeizureEvent.startTime, order: .reverse) private var seizures: [SeizureEvent]
    @Query private var profiles: [ChildProfile]
    @Query private var moods: [MoodEntry]
    @Query private var observations: [DailyObservation]
    @Query private var logs: [MedicationLog]
    @Query(sort: \SymptomEvent.timestamp, order: .reverse) private var symptoms: [SymptomEvent]

    @State private var viewModel = DashboardViewModel()
    /// Date sélectionnée pour le curseur synchronisé.
    @State private var crosshairDate: Date?
    /// Symptômes que l'utilisateur a sélectionnés pour affichage. `nil` = pas encore choisi
    /// → on initialise avec les plus fréquents au premier render.
    @State private var selectedSymptoms: Set<RettSymptom>?
    @State private var showSymptomPicker = false
    /// Mode d'affichage des graphiques de symptômes : fréquence ou intensité moyenne.
    @State private var symptomChartMode: SymptomChartMode = .frequency

    private var profile: ChildProfile? { profiles.first }

    private var effectiveSelectedSymptoms: Set<RettSymptom> {
        if let s = selectedSymptoms { return s }
        // Sélection par défaut : top 3 symptômes de la période courante.
        let breakdown = viewModel.symptomBreakdown(for: symptoms)
        return Set(breakdown.prefix(3).map(\.type))
    }

    enum SymptomChartMode: String, CaseIterable, Identifiable {
        case frequency, intensity
        var id: String { rawValue }
        var label: String {
            switch self {
            case .frequency: return "Fréquence"
            case .intensity: return "Intensité"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                scalePicker
                navHeader
                summaryCards
                if crosshairDate != nil { crosshairLegend }

                frequencyChart
                intensityChart
                moodChart
                adherenceChart
                symptomsSection

                Spacer(minLength: 24)
            }
            .padding(.horizontal)
        }
        .background(Color.afsrBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: viewModel.scale) { _, _ in crosshairDate = nil }
        .onChange(of: viewModel.referenceDate) { _, _ in crosshairDate = nil }
    }

    private var title: String {
        if let n = profile?.firstName, !n.isEmpty {
            return "Bilan — \(n)"
        }
        return "Bilan"
    }

    // MARK: - Picker / nav

    private var scalePicker: some View {
        Picker("Échelle", selection: $viewModel.scale) {
            ForEach(DashboardScale.allCases) { s in
                Text(s.label).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 8)
    }

    private var navHeader: some View {
        HStack {
            Button { viewModel.shift(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.bordered).tint(.afsrPurpleAdaptive)
            Spacer()
            Text(viewModel.windowLabel())
                .font(AFSRFont.headline(16))
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer()
            Button { viewModel.shift(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.bordered).tint(.afsrPurpleAdaptive)
        }
    }

    // MARK: - Synthèse

    private var summaryCards: some View {
        let s = viewModel.summary(for: seizures)
        let prev = viewModel.previousSummary(for: seizures)
        let countTrend = DashboardViewModel.trend(current: Double(s.totalCount), previous: Double(prev.totalCount))
        let durationTrend = DashboardViewModel.trend(current: Double(s.totalDurationSec), previous: Double(prev.totalDurationSec))
        let avgTrend = DashboardViewModel.trend(current: s.avgDurationSec, previous: prev.avgDurationSec)
        // Pour les crises : "up" est négatif (mauvais), "down" est positif (bon).
        return HStack(spacing: 12) {
            SummaryCard(title: "Crises", value: "\(s.totalCount)",
                        subtitle: s.totalCount <= 1 ? "événement" : "événements",
                        color: .afsrPurpleAdaptive, systemImage: "waveform.path.ecg",
                        trend: countTrend, increaseIsGood: false)
            SummaryCard(title: "Durée totale", value: formatDuration(s.totalDurationSec),
                        subtitle: "cumulée", color: .afsrEmergency, systemImage: "clock.fill",
                        trend: durationTrend, increaseIsGood: false)
            SummaryCard(title: "Moyenne",
                        value: s.totalCount > 0 ? formatDuration(Int(s.avgDurationSec)) : "—",
                        subtitle: "par crise", color: .afsrSuccess, systemImage: "chart.bar.fill",
                        trend: s.totalCount > 0 && prev.totalCount > 0 ? avgTrend : nil,
                        increaseIsGood: false)
        }
    }

    private var crosshairLegend: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope").foregroundStyle(.afsrPurpleAdaptive)
            if let d = crosshairDate {
                (
                    Text("Curseur synchronisé : ").font(AFSRFont.caption()) +
                    Text(d, format: .dateTime.day().month().year())
                        .font(AFSRFont.caption()).bold()
                )
            }
            Spacer()
            Button("Effacer") { crosshairDate = nil }
                .font(AFSRFont.caption())
                .foregroundStyle(.afsrPurpleAdaptive)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.afsrPurpleAdaptive.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Charts

    private var frequencyChart: some View {
        let buckets = viewModel.buckets(for: seizures)
        return SectionCard(title: "Fréquence des crises", systemImage: "chart.bar.xaxis", accent: .afsrPurpleAdaptive) {
            if buckets.allSatisfy({ $0.count == 0 }) {
                emptyChartPlaceholder
            } else {
                Chart {
                    ForEach(buckets) { b in
                        BarMark(
                            x: .value("Date", b.date, unit: viewModel.scale.calendarComponent),
                            y: .value("Crises", b.count)
                        )
                        .foregroundStyle(Color.afsrPurpleAdaptive)
                        .cornerRadius(4)
                    }
                    if let d = crosshairDate {
                        RuleMark(x: .value("Sélection", d, unit: viewModel.scale.calendarComponent))
                            .foregroundStyle(.gray.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .frame(height: 180)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        if let d = value.as(Date.self) {
                            AxisValueLabel { Text(d, format: viewModel.scale.bucketDateFormat) }
                        }
                        AxisTick()
                    }
                }
                .chartOverlay(content: crosshairCapture)
            }
        }
    }

    private var intensityChart: some View {
        let buckets = viewModel.buckets(for: seizures)
        return SectionCard(title: "Intensité (durée totale)", systemImage: "waveform.path", accent: .afsrEmergency) {
            if buckets.allSatisfy({ $0.totalDurationSec == 0 }) {
                emptyChartPlaceholder
            } else {
                Chart {
                    ForEach(buckets) { b in
                        LineMark(
                            x: .value("Date", b.date, unit: viewModel.scale.calendarComponent),
                            y: .value("Secondes", b.totalDurationSec)
                        )
                        .foregroundStyle(Color.afsrEmergency)
                        .interpolationMethod(.monotone)
                        AreaMark(
                            x: .value("Date", b.date, unit: viewModel.scale.calendarComponent),
                            y: .value("Secondes", b.totalDurationSec)
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [Color.afsrEmergency.opacity(0.35), Color.afsrEmergency.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .interpolationMethod(.monotone)
                    }
                    if let d = crosshairDate {
                        RuleMark(x: .value("Sélection", d, unit: viewModel.scale.calendarComponent))
                            .foregroundStyle(.gray.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .frame(height: 180)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        if let v = value.as(Int.self) {
                            AxisValueLabel { Text(formatDuration(v)).font(.caption2) }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        if let d = value.as(Date.self) {
                            AxisValueLabel { Text(d, format: viewModel.scale.bucketDateFormat) }
                        }
                        AxisTick()
                    }
                }
                .chartOverlay(content: crosshairCapture)
            }
        }
    }

    private var moodChart: some View {
        let buckets = viewModel.moodBuckets(for: moods)
        let nonNil = buckets.filter { $0.value != nil }
        return SectionCard(title: "Humeur moyenne", systemImage: "face.smiling", accent: .afsrSuccess) {
            if nonNil.isEmpty {
                emptyChartPlaceholder
            } else {
                Chart {
                    ForEach(buckets) { b in
                        if let v = b.value {
                            LineMark(
                                x: .value("Date", b.date, unit: viewModel.scale.calendarComponent),
                                y: .value("Humeur", v)
                            )
                            .foregroundStyle(Color.afsrSuccess)
                            .interpolationMethod(.monotone)
                            PointMark(
                                x: .value("Date", b.date, unit: viewModel.scale.calendarComponent),
                                y: .value("Humeur", v)
                            )
                            .foregroundStyle(Color.afsrSuccess)
                            .symbolSize(60)
                        }
                    }
                    if let d = crosshairDate {
                        RuleMark(x: .value("Sélection", d, unit: viewModel.scale.calendarComponent))
                            .foregroundStyle(.gray.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .frame(height: 160)
                .chartYScale(domain: 1...5)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [1, 2, 3, 4, 5]) { value in
                        if let v = value.as(Int.self), let m = MoodLevel(rawValue: v) {
                            AxisValueLabel { Text(m.emoji).font(.caption2) }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        if let d = value.as(Date.self) {
                            AxisValueLabel { Text(d, format: viewModel.scale.bucketDateFormat) }
                        }
                        AxisTick()
                    }
                }
                .chartOverlay(content: crosshairCapture)
            }
        }
    }

    private var adherenceChart: some View {
        let buckets = viewModel.adherenceBuckets(for: logs)
        let nonNil = buckets.filter { $0.value != nil }
        return SectionCard(title: "Observance médicamenteuse", systemImage: "pill.fill", accent: .afsrPurpleAdaptive) {
            if nonNil.isEmpty {
                emptyChartPlaceholder
            } else {
                Chart {
                    ForEach(buckets) { b in
                        if let v = b.value {
                            BarMark(
                                x: .value("Date", b.date, unit: viewModel.scale.calendarComponent),
                                y: .value("%", v)
                            )
                            .foregroundStyle(barColor(for: v))
                            .cornerRadius(3)
                        }
                    }
                    if let d = crosshairDate {
                        RuleMark(x: .value("Sélection", d, unit: viewModel.scale.calendarComponent))
                            .foregroundStyle(.gray.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .frame(height: 160)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        if let v = value.as(Int.self) {
                            AxisValueLabel { Text("\(v) %").font(.caption2) }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        if let d = value.as(Date.self) {
                            AxisValueLabel { Text(d, format: viewModel.scale.bucketDateFormat) }
                        }
                        AxisTick()
                    }
                }
                .chartOverlay(content: crosshairCapture)
            }
        }
    }

    // MARK: - Symptoms section

    private var symptomsSection: some View {
        let breakdown = viewModel.symptomBreakdown(for: symptoms)
        let totalInPeriod = breakdown.reduce(0) { $0 + $1.count }
        let displayed = effectiveSelectedSymptoms

        return SectionCard(
            title: "Symptômes Rett",
            systemImage: "stethoscope",
            accent: .afsrPurpleAdaptive
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(totalInPeriod) observation\(totalInPeriod > 1 ? "s" : "") sur la période")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showSymptomPicker = true
                    } label: {
                        Label("Choisir", systemImage: "slider.horizontal.3")
                            .font(AFSRFont.caption())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.afsrPurpleAdaptive)
                }

                if totalInPeriod == 0 {
                    emptyChartPlaceholder
                } else {
                    Picker("Mode", selection: $symptomChartMode) {
                        ForEach(SymptomChartMode.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    if displayed.isEmpty {
                        Text("Aucun symptôme sélectionné — touchez « Choisir » pour activer un graphique.")
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(Array(displayed).sorted(by: { $0.label < $1.label })) { s in
                            symptomMiniChart(for: s)
                        }
                    }

                    if breakdown.count > 1 {
                        Divider().padding(.vertical, 4)
                        symptomBreakdownRows(breakdown: breakdown, total: totalInPeriod)
                    }
                }
            }
        }
        .sheet(isPresented: $showSymptomPicker) {
            SymptomPickerSheet(
                allSymptoms: breakdown,
                selection: Binding(
                    get: { effectiveSelectedSymptoms },
                    set: { selectedSymptoms = $0 }
                )
            )
        }
    }

    private func symptomMiniChart(for type: RettSymptom) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: type.icon).foregroundStyle(.afsrPurpleAdaptive)
                Text(type.label).font(AFSRFont.caption()).bold()
            }
            switch symptomChartMode {
            case .frequency:
                let buckets = viewModel.symptomBuckets(for: symptoms, type: type)
                Chart {
                    ForEach(buckets) { b in
                        BarMark(
                            x: .value("Date", b.date, unit: viewModel.scale.calendarComponent),
                            y: .value("Occurrences", b.count)
                        )
                        .foregroundStyle(Color.afsrPurpleAdaptive.opacity(0.85))
                        .cornerRadius(3)
                    }
                    if let d = crosshairDate {
                        RuleMark(x: .value("Sélection", d, unit: viewModel.scale.calendarComponent))
                            .foregroundStyle(.gray.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .frame(height: 110)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        if let d = value.as(Date.self) {
                            AxisValueLabel { Text(d, format: viewModel.scale.bucketDateFormat) }
                        }
                        AxisTick()
                    }
                }
                .chartOverlay(content: crosshairCapture)
            case .intensity:
                let buckets = viewModel.symptomIntensityBuckets(for: symptoms, type: type)
                let nonNil = buckets.filter { $0.value != nil }
                if nonNil.isEmpty {
                    Text("Intensité non renseignée pour ce symptôme.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    Chart {
                        ForEach(buckets) { b in
                            if let v = b.value {
                                LineMark(
                                    x: .value("Date", b.date, unit: viewModel.scale.calendarComponent),
                                    y: .value("Intensité", v)
                                )
                                .foregroundStyle(Color.afsrEmergency)
                                .interpolationMethod(.monotone)
                                PointMark(
                                    x: .value("Date", b.date, unit: viewModel.scale.calendarComponent),
                                    y: .value("Intensité", v)
                                )
                                .foregroundStyle(Color.afsrEmergency)
                                .symbolSize(40)
                            }
                        }
                        if let d = crosshairDate {
                            RuleMark(x: .value("Sélection", d, unit: viewModel.scale.calendarComponent))
                                .foregroundStyle(.gray.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                    }
                    .frame(height: 110)
                    .chartYScale(domain: 1...5)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [1, 3, 5])
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { value in
                            if let d = value.as(Date.self) {
                                AxisValueLabel { Text(d, format: viewModel.scale.bucketDateFormat) }
                            }
                            AxisTick()
                        }
                    }
                    .chartOverlay(content: crosshairCapture)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func symptomBreakdownRows(breakdown: [(type: RettSymptom, count: Int)], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Répartition (période)")
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
            ForEach(breakdown.prefix(6), id: \.type) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.type.icon)
                        .foregroundStyle(.afsrPurpleAdaptive)
                        .font(.system(size: 12))
                        .frame(width: 18)
                    Text(item.type.label).font(AFSRFont.caption())
                    Spacer()
                    Text("\(item.count)")
                        .font(AFSRFont.caption())
                        .monospacedDigit()
                    Text("(\(Int((Double(item.count) / Double(max(total, 1)) * 100).rounded())) %)")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func barColor(for percentage: Double) -> Color {
        switch percentage {
        case ..<50:  return .afsrEmergency
        case ..<80:  return .afsrWarning
        default:     return .afsrSuccess
        }
    }

    // MARK: - Crosshair capture

    /// Overlay transparent : capture le tap n'importe où dans le chart, projette
    /// la position X en Date, met à jour le binding partagé.
    @ViewBuilder
    private func crosshairCapture(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(coordinateSpace: .local)
                        .onEnded { event in
                            updateCrosshair(at: event.location, proxy: proxy, geo: geo)
                        }
                )
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            updateCrosshair(at: value.location, proxy: proxy, geo: geo)
                        }
                )
        }
    }

    private func updateCrosshair(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        let plotFrame = geo[proxy.plotAreaFrame]
        let xInPlot = location.x - plotFrame.origin.x
        if let date: Date = proxy.value(atX: xInPlot) {
            crosshairDate = date
        }
    }

    // MARK: - Helpers

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.flattrend.xyaxis")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("Aucune donnée pour cette période")
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
        }
        .frame(height: 140).frame(maxWidth: .infinity)
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds == 0 { return "0 s" }
        let m = seconds / 60
        let s = seconds % 60
        if m == 0 { return "\(s) s" }
        if s == 0 { return "\(m) min" }
        return "\(m) min \(s) s"
    }
}

// MARK: - Carte synthèse

private struct SummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let systemImage: String
    var trend: DashboardViewModel.TrendDelta? = nil
    /// Sémantique d'évolution : pour les crises, l'augmentation est mauvaise (rouge).
    /// Pour l'humeur ou l'observance, l'augmentation est bonne (vert).
    var increaseIsGood: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title).font(AFSRFont.caption())
            }
            .foregroundStyle(color)
            Text(value).font(AFSRFont.title(22)).lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                Text(subtitle).font(AFSRFont.caption()).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let t = trend {
                    trendBadge(t)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: AFSRTokens.cornerRadiusSmall))
    }

    @ViewBuilder
    private func trendBadge(_ t: DashboardViewModel.TrendDelta) -> some View {
        if t.isFlat && !t.isNewlyAppeared {
            HStack(spacing: 2) {
                Image(systemName: "equal").font(.system(size: 9, weight: .bold))
                Text("=").font(AFSRFont.caption())
            }
            .foregroundStyle(.secondary)
        } else if t.isNewlyAppeared {
            Text("nouv.")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
        } else if let pct = t.percentChange {
            let badgeColor = trendColor(t)
            HStack(spacing: 2) {
                Image(systemName: t.isUp ? "arrow.up" : "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                Text(formatPercent(abs(pct)))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(badgeColor)
        }
    }

    private func trendColor(_ t: DashboardViewModel.TrendDelta) -> Color {
        if t.isFlat { return .secondary }
        let goingUp = t.isUp
        if goingUp == increaseIsGood {
            return .afsrSuccess
        } else {
            return .afsrEmergency
        }
    }

    private func formatPercent(_ p: Double) -> String {
        if p >= 100 { return String(format: "%.0f%%", p) }
        if p >= 10 { return String(format: "%.0f%%", p) }
        return String(format: "%.1f%%", p)
    }
}

// MARK: - Symptom picker sheet

private struct SymptomPickerSheet: View {
    let allSymptoms: [(type: RettSymptom, count: Int)]
    @Binding var selection: Set<RettSymptom>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if allSymptoms.isEmpty {
                        Text("Aucun symptôme observé sur la période.")
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(allSymptoms, id: \.type) { item in
                            Button {
                                toggle(item.type)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selection.contains(item.type) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(selection.contains(item.type) ? .afsrPurpleAdaptive : .secondary)
                                        .font(.system(size: 18))
                                    Image(systemName: item.type.icon)
                                        .foregroundStyle(.afsrPurpleAdaptive)
                                        .frame(width: 22)
                                    Text(item.type.label).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(item.count)")
                                        .font(AFSRFont.caption())
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Symptômes observés sur la période")
                } footer: {
                    Text("Cochez ceux à afficher en graphique. Les autres restent visibles dans la répartition globale.")
                }
            }
            .navigationTitle("Choix des symptômes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }.bold()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggle(_ s: RettSymptom) {
        if selection.contains(s) {
            selection.remove(s)
        } else {
            selection.insert(s)
        }
    }
}

#Preview {
    NavigationStack { DashboardView() }
        .modelContainer(PreviewData.container)
}
