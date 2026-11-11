import CoreLocation
import XCTest
@testable import RettApp

/// L'annuaire des lieux, côté app : la forme du contrat servi par le site, et
/// les petites règles qu'une erreur rendrait invisibles — une note sans le
/// nombre d'avis qui la fonde, une recherche qui rate les accents, un texte
/// d'avis absent qu'on prendrait pour une absence d'avis.
///
/// Portés depuis la branche `claude/eager-pascal-nz59mz` (PR #63), où une
/// autre session avait construit l'annuaire en parallèle. Son implémentation
/// n'a pas été retenue — celle de `main` était déjà alignée sur l'épingle, les
/// extensions du client HTTP et la politique de confidentialité corrigée — mais
/// ses tests couvraient précisément ce qui n'était gardé par rien ici.
///
/// Deux de ses six tests n'ont pas été portés, et ce n'est pas un oubli :
/// `test_categoriePlansVersTypeDuSite` et `test_distanceLisible` éprouvent une
/// correspondance entre catégories de Plans et types du site, et un formatage
/// de distance. Ni l'une ni l'autre n'existe dans cette implémentation, qui ne
/// fait pas de recherche de points d'intérêt et n'affiche aucune distance : les
/// porter aurait demandé d'ajouter du code que personne n'appelle.
final class PlacesTests: XCTestCase {

    /// Le même décodeur que `MemberAPIClient`. S'en écarter ferait passer des
    /// tests sur un contrat que l'application n'utilise pas.
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Le contrat de l'annuaire

    func test_la_liste_decode_et_distingue_les_lieux_sans_position() throws {
        let reponse = try decode(PlaceListResponse.self, """
        {"total":2,"establishments":[
        {"id":"a","slug":"hotel-atlantique-x1","name":"Hôtel Atlantique","type":"hotel","type_label":"Hôtel",
         "address":"1 quai","postal_code":"44000","city":"Nantes","country":"France","department":"Loire-Atlantique",
         "latitude":47.2184,"longitude":-1.5536,"rating":4.5,"review_count":3},
        {"id":"b","slug":"creperie-y2","name":"Crêperie","type":"restaurant","type_label":"Restaurant",
         "address":null,"postal_code":null,"city":"Quiberon","country":null,"department":null,
         "latitude":null,"longitude":null,"rating":null,"review_count":0}]}
        """)

        XCTAssertEqual(reponse.total, 2)
        XCTAssertEqual(reponse.establishments.count, 2)

        let situe = reponse.establishments[0]
        XCTAssertNotNil(situe.coordinate)
        XCTAssertTrue(situe.hasCoordinates)
        XCTAssertEqual(situe.postalLine, "1 quai, 44000 Nantes")

        // Une fiche sans coordonnées existe dans l'annuaire : elle n'a
        // simplement pas de point sur la carte. L'écarter de la liste la
        // ferait croire disparue.
        let nonSitue = reponse.establishments[1]
        XCTAssertNil(nonSitue.coordinate)
        XCTAssertFalse(nonSitue.hasCoordinates)
        XCTAssertEqual(nonSitue.postalLine, "Quiberon")
    }

    func test_une_note_sans_avis_n_est_pas_une_note_de_zero() throws {
        let reponse = try decode(PlaceListResponse.self, """
        {"total":1,"establishments":[
        {"id":"b","slug":"s","name":"Crêperie","type":"restaurant","type_label":"Restaurant",
         "address":null,"postal_code":null,"city":"Quiberon","country":null,"department":null,
         "latitude":null,"longitude":null,"rating":null,"review_count":0}]}
        """)

        // `rating` nul et non zéro : une absence de témoignage n'est pas un
        // mauvais accueil, et c'est exactement ce qu'un « 0 / 5 » laisserait
        // croire. L'écran s'appuie sur cette distinction.
        XCTAssertNil(reponse.establishments[0].rating)
        XCTAssertEqual(reponse.establishments[0].reviewCount, 0)
    }

    // MARK: - La fiche

    func test_la_fiche_dit_pourquoi_les_temoignages_sont_absents() throws {
        let reponse = try decode(PlaceDetailResponse.self, """
        {"establishment":{"id":"a","slug":"s","name":"N","type":"hotel","type_label":"Hôtel","address":null,
        "postal_code":null,"city":"Nantes","country":null,"department":null,"latitude":null,"longitude":null,
        "rating":5.0,"review_count":1,"description":null,"website":null,"phone":null,"reply":null,"reply_at":null,
        "findings":[{"handle":"acces_plain_pied","constat":"Accès sans marche","oui":1,"non":0,"total":1,
                     "phrase":"constaté par 1 adhérent"}],
        "criteria":[{"handle":"acces_plain_pied","question":"Entrer sans marche, en fauteuil roulant"}],
        "reviews_readable":false,"reviews":[]},
        "my_review":null,"can_review":false}
        """)

        // La liste d'avis est vide ET le texte est fermé : l'écran doit pouvoir
        // expliquer « réservé aux adhérents à jour » au lieu d'afficher
        // « aucun avis », qui serait faux — le compte dit qu'il y en a un.
        XCTAssertFalse(reponse.establishment.reviewsReadable)
        XCTAssertTrue(reponse.establishment.reviews.isEmpty)
        XCTAssertEqual(reponse.establishment.reviewCount, 1)

        // Pas d'adhésion à jour : l'écran ne propose pas de déposer un avis.
        XCTAssertFalse(reponse.canReview)
        XCTAssertNil(reponse.myReview)

        let constat = reponse.establishment.findings[0]
        XCTAssertTrue(constat.mostlyPresent)
        XCTAssertEqual(constat.phrase, "constaté par 1 adhérent")
        XCTAssertEqual(reponse.establishment.criteria.first?.handle, "acces_plain_pied")
    }

    func test_un_constat_majoritairement_absent_n_est_pas_confirme() throws {
        let constat = try decode(PlaceFinding.self, """
        {"handle":"wc_adaptes","constat":"Toilettes adaptées","oui":1,"non":3,"total":4,
         "phrase":"constaté par 1 adhérent sur 4"}
        """)

        // `mostlyPresent` commande la coche verte ou la croix rouge sur la
        // fiche. Inversée, elle annoncerait accessible un lieu que trois
        // familles sur quatre ont trouvé inaccessible.
        XCTAssertFalse(constat.mostlyPresent)
    }

    // MARK: - Mes avis

    func test_mon_avis_porte_son_etat_de_moderation() throws {
        let avis = try decode(MyPlaceReview.self, """
        {"id":7,"establishment_id":"a","establishment_name":"N","status":"pending","rating":4,"comment":null,
         "visited_on":"2026-05","answers":{"acces_plain_pied":"oui"},"show_area":false,"criteria":[],
         "moderation_note":null}
        """)

        // Rien ne se publie avant relecture : l'écran « Mes avis » existe pour
        // que l'adhérent le voie, et ne redépose pas son témoignage en croyant
        // l'avoir perdu.
        XCTAssertEqual(avis.state, .pending)
        XCTAssertEqual(avis.state.label, "En relecture")
        XCTAssertEqual(avis.answers["acces_plain_pied"], "oui")
        // En minuscule : en français un mois ne se capitalise pas, et la fiche
        // l'affiche dans « Visite en mai 2026 ».
        XCTAssertEqual(PlaceFormat.month(avis.visitedOn), "mai 2026")
    }

    func test_un_avis_ecarte_porte_son_motif() throws {
        let avis = try decode(MyPlaceReview.self, """
        {"id":8,"establishment_id":"a","establishment_name":"N","status":"rejected","rating":2,
         "comment":"Un texte","visited_on":null,"answers":{},"show_area":true,"criteria":[],
         "moderation_note":"Le texte nomme un membre du personnel."}
        """)

        // Le motif d'un refus est dû à son auteur : c'est la seule chose qui
        // lui permette de corriger plutôt que de recommencer à l'identique.
        XCTAssertEqual(avis.state, .rejected)
        XCTAssertEqual(avis.state.label, "Écarté")
        XCTAssertEqual(avis.moderationNote, "Le texte nomme un membre du personnel.")
    }

    func test_un_etat_inconnu_du_serveur_ne_fait_pas_disparaitre_l_avis() throws {
        let avis = try decode(MyPlaceReview.self, """
        {"id":9,"establishment_id":"a","establishment_name":"N","status":"archived","rating":3,"comment":null,
         "visited_on":null,"answers":{},"show_area":false,"criteria":[],"moderation_note":null}
        """)

        // Le site pourrait ajouter un état. On retombe sur « en relecture »
        // plutôt que d'échouer au décodage : un état inattendu ne doit pas
        // faire disparaître la liste entière de l'écran.
        XCTAssertEqual(avis.state, .pending)
    }

    // MARK: - La recherche locale

    func test_la_recherche_ignore_les_accents_et_la_casse() {
        XCTAssertEqual(PlacesStore.fold("  Crêperie DU Port "), "creperie du port")

        // Le cas qui a motivé ce pli : « localizedCaseInsensitiveContains »
        // ignore la casse mais pas les diacritiques, si bien que « creperie »
        // ne trouvait pas « Crêperie » — et une recherche qui ne trouve rien
        // ressemble à un annuaire vide.
        XCTAssertTrue(PlacesStore.fold("Crêperie du Port").contains(PlacesStore.fold("creperie")))
        XCTAssertTrue(PlacesStore.fold("Hôtel de Nantes").contains(PlacesStore.fold("hotel")))
        XCTAssertTrue(PlacesStore.fold("Gîte des Noues").contains(PlacesStore.fold("GITE")))
    }

    // MARK: - Le brouillon envoyé au serveur

    func test_une_reponse_inconnue_ne_part_pas_dans_les_criteres() {
        var brouillon = PlaceReviewDraft()
        brouillon.mode = .existant
        brouillon.establishmentID = "a"
        brouillon.rating = 4
        brouillon.engagement = true
        brouillon.answers = ["acces_plain_pied": "oui", "wc_adaptes": "non"]

        let charge = brouillon.payload()

        XCTAssertEqual(charge.criteres, ["acces_plain_pied": "oui", "wc_adaptes": "non"])
        // Les champs du lieu proposé ne partent pas sur un lieu existant :
        // l'encodeur omet les valeurs nulles, et la validation du site ne les
        // exige que dans l'autre mode.
        XCTAssertNil(charge.name)
        XCTAssertNil(charge.city)
        XCTAssertNil(charge.latitude)
        XCTAssertEqual(charge.establishmentID, "a")
    }

    func test_un_lieu_propose_emporte_son_point_et_pas_son_identifiant() {
        var brouillon = PlaceReviewDraft()
        brouillon.mode = .nouveau
        brouillon.name = "  Camping des essais  "
        brouillon.establishmentType = "hebergement"
        brouillon.city = "Pornic"
        brouillon.latitude = 47.11
        brouillon.longitude = -2.10
        brouillon.rating = 5
        brouillon.engagement = true

        let charge = brouillon.payload()

        XCTAssertNil(charge.establishmentID)
        XCTAssertEqual(charge.name, "Camping des essais")
        XCTAssertEqual(charge.city, "Pornic")
        XCTAssertEqual(charge.latitude, 47.11)
        XCTAssertEqual(charge.longitude, -2.10)
        // Non renseigné reste absent plutôt que vide : une chaîne vide serait
        // lue comme une saisie par la validation du site.
        XCTAssertNil(charge.website)
    }
}
