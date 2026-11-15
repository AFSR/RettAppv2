import Foundation
import os.log

/// Les cahiers que cette app a imprimés, et ce qu'il y avait dessus.
///
/// ## Pourquoi ce fichier existe
///
/// Le `BookletSchema` d'une page n'existait **qu'à un seul endroit** : le QR
/// imprimé en haut à droite. Le générateur le construisait, le dessinait, et
/// l'oubliait. Un QR illisible — photo floue, impression pâle, cartouche en
/// fin de vie — et la feuille devenait définitivement inexploitable, alors
/// qu'une semaine entière y avait été notée à la main par l'école. Perdre
/// cette semaine signifie la ressaisir case par case, ou l'abandonner.
///
/// L'app sait pourtant ce qu'elle a imprimé. Il suffisait de le garder.
///
/// Le QR reste la voie normale : il identifie la page **sans que personne ait
/// à choisir**, et il donne en prime le repère géométrique. Ce fichier est le
/// filet quand il ne se lit pas.
///
/// ## Pourquoi un fichier et pas un modèle SwiftData
///
/// Même raison que `TrashStore`. Ajouter un `@Model` modifie le schéma du
/// magasin, et `RettAppApp` l'ouvre avec une récupération qui, en cas
/// d'échec, **efface le fichier et recommence**. On ne met pas en jeu le
/// suivi médical de chaque famille pour une commodité d'import.
enum PrintedBookletStore {

    // MARK: - Modèle

    struct Item: Codable, Identifiable, Equatable {
        let id: UUID
        let printedAt: Date
        let schema: BookletSchema

        /// Tout champ ajouté ici plus tard devra être **optionnel**. Le
        /// décodeur synthétisé de Swift échoue sur une clé absente et ne
        /// retombe pas sur la valeur par défaut d'une propriété : un champ
        /// obligatoire rendrait illisibles d'un coup tous les fichiers déjà
        /// écrits — et avec eux le repli que ce magasin existe pour offrir.
        init(id: UUID = UUID(), printedAt: Date = Date(), schema: BookletSchema) {
            self.id = id
            self.printedAt = printedAt
            self.schema = schema
        }

        /// Le titre tel qu'il est imprimé en haut de la page : c'est à lui que
        /// le parent reconnaît sa feuille, pas à une date technique. Même
        /// format que `FollowUpBookletView.defaultPeriodLabel()`.
        var libelle: String {
            guard let debut = schema.weekStartDate else { return schema.start }
            let calendrier = Calendar(identifier: .gregorian)
            let fin = calendrier.date(byAdding: .day,
                                      value: max(0, schema.days - 1),
                                      to: debut) ?? debut
            let f = DateFormatter()
            f.locale = Locale(identifier: "fr_FR")
            f.dateFormat = "d MMMM"
            return "Semaine du \(f.string(from: debut)) au \(f.string(from: fin))"
        }

        /// De quoi distinguer deux impressions de la même semaine — c'est le
        /// cas où le parent doit vraiment choisir.
        var detail: String {
            let sections = schema.includedSections.count
            let elements = [
                "\(schema.days) jours",
                sections > 1 ? "\(sections) rubriques" : "1 rubrique",
                schema.meds.isEmpty ? nil : "\(schema.meds.count) prises"
            ].compactMap { $0 }
            return elements.joined(separator: " · ")
        }
    }

    /// Six mois. Au-delà, un cahier n'a plus de raison d'être rescanné, et la
    /// liste proposée au repli deviendrait trop longue pour qu'on y reconnaisse
    /// la bonne feuille.
    static let retention: TimeInterval = 180 * 24 * 3600

    // MARK: - Interne

    private static let log = Logger(subsystem: "fr.afsr.RettApp", category: "BookletScan")
    private static let queue = DispatchQueue(label: "afsr.printedBooklets")

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
        URL.applicationSupportDirectory.appending(path: "printed_booklets.json")
    }

    // MARK: - Écriture

    /// Enregistre le schéma d'une page au moment où elle est dessinée — donc
    /// exactement ce qui part à l'impression, et non ce que les réglages
    /// disaient avant ou après.
    @discardableResult
    static func record(_ schema: BookletSchema, printedAt: Date = Date()) -> UUID {
        let nouvel = Item(printedAt: printedAt, schema: schema)
        queue.sync {
            var items = nonExpires(loadUnsafe())
            // Réimprimer la même page ne crée pas une seconde entrée : c'est
            // la même feuille, et en proposer deux au repli obligerait à
            // choisir entre deux identiques.
            items.removeAll { $0.schema == schema }
            items.append(nouvel)
            persistUnsafe(items)
        }
        return nouvel.id
    }

    /// Retire une entrée. Sert au ménage des tests, et à ne pas garder la
    /// trace d'un cahier qu'on sait ne jamais devoir rescanner.
    static func forget(id: UUID) {
        queue.sync {
            var items = loadUnsafe()
            items.removeAll { $0.id == id }
            persistUnsafe(items)
        }
    }

    // MARK: - Lecture

    /// Les cahiers imprimés non expirés, le plus récent d'abord.
    static func items() -> [Item] {
        nonExpires(queue.sync { loadUnsafe() })
            .sorted { $0.printedAt > $1.printedAt }
    }

    // MARK: - Disque

    private static func nonExpires(_ items: [Item]) -> [Item] {
        let limite = Date().addingTimeInterval(-retention)
        return items.filter { $0.printedAt > limite }
    }

    /// Doit être appelé depuis `queue`.
    private static func loadUnsafe() -> [Item] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try Self.decoder.decode([Item].self, from: data)
        } catch {
            // Un historique illisible ne doit jamais empêcher d'imprimer : on
            // repart à vide. On perd un repli, jamais une donnée.
            log.error("historique des cahiers illisible, repart à vide — \(error.localizedDescription, privacy: .public)")
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
            log.error("historique des cahiers non enregistré — \(error.localizedDescription, privacy: .public)")
        }
    }
}
