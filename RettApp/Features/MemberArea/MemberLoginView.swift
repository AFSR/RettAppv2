import SwiftUI

/// Connexion à l'espace adhérent : un code reçu par SMS ou par e-mail, sans
/// mot de passe. Trois étapes dans le même écran — identifiant, code, et le
/// choix d'une fiche quand plusieurs partagent l'identifiant.
struct MemberLoginView: View {
    let session: MemberSession

    private enum Step: Equatable {
        case identifier
        case code(challenge: String, channel: String)
        case chooseAccount(selection: String, accounts: [MemberAccountChoice])
    }

    @State private var step: Step = .identifier
    @State private var identifier = ""
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private static let joinURL = URL(string: "https://afsr.fr/nous-soutenir/adherer")!

    var body: some View {
        Form {
            header

            if let notice = session.expiredNotice {
                Section {
                    Label(notice, systemImage: "clock.badge.exclamationmark")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.afsrWarning)
                }
            }

            switch step {
            case .identifier: identifierSection
            case .code(_, let channel): codeSection(channel: channel)
            case .chooseAccount(_, let accounts): accountSection(accounts)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.afsrEmergency)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Link(destination: Self.joinURL) {
                    Label("Pas encore adhérent ? Adhérer sur afsr.fr", systemImage: "person.badge.plus")
                }
            } footer: {
                Text("Votre compte AFSR n'a rien à voir avec vos données de suivi, qui restent sur cet appareil et dans votre iCloud.")
            }
        }
        .navigationTitle("Espace adhérent")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isWorking)
        .overlay { if isWorking { ProgressView().controlSize(.large) } }
    }

    // MARK: - Sections

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.afsrPurpleAdaptive)
                Text("Retrouvez votre adhésion, vos dons et attestations fiscales, et les publications réservées aux adhérents.")
                    .font(AFSRFont.body(15))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    private var identifierSection: some View {
        Section {
            TextField("E-mail ou mobile", text: $identifier)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.go)
                .onSubmit { Task { await requestCode() } }

            Button("Recevoir un code") { Task { await requestCode() } }
                .disabled(identifier.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Connexion")
        } footer: {
            Text("Saisissez l'adresse e-mail ou le numéro de mobile de votre compte. Nous vous envoyons un code à six chiffres.")
        }
    }

    private func codeSection(channel: String) -> some View {
        Section {
            TextField("Code à 6 chiffres", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                .onChange(of: code) { _, newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(6))
                    if digits != newValue { code = digits }
                    // Le code s'envoie seul dès que les six chiffres y sont :
                    // le remplissage automatique du SMS n'a pas de bouton à toucher.
                    if digits.count == 6 { Task { await verify() } }
                }

            Button("Renvoyer un code") { Task { await requestCode() } }
            Button("Changer d'identifiant", role: .cancel) { reset() }
        } header: {
            Text("Code de confirmation")
        } footer: {
            Text(channel == "email"
                 ? "Si un compte correspond à cette adresse, un code vient d'y être envoyé. Il est valable 10 minutes."
                 : "Si un compte correspond à ce numéro, un code vient d'être envoyé par SMS. Il est valable 10 minutes.")
        }
    }

    private func accountSection(_ accounts: [MemberAccountChoice]) -> some View {
        Section {
            ForEach(accounts) { account in
                Button {
                    Task { await choose(account) }
                } label: {
                    HStack {
                        Text(account.name).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
            }
            Button("Annuler", role: .cancel) { reset() }
        } header: {
            Text("Qui êtes-vous ?")
        } footer: {
            Text("Plusieurs fiches partagent cet identifiant. Choisissez la vôtre.")
        }
    }

    // MARK: - Actions

    private func requestCode() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let challenge = try await session.requestCode(identifier: identifier)
            code = ""
            step = .code(challenge: challenge.challenge, channel: challenge.channel)
            focused = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verify() async {
        guard case .code(let challenge, _) = step, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            if let pending = try await session.verify(challenge: challenge, code: code) {
                step = .chooseAccount(selection: pending.selection, accounts: pending.accounts)
            }
            // Sinon la session est ouverte : `MemberAreaView` change d'écran.
        } catch {
            errorMessage = error.localizedDescription
            code = ""
        }
    }

    private func choose(_ account: MemberAccountChoice) async {
        guard case .chooseAccount(let selection, _) = step else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await session.chooseAccount(selection: selection, account: account.id)
        } catch {
            errorMessage = error.localizedDescription
            // Une sélection est à usage unique : en cas d'échec il faut repartir de zéro.
            step = .identifier
        }
    }

    private func reset() {
        step = .identifier
        code = ""
        errorMessage = nil
    }
}
