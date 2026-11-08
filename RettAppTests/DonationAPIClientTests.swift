import XCTest
@testable import RettApp

/// Ce que l'app dit au donateur selon ce que le serveur répond.
///
/// Deux confusions seraient graves. Dire « c'est bon » après un refus —
/// quelqu'un croirait avoir donné. Et dire « échec » après un débit réussi —
/// quelqu'un croirait n'avoir rien donné, et recommencerait.
final class DonationAPIClientTests: XCTestCase {

    private func body(_ json: String) -> Data { Data(json.utf8) }

    // MARK: - Paiement pris

    /// Le site répond 202 : le paiement est encaissé, l'écriture dans
    /// Salesforce suit côté serveur. Pour le donateur, c'est un succès.
    func test_202_estUnSucces() {
        XCTAssertEqual(
            DonationAPIClient.outcome(status: 202, body: body(#"{"status":"accepted"}"#)),
            .accepted
        )
    }

    func test_200_estAussiUnSucces() {
        XCTAssertEqual(DonationAPIClient.outcome(status: 200, body: body("{}")), .accepted)
    }

    // MARK: - Refus

    func test_402_ditQueRienNAEteDebite() {
        let resultat = DonationAPIClient.outcome(
            status: 402,
            body: body(#"{"status":"payment_failed","message":"Le paiement n'a pas abouti. Vous n'avez pas été débité."}"#)
        )
        guard case .paymentRefused(let message) = resultat else {
            return XCTFail("un refus de paiement n'est pas une erreur serveur")
        }
        XCTAssertTrue(message.contains("pas été débité"))
    }

    func test_402_sansMessage_aUnTexteParDefautRassurant() {
        guard case .paymentRefused(let message) = DonationAPIClient.outcome(status: 402, body: body("{}")) else {
            return XCTFail("attendu : refus")
        }
        XCTAssertTrue(message.contains("débité"), "le donateur doit savoir qu'il n'a rien payé")
    }

    // MARK: - Erreurs de configuration

    /// Jeton absent ou route inexistante : l'utilisateur n'y peut rien, et le
    /// détail technique ne lui apprendrait rien.
    func test_401_et_404_restentDiscrets() {
        for code in [401, 404] {
            guard case .serverError(let message) = DonationAPIClient.outcome(status: code, body: body("{}")) else {
                return XCTFail("code \(code) : attendu une erreur serveur")
            }
            XCTAssertFalse(message.lowercased().contains("jeton"), "ne pas exposer la cause technique")
            XCTAssertFalse(message.lowercased().contains("404"))
        }
    }

    func test_422_remonteLeMessageDeValidation() {
        guard case .serverError(let message) = DonationAPIClient.outcome(
            status: 422, body: body(#"{"message":"Le code postal est invalide."}"#)
        ) else { return XCTFail("attendu : erreur serveur") }
        XCTAssertEqual(message, "Le code postal est invalide.")
    }

    func test_500_aUnMessageParDefaut() {
        guard case .serverError(let message) = DonationAPIClient.outcome(status: 500, body: body("")) else {
            return XCTFail("attendu : erreur serveur")
        }
        XCTAssertFalse(message.isEmpty)
    }

    // MARK: - Complétude du donateur

    /// L'attestation fiscale porte une identité et une adresse : sans elles
    /// elle n'est pas émettable.
    func test_donateurIncomplet_estDetecte() {
        var donateur = DonationAPIClient.Donor(
            firstName: "Camille", lastName: "Martin", email: "c@example.org",
            address: "1 rue des Lilas", addressComplement: "", postalCode: "75001", city: "Paris"
        )
        XCTAssertTrue(donateur.isComplete)

        donateur.postalCode = "   "
        XCTAssertFalse(donateur.isComplete, "un champ d'espaces n'est pas rempli")

        donateur.postalCode = "75001"
        donateur.addressComplement = ""
        XCTAssertTrue(donateur.isComplete, "le complément d'adresse reste facultatif")
    }
}
