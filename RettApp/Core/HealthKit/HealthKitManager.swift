import Foundation
import HealthKit

enum HealthKitError: LocalizedError {
    case unavailable
    case notAuthorized
    case unsupportedType
    case write(Error)
    case read(Error)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Santé n'est pas disponible sur cet appareil."
        case .notAuthorized: return "Permission Apple Santé refusée."
        case .unsupportedType: return "Le type HealthKit requis n'est pas disponible sur cette version d'iOS."
        case .write(let e): return "Impossible d'écrire dans Apple Santé : \(e.localizedDescription)"
        case .read(let e): return "Impossible de lire Apple Santé : \(e.localizedDescription)"
        }
    }
}

/// Gestionnaire HealthKit central.
///
/// ⚠️ L'API publique `HKCategoryTypeIdentifier.seizure` n'existe pas dans le SDK iOS 17.
/// L'écriture des crises dans Apple Santé n'est donc pas possible via HealthKit
/// aujourd'hui — les crises sont stockées uniquement en SwiftData et peuvent être
/// exportées en CSV depuis les réglages.
///
/// Lecture des données de l'enfant : depuis iOS 17, Apple permet le partage de
/// données Santé entre membres d'une famille iCloud (Health Sharing). Une fois
/// le partage configuré au niveau OS sur l'iPhone/Apple Watch de l'enfant, les
/// requêtes HKSampleQuery sur le store du parent renvoient automatiquement les
/// échantillons partagés. Cela permet d'agréger sommeil / rythme cardiaque /
/// activité de l'enfant sans architecture custom.
final class HealthKitManager {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Types qu'on souhaite lire pour le suivi parental. La permission par type
    /// est gérée par l'OS (Réglages → Confidentialité → Santé).
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(hr)
        }
        if let restingHr = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHr)
        }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        return types
    }

    /// Statut d'autorisation simplifié pour l'UI.
    enum SimpleAuthStatus { case notDetermined, denied, authorized, unavailable }

    func authorizationStatus() -> SimpleAuthStatus {
        guard isAvailable else { return .unavailable }
        // Pour la lecture, HealthKit ne révèle pas l'état exact (Apple cache la
        // permission à des fins de privacy). On renvoie .notDetermined pour
        // forcer l'UI à proposer la demande à chaque entrée du panneau.
        return .notDetermined
    }

    /// Demande d'autorisation pour lire les types listés. La présentation de la
    /// feuille système est gérée par l'OS lui-même.
    @discardableResult
    func requestAuthorizationIfNeeded() async throws -> Bool {
        guard isAvailable else { throw HealthKitError.unavailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        return true
    }

    // MARK: - Seizure writes

    /// Écrit (théoriquement) une crise dans Apple Santé. Indisponible aujourd'hui
    /// car le type catégorie `.seizure` n'est pas exposé publiquement.
    func writeSeizure(event: SeizureEvent, childFirstName: String) async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        throw HealthKitError.unsupportedType
    }

    // MARK: - Reads

    /// Agrège les données de santé par jour sur la période demandée. Utilise les
    /// API statistique pour le rythme cardiaque et de discrete sample pour le sommeil.
    func dailyAggregates(start: Date, end: Date) async throws -> [DailyHealthAggregate] {
        guard isAvailable else { throw HealthKitError.unavailable }
        let cal = Calendar.current
        let dayStarts: [Date] = {
            var result: [Date] = []
            var cursor = cal.startOfDay(for: start)
            let endDay = cal.startOfDay(for: end)
            while cursor <= endDay {
                result.append(cursor)
                cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? endDay.addingTimeInterval(1)
            }
            return result
        }()

        async let sleep = sleepMinutesPerDay(dayStarts: dayStarts, calendar: cal)
        async let avgHr = averageHeartRatePerDay(dayStarts: dayStarts, calendar: cal)
        async let restingHr = restingHeartRatePerDay(dayStarts: dayStarts, calendar: cal)
        async let steps = totalStepsPerDay(dayStarts: dayStarts, calendar: cal)
        async let energy = activeEnergyPerDay(dayStarts: dayStarts, calendar: cal)

        let sleepResult = try await sleep
        let hrResult = try await avgHr
        let restingResult = try await restingHr
        let stepsResult = try await steps
        let energyResult = try await energy

        return dayStarts.map { day in
            DailyHealthAggregate(
                day: day,
                sleepMinutes: sleepResult[day],
                avgHeartRate: hrResult[day],
                restingHeartRate: restingResult[day],
                steps: stepsResult[day],
                activeEnergyKcal: energyResult[day]
            )
        }
    }

    // MARK: - Per-type queries

    private func sleepMinutesPerDay(dayStarts: [Date], calendar: Calendar) async throws -> [Date: Int] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let first = dayStarts.first,
              let last = dayStarts.last else { return [:] }
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        let predicate = HKQuery.predicateForSamples(withStart: first, end: dayEnd, options: .strictStartDate)
        let samples = try await fetchSamples(of: type, predicate: predicate)

        var result: [Date: Int] = [:]
        for sample in samples {
            guard let cat = sample as? HKCategorySample else { continue }
            // On ne compte que les phases « endormi » (asleep* ou unspecified asleep).
            let value = cat.value
            let isAsleep = value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                || value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                || value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                || value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
            guard isAsleep else { continue }
            let minutes = Int(cat.endDate.timeIntervalSince(cat.startDate) / 60)
            // On rattache l'épisode au jour de son startDate.
            let dayKey = calendar.startOfDay(for: cat.startDate)
            result[dayKey, default: 0] += minutes
        }
        return result
    }

    private func averageHeartRatePerDay(dayStarts: [Date], calendar: Calendar) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [:] }
        return try await statisticsCollection(
            type: type,
            unit: HKUnit(from: "count/min"),
            options: .discreteAverage,
            dayStarts: dayStarts,
            calendar: calendar,
            extractor: { $0.averageQuantity() }
        )
    }

    private func restingHeartRatePerDay(dayStarts: [Date], calendar: Calendar) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else { return [:] }
        return try await statisticsCollection(
            type: type,
            unit: HKUnit(from: "count/min"),
            options: .discreteAverage,
            dayStarts: dayStarts,
            calendar: calendar,
            extractor: { $0.averageQuantity() }
        )
    }

    private func totalStepsPerDay(dayStarts: [Date], calendar: Calendar) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return [:] }
        return try await statisticsCollection(
            type: type,
            unit: .count(),
            options: .cumulativeSum,
            dayStarts: dayStarts,
            calendar: calendar,
            extractor: { $0.sumQuantity() }
        )
    }

    private func activeEnergyPerDay(dayStarts: [Date], calendar: Calendar) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else { return [:] }
        return try await statisticsCollection(
            type: type,
            unit: .kilocalorie(),
            options: .cumulativeSum,
            dayStarts: dayStarts,
            calendar: calendar,
            extractor: { $0.sumQuantity() }
        )
    }

    // MARK: - Generic helpers

    private func fetchSamples(of type: HKSampleType, predicate: NSPredicate) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
            let q = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: HealthKitError.read(error)) }
                else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(q)
        }
    }

    private func statisticsCollection(
        type: HKQuantityType,
        unit: HKUnit,
        options: HKStatisticsOptions,
        dayStarts: [Date],
        calendar: Calendar,
        extractor: @escaping (HKStatistics) -> HKQuantity?
    ) async throws -> [Date: Double] {
        guard let anchor = dayStarts.first,
              let last = dayStarts.last else { return [:] }
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: dayEnd, options: .strictStartDate)
        let interval = DateComponents(day: 1)

        let stats: HKStatisticsCollection = try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsCollectionQuery(
                quantityType: type, quantitySamplePredicate: predicate,
                options: options, anchorDate: anchor, intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, error in
                if let error { cont.resume(throwing: HealthKitError.read(error)) }
                else if let results { cont.resume(returning: results) }
                else { cont.resume(throwing: HealthKitError.unsupportedType) }
            }
            store.execute(query)
        }

        var output: [Date: Double] = [:]
        stats.enumerateStatistics(from: anchor, to: dayEnd) { stat, _ in
            let key = calendar.startOfDay(for: stat.startDate)
            if let q = extractor(stat) {
                output[key] = q.doubleValue(for: unit)
            }
        }
        return output
    }
}

/// Une journée de données HealthKit consolidées. Les champs sont optionnels :
/// - `nil` signifie « aucun échantillon » (l'enfant n'a pas porté la montre,
///   ou les données ne sont pas partagées avec ce parent).
/// - `0` est une vraie valeur (ex. 0 pas).
struct DailyHealthAggregate: Identifiable {
    let id = UUID()
    let day: Date
    let sleepMinutes: Int?
    let avgHeartRate: Double?
    let restingHeartRate: Double?
    let steps: Double?
    let activeEnergyKcal: Double?

    var hasAnyData: Bool {
        sleepMinutes != nil || avgHeartRate != nil || restingHeartRate != nil
            || steps != nil || activeEnergyKcal != nil
    }
}
