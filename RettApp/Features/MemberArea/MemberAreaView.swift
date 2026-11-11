import SwiftUI

/// Espace adhérent, dans l'application.
///
/// Les écrans sont ceux de l'app — barre de navigation, listes, formulaires
/// iOS, Aperçu pour les documents — et non des pages du site affichées dans
/// une vue web. Les données viennent de l'API `/api/membre` d'afsr.fr, qui
/// reste la source de vérité : l'adhésion, les droits selon qu'elle est à
/// jour, la génération des attestations fiscales. L'app les présente, elle ne
/// les recalcule pas — un adhérent voit la même chose ici et sur le site.
///
/// La connexion se fait par code reçu en SMS ou par e-mail, sans mot de passe.
/// Le jeton obtenu est rangé dans le trousseau de l'appareil.
struct MemberAreaView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Lu dans `body`, isolé sur le MainActor, et non dans un initialiseur
        // de propriété : `MemberSession` est isolée MainActor.
        let session = MemberSession.shared
        return Group {
            if !session.isSignedIn {
                MemberLoginView(session: session)
            } else if !session.isUnlocked {
                MemberLockView(session: session)
            } else {
                MemberHomeView(session: session)
            }
        }
        .animation(.default, value: session.isSignedIn)
        .animation(.default, value: session.isUnlocked)
        // Dans le sélecteur d'apps, iOS prend une capture : on la floute pour
        // que ni le nom, ni les dons, ni la famille n'y apparaissent.
        .overlay {
            if session.isUnlocked && scenePhase != .active {
                Rectangle().fill(.regularMaterial).ignoresSafeArea()
            }
        }
    }
}

/// Accueil de l'espace : la personne, son adhésion, puis les rubriques.
struct MemberHomeView: View {
    let session: MemberSession

    @State private var sections: [MemberSection] = []
    @State private var showLogoutConfirm = false

    private var isActiveMember: Bool { session.profile?.membership.active ?? false }

    var body: some View {
        List {
            headerSection
            accountSection
            contentSection
            if !sections.isEmpty { sectionsSection }
            moreSection
            privacySection
        }
        .navigationTitle("Espace adhérent")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // Verrouiller sans se déconnecter : l'espace se referme, la
                // session reste, Face ID la rouvre.
                Button {
                    session.lock()
                } label: {
                    Image(systemName: "lock.fill")
                }
                .accessibilityLabel("Verrouiller l'espace adhérent")
                .disabled(!session.hasStoredSession)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showLogoutConfirm = true
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.forward")
                }
                .accessibilityLabel("Se déconnecter")
            }
        }
        .confirmationDialog(
            "Se déconnecter de votre compte AFSR ?",
            isPresented: $showLogoutConfirm,
            titleVisibility: .visible
        ) {
            Button("Se déconnecter", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            // Lever l'ambiguïté : le compte AFSR n'a rien à voir avec les
            // données de suivi, qui vivent sur l'appareil et dans l'iCloud
            // personnel. Se déconnecter ici n'y touche pas.
            Text("Vos données de suivi ne sont pas concernées : elles restent sur cet appareil et dans votre iCloud.")
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.afsrPurpleAdaptive)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.profile?.fullName ?? "Mon compte")
                            .font(AFSRFont.headline(18))
                        if let email = session.profile?.email {
                            Text(email)
                                .font(AFSRFont.caption())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                membershipBadge
                if let notice = session.persistenceNotice {
                    Label(notice, systemImage: "lock.open.trianglebadge.exclamationmark")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.afsrWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var privacySection: some View {
        Section {
            MemberPrivacyNotice()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var membershipBadge: some View {
        if let membership = session.profile?.membership {
            let end = MemberFormat.longDate(membership.endDate)
            HStack(spacing: 6) {
                Image(systemName: membership.active ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                Text(membership.active
                     ? (end.map { "Adhésion active jusqu'au \($0)" } ?? "Adhésion active")
                     : (end.map { "Adhésion expirée depuis le \($0)" } ?? "Aucune adhésion en cours"))
                    .font(AFSRFont.caption())
            }
            .foregroundStyle(membership.active ? Color.afsrSuccess : Color.afsrWarning)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (membership.active ? Color.afsrSuccess : Color.afsrWarning).opacity(0.12),
                in: Capsule()
            )
        }
    }

    private var accountSection: some View {
        Section("Mon compte") {
            NavigationLink {
                MemberMembershipView(session: session)
            } label: {
                Label("Mon adhésion", systemImage: "checkmark.seal")
            }
            NavigationLink {
                MemberProfileView(session: session)
            } label: {
                Label("Mes informations", systemImage: "person.text.rectangle")
            }
            NavigationLink {
                MemberFamilyView(session: session)
            } label: {
                Label("Ma famille", systemImage: "person.2")
            }
            NavigationLink {
                MemberDonationsView(session: session)
            } label: {
                Label("Dons et attestations fiscales", systemImage: "gift")
            }
            NavigationLink {
                MemberPreferencesView(session: session)
            } label: {
                Label("Réception des envois", systemImage: "envelope")
            }
        }
    }

    private var contentSection: some View {
        Section {
            NavigationLink {
                MemberPublicationsView(session: session)
            } label: {
                lockableLabel("Publications AFSR", systemImage: "books.vertical", locked: !isActiveMember)
            }
            NavigationLink {
                MemberCommunicationsView(session: session)
            } label: {
                lockableLabel("Communications", systemImage: "bubble.left.and.bubble.right", locked: !isActiveMember)
            }
        } header: {
            Text("Réservé aux adhérents")
        } footer: {
            if !isActiveMember && session.profile != nil {
                Text("Ces contenus sont accessibles avec une adhésion à jour.")
            }
        }
    }

    private var sectionsSection: some View {
        Section("Rubriques") {
            ForEach(sections) { section in
                NavigationLink {
                    MemberSectionView(session: session, section: section)
                } label: {
                    lockableLabel(
                        section.title,
                        systemImage: MemberFormat.symbol(forSiteIcon: section.icon),
                        locked: section.locked
                    )
                }
            }
        }
    }

    private var moreSection: some View {
        Section {
            // L'annuaire est public. Le dépôt d'avis, lui, demande de se
            // connecter sur le site : il n'est pas encore dans l'app.
            Link(destination: URL(string: "https://afsr.fr/rett-friendly")!) {
                Label("Annuaire des lieux Rett friendly", systemImage: "mappin.and.ellipse")
            }
        } footer: {
            Text("S'ouvre sur afsr.fr. Pour déposer un avis sur un lieu, connectez-vous au site.")
        }
    }

    private func lockableLabel(_ title: String, systemImage: String, locked: Bool) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            if locked {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Réservé aux adhérents")
            }
        }
    }

    // MARK: - Chargement

    private func reload() async {
        await session.refreshProfile()
        if let response: SectionsResponse = try? await session.client.get("/rubriques") {
            sections = response.sections
        }
    }
}

#Preview {
    NavigationStack { MemberAreaView() }
}
