import Foundation

// MARK: - Contrat de l'API /api/membre
//
// Ces types suivent `docs/api-membre.md` du dépôt AFSR/website. Les clés
// arrivent en snake_case et sont lues avec `.convertFromSnakeCase`. Les dates
// sont des chaînes « AAAA-MM-JJ » : on les garde telles quelles et on ne les
// convertit qu'à l'affichage (voir `MemberFormat`), pour qu'un jour de fin
// d'adhésion ne glisse jamais d'une journée selon le fuseau de l'appareil.

struct MemberProfile: Decodable, Equatable {
    let id: String
    let firstName: String
    let lastName: String
    let fullName: String
    let email: String?
    let mobilePhone: String?
    let membership: MemberMembership
    let address: MemberAddress
    let receivesPostalMail: Bool
}

struct MemberMembership: Decodable, Equatable {
    let active: Bool
    let endDate: String?
}

struct MemberAddress: Decodable, Equatable {
    let street: String?
    let city: String?
    let postalCode: String?
}

struct MemberEnvelope: Decodable {
    let member: MemberProfile
}

// MARK: - Connexion

struct LoginChallenge: Decodable {
    let challenge: String
    /// « sms » ou « email » : décide du libellé de l'étape suivante.
    let channel: String
    let message: String
}

struct MemberAccountChoice: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
}

/// Réponse des deux dernières étapes de connexion. Un seul type pour les deux
/// issues possibles : `status` dit laquelle des deux a eu lieu.
struct LoginResult: Decodable {
    let status: String
    let token: String?
    /// Second secret, qui ne sert qu'à détruire le jeton côté site.
    let revokeToken: String?
    let member: MemberProfile?
    let selection: String?
    let accounts: [MemberAccountChoice]?
}

// MARK: - Adhésion

struct MembershipOverview: Decodable {
    let membership: MemberMembership
    let renewal: Renewal
    let stopAlreadyRequested: Bool
    let membershipUrl: String
    let contactEmail: String

    struct Renewal: Decodable {
        /// « active », « none » ou « unavailable ».
        ///
        /// « unavailable » veut dire que le site n'a pas pu interroger
        /// Salesforce : on ne sait PAS si la personne est prélevée. Ne
        /// jamais l'afficher comme « aucun renouvellement ».
        let state: String
        let nextPaymentDate: String?
    }
}

struct StopRequestResult: Decodable {
    let status: String
    let message: String
}

// MARK: - Famille, dons

struct FamilyResponse: Decodable {
    let members: [FamilyMember]
}

struct FamilyMember: Decodable, Identifiable, Equatable {
    let id: String
    let firstName: String
    let lastName: String
    let email: String?
    let phone: String?
    let role: String?
}

struct DonationsResponse: Decodable {
    let groups: [DonationGroup]
}

struct DonationGroup: Decodable {
    let contactName: String
    let items: [DonationLine]
}

struct DonationLine: Decodable {
    let id: String
    /// « donation » ou « membership ».
    let kind: String
    let label: String
    let date: String?
    let amount: Double
    let currency: String
    let nature: String?
    let paymentType: String?
    let receipt: Receipt?

    struct Receipt: Decodable {
        let number: String
        /// Faux pour un reçu à zéro euro : il existe, mais l'association le
        /// délivre à la main.
        let available: Bool
    }

    var isDonation: Bool { kind == "donation" }
}

// MARK: - Contenus réservés

struct PublicationsResponse: Decodable {
    let rettInfos: [MemberPublication]
    let documents: [MemberPublication]
}

struct MemberPublication: Decodable, Identifiable, Equatable {
    let slug: String
    let title: String
    let label: String
    let description: String?
    let issueNumber: Int?
    let issueYear: Int?
    let date: String?
    let coverUrl: String?
    let downloadable: Bool
    let downloadPath: String?

    var id: String { slug }
}

struct CommunicationsResponse: Decodable {
    let communications: [MemberCommunication]
}

struct MemberCommunication: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let date: String?
    let html: String
    let logoUrl: String?
}

struct SectionsResponse: Decodable {
    let sections: [MemberSection]
}

struct MemberSection: Decodable, Identifiable, Equatable {
    let slug: String
    let title: String
    let icon: String
    let introduction: String?
    let locked: Bool

    var id: String { slug }
}

struct SectionDetailResponse: Decodable {
    let section: Detail

    struct Detail: Decodable {
        let slug: String
        let title: String
        let introduction: String?
        let html: String?
        let files: [File]
    }

    struct File: Decodable, Identifiable, Equatable {
        let name: String
        let size: Int?
        let index: Int

        var id: Int { index }
    }
}

struct PreferencesResponse: Decodable {
    /// « paper_and_email » ou « email_only ».
    let format: String
}
