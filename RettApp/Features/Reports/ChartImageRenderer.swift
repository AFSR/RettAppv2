import SwiftUI
import Charts
import UIKit

/// Rend des graphiques SwiftUI Charts en `UIImage` pour insertion dans un PDF.
/// Utilise `ImageRenderer` (iOS 16+).
enum ChartImageRenderer {

    /// Graphique fréquence (BarMark) — nb crises par bucket.
    static func frequencyChart(
        buckets: [MedicalReportAnalysis.Bucket],
        granularity: MedicalReportAnalysis.Granularity,
        size: CGSize
    ) -> UIImage? {
        guard !buckets.isEmpty else { return nil }
        let view = FrequencyChartView(buckets: buckets, granularity: granularity)
            .frame(width: size.width, height: size.height)
            .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }

    /// Graphique intensité (LineMark + AreaMark) — durée totale par bucket.
    static func intensityChart(
        buckets: [MedicalReportAnalysis.Bucket],
        granularity: MedicalReportAnalysis.Granularity,
        size: CGSize
    ) -> UIImage? {
        guard !buckets.isEmpty else { return nil }
        let view = IntensityChartView(buckets: buckets, granularity: granularity)
            .frame(width: size.width, height: size.height)
            .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }

    /// Graphique horizontal des types de crises (proportions).
    static func typeBreakdownChart(
        items: [(type: SeizureType, count: Int, percentage: Double)],
        size: CGSize
    ) -> UIImage? {
        guard !items.isEmpty else { return nil }
        let view = TypeBreakdownChartView(items: items)
            .frame(width: size.width, height: size.height)
            .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }
}

// MARK: - Internal SwiftUI views

private struct FrequencyChartView: View {
    let buckets: [MedicalReportAnalysis.Bucket]
    let granularity: MedicalReportAnalysis.Granularity

    var body: some View {
        Chart(buckets, id: \.start) { b in
            BarMark(
                x: .value("Date", b.start, unit: granularity.calendarComponent),
                y: .value("Crises", b.count)
            )
            .foregroundStyle(Color(red: 0.42, green: 0.25, blue: 0.63)) // afsrPurple
            .cornerRadius(2)
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                AxisValueLabel().foregroundStyle(.gray)
                AxisGridLine().foregroundStyle(.gray.opacity(0.3))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                if let d = value.as(Date.self) {
                    AxisValueLabel { Text(d, format: dateFormat).font(.caption2) }
                }
                AxisTick().foregroundStyle(.gray)
            }
        }
        .padding(8)
    }

    private var dateFormat: Date.FormatStyle {
        switch granularity {
        case .daily:   return .dateTime.day().month(.abbreviated)
        case .weekly:  return .dateTime.day().month(.abbreviated)
        case .monthly: return .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }
}

private struct IntensityChartView: View {
    let buckets: [MedicalReportAnalysis.Bucket]
    let granularity: MedicalReportAnalysis.Granularity

    var body: some View {
        Chart(buckets, id: \.start) { b in
            AreaMark(
                x: .value("Date", b.start, unit: granularity.calendarComponent),
                y: .value("Secondes", b.totalDurationSec)
            )
            .foregroundStyle(LinearGradient(
                colors: [Color(red: 0.90, green: 0.22, blue: 0.21).opacity(0.4),
                         Color(red: 0.90, green: 0.22, blue: 0.21).opacity(0.05)],
                startPoint: .top, endPoint: .bottom
            ))
            .interpolationMethod(.monotone)
            LineMark(
                x: .value("Date", b.start, unit: granularity.calendarComponent),
                y: .value("Secondes", b.totalDurationSec)
            )
            .foregroundStyle(Color(red: 0.90, green: 0.22, blue: 0.21))
            .interpolationMethod(.monotone)
            PointMark(
                x: .value("Date", b.start, unit: granularity.calendarComponent),
                y: .value("Secondes", b.totalDurationSec)
            )
            .foregroundStyle(Color(red: 0.90, green: 0.22, blue: 0.21))
            .symbolSize(30)
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                if let v = value.as(Int.self) {
                    AxisValueLabel { Text(formatDur(v)).font(.caption2) }
                }
                AxisGridLine().foregroundStyle(.gray.opacity(0.3))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                if let d = value.as(Date.self) {
                    AxisValueLabel { Text(d, format: dateFormat).font(.caption2) }
                }
                AxisTick().foregroundStyle(.gray)
            }
        }
        .padding(8)
    }

    private var dateFormat: Date.FormatStyle {
        switch granularity {
        case .daily:   return .dateTime.day().month(.abbreviated)
        case .weekly:  return .dateTime.day().month(.abbreviated)
        case .monthly: return .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }

    private func formatDur(_ seconds: Int) -> String {
        if seconds == 0 { return "0" }
        let m = seconds / 60
        if m > 0 { return "\(m)m" }
        return "\(seconds)s"
    }
}

private struct TypeBreakdownChartView: View {
    let items: [(type: SeizureType, count: Int, percentage: Double)]

    var body: some View {
        Chart {
            ForEach(items, id: \.type.rawValue) { item in
                BarMark(
                    x: .value("Pourcentage", item.percentage),
                    y: .value("Type", item.type.label)
                )
                .foregroundStyle(Color(hex: item.type.color))
                .annotation(position: .trailing) {
                    Text("\(item.count) (\(Int(item.percentage.rounded())) %)")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                if let v = value.as(Double.self) {
                    AxisValueLabel { Text("\(Int(v)) %").font(.caption2) }
                }
                AxisGridLine().foregroundStyle(.gray.opacity(0.3))
            }
        }
        .chartXScale(domain: 0...100)
        .padding(8)
    }
}
