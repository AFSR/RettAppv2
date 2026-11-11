import CoreLocation
import Foundation
import MapKit

// MARK: - Contrat de l'API /api/membre/lieux
//
// Voir `EstablishmentApiController` côté site. L'annuaire est public ; le texte
// des avis (`reviews`) n'est rempli que pour un adhérent à jour connecté.

struct PlaceSummary: Decodable, Identifiable, Hashable {
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
    /// Moyenne des avis publiés, `nil` sans avis. Une note fondée sur un seul
    /// avis n'est pas une note : l'écran affiche toujours `reviewCount` à côté.
    let rating: Double?
    let reviewCount: Int

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// « 12 rue X, 44000 Nantes » — ce que l'on donnerait à un chauffeur.
    var fullAddress: String {
        let town = [postalCode, city].compactMap { $0 }.joined(separator: " ")
        return [address, town.isEmpty ? nil : town].compactMap { $0 }.joined(separator: ", ")
    }

    // La liste est reconstruite à chaque filtre : l'égalité sur l'identifiant
    // évite de rafraîchir la sélection de la carte quand seule la note change.
    static func == (lhs: PlaceSummary, rhs: PlaceSummary) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct PlacesResponse: Decodable {
    let total: Int
    let establishments: [PlaceSummary]
}

struct PlaceCriterion: Decodable, Identifiable, Equatable {
    let handle: String
    let question: String
    var id: String { handle }
}

struct PlaceTypeInfo: Decodable, Identifiable, Equatable {
    let key: String
    let label: String
    let criteria: [PlaceCriterion]
    var id: String { key }
}

struct PlaceDepartment: Decodable, Identifiable, Equatable {
    let code: String
    let name: String
    var id: String { code }
}

struct PlacesMeta: Decodable, Equatable {
    let types: [PlaceTypeInfo]
    let departments: [PlaceDepartment]
}

struct PlaceFinding: Decodable, Identifiable, Equatable {
    let handle: String
    let constat: String
    let oui: Int
    let non: Int
    let total: Int
    /// « constaté par 3 adhérents sur 4 » — rédigée par le site pour ne pas
    /// travestir un décompte en statistique.
    let phrase: String
    var id: String { handle }
    /// Majoritairement confirmé : décide de l'icône, pas du texte.
    var isConfirmed: Bool { oui > non }
}

struct PlaceReview: Decodable, Identifiable, Equatable {
    let id: Int
    /// Un prénom et le département au plus — jamais un nom entier.
    let author: String
    let rating: Int
    let comment: String?
    let visitedOn: String?
    let answers: [String: String]
}

struct PlaceDetail: Decodable, Equatable {
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
    let description: String?
    let website: String?
    let phone: String?
    let reply: String?
    let replyAt: String?
    let findings: [PlaceFinding]
    let criteria: [PlaceCriterion]
    let reviewsReadable: Bool
    let reviews: [PlaceReview]

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var fullAddress: String {
        let town = [postalCode, city].compactMap { $0 }.joined(separator: " ")
        return [address, town.isEmpty ? nil : town].compactMap { $0 }.joined(separator: ", ")
    }
}

struct PlaceDetailResponse: Decodable {
    let establishment: PlaceDetail
    let myReview: MyPlaceReview?
    let canReview: Bool
}

/// Un avis de l'adhérent, avec son état de relecture.
struct MyPlaceReview: Decodable, Identifiable, Equatable {
    let id: Int
    let establishmentId: String
    let establishmentName: String?
    /// « pending », « published » ou « rejected ».
    let status: String
    let rating: Int
    let comment: String?
    let visitedOn: String?
    let answers: [String: String]
    let showArea: Bool
    /// Les questions du type de lieu, pour rouvrir le formulaire.
    let criteria: [PlaceCriterion]
    let moderationNote: String?

    var statusLabel: String {
        switch status {
        case "published": return "Publié"
        case "rejected": return "Refusé"
        default: return "En relecture"
        }
    }
}

struct MyPlaceReviewsResponse: Decodable {
    let reviews: [MyPlaceReview]
}

struct PlaceReviewSubmitResponse: Decodable {
    let review: MyPlaceReview
    let message: String
}

// MARK: - Types de lieux

enum PlaceKind {
    static func symbol(for type: String?) -> String {
        switch type {
        case "hotel": return "bed.double.fill"
        case "restaurant": return "fork.knife"
        case "hebergement": return "house.fill"
        case "loisir": return "ticket.fill"
        default: return "mappin"
        }
    }

    /// Le type du site qui correspond à une catégorie de Plans.
    ///
    /// Plans connaît des dizaines de catégories, le site cinq types : on range
    /// ce qu'on reconnaît et le reste va dans « autre ». Le choix est proposé
    /// à la personne, qui le corrige — la déduction n'est qu'un gain de temps.
    static func type(for category: MKPointOfInterestCategory?) -> String {
        guard let category else { return "autre" }
        switch category {
        case .hotel:
            return "hotel"
        case .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket:
            return "restaurant"
        case .campground:
            return "hebergement"
        case .museum, .park, .nationalPark, .zoo, .aquarium, .amusementPark, .theater,
             .movieTheater, .beach, .stadium, .library, .nightlife, .marina:
            return "loisir"
        default:
            return "autre"
        }
    }
}

// MARK: - Distance

enum PlaceDistance {
    /// « 350 m » ou « 12 km ». Le mètre sous le kilomètre : « 0 km » ne dit rien.
    static func label(_ meters: CLLocationDistance) -> String {
        if meters < 1000 { return "\(Int((meters / 10).rounded()) * 10) m" }
        if meters < 10_000 { return String(format: "%.1f km", meters / 1000).replacingOccurrences(of: ".", with: ",") }
        return "\(Int((meters / 1000).rounded())) km"
    }
}
