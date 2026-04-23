import Foundation
import HealthKit

enum HealthKitError: LocalizedError {
    case unavailable
    case notAuthorized
    case write(Error)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Santé n'est pas disponible sur cet appareil."
        case .notAuthorized: return "Permission Apple Santé refusée."
        case .write(let e): return "Impossible d'écrire dans Apple Santé : \(e.localizedDescription)"
        }
    }
}

final class HealthKitManager {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()

    private var seizureType: HKCategoryType? {
        if #available(iOS 17.0, *) {
            return HKCategoryType(.seizure)
        }
        return nil
    }

    private var typesToShare: Set<HKSampleType> {
        var set: Set<HKSampleType> = []
        if let seizureType { set.insert(seizureType) }
        return set
    }

    private var typesToRead: Set<HKObjectType> {
        var set: Set<HKObjectType> = []
        if let seizureType { set.insert(seizureType) }
        return set
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Demande les permissions nécessaires. À appeler à la première écriture.
    @discardableResult
    func requestAuthorizationIfNeeded() async throws -> Bool {
        guard isAvailable else { throw HealthKitError.unavailable }
        do {
            try await store.requestAuthorization(toShare: typesToShare, read: typesToRead)
            return true
        } catch {
            throw HealthKitError.write(error)
        }
    }

    func authorizationStatus() -> HKAuthorizationStatus {
        guard let seizureType else { return .notDetermined }
        return store.authorizationStatus(for: seizureType)
    }

    // MARK: - Seizure writes

    func writeSeizure(event: SeizureEvent, childFirstName: String) async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        guard let seizureType else { throw HealthKitError.unavailable }

        let status = store.authorizationStatus(for: seizureType)
        if status == .notDetermined {
            try await store.requestAuthorization(toShare: [seizureType], read: [seizureType])
        }

        let metadata: [String: Any] = [
            HKMetadataKeyExternalUUID: event.id.uuidString,
            "AFSRChildFirstName": childFirstName,
            "AFSRSeizureType": event.seizureType.rawValue,
            "AFSRTrigger": event.trigger.rawValue
        ]

        let sample = HKCategorySample(
            type: seizureType,
            value: HKCategoryValueSeverity.moderate.rawValue,
            start: event.startTime,
            end: event.endTime,
            metadata: metadata
        )

        do {
            try await store.save(sample)
        } catch {
            throw HealthKitError.write(error)
        }
    }
}
