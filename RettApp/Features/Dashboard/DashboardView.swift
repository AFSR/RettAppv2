import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query(sort: \SeizureEvent.startTime, order: .reverse) private var seizures: [SeizureEvent]
    @Query private var profiles: [ChildProfile]

    @State private var viewModel = DashboardViewModel()

    private var profile: ChildProfile? { profiles.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                scalePicker

                navHeader

                summaryCards

                frequencyChart

                intensityChart

                Spacer(minLength: 24)
            }
            .padding(.horizontal)
        }
        .background(Color.afsrBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }

    private var title: String {
        if let n = profile?.firstName, !n.isEmpty {
            return "Tableau de bord — \(n)"
        }
        return "Tableau de bord"
    }

    // MARK: - Picker d'échelle

    private var scalePicker: some View {
        Picker("Échelle", selection: $viewModel.scale) {
            ForEach(DashboardScale.allCases) { s in
                Text(s.label).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 8)
    }

    // MARK: - Navigation période

    private var navHeader: some View {
        HStack {
            Button { viewModel.shift(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.bordered)
            .tint(.afsrPurpleAdaptive)

            Spacer()

            Text(viewModel.windowLabel())
                .font(AFSRFont.headline(16))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            Button { viewModel.shift(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.bordered)
            .tint(.afsrPurpleAdaptive)
        }
    }

    // MARK: - Cartes synthèse

    private var summaryCards: some View {
        let s = viewModel.summary(for: seizures)
        return HStack(spacing: 12) {
            SummaryCard(
                title: "Crises",
                value: "\(s.totalCount)",
                subtitle: s.totalCount <= 1 ? "événement" : "événements",
                color: .afsrPurpleAdaptive,
                systemImage: "waveform.path.ecg"
            )
            SummaryCard(
                title: "Durée totale",
                value: formatDuration(s.totalDurationSec),
                subtitle: "cumulée",
                color: .afsrEmergency,
                systemImage: "clock.fill"
            )
            SummaryCard(
                title: "Moyenne",
                value: s.totalCount > 0 ? formatDuration(Int(s.avgDurationSec)) : "—",
                subtitle: "par crise",
                color: .afsrSuccess,
                systemImage: "chart.bar.fill"
            )
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds == 0 { return "0 s" }
        let m = seconds / 60
        let s = seconds % 60
        if m == 0 { return "\(s) s" }
        if s == 0 { return "\(m) min" }
        return "\(m) min \(s) s"
    }

    // MARK: - Graphique fréquence

    private var frequencyChart: some View {
        let buckets = viewModel.buckets(for: seizures)
        return SectionCard(title: "Fréquence", systemImage: "chart.bar.xaxis", accent: .afsrPurpleAdaptive) {
            if buckets.allSatisfy({ $0.count == 0 }) {
                emptyChartPlaceholder
            } else {
                Chart(buckets) { b in
                    BarMark(
                        x: .value("Date", b.date, unit: viewModel.scale.calendarComponent),
                        y: .value("Crises", b.count)
                    )
                    .foregroundStyle(Color.afsrPurpleAdaptive)
                    .cornerRadius(4)
                }
                .frame(height: 180)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                        AxisValueLabel()
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
            }
        }
    }

    // MARK: - Graphique intensité (durée totale)

    private var intensityChart: some View {
        let buckets = viewModel.buckets(for: seizures)
        return SectionCard(title: "Intensité — durée totale", systemImage: "waveform.path", accent: .afsrEmergency) {
            if buckets.allSatisfy({ $0.totalDurationSec == 0 }) {
                emptyChartPlaceholder
            } else {
                Chart(buckets) { b in
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
                    PointMark(
                        x: .value("Date", b.date, unit: viewModel.scale.calendarComponent),
                        y: .value("Secondes", b.totalDurationSec)
                    )
                    .foregroundStyle(Color.afsrEmergency)
                    .symbolSize(40)
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
            }
        }
    }

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.flattrend.xyaxis")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("Aucune crise sur cette période")
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Carte synthèse

private struct SummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(AFSRFont.caption())
            }
            .foregroundStyle(color)
            Text(value)
                .font(AFSRFont.title(22))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: AFSRTokens.cornerRadiusSmall))
    }
}

#Preview {
    NavigationStack { DashboardView() }
        .modelContainer(PreviewData.container)
}
