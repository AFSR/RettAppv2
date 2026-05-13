import Foundation

/// Une prise planifiée d'un médicament : heure, dose, jours de la semaine et
/// préférence de notification individuelle.
///
/// Permet de gérer des plans complexes : « 5 mg en semaine à 8h, 10 mg le
/// week-end à 10h », et de désactiver les rappels pour les jours où l'enfant
/// est pris en charge par un tiers (école, centre, autre parent).
struct MedicationIntake: Codable, Hashable, Identifiable {
    var id: UUID
    var hour: Int
    var minute: Int
    /// Dose spécifique pour cette prise (peut différer des autres).
    var dose: Double
    /// Bitmask des jours actifs : bit `(weekday-1)` où `weekday` suit la
    /// convention `Calendar` (1 = dimanche, 2 = lundi, …, 7 = samedi).
    var weekdaysRaw: Int
    /// Active ou désactive le rappel pour cette prise précise.
    var notifyEnabled: Bool

    init(
        id: UUID = UUID(),
        hour: Int,
        minute: Int,
        dose: Double,
        weekdays: Set<Int> = MedicationIntake.allWeekdays,
        notifyEnabled: Bool = true
    ) {
        self.id = id
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
        self.dose = dose
        self.weekdaysRaw = Self.encode(weekdays)
        self.notifyEnabled = notifyEnabled
    }

    // MARK: - Weekdays helpers

    static var allWeekdays: Set<Int> { Set(1...7) }
    static var weekdaysOnly: Set<Int> { [2, 3, 4, 5, 6] }
    static var weekendOnly: Set<Int> { [1, 7] }

    static func encode(_ days: Set<Int>) -> Int {
        days.reduce(0) { acc, d in acc | (1 << (max(1, min(7, d)) - 1)) }
    }

    var weekdays: Set<Int> {
        get {
            var s = Set<Int>()
            for d in 1...7 where (weekdaysRaw & (1 << (d - 1))) != 0 { s.insert(d) }
            return s
        }
        set { weekdaysRaw = Self.encode(newValue) }
    }

    var isEveryDay: Bool { weekdays == Self.allWeekdays }
    var isWeekdaysOnly: Bool { weekdays == Self.weekdaysOnly }
    var isWeekendOnly: Bool { weekdays == Self.weekendOnly }

    /// Indique si la prise doit avoir lieu un jour donné.
    func applies(to day: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: day)
        return weekdays.contains(weekday)
    }

    // MARK: - Formatting

    var formattedTime: String { String(format: "%02d:%02d", hour, minute) }

    /// Résumé localisé du masque de jours : « tous les jours », « semaine »,
    /// « week-end » ou liste compacte (« lun., mer., ven. »).
    var weekdaySummary: String {
        if isEveryDay { return "tous les jours" }
        if isWeekdaysOnly { return "semaine" }
        if isWeekendOnly { return "week-end" }
        let symbols = Calendar(identifier: .gregorian).shortWeekdaySymbols
        guard symbols.count >= 7 else { return "" }
        let ordered = [2, 3, 4, 5, 6, 7, 1] // Mon..Sun en convention Calendar (1 = Dim)
        let labels = ordered.compactMap { d -> String? in
            let idx = d - 1
            guard weekdays.contains(d), symbols.indices.contains(idx) else { return nil }
            return symbols[idx]
        }
        return labels.joined(separator: ", ")
    }

    /// Sérialise la prise en token compatible avec `MedicationImporter`.
    /// Si la prise utilise la dose par défaut, tous les jours et notif active,
    /// le token reste un simple `HH:MM` (rétrocompatibilité).
    func encode(defaultDose: Double) -> String {
        var token = formattedTime
        if abs(dose - defaultDose) > 0.0001 {
            let numberFormat = dose.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(dose))
                : String(dose)
            token += "@\(numberFormat)"
        }
        if !isEveryDay {
            if isWeekdaysOnly { token += "/WD" }
            else if isWeekendOnly { token += "/WE" }
            else {
                // M=2, T=3, W=4, R=5, F=6, S=7, U=1
                let order: [(Int, Character)] = [
                    (2, "M"), (3, "T"), (4, "W"), (5, "R"),
                    (6, "F"), (7, "S"), (1, "U")
                ]
                let codes = order.compactMap { weekdays.contains($0.0) ? String($0.1) : nil }
                token += "/" + codes.joined()
            }
        }
        if !notifyEnabled { token += "!off" }
        return token
    }

    static func doseLabel(_ amount: Double, unit: DoseUnit) -> String {
        let numberFormat: String = amount.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(amount))
            : String(format: "%.1f", amount)
        return "\(numberFormat) \(unit.label)"
    }
}
