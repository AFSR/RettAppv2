import Foundation
import Observation

/// Les graphiques que le Bilan sait afficher. Les trois cartes de synthèse et
/// « Ce que montrent vos données » ne figurent pas ici : elles ne se
/// réordonnent pas, elles font partie du cadre du Bilan.
enum BilanChart: String, CaseIterable, Identifiable {
    case frequency, intensity, mood, adherence, symptoms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frequency: return "Fréquence des crises"
        case .intensity: return "Intensité (durée totale)"
        case .mood:      return "Humeur moyenne"
        case .adherence: return "Observance médicamenteuse"
        case .symptoms:  return "Symptômes Rett"
        }
    }

    var systemImage: String {
        switch self {
        case .frequency: return "chart.bar.xaxis"
        case .intensity: return "waveform.path"
        case .mood:      return "face.smiling"
        case .adherence: return "pill.fill"
        case .symptoms:  return "stethoscope"
        }
    }

    /// Tous les graphiques sont visibles au départ : l'utilisateur retire ce
    /// qui ne l'intéresse pas, plutôt que de devoir découvrir ce qui existe.
    var visibleByDefault: Bool { true }
}

/// Ordre et visibilité des graphiques du Bilan, mémorisés sur cet appareil.
///
/// C'est une préférence d'affichage : `UserDefaults`, comme `UsageModeStore`.
/// Surtout pas un `@Model` — un changement de schéma SwiftData expose chaque
/// famille à l'effacement du magasin (voir `.claude/rules/sync-cloudkit.md`).
/// Rien ne part vers CloudKit : chaque parent compose son propre Bilan.
@Observable
@MainActor
final class BilanLayoutStore {
    static let shared = BilanLayoutStore()

    static let key = "RettApp.bilanLayout.v1"

    struct Entry: Identifiable, Equatable {
        let chart: BilanChart
        var isVisible: Bool
        var id: String { chart.id }
    }

    /// Tous les graphiques connus, dans l'ordre choisi, visibles ou non.
    private(set) var entries: [Entry]

    private let defaults: UserDefaults

    /// `defaults` est injectable pour les tests.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = Self.load(from: defaults)
    }

    /// Les graphiques à dessiner, dans l'ordre.
    var visibleCharts: [BilanChart] {
        entries.filter(\.isVisible).map(\.chart)
    }

    func isVisible(_ chart: BilanChart) -> Bool {
        entries.first { $0.chart == chart }?.isVisible ?? false
    }

    func setVisible(_ chart: BilanChart, _ visible: Bool) {
        guard let i = entries.firstIndex(where: { $0.chart == chart }) else { return }
        entries[i].isVisible = visible
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        // `Array.move(fromOffsets:)` est dans SwiftUI ; on s'en passe pour
        // garder ce fichier sans dépendance d'interface.
        let moved = source.sorted().map { entries[$0] }
        var rest = entries
        for i in source.sorted().reversed() { rest.remove(at: i) }
        let shift = source.filter { $0 < destination }.count
        rest.insert(contentsOf: moved, at: max(0, min(rest.count, destination - shift)))
        entries = rest
        save()
    }

    func reset() {
        defaults.removeObject(forKey: Self.key)
        entries = Self.defaultEntries()
    }

    var isDefault: Bool { entries == Self.defaultEntries() }

    // MARK: - Persistance

    private struct Stored: Codable {
        var id: String
        var visible: Bool
    }

    private static func defaultEntries() -> [Entry] {
        BilanChart.allCases.map { Entry(chart: $0, isVisible: $0.visibleByDefault) }
    }

    /// Tolérant dans les deux sens : un identifiant inconnu (graphique retiré
    /// dans une version ultérieure, puis retour en arrière) est ignoré, et un
    /// graphique ajouté depuis l'enregistrement arrive en fin de liste,
    /// avec sa visibilité par défaut. Un fichier illisible redonne l'ordre
    /// par défaut plutôt qu'un Bilan vide.
    private static func load(from defaults: UserDefaults) -> [Entry] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([Stored].self, from: data)
        else { return defaultEntries() }

        var seen = Set<BilanChart>()
        var result: [Entry] = []
        for s in stored {
            guard let chart = BilanChart(rawValue: s.id), seen.insert(chart).inserted else { continue }
            result.append(Entry(chart: chart, isVisible: s.visible))
        }
        for chart in BilanChart.allCases where !seen.contains(chart) {
            result.append(Entry(chart: chart, isVisible: chart.visibleByDefault))
        }
        return result
    }

    private func save() {
        let stored = entries.map { Stored(id: $0.chart.rawValue, visible: $0.isVisible) }
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
