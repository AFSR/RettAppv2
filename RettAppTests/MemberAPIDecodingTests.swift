import XCTest
@testable import RettApp

/// L'application lit une API qu'on ne peut pas appeler depuis les tests. Ce
/// qui casse en vrai, ce n'est pas le réseau : c'est l'écart entre ce que le
/// site renvoie et ce que l'app attend. Ces tests figent les formes du contrat
/// (`docs/api-membre.md` côté site) pour qu'un renommage se voie ici plutôt
/// qu'en production sur un écran vide.
final class MemberAPIDecodingTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Profil

    func test_profil() throws {
        let envelope = try decode(MemberEnvelope.self, """
        {"member":{"id":"003X","first_name":"Camille","last_name":"Test","full_name":"Camille TEST",
        "email":"camille@example.org","mobile_phone":null,
        "membership":{"active":true,"end_date":"2035-01-01"},
        "address":{"street":"1 rue A","city":"Lyon","postal_code":"69001"},
        "receives_postal_mail":true}}
        """)
        XCTAssertEqual(envelope.member.firstName, "Camille")
        XCTAssertNil(envelope.member.mobilePhone)
        XCTAssertTrue(envelope.member.membership.active)
        XCTAssertEqual(envelope.member.address.postalCode, "69001")
    }

    // MARK: - Connexion

    func test_connexionReussie() throws {
        let result = try decode(LoginResult.self, """
        {"status":"authenticated","token":"abc","expires_at":"2027-02-01T00:00:00+00:00",
        "member":{"id":"1","first_name":"A","last_name":"B","full_name":"A B","email":null,"mobile_phone":null,
        "membership":{"active":false,"end_date":null},
        "address":{"street":null,"city":null,"postal_code":null},"receives_postal_mail":false}}
        """)
        XCTAssertEqual(result.status, "authenticated")
        XCTAssertEqual(result.token, "abc")
    }

    func test_connexionAvecChoixDeFiche() throws {
        let result = try decode(LoginResult.self, """
        {"status":"choose_account","selection":"s","accounts":[{"id":"1","name":"A B"},{"id":"2","name":"C D"}]}
        """)
        XCTAssertEqual(result.accounts?.count, 2)
        XCTAssertNil(result.token)
    }

    // MARK: - Adhésion

    /// RÉGRESSION À ÉVITER : « unavailable » (Salesforce n'a pas répondu) ne
    /// doit jamais être lu comme « none ». L'écran affiche deux messages
    /// différents, et le second dirait à un adhérent prélevé qu'il ne l'est pas.
    func test_renouvellementIndisponibleResteDistinctDeAucun() throws {
        let unavailable = try decode(MembershipOverview.self, overview(state: "unavailable"))
        let none = try decode(MembershipOverview.self, overview(state: "none"))
        XCTAssertEqual(unavailable.renewal.state, "unavailable")
        XCTAssertEqual(none.renewal.state, "none")
        XCTAssertNotEqual(unavailable.renewal.state, none.renewal.state)
    }

    private func overview(state: String) -> String {
        """
        {"membership":{"active":true,"end_date":"2035-01-01"},
        "renewal":{"state":"\(state)","next_payment_date":null},
        "stop_already_requested":false,"membership_url":"https://afsr.fr/nous-soutenir/adherer",
        "contact_email":"contact@afsr.fr"}
        """
    }

    // MARK: - Dons

    func test_donsAvecEtSansRecu() throws {
        let response = try decode(DonationsResponse.self, """
        {"groups":[{"contact_name":"Camille TEST","items":[
        {"id":"a1","kind":"donation","label":"Don","date":"2026-03-04","amount":50.0,"currency":"EUR",
         "nature":"numéraire","payment_type":"CB","receipt":{"number":"R-1","available":true}},
        {"id":"a2","kind":"membership","label":"Adhésion 2026","date":"2026-01-02","amount":30,"currency":"EUR",
         "nature":null,"payment_type":null,"receipt":null}]}]}
        """)
        let items = response.groups[0].items
        XCTAssertTrue(items[0].isDonation)
        XCTAssertEqual(items[0].receipt?.available, true)
        XCTAssertFalse(items[1].isDonation)
        XCTAssertNil(items[1].receipt)
        XCTAssertEqual(items[1].amount, 30)
    }

    // MARK: - Publications

    func test_publications() throws {
        let response = try decode(PublicationsResponse.self, """
        {"rett_infos":[{"slug":"ri-42","title":"RI","label":"Rett Infos n° 42","description":null,
        "issue_number":42,"issue_year":2026,"date":"2026-05-01","cover_url":null,"downloadable":true,
        "download_path":"/api/membre/publications/ri-42/telecharger"}],"documents":[]}
        """)
        XCTAssertEqual(response.rettInfos.first?.label, "Rett Infos n° 42")
        XCTAssertEqual(response.rettInfos.first?.downloadPath, "/api/membre/publications/ri-42/telecharger")
    }

    // MARK: - Dates

    /// Une date de fin d'adhésion est un jour civil : elle ne doit pas glisser
    /// d'une journée selon le fuseau de l'appareil.
    func test_dateCivileNeGlissePas() {
        let date = MemberFormat.date("2035-01-01")
        XCTAssertNotNil(date)
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(parts.year, 2035)
        XCTAssertEqual(parts.month, 1)
        XCTAssertEqual(parts.day, 1)
    }

    func test_dateIllisibleDonneNil() {
        XCTAssertNil(MemberFormat.longDate(nil))
        XCTAssertNil(MemberFormat.longDate("pas une date"))
    }

    // MARK: - Fichiers

    /// Le nom d'un fichier téléchargé vient du serveur : il ne doit jamais
    /// permettre de sortir du dossier temporaire.
    func test_nomDeFichierSansSeparateur() {
        XCTAssertFalse(MemberAPIClient.safeFileName("../../etc/passwd").contains("/"))
        XCTAssertEqual(MemberAPIClient.safeFileName(""), "document")
        XCTAssertEqual(MemberAPIClient.safeFileName(".hidden"), "document")
        XCTAssertEqual(MemberAPIClient.safeFileName("guide.pdf"), "guide.pdf")
    }
}
