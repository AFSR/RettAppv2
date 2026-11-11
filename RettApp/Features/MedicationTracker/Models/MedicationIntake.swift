import Foundation

/// Une prise planifiée d'un médicament : heure, dose, jours de la semaine et
/// préférence de notification individuelle.
///
/// Permet de gérer des plans complexes : « 5 mg en semaine à 8h, 10 mg le
/// week-end à 10h », et de désactiver les rappels pour les jours où l'enfant
/// est pris en charge par un tiers (école, centre, autre parent).
/// Rythmes de prise les plus courants, et les heures qui vont avec.
///
/// Configurer un médicament pris trois fois par jour demandait trois ajouts
/// puis trois ouvertures pour régler chaque heure. Le plan est volontairement
/// fin — dose par prise, jours actifs, rappel individuel — mais cette finesse
/// ne devrait se payer que pour les cas qui en ont besoin, pas pour le cas
/// ordinaire.
///
/// Les heures retenues suivent le rythme des repas, qui est celui auquel les
/// traitements sont ordinairement calés : matin, midi, goûter, soir. Elles
/// restent modifiables prise par prise — ce n'est qu'un point de départ.
enum MedicationRhythm {

    /// Rythmes proposés au démarrage rapide.
    static let commonCounts = [1, 2, 3, 4]

    /// Heures par défaut pour un nombre de prises par jour.
    ///
    /// Au-delà de quatre, on répartit régulièrement entre 8 h et 20 h : un
    /// rythme inhabituel sera de toute façon ajusté à la main, autant
    /// proposer quelque chose de régulier plutôt que rien.
    static func hours(forCountPerDay count: Int) -> [HourMinute] {
        switch count {
        case ..<1:  return []
        case 1:     return [HourMinute(hour: 8, minute: 0)]
        case 2:     return [HourMinute(hour: 8, minute: 0), HourMinute(hour: 20, minute: 0)]
        case 3:     return [HourMinute(hour: 8, minute: 0),
                            HourMinute(hour: 12, minute: 0),
                            HourMinute(hour: 20, minute: 0)]
        case 4:     return [HourMinute(hour: 8, minute: 0),
                            HourMinute(hour: 12, minute: 0),
                            HourMinute(hour: 16, minute: 0),
                            HourMinute(hour: 20, minute: 0)]
        default:
            // Répartition régulière entre 8 h et 20 h. On travaille en
            // minutes depuis minuit plutôt qu'en heures décimales : arrondir
            // les minutes séparément pouvait produire « 14 h 60 », une heure
            // qui n'existe pas et que le sélecteur refuserait.
            let premiere = 8 * 60, derniere = 20 * 60
            let pas = Double(derniere - premiere) / Double(count - 1)
            return (0..<count).map { i in
                let brut = Double(premiere) + pas * Double(i)
                let minutes = min(derniere, Int((brut / 5).rounded()) * 5)
                return HourMinute(hour: minutes / 60, minute: minutes % 60)
            }
        }
    }

    /// Prises prêtes à l'emploi : heures par défaut, dose habituelle, tous
    /// les jours, rappel actif. Tout reste ajustable ensuite.
    static func intakes(countPerDay count: Int, dose: Double) -> [MedicationIntake] {
        hours(forCountPerDay: count).map {
            MedicationIntake(
                hour: $0.hour,
                minute: $0.minute,
                dose: dose,
                weekdays: MedicationIntake.allWeekdays,
                notifyEnabled: true
            )
        }
    }

    /// Libellé du rythme, pour les boutons.
    static func label(forCountPerDay count: Int) -> String {
        count == 1 ? "1 fois par jour" : "\(count) fois par jour"
    }
}

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
