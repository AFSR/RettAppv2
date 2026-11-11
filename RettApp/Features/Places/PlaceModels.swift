import Foundation

/// Les lieux Rett friendly, tels que l'API de l'espace adhérent les sert.
///
/// Rien n'est codé en dur ici : ni les types de lieu, ni les critères
/// d'accessibilité, ni leurs libellés. Ils viennent de `/lieux/meta` et des
/// fiches elles-mêmes. C'est volontaire — l'association ajoute un critère
/// quand l'usage le demande, et une application qui en gardait sa propre liste
/// poserait des questions qui ne sont plus celles du site, ou enverrait des
/// réponses à un critère retiré.
///
/// Le décodeur du client applique `convertFromSnakeCase` : les clés JSON
/// `type_label`, `review_count`, `reviews_readable` arrivent donc en
/// `typeLabel`, `reviewCount`, `reviewsReadable`.

// MARK: - Référentiel

struct PlaceMeta: Decodable {
    let types: [PlaceType]
    let departments: [PlaceDepartment]
}

struct PlaceType: Decodable, Identifiable, Hashable {
    let key: String
    let label: String
    /// Les critères qu'on pose pour ce type. On ne demande pas à un restaurant
    /// s'il y a une prise près du lit.
    let criteria: [PlaceCriterion]

    var id: String { key }
}

struct PlaceDepartment: Decodable, Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }
}

struct PlaceCriterion: Decodable, Identifiable, Hashable {
    let handle: String
    /// La formulation posée à l'adhérent : « Entrer sans marche, en fauteuil ».
    let question: String

    var id: String { handle }
}

// MARK: - L'annuaire

struct PlaceListResponse: Decodable {
    /// Le total de l'annuaire, pour dire « 12 lieux sur 148 » après un filtre
    /// au lieu d'un nombre sans repère.
    let total: Int
    let establishments: [Place]
}

struct Place: Decodable, Identifiable, Hashable {
    let id: String
    let slug: String
    let name: String
    let type: String?
    let typeLabel: String
    let address: String?
    let postalCode: String?
    let city: String?
    let country: String?
    let department: String?

    /// Nuls quand la fiche n'a pas été géocodée. Un tel lieu existe : il n'a
    /// simplement pas de point sur la carte, et la liste le garde.
    let latitude: Double?
    let longitude: Double?

    /// La note moyenne de l'accueil, sur 5. Nulle sans aucun avis publié —
    /// afficher 0 laisserait croire à un mauvais accueil plutôt qu'à une
    /// absence de témoignage.
    let rating: Double?
    let reviewCount: Int

    var hasCoordinates: Bool { latitude != nil && longitude != nil }

    /// « 12 rue des Lilas, 44000 Nantes », sans les virgules des champs vides.
    var postalLine: String {
        [address, [postalCode, city].compactMap(\.self).joined(separator: " ")]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: ", ")
    }

    /// Ce qu'on montre sous le nom dans une liste : le type, puis la ville.
    var subtitle: String {
        [typeLabel, city].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - La fiche

struct PlaceDetailResponse: Decodable {
    let establishment: PlaceDetail
    /// Mon propre avis, quel que soit son état : c'est ce qui permet de
    /// proposer « Modifier mon avis » au lieu d'ouvrir un formulaire que
    /// l'enregistrement refuserait.
    let myReview: MyPlaceReview?
    let canReview: Bool
}

struct PlaceDetail: Decodable, Identifiable {
    let id: String
    let slug: String
    let name: String
    let type: String?
    let typeLabel: String
    let address: String?
    let postalCode: String?
    let city: String?
    let country: String?
    let department: String?
    let latitude: Double?
    let longitude: Double?
    let rating: Double?
    let reviewCount: Int

    /// Présentation du lieu, en HTML, saisie par l'association.
    let description: String?
    let website: String?
    let phone: String?

    /// La réponse de l'établissement, s'il en a donné une. Elle compte : un
    /// commerce dont on relate l'accueil doit pouvoir répondre.
    let reply: String?
    let replyAt: String?

    /// Les constats, avec la phrase qui les restitue sans les travestir
    /// (« constaté par 2 adhérents sur 3 »). La phrase vient du serveur :
    /// deux implémentations de cette règle de langue ne la tiendraient pas
    /// pareil.
    let findings: [PlaceFinding]

    /// Les critères posés pour ce type de lieu, pour le formulaire.
    let criteria: [PlaceCriterion]

    let reviewsReadable: Bool
    let reviews: [PlaceReview]

    var hasCoordinates: Bool { latitude != nil && longitude != nil }

    var postalLine: String {
        [address, [postalCode, city].compactMap(\.self).joined(separator: " ")]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: ", ")
    }
}

struct PlaceFinding: Decodable, Identifiable, Hashable {
    let handle: String
    /// Le constat tel qu'il se lit sur la fiche : « Accès sans marche ».
    let constat: String
    let oui: Int
    let non: Int
    let total: Int
    let phrase: String

    var id: String { handle }

    /// Vrai quand les adhérents sont majoritairement d'accord que c'est là.
    var mostlyPresent: Bool { oui > non }
}

struct PlaceReview: Decodable, Identifiable, Hashable {
    let id: Int
    /// Un prénom, et un département au plus. Jamais davantage.
    let author: String
    let rating: Int
    let comment: String?
    /// Un mois, « 2026-08 » : le jour exact n'intéresse personne, et un séjour
    /// se situe dans un mois.
    let visitedOn: String?
    let answers: [String: String]
}

// MARK: - Mes avis

struct MyPlaceReviewsResponse: Decodable {
    let reviews: [MyPlaceReview]
}

struct MyPlaceReview: Decodable, Identifiable, Hashable {
    let id: Int
    let establishmentId: String
    let establishmentName: String
    let status: String
    let rating: Int
    let comment: String?
    let visitedOn: String?
    let answers: [String: String]
    let showArea: Bool
    let criteria: [PlaceCriterion]
    /// Le motif d'un refus. L'association doit pouvoir l'expliquer à l'auteur,
    /// et l'auteur doit pouvoir le lire.
    let moderationNote: String?

    enum State: String {
        case pending
        case published
        case rejected
    }

    var state: State { State(rawValue: status) ?? .pending }
}

extension MyPlaceReview.State {
    var label: String {
        switch self {
        case .pending: return "En relecture"
        case .published: return "En ligne"
        case .rejected: return "Écarté"
        }
    }

    var systemImage: String {
        switch self {
        case .pending: return "clock"
        case .published: return "checkmark.seal"
        case .rejected: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Dépôt

/// Ce qu'on envoie pour déposer ou modifier un avis.
///
/// Les clés sont celles du formulaire du site, parce que c'est le même
/// `FormRequest` qui les valide de l'autre côté. Les renommer ici casserait le
/// dépôt sans qu'aucun test de l'application ne s'en aperçoive.
struct PlaceReviewDraft {
    enum Mode: String {
        case existant
        case nouveau
    }

    var mode: Mode = .existant
    var establishmentID: String?

    // Pour un lieu proposé.
    var name: String = ""
    var establishmentType: String?
    var address: String = ""
    var postalCode: String = ""
    var city: String = ""
    var country: String = ""
    var website: String = ""

    var rating: Int = 0
    /// Les réponses aux critères : « oui », « non », ou absent quand on ne
    /// sait pas. L'absence est une réponse en soi, et le serveur écarte
    /// d'ailleurs tout ce qui n'est ni oui ni non.
    var answers: [String: String] = [:]
    var comment: String = ""
    /// Le mois de la visite, « 2026-08 ».
    var visitedOn: String?
    var showArea: Bool = false
    var engagement: Bool = false

    /// Le corps envoyé au serveur.
    ///
    /// Les champs du lieu proposé ne partent qu'en mode « nouveau » : nuls,
    /// l'encodeur les omet, et la validation ne les voit pas — ce qui est
    /// exactement ce qu'on veut, puisqu'ils ne sont exigés que dans ce mode.
    struct Payload: Encodable {
        let mode: String
        let establishmentID: String?
        let name: String?
        let establishmentType: String?
        let address: String?
        let postalCode: String?
        let city: String?
        let country: String?
        let website: String?
        let rating: Int
        /// L'objet `handle → « oui » | « non »`. Imbriqué, parce que le
        /// serveur attend un tableau.
        let criteres: [String: String]
        let comment: String?
        let visitedOn: String?
        let showArea: Bool
        let engagement: Bool

        /// Les clés sont celles du formulaire du site : c'est le même
        /// `FormRequest` qui les valide de l'autre côté, et les renommer ici
        /// casserait le dépôt sans qu'aucun test de l'application ne s'en
        /// aperçoive.
        enum CodingKeys: String, CodingKey {
            case mode
            case establishmentID = "establishment_id"
            case name
            case establishmentType = "establishment_type"
            case address
            case postalCode = "postal_code"
            case city
            case country
            case website
            case rating
            case criteres
            case comment
            case visitedOn = "visited_on"
            case showArea = "show_area"
            case engagement
        }
    }

    func payload() -> Payload {
        let nouveau = mode == .nouveau

        return Payload(
            mode: mode.rawValue,
            establishmentID: nouveau ? nil : establishmentID,
            name: nouveau ? Self.propre(name) : nil,
            establishmentType: nouveau ? establishmentType : nil,
            address: nouveau ? Self.propre(address) : nil,
            postalCode: nouveau ? Self.propre(postalCode) : nil,
            city: nouveau ? Self.propre(city) : nil,
            country: nouveau ? Self.propre(country) : nil,
            website: nouveau ? Self.propre(website) : nil,
            rating: rating,
            criteres: answers,
            comment: Self.propre(comment),
            visitedOn: visitedOn,
            showArea: showArea,
            engagement: engagement
        )
    }

    /// Une chaîne débarrassée de ses espaces, ou rien du tout si elle est vide.
    private static func propre(_ valeur: String) -> String? {
        let net = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
        return net.isEmpty ? nil : net
    }
}

struct PlaceReviewSubmissionResponse: Decodable {
    let review: MyPlaceReview?
    let message: String?
}
