import Foundation

/// Heure/minute indépendante de la date (pour les plans de médication récurrents).
struct HourMinute: Codable, Hashable, Identifiable {
    var id: String { "\(hour):\(minute)" }
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }

    init(date: Date) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        self.hour = comps.hour ?? 0
        self.minute = comps.minute ?? 0
    }

    var asDate: Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }

    /// Date absolue correspondant à cette heure/minute le jour donné.
    func date(on day: Date, calendar: Calendar = .current) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps) ?? day
    }

    var formatted: String {
        String(format: "%02d:%02d", hour, minute)
    }

    enum DayPeriod: String, CaseIterable { case morning, noon, evening, other
        var label: String {
            switch self {
            case .morning: return "Matin"
            case .noon: return "Midi"
            case .evening: return "Soir"
            case .other: return "Autres"
            }
        }
    }

    var period: DayPeriod {
        switch hour {
        case 5..<11: return .morning
        case 11..<15: return .noon
        case 17..<22: return .evening
        default: return .other
        }
    }
}
