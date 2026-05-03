import Foundation
import HealthKit

enum HealthKitError: LocalizedError {
    case unavailable
    case notAuthorized
    case unsupportedType
    case write(Error)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Santé n'est pas disponible sur cet appareil."
        case .notAuthorized: return "Permission Apple Santé refusée."
        case .unsupportedType: return "Le type HealthKit requis n'est pas disponible sur cette version d'iOS."
        case .write(let e): return "Impossible d'écrire dans Apple Santé : \(e.localizedDescription)"
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
/// Ce manager reste en place pour :
/// - vérifier la disponibilité de HealthKit sur l'appareil,
/// - servir de point d'entrée futur si Apple expose un type dédié,
/// - laisser les entitlements HealthKit actifs pour d'éventuels autres types.
final class HealthKitManager {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Statut d'autorisation simplifié pour l'UI (aucun type réellement demandé tant
    /// que l'API seizure n'est pas disponible publiquement).
    enum SimpleAuthStatus { case notDetermined, denied, authorized, unavailable }

    func authorizationStatus() -> SimpleAuthStatus {
        isAvailable ? .notDetermined : .unavailable
    }

    /// Demande d'autorisation — no-op tant qu'aucun type n'est pris en charge.
    @discardableResult
    func requestAuthorizationIfNeeded() async throws -> Bool {
        guard isAvailable else { throw HealthKitError.unavailable }
        return true
    }

    // MARK: - Seizure writes

    /// Écrit (théoriquement) une crise dans Apple Santé. Indisponible aujourd'hui
    /// car le type catégorie `.seizure` n'est pas exposé publiquement.
    func writeSeizure(event: SeizureEvent, childFirstName: String) async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        throw HealthKitError.unsupportedType
    }
}
