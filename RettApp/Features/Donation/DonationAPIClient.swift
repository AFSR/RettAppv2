import Foundation

/// Envoi d'un don à afsr.fr.
///
/// L'app ne débite pas et n'écrit pas dans Salesforce : elle n'en a ni les
/// clés ni le droit. Elle présente Apple Pay, obtient un jeton de paiement,
/// et le transmet ici. Le site débite via Stripe puis crée la commande dans
/// Salesforce, qui reste la base de référence.
///
/// Une réponse positive signifie **« paiement accepté »**, pas « don
/// enregistré ». L'enregistrement est déclenché par le webhook Stripe,
/// réessayé jusqu'à trois jours s'il échoue. L'app n'a donc pas à l'attendre,
/// et surtout ne doit pas prétendre le connaître.
struct DonationAPIClient {

    /// Hôte de l'association. Le jeton applicatif, lui, n'est pas un secret :
    /// il est forcément dans le binaire. Ce qui protège réellement est côté
    /// serveur — montants bornés, clé Stripe jamais embarquée, limitation de
    /// débit.
    static let endpoint = URL(string: "https://afsr.fr/api/mobile/contribution")!

    /// À renseigner avec la valeur déclarée dans le `.env` du site
    /// (`AFSR_APP_API_TOKEN`). Vide, le site répond 404.
    static var appToken: String = ""

    struct Donor: Equatable {
        var firstName: String = ""
        var lastName: String = ""
        var email: String = ""
        var address: String = ""
        var addressComplement: String = ""
        var postalCode: String = ""
        var city: String = ""

        /// L'attestation fiscale porte une identité et une adresse postale :
        /// sans elles elle n'est pas émettable. D'où l'exigence, qui n'est
        /// pas une coquetterie de formulaire.
        var isComplete: Bool {
            ![firstName, lastName, email, address, postalCode, city]
                .contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    enum Outcome: Equatable {
        /// Paiement pris. L'enregistrement suit, côté serveur.
        case accepted
        /// Refusé par la banque ou Stripe. Rien n'a été débité.
        case paymentRefused(String)
        /// Le site n'a pas pu traiter la demande.
        case serverError(String)
        case network(String)
    }

    /// `paymentToken` est le jeton produit par Apple Pay puis tokenisé avec
    /// la clé publiable Stripe. Il est à usage unique et ne vaut rien sans la
    /// clé secrète, qui ne quitte pas le serveur.
    func send(
        amountCents: Int,
        donor: Donor,
        paymentToken: String,
        session: URLSession = .shared
    ) async -> Outcome {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(Self.appToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "kind": "don",
            "amount_cents": amountCents,
            "payment_token": paymentToken,
            "first_name": donor.firstName,
            "last_name": donor.lastName,
            "email": donor.email,
            "address": donor.address,
            "address_complement": donor.addressComplement,
            "postal_code": donor.postalCode,
            "city": donor.city,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            return .network("Réponse inattendue du serveur.")
        }

        return Self.outcome(status: http.statusCode, body: data)
    }

    /// Séparé de l'envoi pour être testable sans réseau : c'est la
    /// correspondance entre codes HTTP et message affiché qui compte, et
    /// elle est facile à casser sans s'en apercevoir.
    static func outcome(status: Int, body: Data) -> Outcome {
        let message = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])
            .flatMap { $0?["message"] as? String }

        switch status {
        case 200, 202:
            return .accepted
        case 402:
            return .paymentRefused(message ?? "Le paiement n'a pas abouti. Vous n'avez pas été débité.")
        case 401, 404:
            // Jeton absent ou route inexistante : une erreur de configuration,
            // que l'utilisateur ne peut pas corriger. On ne lui montre pas le
            // détail, qui ne lui apprendrait rien.
            return .serverError("Le don n'est pas disponible pour le moment.")
        case 422:
            return .serverError(message ?? "Certaines informations sont incomplètes.")
        default:
            return .serverError(message ?? "Le service de don est momentanément indisponible.")
        }
    }
}
