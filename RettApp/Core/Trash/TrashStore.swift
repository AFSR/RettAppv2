import Foundation
import SwiftData
import os.log

/// Corbeille : ce qui a été supprimé délibérément, et depuis quand.
///
/// Deux rôles, et le second compte plus que le premier.
///
/// **Rendre une suppression réversible.** Une crise, un médicament effacés par
/// erreur sont récupérables pendant trente jours. Passé ce délai l'entrée
/// disparaît pour de bon.
///
/// **Empêcher une résurrection.** C'est le vrai sujet. Sans trace d'une
/// suppression, restaurer un instantané de sécurité antérieur réinsère ce qui
/// avait été supprimé depuis — la donnée revient d'entre les morts, et le
/// parent qui l'avait retirée la retrouve sans comprendre. La corbeille donne
/// à l'import la réponse qui lui manquait : « cet enregistrement a été
/// supprimé le 3, ton instantané date du 1er, ne le remets pas ».
///
/// ## Pourquoi un fichier et pas un modèle SwiftData
///
/// Ajouter un `@Model` modifie le schéma du magasin. Or `RettAppApp` ouvre le
/// magasin avec une récupération qui, en cas d'échec, **efface le fichier et
/// recommence**. Une migration légère qui ne se passerait pas comme prévu
/// coûterait donc à chaque famille la totalité de ses données locales. Le jeu
/// n'en vaut pas la chandelle pour une corbeille : on suit le modèle déjà
/// retenu par `PendingWriteStore` et `SafetySnapshots`, un fichier JSON dans
/// Application Support. Aucun changement de schéma, aucun risque de migration.
///
/// ## Charge utile
///
/// Chaque entrée embarque un `CombinedBackup` ne contenant que
/// l'enregistrement supprimé. Restaurer revient donc à importer une sauvegarde
/// d'un seul élément, en réutilisant `CombinedBackupService` — déjà durci,
/// déjà testé, et qui sait repousser vers CloudKit.
enum TrashStore {

    // MARK: - Modèle

    struct Item: Codable, Identifiable, Hashable {
        /// Identifiant de l'entrée de corbeille, pas de l'enregistrement.
        let id: UUID
        /// Identifiant de l'enregistrement supprimé.
        let recordName: String
        let recordType: String
        let deletedAt: Date
        /// Libellé lisible, pour la liste de la corbeille.
        let summary: String
        /// Sauvegarde d'un seul enregistrement.
        let payload: CombinedBackup

        /// Une entrée venue de l'autre parent ne transporte pas le contenu
        /// supprimé, seulement la suppression : il n'y a rien à remettre en
        /// place, et proposer « Restaurer » mentirait. Par défaut vrai, pour
        /// que les entrées déjà enregistrées avant ce champ restent
        /// restaurables.
        var restorable: Bool = true

        var expiresAt: Date { deletedAt.addingTimeInterval(TrashStore.retention) }

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// Trente jours, comme arbitré (décision 7).
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    static let didChangeNotification = Notification.Name("afsr.trash.didChange")

    private static let log = Logger(subsystem: "fr.afsr.RettApp", category: "Trash")
    private static let queue = DispatchQueue(label: "afsr.trash")

    /// Mêmes réglages que les sauvegardes complètes : la charge utile est un
    /// `CombinedBackup`, et deux stratégies de date différentes rendraient un
    /// fichier illisible par l'autre.
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "trash.json")
    }

    // MARK: - Lecture

    /// Entrées non expirées, la plus récente d'abord.
    static func items() -> [Item] {
        queue.sync { loadUnsafe() }
            .filter { $0.expiresAt > Date() }
            .sorted { $0.deletedAt > $1.deletedAt }
    }

    /// Cet enregistrement a-t-il été supprimé **après** la date donnée ?
    ///
    /// C'est la question que pose un import : une sauvegarde prise le 1er ne
    /// doit pas réinsérer ce qui a été supprimé le 3. Une suppression
    /// antérieure à la sauvegarde, elle, ne dit rien — l'enregistrement a pu
    /// être recréé depuis.
    static func wasDeleted(recordName: String, after date: Date) -> Bool {
        queue.sync { loadUnsafe() }
            .contains { $0.recordName == recordName && $0.deletedAt > date }
    }

    /// Identifiants supprimés après la date donnée. Variante groupée de
    /// `wasDeleted`, pour qu'un import de plusieurs milliers de lignes ne
    /// relise pas le fichier à chaque ligne.
    static func recordNamesDeleted(after date: Date) -> Set<String> {
        Set(
            queue.sync { loadUnsafe() }
                .filter { $0.deletedAt > date }
                .map(\.recordName)
        )
    }

    // MARK: - Écriture

    /// Dépose une entrée. À appeler **avant** la suppression effective, tant
    /// que l'objet est encore lisible.
    static func record(
        recordName: String,
        recordType: String,
        summary: String,
        payload: CombinedBackup,
        deletedAt: Date = Date(),
        restorable: Bool = true
    ) {
        let item = Item(
            id: UUID(),
            recordName: recordName,
            recordType: recordType,
            deletedAt: deletedAt,
            summary: summary,
            payload: payload,
            restorable: restorable
        )
        queue.sync {
            var all = loadUnsafe()
            // Une suppression plus récente du même enregistrement remplace la
            // précédente : deux entrées pour un même identifiant donneraient
            // deux lignes dans la corbeille pour une seule chose.
            all.removeAll { $0.recordName == recordName }
            all.append(item)
            persistUnsafe(all)
        }
        log.info("corbeille: \(recordType, privacy: .public) déposé")

        // La suppression doit atteindre l'autre parent, et y rester opposable
        // même s'il repousse plus tard une copie périmée. Seules les
        // suppressions faites ICI sont poussées : une pierre tombale reçue
        // n'est pas renvoyée, sinon les deux appareils se la relanceraient.
        if restorable {
            PendingWriteStore.shared.markUpsert(
                recordType: CKRecordType.tombstone,
                recordName: cloudRecordName(forTarget: recordName)
            )
        }

        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Retire une entrée sans rien restaurer — la suppression devient
    /// définitive avant l'heure.
    static func forget(id: UUID) {
        queue.sync {
            var all = loadUnsafe()
            all.removeAll { $0.id == id }
            persistUnsafe(all)
        }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Supprime les entrées dont les trente jours sont écoulés. Idempotent,
    /// appelé au lancement.
    @discardableResult
    static func purgeExpired(now: Date = Date()) -> Int {
        let removed: Int = queue.sync {
            let all = loadUnsafe()
            let kept = all.filter { $0.expiresAt > now }
            guard kept.count != all.count else { return 0 }
            persistUnsafe(kept)
            return all.count - kept.count
        }
        if removed > 0 {
            log.info("corbeille: \(removed) entrée(s) expirée(s) purgée(s)")
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
        return removed
    }

    /// Remet l'enregistrement en place et retire l'entrée de la corbeille.
    ///
    /// L'import se charge du reste : il réinsère, horodate et met en file
    /// l'écriture vers CloudKit, si bien que l'autre parent récupère la
    /// donnée restaurée comme n'importe quelle modification.
    /// On repasse par l'encodage plutôt que d'ajouter une variante d'import
    /// prenant un `CombinedBackup` : un aller-retour JSON sur un seul
    /// enregistrement ne coûte rien, et toucher à la fonction d'import —
    /// la plus durcie du dossier — pour ce seul confort serait un mauvais
    /// échange.
    @discardableResult
    static func restore(_ item: Item, context: ModelContext) async -> CombinedBackupService.ImportResult {
        guard let data = try? encoder.encode(item.payload) else {
            log.error("corbeille: restauration impossible, charge utile illisible")
            return CombinedBackupService.ImportResult()
        }
        let result = await CombinedBackupService.importBackup(contents: data, context: context)
        forget(id: item.id)
        return result
    }

    // MARK: - Disque

    /// Doit être appelé depuis `queue`.
    private static func loadUnsafe() -> [Item] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try Self.decoder.decode([Item].self, from: data)
        } catch {
            // Un fichier illisible ne doit pas empêcher l'app de démarrer, et
            // surtout pas empêcher une suppression. On repart d'une corbeille
            // vide : on perd une possibilité d'annuler, jamais une donnée.
            log.error("corbeille illisible, repart à vide — \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Doit être appelé depuis `queue`.
    private static func persistUnsafe(_ items: [Item]) {
        do {
            let data = try Self.encoder.encode(items)
            try FileManager.default.createDirectory(
                at: URL.applicationSupportDirectory, withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("corbeille non enregistrée — \(error.localizedDescription, privacy: .public)")
        }
    }
}
