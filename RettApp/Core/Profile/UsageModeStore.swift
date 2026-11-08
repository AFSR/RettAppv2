import Foundation
import Observation

/// Usage de l'application : l'app complète, ou le sous-ensemble destiné à
/// qui ne suit pas d'enfant.
///
/// ⚠️ À ne pas confondre avec `DeviceRole` (parent / enfant), qui répond à une
/// tout autre question : « sur quel iPhone cette copie est-elle installée ? »,
/// et ne sert qu'à savoir où lire Apple Santé. Deux notions voisines nommées
/// « mode » dans les réglages seraient incompréhensibles, d'où le choix de
/// vocabulaire : **usage** ici, **rôle de l'appareil** là-bas. En usage
/// « découverte », la question du rôle d'appareil ne se pose jamais et
/// n'apparaît pas.
enum AppUsage: String, CaseIterable, Identifiable, Codable {
    /// L'app complète : journal, plan médicamenteux, bilan, documents,
    /// partage entre parents — plus tout ce que l'usage découverte propose.
    case suivi

    /// Le sous-ensemble : actualités de l'AFSR, information sur la maladie et
    /// la recherche, espace adhérent, don. Ce qui ne sert pas n'apparaît pas :
    /// pas d'onglet vide, pas de menu grisé, pas d'avertissement médical à
    /// accepter pour lire une actualité.
    case decouverte

    var id: String { rawValue }

    var label: String {
        switch self {
        case .suivi:      return "Je suis les soins d'un enfant"
        case .decouverte: return "Je découvre l'AFSR"
        }
    }

    var detailedLabel: String {
        switch self {
        case .suivi:
            return "Journal quotidien, plan médicamenteux, bilan, documents pour le médecin et l'école, partage avec l'autre parent. Vous accédez aussi aux actualités et à l'espace adhérent."
        case .decouverte:
            return "Actualités de l'association, information sur le syndrome de Rett, espace adhérent et soutien. Vous pourrez créer un suivi plus tard si besoin."
        }
    }

    var systemImage: String {
        switch self {
        case .suivi:      return "heart.text.square.fill"
        case .decouverte: return "sparkles"
        }
    }
}

/// Mémorise l'usage choisi, localement. Aucun effet sur le schéma SwiftData
/// ni sur CloudKit : c'est une préférence d'affichage de cet appareil.
@Observable
@MainActor
final class UsageModeStore {
    static let shared = UsageModeStore()

    static let key = "RettApp.appUsage.v1"

    private let defaults: UserDefaults

    /// `nil` tant que la question n'a jamais été posée. C'est ce qui déclenche
    /// l'écran de choix au premier lancement — et uniquement là.
    private(set) var usage: AppUsage?

    /// `defaults` est injectable pour les tests ; l'app passe toujours par
    /// `shared`, qui utilise `UserDefaults.standard`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.key) {
            usage = AppUsage(rawValue: raw)
        }
    }

    func set(_ newValue: AppUsage) {
        usage = newValue
        defaults.set(newValue.rawValue, forKey: Self.key)
    }

    /// Enregistre l'usage « suivi » sans repasser par la question, pour un
    /// utilisateur qui a déjà un profil enfant.
    ///
    /// Indispensable à la migration depuis les versions antérieures : sans
    /// cela, une famille qui met à jour verrait apparaître une question
    /// inédite alors qu'elle utilise l'app depuis des mois. Idempotent.
    func adoptSuiviIfUnset() {
        guard usage == nil else { return }
        set(.suivi)
    }

    /// Bascule de découverte vers suivi. L'inverse n'existe pas : on ne
    /// « redevient » pas découverte, on efface ses données (voir Réglages →
    /// Mes données). Laisser une bascule retour laisserait croire que le
    /// suivi se met en veille, alors qu'il resterait en base et continuerait
    /// de se synchroniser.
    func startSuivi() {
        set(.suivi)
    }
}
