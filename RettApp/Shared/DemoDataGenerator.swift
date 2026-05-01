import Foundation
import SwiftData

/// Génère des données de démonstration synthétiques pour les crises et le plan
/// médicamenteux. Utilisé depuis les Réglages — utile pour montrer le tableau de bord
/// sans avoir à attendre des semaines de saisie réelle.
enum DemoDataGenerator {

    struct Result {
        let seizuresCreated: Int
        let medicationsCreated: Int
        let logsCreated: Int
    }

    /// Génère ~3 mois de crises et un plan médicamenteux type. N'efface rien
    /// — additif uniquement. Si un profil existe, les nouvelles données lui sont rattachées.
    @discardableResult
    static func generate(in context: ModelContext) -> Result {
        let profile = (try? context.fetch(FetchDescriptor<ChildProfile>()))?.first
        let now = Date()
        let cal = Calendar.current

        // -------- Crises --------
        var seizureCount = 0
        // ~3 mois en arrière, fréquence variable, types pondérés
        let types: [SeizureType] = [.tonicClonic, .absence, .focal, .myoclonic, .atonic, .other]
        let triggers: [SeizureTrigger] = [.none, .fever, .fatigue, .emotion, .heat, .other]
        let typeWeights: [Double] = [0.15, 0.45, 0.10, 0.20, 0.05, 0.05] // surtout absences

        for daysBack in 0..<90 {
            // ~30% des jours ont au moins une crise
            guard Double.random(in: 0...1) < 0.30 else { continue }
            let crisesThisDay = Int.random(in: 1...3)
            for _ in 0..<crisesThisDay {
                guard let baseDate = cal.date(byAdding: .day, value: -daysBack, to: now) else { continue }
                let hour = Int.random(in: 6...22)
                let minute = Int.random(in: 0...59)
                var comps = cal.dateComponents([.year, .month, .day], from: baseDate)
                comps.hour = hour; comps.minute = minute
                guard let start = cal.date(from: comps) else { continue }

                let type = weightedPick(types, weights: typeWeights)
                let durationSec: Int = {
                    switch type {
                    case .absence: return Int.random(in: 5...20)
                    case .myoclonic: return Int.random(in: 2...10)
                    case .atonic: return Int.random(in: 2...8)
                    case .focal: return Int.random(in: 30...120)
                    case .tonicClonic: return Int.random(in: 60...240)
                    case .other: return Int.random(in: 10...90)
                    }
                }()
                let end = start.addingTimeInterval(TimeInterval(durationSec))
                let trigger = triggers.randomElement() ?? .none

                let seizure = SeizureEvent(
                    startTime: start,
                    endTime: end,
                    seizureType: type,
                    trigger: trigger,
                    triggerNotes: "",
                    notes: "Données de démonstration",
                    childProfileId: profile?.id
                )
                context.insert(seizure)
                seizureCount += 1
            }
        }

        // -------- Médicaments --------
        var medCount = 0
        var logCount = 0
        let demoMeds: [(name: String, dose: Double, unit: DoseUnit, hours: [HourMinute])] = [
            ("Keppra (démo)", 500, .mg, [HourMinute(hour: 8, minute: 0), HourMinute(hour: 20, minute: 0)]),
            ("Dépakine (démo)", 250, .mg, [HourMinute(hour: 8, minute: 0), HourMinute(hour: 12, minute: 0), HourMinute(hour: 20, minute: 0)])
        ]
        for m in demoMeds {
            let med = Medication(
                name: m.name,
                doseAmount: m.dose,
                doseUnit: m.unit,
                scheduledHours: m.hours,
                isActive: true
            )
            med.childProfile = profile
            context.insert(med)
            medCount += 1

            // 14 jours de logs en arrière, ~95% pris
            for daysBack in 0..<14 {
                guard let day = cal.date(byAdding: .day, value: -daysBack, to: now) else { continue }
                for slot in m.hours {
                    let scheduled = slot.date(on: day)
                    let taken = Double.random(in: 0...1) < 0.95
                    let log = MedicationLog(
                        medicationId: med.id,
                        medicationName: med.name,
                        scheduledTime: scheduled,
                        takenTime: taken ? scheduled.addingTimeInterval(Double.random(in: -300...600)) : nil,
                        taken: taken,
                        dose: m.dose,
                        doseUnit: m.unit,
                        childProfileId: profile?.id
                    )
                    context.insert(log)
                    logCount += 1
                }
            }
        }

        try? context.save()
        return Result(seizuresCreated: seizureCount, medicationsCreated: medCount, logsCreated: logCount)
    }

    /// Supprime tout ce qui contient "démo" dans le nom (médicaments + logs liés) et
    /// les crises avec note "Données de démonstration". Préserve les données réelles.
    @discardableResult
    static func purgeDemoData(in context: ModelContext) -> Int {
        var deleted = 0
        let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        for m in meds where m.name.localizedCaseInsensitiveContains("démo") {
            context.delete(m); deleted += 1
        }
        let logs = (try? context.fetch(FetchDescriptor<MedicationLog>())) ?? []
        for l in logs where l.medicationName.localizedCaseInsensitiveContains("démo") {
            context.delete(l); deleted += 1
        }
        let seizures = (try? context.fetch(FetchDescriptor<SeizureEvent>())) ?? []
        for s in seizures where s.notes == "Données de démonstration" {
            context.delete(s); deleted += 1
        }
        try? context.save()
        return deleted
    }

    // MARK: - Helpers

    private static func weightedPick<T>(_ items: [T], weights: [Double]) -> T {
        let total = weights.reduce(0, +)
        let r = Double.random(in: 0...total)
        var acc = 0.0
        for (i, w) in weights.enumerated() {
            acc += w
            if r <= acc { return items[i] }
        }
        return items.last!
    }
}
