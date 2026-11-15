import Foundation

/// Le prénom du parent qui se sert de CET appareil.
///
/// Il sert à deux choses, et c'est la même : dire qui est qui quand deux
/// parents suivent le même enfant. Sur l'écran de partage — « Partagé avec
/// Marie » — et sur chaque entrée du journal, pour qu'on sache qui l'a notée.
///
/// Il est **demandé**, jamais deviné. Le nom du compte iCloud serait tentant,
/// mais iOS 17 ne le donne plus : `discoverUserIdentity` n'est plus servie, et
/// c'est ce qui laissait les deux parents anonymes l'un pour l'autre sans que
/// rien ne le signale.
///
/// Rangé dans les réglages de l'appareil et non en base : c'est une préférence
/// locale, et la corbeille a montré ce que coûte un changement de schéma
/// SwiftData. Il ne quitte l'appareil qu'avec le partage, c'est-à-dire vers
/// l'iCloud personnel de la famille — jamais vers un serveur de l'AFSR.
///
/// `nonisolated` et sans instance : les initialiseurs des modèles le lisent, et
/// ils tournent partout, y compris hors du MainActor.
enum ParentIdentity {

    /// La clé était celle du partage seul. Elle est conservée telle quelle :
    /// la renommer ferait perdre son prénom à chaque famille déjà installée.
    static let defaultsKey = "afsr.sharing.ownerFirstName"

    /// Le prénom tel qu'il a été saisi, ou une chaîne vide.
    static var current: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? "" }
        set {
            UserDefaults.standard.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: defaultsKey
            )
        }
    }

    /// Le prénom, ou `nil` s'il n'y en a pas. Évite de semer des chaînes vides
    /// dans les enregistrements et dans l'affichage.
    static var currentOrNil: String? {
        let nettoye = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return nettoye.isEmpty ? nil : nettoye
    }

    /// Cette entrée a-t-elle été notée par quelqu'un d'autre que moi ?
    ///
    /// Comparaison insensible à la casse et aux espaces : deux appareils d'une
    /// même famille peuvent avoir saisi « marie » et « Marie », et afficher
    /// « Marie » sur ses propres entrées serait déroutant.
    static func estUnAutre(_ auteur: String) -> Bool {
        let a = auteur.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty else { return false }
        return a.compare(current.trimmingCharacters(in: .whitespacesAndNewlines),
                         options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
    }
}
