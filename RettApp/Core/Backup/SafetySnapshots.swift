import Foundation
import SwiftData
import os.log

/// Instantanés de sécurité locaux : une copie JSON complète de la base est
/// prise automatiquement AVANT toute opération de fusion susceptible de
/// supprimer des données (dedup multi-appareil). L'utilisateur peut
/// restaurer depuis Réglages → Mes données → Instantanés de sécurité.
///
/// Filet de sécurité né d'un constat : à chaque évolution de la couche de
/// synchronisation, les parents craignent (parfois à raison) pour leurs
/// données. Avec un instantané pris juste avant chaque fusion, AUCUNE
/// opération automatique ne peut plus détruire quoi que ce soit
/// d'irrécupérable : le pire cas devient « restaurer l'instantané ».
///
/// Stockage : Application Support/SafetySnapshots/*.json — local à
/// l'appareil, jamais transmis. On garde les `maxKept` plus récents.
enum SafetySnapshots {
    private static let log = Logger(subsystem: "fr.afsr.RettApp", category: "SafetySnapshots")
    static let maxKept = 7

    static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("SafetySnapshots", isDirectory: true)
    }

    /// Prend un instantané complet. Best-effort : un échec est loggé mais ne
    /// bloque jamais l'appelant (la fusion reste préférable à un crash).
    @MainActor
    static func take(context: ModelContext, label: String) {
        do {
            let tmpURL = try CombinedBackupService.export(context: context)
            let dir = directory()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let dest = dir.appendingPathComponent("rettapp-\(label)-\(stamp).json")
            try FileManager.default.moveItem(at: tmpURL, to: dest)
            prune()
            log.info("Instantané pris : \(dest.lastPathComponent)")
        } catch {
            log.error("Échec instantané : \(error.localizedDescription)")
        }
    }

    /// Liste des instantanés disponibles, du plus récent au plus ancien.
    static func list() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory(),
            includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Date de création lisible d'un instantané (depuis les attributs fichier).
    static func creationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    /// Restaure un instantané via l'import standard (idempotent par UUID :
    /// les records encore présents sont mis à jour, les supprimés recréés).
    /// Le `saveTouching` interne re-propage les données restaurées via la
    /// synchronisation normale.
    @MainActor
    @discardableResult
    static func restore(url: URL, context: ModelContext) -> CombinedBackupService.ImportResult {
        guard let data = try? Data(contentsOf: url) else {
            var r = CombinedBackupService.ImportResult()
            r.errors.append("Impossible de lire l'instantané.")
            return r
        }
        return CombinedBackupService.importBackup(contents: data, context: context)
    }

    private static func prune() {
        let all = list()
        guard all.count > maxKept else { return }
        for url in all.dropFirst(maxKept) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
