import Foundation
import Observation

/// Rôle de l'appareil : sur quel iPhone est installée cette copie de RettApp ?
///
/// - `.parent` : le mode par défaut. Saisie manuelle, dashboard, partage CloudKit
///   bidirectionnel avec d'autres parents.
/// - `.child` : RettApp est installée sur l'iPhone de l'enfant (suivi 24/7,
///   sommeil, hydratation, repas via Apple Santé local). Les données sont
///   poussées vers les parents via le même CKShare.
///
/// Le choix est local à chaque appareil et stocké dans `UserDefaults`. Aucun
/// effet sur le schéma SwiftData ou CloudKit.
enum DeviceRole: String, CaseIterable, Identifiable {
    case parent
    case child

    var id: String { rawValue }

    var label: String {
        switch self {
        case .parent: return "Parent / aidant"
        case .child:  return "Enfant"
        }
    }

    var detailedLabel: String {
        switch self {
        case .parent: return "Cet iPhone est utilisé par un parent ou un aidant qui assure le suivi."
        case .child:  return "Cet iPhone est utilisé par l'enfant. Les données Apple Santé locales (sommeil, hydratation, repas, etc.) seront partagées avec les parents."
        }
    }

    var systemImage: String {
        switch self {
        case .parent: return "person.fill"
        case .child:  return "figure.child"
        }
    }
}

/// État global du rôle de l'appareil. Observable pour que les vues réagissent
/// instantanément au changement.
@Observable
@MainActor
final class DeviceRoleStore {
    static let shared = DeviceRoleStore()

    private let key = "RettApp.deviceRole.v1"
    private let healthSelectionKey = "RettApp.childHealthSelection.v1"

    var role: DeviceRole {
        didSet {
            UserDefaults.standard.set(role.rawValue, forKey: key)
        }
    }

    /// Types Apple Santé sélectionnés à lire — actif uniquement quand role == .child.
    /// Les parents lisent automatiquement tout ce que la famille iCloud leur a partagé.
    var childHealthSelection: ChildHealthSelection {
        didSet {
            if let data = try? JSONEncoder().encode(childHealthSelection) {
                UserDefaults.standard.set(data, forKey: healthSelectionKey)
            }
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: key) ?? DeviceRole.parent.rawValue
        self.role = DeviceRole(rawValue: raw) ?? .parent
        if let data = UserDefaults.standard.data(forKey: healthSelectionKey),
           let decoded = try? JSONDecoder().decode(ChildHealthSelection.self, from: data) {
            self.childHealthSelection = decoded
        } else {
            self.childHealthSelection = .defaults
        }
    }
}

/// Cases sélectionnables d'Apple Santé pour le mode « iPhone de l'enfant ».
/// Par défaut, tout est désactivé — l'utilisateur opte explicitement.
struct ChildHealthSelection: Codable, Equatable {
    var hydration: Bool         // dietaryWater (hydratation)
    var meals: Bool             // dietaryEnergyConsumed + carbs/protein/fat (repas)
    var nightSleep: Bool        // sleepAnalysis filtré sur les sessions de nuit
    var naps: Bool              // sleepAnalysis filtré sur les sessions diurnes
    var heartRate: Bool         // heartRate + restingHeartRate
    var activity: Bool          // stepCount + activeEnergyBurned

    static let defaults = ChildHealthSelection(
        hydration: false, meals: false,
        nightSleep: true, naps: true,
        heartRate: true, activity: true
    )

    static let none = ChildHealthSelection(
        hydration: false, meals: false,
        nightSleep: false, naps: false,
        heartRate: false, activity: false
    )

    var anySelected: Bool {
        hydration || meals || nightSleep || naps || heartRate || activity
    }
}
