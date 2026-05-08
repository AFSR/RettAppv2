import Foundation

/// Schéma compact d'un cahier de suivi imprimé. Encodé en JSON dans un QR
/// code en haut à droite de la page. Au scan, le QR est décodé pour
/// restituer exactement la structure du cahier (date de début de semaine,
/// médicaments à suivre, repas, symptômes), et `BookletLayoutEngine`
/// re-calcule les positions exactes des cases à cocher.
///
/// Le payload JSON utilise des clés courtes pour rester sous les ~400
/// caractères et tenir dans un QR code de version raisonnable (v8-v12).
struct BookletSchema: Codable, Equatable {

    /// Version du format. Bumper si le schéma ou l'algorithme de layout
    /// change de manière incompatible.
    let v: Int

    /// Date du lundi (premier jour) de la semaine, format ISO « yyyy-MM-dd ».
    let start: String

    /// Nombre de jours couverts (5 ou 7).
    let days: Int

    /// Sections incluses, codées par lettres :
    ///   M = Médicaments
    ///   S = Crises (Seizures)
    ///   D = Humeur (mood Dominant)
    ///   L = Repas (Lunch et autres)
    ///   H = Hydratation (toujours avec L si présent)
    ///   P = Sommeil (sleeP)
    ///   Y = Symptômes Rett
    ///   E = Événements particuliers
    let incl: String

    /// Médicaments à suivre — un libellé par prise « Nom dose @ HH:MM ».
    let meds: [String]

    /// Slots de repas, sous-ensemble de "B" (breakfast), "L" (lunch),
    /// "S" (snack), "D" (dinner). Concaténés en string pour économiser.
    let mealSlots: String

    /// Symptômes Rett : raw values de l'enum RettSymptom.
    let symptoms: [String]

    enum CodingKeys: String, CodingKey {
        case v
        case start = "s"
        case days = "d"
        case incl = "i"
        case meds = "m"
        case mealSlots = "ml"
        case symptoms = "sy"
    }

    /// Encode en JSON compact pour intégration dans le QR.
    func encodedJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    /// Décode depuis le contenu d'un QR code.
    static func decode(_ payload: String) -> BookletSchema? {
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BookletSchema.self, from: data)
    }

    /// Date Swift correspondant au lundi de la semaine.
    var weekStartDate: Date? {
        var f = DateComponents()
        let parts = start.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        f.year = parts[0]; f.month = parts[1]; f.day = parts[2]
        return Calendar(identifier: .gregorian).date(from: f)
    }

    /// Date du jour `dayIndex` (0 = lundi).
    func date(forDayIndex dayIndex: Int, calendar: Calendar = .current) -> Date? {
        guard let start = weekStartDate else { return nil }
        return calendar.date(byAdding: .day, value: dayIndex, to: start)
    }

    /// Sections incluses sous forme de Set.
    var includedSections: Set<Section> {
        Set(incl.compactMap { Section(letter: String($0)) })
    }

    enum Section: String, Hashable {
        case medication, seizure, mood, meals, hydration, sleep, symptoms, events

        init?(letter: String) {
            switch letter {
            case "M": self = .medication
            case "S": self = .seizure
            case "D": self = .mood
            case "L": self = .meals
            case "H": self = .hydration
            case "P": self = .sleep
            case "Y": self = .symptoms
            case "E": self = .events
            default:  return nil
            }
        }

        var letter: String {
            switch self {
            case .medication: return "M"
            case .seizure:    return "S"
            case .mood:       return "D"
            case .meals:      return "L"
            case .hydration:  return "H"
            case .sleep:      return "P"
            case .symptoms:   return "Y"
            case .events:     return "E"
            }
        }
    }

    /// Construit un schéma à partir des options actuelles du générateur.
    static func from(
        options: FollowUpBookletGenerator.Options,
        weekStart: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> BookletSchema {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let startStr = f.string(from: weekStart)

        var sections: [Section] = []
        if options.includeMedicationGrid { sections.append(.medication) }
        if options.includeSeizureGrid    { sections.append(.seizure) }
        if options.includeMoodGrid       { sections.append(.mood) }
        if options.includeMealsGrid {
            sections.append(.meals)
            sections.append(.hydration)
        }
        if options.includeSleepGrid      { sections.append(.sleep) }
        if options.includeSymptomsGrid   { sections.append(.symptoms) }
        if options.includeFreeNotes      { sections.append(.events) }

        // Liste des prises de médicaments dans l'ordre du PDF
        let actives = options.medications.filter { $0.isActive }
        var medsList: [String] = []
        for med in actives {
            for h in med.scheduledHours {
                let key = DoseKey(medicationID: med.id, hour: h.hour, minute: h.minute)
                if options.allDosesSelected || options.selectedDoses.contains(key) {
                    medsList.append("\(med.name) \(med.doseLabel) @ \(h.formatted)")
                }
            }
        }

        // Slots repas dans l'ordre canonique
        let allSlots: [(MealSlot, String)] = [
            (.breakfast, "B"), (.lunch, "L"), (.snack, "S"), (.dinner, "D")
        ]
        let mealLetters = allSlots
            .filter { options.selectedMealSlots.contains($0.0) }
            .map { $0.1 }
            .joined()

        // Symptômes dans l'ordre RettSymptom.allCases
        let symptomList = RettSymptom.allCases
            .filter { options.selectedSymptoms.contains($0) }
            .map { $0.rawValue }

        return BookletSchema(
            v: 1,
            start: startStr,
            days: options.dayCount,
            incl: sections.map(\.letter).joined(),
            meds: medsList,
            mealSlots: mealLetters,
            symptoms: symptomList
        )
    }
}
