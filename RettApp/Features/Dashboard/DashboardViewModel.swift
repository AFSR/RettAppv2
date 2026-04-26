import Foundation
import Observation

/// Échelles temporelles pour le tableau de bord.
enum DashboardScale: String, CaseIterable, Identifiable {
    case day, week, month, year
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: return "Jour"
        case .week: return "Semaine"
        case .month: return "Mois"
        case .year: return "Année"
        }
    }
    /// Composant Calendar utilisé pour découper en buckets.
    var calendarComponent: Calendar.Component {
        switch self {
        case .day: return .hour
        case .week: return .day
        case .month: return .day
        case .year: return .month
        }
    }
    /// Période totale couverte par l'écran.
    var spanComponent: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
    /// Format compact pour l'axe X.
    var bucketDateFormat: Date.FormatStyle {
        switch self {
        case .day:   return .dateTime.hour()
        case .week:  return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day()
        case .year:  return .dateTime.month(.abbreviated)
        }
    }
}

/// Un bucket d'agrégation pour le graphique.
struct SeizureBucket: Identifiable {
    let id = UUID()
    let date: Date          // début du bucket
    let count: Int          // nombre de crises
    let totalDurationSec: Int  // durée totale en secondes (intensité)
    var avgDurationSec: Double {
        count > 0 ? Double(totalDurationSec) / Double(count) : 0
    }
}

@Observable
final class DashboardViewModel {
    var scale: DashboardScale = .week
    /// Date de référence (par défaut : maintenant). L'utilisateur peut naviguer dans le passé.
    var referenceDate: Date = Date()

    /// Bornes [start, end[ de la fenêtre actuellement visible selon `scale` + `referenceDate`.
    func windowBounds(calendar: Calendar = .current) -> (start: Date, end: Date) {
        let cal = calendar
        switch scale {
        case .day:
            let start = cal.startOfDay(for: referenceDate)
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
            return (start, end)
        case .week:
            let interval = cal.dateInterval(of: .weekOfYear, for: referenceDate)!
            return (interval.start, interval.end)
        case .month:
            let interval = cal.dateInterval(of: .month, for: referenceDate)!
            return (interval.start, interval.end)
        case .year:
            let interval = cal.dateInterval(of: .year, for: referenceDate)!
            return (interval.start, interval.end)
        }
    }

    /// Construit la liste des buckets à partir des crises données et de la fenêtre courante.
    func buckets(for seizures: [SeizureEvent], calendar: Calendar = .current) -> [SeizureBucket] {
        let cal = calendar
        let (windowStart, windowEnd) = windowBounds(calendar: cal)
        let bucketComp = scale.calendarComponent

        // Pré-construire tous les buckets de la fenêtre, même vides.
        var bucketStarts: [Date] = []
        var cursor = windowStart
        while cursor < windowEnd {
            bucketStarts.append(cursor)
            cursor = cal.date(byAdding: bucketComp, value: 1, to: cursor) ?? windowEnd
        }

        // Indexer les crises par bucket de début.
        var counts: [Date: Int] = [:]
        var durations: [Date: Int] = [:]
        for seizure in seizures where seizure.startTime >= windowStart && seizure.startTime < windowEnd {
            // Trouver le bucket de la crise (celui dont la date de début est <= seizure.startTime, max parmi ceux-là)
            guard let bucket = bucketStarts.last(where: { $0 <= seizure.startTime }) else { continue }
            counts[bucket, default: 0] += 1
            durations[bucket, default: 0] += seizure.durationSeconds
        }

        return bucketStarts.map { start in
            SeizureBucket(
                date: start,
                count: counts[start] ?? 0,
                totalDurationSec: durations[start] ?? 0
            )
        }
    }

    /// Statistiques globales sur la fenêtre courante.
    func summary(for seizures: [SeizureEvent], calendar: Calendar = .current) -> Summary {
        let bucketsList = buckets(for: seizures, calendar: calendar)
        let total = bucketsList.reduce(0) { $0 + $1.count }
        let totalSec = bucketsList.reduce(0) { $0 + $1.totalDurationSec }
        let avg = total > 0 ? Double(totalSec) / Double(total) : 0
        return Summary(totalCount: total, totalDurationSec: totalSec, avgDurationSec: avg)
    }

    struct Summary {
        let totalCount: Int
        let totalDurationSec: Int
        let avgDurationSec: Double
    }

    /// Décale `referenceDate` d'une unité d'échelle (négatif = passé).
    func shift(_ direction: Int, calendar: Calendar = .current) {
        let comp = scale.spanComponent
        if let d = calendar.date(byAdding: comp, value: direction, to: referenceDate) {
            referenceDate = d
        }
    }

    /// Libellé compact de la fenêtre courante (ex. "Avril 2026", "Sem. 17", "26 avr.").
    func windowLabel() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        let (start, end) = windowBounds()
        switch scale {
        case .day:
            f.dateFormat = "EEEE d MMMM"
            return f.string(from: start).capitalized
        case .week:
            let cal = Calendar.current
            let week = cal.component(.weekOfYear, from: start)
            f.dateFormat = "d MMM"
            let endLabel = f.string(from: cal.date(byAdding: .day, value: -1, to: end) ?? end)
            let startLabel = f.string(from: start)
            return "Sem. \(week) — \(startLabel) → \(endLabel)"
        case .month:
            f.dateFormat = "LLLL yyyy"
            return f.string(from: start).capitalized
        case .year:
            f.dateFormat = "yyyy"
            return f.string(from: start)
        }
    }
}
