import MapKit
import XCTest
@testable import RettApp

/// L'annuaire des lieux, côté app : la forme du contrat, le filtrage local, et
/// les petites règles qu'une erreur rendrait invisibles (une note sans le
/// nombre d'avis, une recherche qui rate les accents).
final class PlacesTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Contrat

    func test_listeDesLieux() throws {
        let response = try decode(PlacesResponse.self, """
        {"total":2,"establishments":[
        {"id":"a","slug":"hotel-atlantique-x1","name":"Hôtel Atlantique","type":"hotel","type_label":"Hôtel",
         "address":"1 quai","postal_code":"44000","city":"Nantes","country":"France","department":"Loire-Atlantique",
         "latitude":47.2184,"longitude":-1.5536,"rating":4.5,"review_count":3},
        {"id":"b","slug":"creperie-y2","name":"Crêperie","type":"restaurant","type_label":"Restaurant",
         "address":null,"postal_code":null,"city":"Quiberon","country":null,"department":null,
         "latitude":null,"longitude":null,"rating":null,"review_count":0}]}
        """)
        XCTAssertEqual(response.establishments.count, 2)
        XCTAssertNotNil(response.establishments[0].coordinate)
        // Une fiche sans position existe dans l'annuaire : elle n'a juste pas de repère.
        XCTAssertNil(response.establishments[1].coordinate)
        XCTAssertEqual(response.establishments[0].fullAddress, "1 quai, 44000 Nantes")
    }

    func test_ficheAvecAvisFermes() throws {
        let response = try decode(PlaceDetailResponse.self, """
        {"establishment":{"id":"a","slug":"s","name":"N","type":"hotel","type_label":"Hôtel","address":null,
        "postal_code":null,"city":"Nantes","country":null,"department":null,"latitude":null,"longitude":null,
        "rating":5.0,"review_count":1,"description":null,"website":null,"phone":null,"reply":null,"reply_at":null,
        "findings":[{"handle":"acces","constat":"Accès sans marche","oui":1,"non":0,"total":1,"phrase":"constaté par 1 adhérent"}],
        "criteria":[{"handle":"acces","question":"Entrer sans marche"}],
        "reviews_readable":false,"reviews":[]},
        "my_review":null,"can_review":false}
        """)
        // Le texte des avis est réservé aux adhérents : l'écran doit le savoir
        // pour expliquer pourquoi la liste est vide plutôt que dire « aucun avis ».
        XCTAssertFalse(response.establishment.reviewsReadable)
        XCTAssertTrue(response.establishment.findings[0].isConfirmed)
        XCTAssertFalse(response.canReview)
    }

    func test_monAvisPorteSonEtat() throws {
        let review = try decode(MyPlaceReview.self, """
        {"id":7,"establishment_id":"a","establishment_name":"N","status":"pending","rating":4,"comment":null,
        "visited_on":"2026-05","answers":{"acces":"oui"},"show_area":false,"criteria":[],"moderation_note":null}
        """)
        XCTAssertEqual(review.statusLabel, "En relecture")
        XCTAssertEqual(review.answers["acces"], "oui")
    }

    // MARK: - Recherche

    func test_rechercheSansAccentsNiCasse() {
        XCTAssertEqual(PlacesStore.fold("  Crêperie DU Port "), "creperie du port")
        XCTAssertTrue(PlacesStore.fold("Hôtel de Nantes").contains(PlacesStore.fold("hotel")))
    }

    // MARK: - Types

    func test_categoriePlansVersTypeDuSite() {
        XCTAssertEqual(PlaceKind.type(for: .hotel), "hotel")
        XCTAssertEqual(PlaceKind.type(for: .restaurant), "restaurant")
        XCTAssertEqual(PlaceKind.type(for: .museum), "loisir")
        XCTAssertEqual(PlaceKind.type(for: .campground), "hebergement")
        // Ce qu'on ne reconnaît pas — et l'absence de catégorie — va dans « autre ».
        XCTAssertEqual(PlaceKind.type(for: .atm), "autre")
        XCTAssertEqual(PlaceKind.type(for: nil), "autre")
    }

    // MARK: - Distance

    func test_distanceLisible() {
        XCTAssertEqual(PlaceDistance.label(350), "350 m")
        XCTAssertEqual(PlaceDistance.label(2_400), "2,4 km")
        XCTAssertEqual(PlaceDistance.label(48_000), "48 km")
    }
}
