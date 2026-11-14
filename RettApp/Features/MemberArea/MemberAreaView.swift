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

    /// Les destinations de l'espace adhérent, poussées **par valeur**.
    ///
    /// Ce n'était pas le cas, et c'est ce qui cassait l'ouverture des lieux.
    /// Avec `NavigationLink { Destination() }`, l'identité de la destination
    /// tient à la place du lien dans la liste. Or cette liste se réorganise
    /// toute seule : `reload()` arrive après l'affichage et insère la section
    /// « Rubriques » **au-dessus** de « Lieux Rett friendly ». Un écran poussé
    /// juste avant était alors dépilé — on touchait la ligne, et on revenait
    /// aussitôt d'où l'on venait.
    ///
    /// Poussée par valeur, la destination ne dépend plus de la forme de la
    /// liste. Elle survit au rechargement des rubriques.
    private enum Destination: Hashable {
        case adhesion, informations, famille, dons, preferences
        case publications, communications
        case rubrique(MemberSection)
        case lieux, mesAvis
    }

    var body: some View {
        List {
            headerSection
            accountSection
            contentSection
            if !sections.isEmpty { sectionsSection }
            moreSection
            privacySection
        }
        .afsrListBackground()
        .navigationDestination(for: Destination.self) { destination in
            switch destination {
            case .adhesion:       MemberMembershipView(session: session)
            case .informations:   MemberProfileView(session: session)
            case .famille:        MemberFamilyView(session: session)
            case .dons:           MemberDonationsView(session: session)
            case .preferences:    MemberPreferencesView(session: session)
            case .publications:   MemberPublicationsView(session: session)
            case .communications: MemberCommunicationsView(session: session)
            case .rubrique(let section): MemberSectionView(session: session, section: section)
            case .lieux:          PlacesDirectoryView(session: session)
            case .mesAvis:        MyPlaceReviewsView(session: session)
            }
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
                HStack(spacing: 14) {
                    AFSRAvatar(name: session.profile?.fullName ?? "", size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.profile?.fullName ?? "Mon compte")
                            .font(AFSRFont.headline(19))
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
            NavigationLink(value: Destination.adhesion) {
                AFSRRowLabel(title: "Mon adhésion", systemImage: "checkmark.seal.fill", color: .afsrSuccess)
            }
            NavigationLink(value: Destination.informations) {
                AFSRRowLabel(title: "Mes informations", systemImage: "person.text.rectangle.fill", color: .afsrPurple)
            }
            NavigationLink(value: Destination.famille) {
                AFSRRowLabel(title: "Ma famille", systemImage: "person.2.fill", color: Color(hex: "#3949AB"))
            }
            NavigationLink(value: Destination.dons) {
                AFSRRowLabel(title: "Dons et attestations fiscales", systemImage: "gift.fill", color: .afsrEmergency)
            }
            NavigationLink(value: Destination.preferences) {
                AFSRRowLabel(title: "Réception des envois", systemImage: "envelope.fill", color: Color(hex: "#1E88E5"))
            }
        }
    }

    private var contentSection: some View {
        Section {
            NavigationLink(value: Destination.publications) {
                lockableLabel("Publications AFSR", systemImage: "books.vertical", locked: !isActiveMember)
            }
            NavigationLink(value: Destination.communications) {
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
                NavigationLink(value: Destination.rubrique(section)) {
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
            // L'annuaire et le dépôt d'avis sont désormais dans l'app : plus
            // de détour par Safari, où il fallait se reconnecter au site.
            NavigationLink(value: Destination.lieux) {
                AFSRRowLabel(title: "Lieux Rett friendly",
                             systemImage: "mappin.and.ellipse",
                             color: Color(hex: "#00897B"),
                             subtitle: "Chercher un lieu qui accueille bien, sur une carte ou dans la liste")
            }

            NavigationLink(value: Destination.mesAvis) {
                AFSRRowLabel(title: "Mes avis sur les lieux",
                             systemImage: "text.bubble",
                             color: Color(hex: "#00897B"),
                             subtitle: "Ce que j'ai déposé, et où ça en est")
            }
        } footer: {
            Text("L'annuaire se construit par les familles. Un lieu proposé, comme un avis déposé, paraît après relecture par l'association.")
        }
    }

    private func lockableLabel(_ title: String, systemImage: String, locked: Bool) -> some View {
        HStack {
            AFSRRowLabel(title: title, systemImage: systemImage,
                         color: locked ? Color(hex: "#8E8E93") : .afsrPurpleLight)
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
