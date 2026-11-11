import SwiftUI

// MARK: - Mon adhésion

struct MemberMembershipView: View {
    let session: MemberSession

    var body: some View {
        MemberResourceView<MembershipOverview, MembershipContent>(session: session, path: "/adhesion") { overview, reload in
            MembershipContent(session: session, overview: overview, reload: reload)
        }
        .navigationTitle("Mon adhésion")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MembershipContent: View {
    let session: MemberSession
    let overview: MembershipOverview
    let reload: () async -> Void

    @State private var showStopConfirm = false
    @State private var isSending = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    private var membership: MemberMembership { overview.membership }
    private var endDate: String? { MemberFormat.longDate(membership.endDate) }

    var body: some View {
        List {
            Section("Statut de l'adhésion") {
                if membership.active {
                    Label(endDate.map { "Adhésion active, jusqu'au \($0)." } ?? "Adhésion active.",
                          systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.afsrSuccess)
                } else if let endDate {
                    Label("Adhésion expirée depuis le \(endDate).", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.afsrWarning)
                } else {
                    Label("Aucune adhésion en cours.", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.afsrWarning)
                }
            }

            renewalSection

            if let resultMessage {
                Section { Label(resultMessage, systemImage: "checkmark.circle.fill").foregroundStyle(.afsrSuccess) }
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.afsrEmergency) }
            }
        }
        .refreshable { await reload() }
        .confirmationDialog(
            "Demander l'arrêt du renouvellement automatique ?",
            isPresented: $showStopConfirm,
            titleVisibility: .visible
        ) {
            Button("Demander l'arrêt", role: .destructive) { Task { await requestStop() } }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("L'association s'en charge auprès de notre prestataire de paiement. Votre adhésion reste valable jusqu'à son terme.")
        }
    }

    @ViewBuilder
    private var renewalSection: some View {
        let renewal = overview.renewal
        Section("Renouvellement automatique") {
            switch renewal.state {
            case "unavailable":
                // Le site n'a pas pu vérifier. Annoncer « aucun renouvellement »
                // à quelqu'un qui est peut-être prélevé serait le pire des messages.
                Text("Nous ne parvenons pas à afficher l'état de votre renouvellement automatique.")
                if let mail = URL(string: "mailto:\(overview.contactEmail)") {
                    Link("Écrire à \(overview.contactEmail)", destination: mail)
                }

            case "active":
                Label(
                    MemberFormat.longDate(renewal.nextPaymentDate).map { "Actif. Prochain prélèvement le \($0)." } ?? "Actif.",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                if overview.stopAlreadyRequested {
                    Text("Votre demande d'arrêt nous est parvenue. L'association la transmet à notre prestataire de paiement. Si une échéance est imminente, prévenez-nous directement.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Votre adhésion se renouvelle d'elle-même à chaque échéance. Vous pouvez demander son arrêt.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                    Button("Demander l'arrêt du renouvellement", role: .destructive) { showStopConfirm = true }
                        .disabled(isSending)
                }

            default:
                Text("Aucun renouvellement automatique en cours.")
                Text(membership.active
                     ? "Votre adhésion ne se renouvelle pas d'elle-même : elle prendra fin à son terme, sauf si vous la renouvelez. Sur le formulaire, choisissez le renouvellement automatique pour ne plus avoir à y penser."
                     : "Votre adhésion n'est plus active. En adhérant de nouveau, vous pouvez choisir le renouvellement automatique sur le formulaire.")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                if let url = URL(string: overview.membershipUrl) {
                    Link(membership.active ? "Renouveler mon adhésion" : "Adhérer", destination: url)
                }
            }
        }
    }

    private func requestStop() async {
        isSending = true
        resultMessage = nil
        errorMessage = nil
        defer { isSending = false }
        do {
            let result: StopRequestResult = try await session.client.post("/adhesion/renouvellement/arret")
            resultMessage = result.message
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Mes informations

struct MemberProfileView: View {
    let session: MemberSession

    var body: some View {
        Group {
            if let profile = session.profile {
                ProfileForm(session: session, profile: profile)
            } else {
                ProgressView("Chargement…")
                    .task { await session.refreshProfile() }
            }
        }
        .navigationTitle("Mes informations")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProfileForm: View {
    let session: MemberSession
    let profile: MemberProfile

    @State private var firstName: String
    @State private var lastName: String
    @State private var email: String
    @State private var mobile: String
    @State private var street: String
    @State private var city: String
    @State private var postalCode: String

    @State private var savingSection: String?
    @State private var fieldErrors: [String: String] = [:]
    @State private var message: String?
    @State private var errorMessage: String?

    init(session: MemberSession, profile: MemberProfile) {
        self.session = session
        self.profile = profile
        _firstName = State(initialValue: profile.firstName)
        _lastName = State(initialValue: profile.lastName)
        _email = State(initialValue: profile.email ?? "")
        _mobile = State(initialValue: profile.mobilePhone ?? "")
        _street = State(initialValue: profile.address.street ?? "")
        _city = State(initialValue: profile.address.city ?? "")
        _postalCode = State(initialValue: profile.address.postalCode ?? "")
    }

    var body: some View {
        Form {
            Section {
                field("Prénom", text: $firstName, key: "FirstName", content: .givenName)
                field("Nom", text: $lastName, key: "LastName", content: .familyName)
                field("E-mail", text: $email, key: "Email", content: .emailAddress, keyboard: .emailAddress)
                field("Mobile", text: $mobile, key: "MobilePhone", content: .telephoneNumber, keyboard: .phonePad)
                Button("Enregistrer mes coordonnées") { Task { await saveContact() } }
                    .disabled(savingSection != nil || firstName.isEmpty || lastName.isEmpty || email.isEmpty)
            } header: {
                Text("Coordonnées")
            } footer: {
                Text("Votre e-mail et votre mobile servent aussi à vous connecter à votre compte.")
            }

            Section {
                field("Adresse", text: $street, key: "BillingStreet", content: .streetAddressLine1)
                field("Code postal", text: $postalCode, key: "BillingPostalCode", content: .postalCode, keyboard: .numberPad)
                field("Ville", text: $city, key: "BillingCity", content: .addressCity)
                Button("Enregistrer mon adresse") { Task { await saveAddress() } }
                    .disabled(savingSection != nil || street.isEmpty || city.isEmpty || postalCode.isEmpty)
            } header: {
                Text("Adresse")
            } footer: {
                Text("L'adresse est partagée par le foyer. Elle figure sur vos attestations fiscales.")
            }

            if let message {
                Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.afsrSuccess) }
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.afsrEmergency) }
            }
        }
        .disabled(savingSection != nil)
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        key: String,
        content: UITextContentType,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: text)
                .textContentType(content)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled(keyboard == .emailAddress)
            if let error = fieldErrors[key] {
                Text(error)
                    .font(AFSRFont.caption())
                    .foregroundStyle(.afsrEmergency)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func saveContact() async {
        await save(section: "contact", path: "/moi", body: [
            "FirstName": firstName.trimmingCharacters(in: .whitespaces),
            "LastName": lastName.trimmingCharacters(in: .whitespaces),
            "Email": email.trimmingCharacters(in: .whitespaces),
            "MobilePhone": mobile.trimmingCharacters(in: .whitespaces)
        ], success: "Vos coordonnées ont bien été enregistrées.")
    }

    private func saveAddress() async {
        await save(section: "address", path: "/moi/adresse", body: [
            "BillingStreet": street.trimmingCharacters(in: .whitespaces),
            "BillingCity": city.trimmingCharacters(in: .whitespaces),
            "BillingPostalCode": postalCode.trimmingCharacters(in: .whitespaces)
        ], success: "Votre adresse a bien été enregistrée.")
    }

    private func save(section: String, path: String, body: [String: String], success: String) async {
        savingSection = section
        message = nil
        errorMessage = nil
        fieldErrors = [:]
        defer { savingSection = nil }
        do {
            let envelope: MemberEnvelope = try await session.client.post(path, body: body)
            session.update(profile: envelope.member)
            message = success
        } catch let MemberAPIError.validation(summary, fields) {
            fieldErrors = fields
            if fields.isEmpty { errorMessage = summary }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Ma famille

struct MemberFamilyView: View {
    let session: MemberSession

    var body: some View {
        MemberResourceView<FamilyResponse, FamilyContent>(session: session, path: "/famille") { response, reload in
            FamilyContent(members: response.members, reload: reload)
        }
        .navigationTitle("Ma famille")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FamilyContent: View {
    let members: [FamilyMember]
    let reload: () async -> Void

    var body: some View {
        List {
            if members.isEmpty {
                ContentUnavailableView(
                    "Aucun membre trouvé",
                    systemImage: "person.2",
                    description: Text("Nous n'avons pas retrouvé les membres de votre famille. Si vous pensez qu'il s'agit d'une erreur, contactez l'AFSR.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(members) { member in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(member.firstName) \(member.lastName)")
                            .font(AFSRFont.headline(16))
                        Spacer()
                        Text(member.role ?? "Rôle non défini")
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }
                    if let email = member.email {
                        Text(email).font(AFSRFont.caption()).foregroundStyle(.secondary)
                    }
                    if let phone = member.phone {
                        Text(phone).font(AFSRFont.caption()).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .refreshable { await reload() }
    }
}

// MARK: - Dons et attestations

struct MemberDonationsView: View {
    let session: MemberSession
    @State private var opener = MemberDocumentOpener()

    var body: some View {
        MemberResourceView<DonationsResponse, DonationsContent>(session: session, path: "/dons") { response, reload in
            DonationsContent(session: session, opener: opener, groups: response.groups, reload: reload)
        }
        .navigationTitle("Dons et attestations")
        .navigationBarTitleDisplayMode(.inline)
        .memberDocumentPreview(opener)
    }
}

private struct DonationsContent: View {
    let session: MemberSession
    let opener: MemberDocumentOpener
    let groups: [DonationGroup]
    let reload: () async -> Void

    var body: some View {
        List {
            if groups.isEmpty {
                ContentUnavailableView(
                    "Aucun don retrouvé",
                    systemImage: "gift",
                    description: Text("Nous n'avons retrouvé aucun don sur votre compte. Si vous pensez qu'il s'agit d'une erreur, contactez l'AFSR pour retrouver votre don et obtenir votre reçu fiscal.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                Section("Dons et adhésion de \(group.contactName)") {
                    ForEach(Array(group.items.enumerated()), id: \.offset) { _, line in
                        row(line)
                    }
                }
            }
        }
        .refreshable { await reload() }
    }

    private func row(_ line: DonationLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(line.isDonation ? "Don" : "Adhésion",
                      systemImage: line.isDonation ? "heart.fill" : "checkmark.seal.fill")
                    .font(AFSRFont.caption())
                    .foregroundStyle(line.isDonation ? Color.afsrEmergency : Color.afsrPurpleAdaptive)
                Spacer()
                Text(MemberFormat.amount(line.amount, currency: line.currency))
                    .font(AFSRFont.headline(16))
            }
            Text(line.label).font(AFSRFont.body(15))
            Text(detail(line))
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)

            if let receipt = line.receipt {
                if receipt.available {
                    Button {
                        Task {
                            await opener.open(
                                key: line.id,
                                path: "/api/membre/dons/\(line.id)/attestation",
                                fallbackName: "attestation-\(receipt.number).pdf",
                                using: session
                            )
                        }
                    } label: {
                        HStack {
                            Label("Attestation fiscale", systemImage: "doc.richtext")
                            if opener.busyKey == line.id { ProgressView() }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(opener.busyKey != nil)
                } else {
                    Label("Contactez l'AFSR pour l'attestation fiscale", systemImage: "envelope")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                }
                Text("Reçu n° \(receipt.number)")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func detail(_ line: DonationLine) -> String {
        var parts: [String] = []
        if let date = MemberFormat.longDate(line.date) { parts.append(date) }
        if line.isDonation, let nature = line.nature { parts.append("en \(nature)") }
        if let payment = line.paymentType { parts.append("par \(payment)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Réception des envois

struct MemberPreferencesView: View {
    let session: MemberSession

    var body: some View {
        MemberResourceView<PreferencesResponse, PreferencesContent>(session: session, path: "/preferences") { response, reload in
            PreferencesContent(session: session, current: response.format, reload: reload)
        }
        .navigationTitle("Réception des envois")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PreferencesContent: View {
    let session: MemberSession
    let current: String
    let reload: () async -> Void

    @State private var selection: String
    @State private var isSaving = false
    @State private var message: String?
    @State private var errorMessage: String?

    init(session: MemberSession, current: String, reload: @escaping () async -> Void) {
        self.session = session
        self.current = current
        self.reload = reload
        _selection = State(initialValue: current)
    }

    var body: some View {
        Form {
            Section {
                Picker("Format", selection: $selection) {
                    Text("Papier et e-mail").tag("paper_and_email")
                    Text("E-mail uniquement").tag("email_only")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Comment souhaitez-vous recevoir les envois de l'association ?")
                    .textCase(nil)
            } footer: {
                Text("Ce choix vaut consentement : il indique par quel canal l'association peut vous joindre.")
            }

            Section {
                Button("Enregistrer") { Task { await save() } }
                    .disabled(isSaving || selection == current)
            }

            if let message {
                Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.afsrSuccess) }
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.afsrEmergency) }
            }
        }
    }

    private func save() async {
        isSaving = true
        message = nil
        errorMessage = nil
        defer { isSaving = false }
        do {
            let _: PreferencesResponse = try await session.client.post("/preferences", body: ["format": selection])
            message = "Votre préférence de réception a bien été enregistrée."
            await session.refreshProfile()
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
