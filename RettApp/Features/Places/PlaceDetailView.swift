import MapKit
import SwiftUI

/// La fiche d'un lieu.
///
/// L'ordre des sections n'est pas décoratif : il suit ce dont une famille a
/// besoin dans l'ordre où elle en a besoin. D'abord **y aller** — l'itinéraire
/// et le téléphone, c'est-à-dire ce qu'on cherche sur un trottoir, une
/// poussette à la main. Ensuite **les constats**, les faits qui décident d'une
/// réservation : savoir qu'il faudra changer sa fille par terre tranche, une
/// note sur 5 ne tranche rien. Les avis rédigés viennent après, et la note
/// ensuite : elle ne porte que sur l'accueil ressenti.
struct PlaceDetailView: View {
    let session: MemberSession
    let slug: String
    let nom: String

    @State private var formulaire: FormulaireDemande?
    @State private var retrait: MyPlaceReview?

    /// Ce qu'il faut pour rouvrir le formulaire : le lieu, et l'avis à
    /// modifier s'il y en a un.
    struct FormulaireDemande: Identifiable {
        let lieuID: String
        let nom: String
        let sousTitre: String
        let criteres: [PlaceCriterion]
        let existant: MyPlaceReview?

        var id: String { (existant?.id).map(String.init) ?? lieuID }
    }

    var body: some View {
        MemberResourceView<PlaceDetailResponse, AnyView>(
            session: session,
            path: "/lieux/\(slug)"
        ) { reponse, recharger in
            AnyView(
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        entete(reponse.establishment)
                        actions(reponse.establishment)
                        constats(reponse.establishment)
                        presentation(reponse.establishment)
                        reponseEtablissement(reponse.establishment)
                        monAvis(reponse, recharger: recharger)
                        avis(reponse.establishment)
                    }
                    .padding(16)
                }
                .background(Color.afsrBackground)
                .sheet(item: $formulaire) { demande in
                    NavigationStack {
                        PlaceReviewSheet(
                            session: session,
                            place: .init(
                                establishmentID: demande.lieuID,
                                name: demande.nom,
                                subtitle: demande.sousTitre,
                                criteria: demande.criteres,
                                proposal: nil
                            ),
                            existing: demande.existant
                        ) {
                            await recharger()
                        }
                    }
                }
                .confirmationDialog(
                    "Retirer mon avis ?",
                    isPresented: .init(get: { retrait != nil }, set: { if !$0 { retrait = nil } }),
                    titleVisibility: .visible
                ) {
                    Button("Retirer", role: .destructive) {
                        if let avis = retrait {
                            Task {
                                await retirer(avis, recharger: recharger)
                            }
                        }
                    }
                    Button("Annuler", role: .cancel) { retrait = nil }
                } message: {
                    Text("Votre témoignage ne sera plus visible. Vous pourrez en déposer un nouveau.")
                }
            )
        }
        .navigationTitle(nom)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private func entete(_ lieu: PlaceDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lieu.name)
                .font(AFSRFont.headline(22))

            Text([lieu.typeLabel, lieu.postalLine].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)

            PlaceRatingView(rating: lieu.rating, count: lieu.reviewCount)
                .padding(.top, 2)
        }
    }

    /// Y aller, appeler, ouvrir le site. En haut, parce que c'est ce qu'on
    /// cherche quand on est déjà en route.
    private func actions(_ lieu: PlaceDetail) -> some View {
        HStack(spacing: 10) {
            Button {
                itineraire(vers: lieu)
            } label: {
                Label("Itinéraire", systemImage: "arrow.triangle.turn.up.right.diamond")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if let telephone = lieu.phone, let url = URL(string: "tel:\(telephone.filter { !$0.isWhitespace })") {
                Link(destination: url) {
                    Label("Appeler", systemImage: "phone")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if let site = lieu.website, let url = URL(string: site) {
                Link(destination: url) {
                    Label("Site", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .labelStyle(.titleAndIcon)
        .font(AFSRFont.body())
    }

    @ViewBuilder
    private func constats(_ lieu: PlaceDetail) -> some View {
        if !lieu.findings.isEmpty {
            SectionCard(title: "Ce que les adhérents ont constaté") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(lieu.findings) { constat in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: constat.mostlyPresent ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(constat.mostlyPresent ? Color.afsrSuccess : Color.afsrEmergency)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(constat.constat)
                                    .font(AFSRFont.body())
                                Text(constat.phrase)
                                    .font(AFSRFont.caption())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }

                    Text("Ce sont des constats rapportés par des familles, pas une vérification de l'association.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func presentation(_ lieu: PlaceDetail) -> some View {
        if let description = lieu.description, !description.isEmpty {
            SectionCard(title: "Le lieu") {
                MemberHTMLText(html: description)
            }
        }
    }

    /// La réponse de l'établissement. Elle compte : un commerce dont on
    /// relate l'accueil doit pouvoir répondre, et le lecteur doit le voir.
    @ViewBuilder
    private func reponseEtablissement(_ lieu: PlaceDetail) -> some View {
        if let reponse = lieu.reply, !reponse.isEmpty {
            SectionCard(title: "La réponse de l'établissement") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(reponse).font(AFSRFont.body())
                    if let date = MemberFormat.longDate(lieu.replyAt) {
                        Text(date).font(AFSRFont.caption()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func monAvis(_ reponse: PlaceDetailResponse, recharger: @escaping () async -> Void) -> some View {
        if let mien = reponse.myReview {
            SectionCard(title: "Mon avis") {
                VStack(alignment: .leading, spacing: 12) {
                    MyReviewStatusBadge(state: mien.state)

                    if let note = mien.moderationNote, mien.state == .rejected {
                        Text(note)
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }

                    if let commentaire = mien.comment, !commentaire.isEmpty {
                        Text(commentaire).font(AFSRFont.body())
                    }

                    HStack(spacing: 10) {
                        Button {
                            formulaire = FormulaireDemande(
                                lieuID: reponse.establishment.id,
                                nom: reponse.establishment.name,
                                sousTitre: Self.sousTitre(reponse.establishment),
                                criteres: mien.criteria.isEmpty ? reponse.establishment.criteria : mien.criteria,
                                existant: mien
                            )
                        } label: {
                            Label("Modifier", systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            retrait = mien
                        } label: {
                            Label("Retirer", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(AFSRFont.body())

                    Text("Un avis modifié repasse en relecture avant d'être publié.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                }
            }
        } else if reponse.canReview {
            Button {
                formulaire = FormulaireDemande(
                    lieuID: reponse.establishment.id,
                    nom: reponse.establishment.name,
                    sousTitre: Self.sousTitre(reponse.establishment),
                    criteres: reponse.establishment.criteria,
                    existant: nil
                )
            } label: {
                Label("Donner mon avis sur ce lieu", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func avis(_ lieu: PlaceDetail) -> some View {
        if !lieu.reviewsReadable {
            SectionCard(title: "Les témoignages") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Réservés aux adhérents à jour", systemImage: "lock")
                        .font(AFSRFont.body())
                    Text("Les notes et les constats sont publics. Le texte des témoignages, lui, reste entre adhérents : c'est là qu'une famille raconte son séjour.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                }
            }
        } else if !lieu.reviews.isEmpty {
            SectionCard(title: lieu.reviews.count == 1 ? "1 témoignage" : "\(lieu.reviews.count) témoignages") {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(lieu.reviews) { avis in
                        PlaceReviewRow(avis: avis)
                        if avis.id != lieu.reviews.last?.id { Divider() }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    /// Ouvre l'itinéraire dans Plans.
    ///
    /// Avec les coordonnées quand la fiche en porte — c'est le plus fiable. À
    /// défaut, une recherche sur le nom et l'adresse : mieux vaut un plan
    /// approximatif que pas de plan.
    private func itineraire(vers lieu: PlaceDetail) {
        if let coordonnees = lieu.coordinate {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordonnees))
            item.name = lieu.name
            item.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
            ])
            return
        }

        let recherche = [lieu.name, lieu.postalLine].filter { !$0.isEmpty }.joined(separator: ", ")
        guard
            let encode = recherche.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "http://maps.apple.com/?q=\(encode)")
        else { return }

        UIApplication.shared.open(url)
    }

    private static func sousTitre(_ lieu: PlaceDetail) -> String {
        [lieu.typeLabel, lieu.city].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func retirer(_ avis: MyPlaceReview, recharger: @escaping () async -> Void) async {
        retrait = nil
        struct Vide: Decodable { let status: String? }
        let _: Vide? = try? await session.client.post("/avis/\(avis.id)/retirer")
        await recharger()
    }
}

// MARK: - Pièces

struct MyReviewStatusBadge: View {
    let state: MyPlaceReview.State

    var body: some View {
        Label(state.label, systemImage: state.systemImage)
            .font(AFSRFont.caption())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(couleur.opacity(0.15), in: Capsule())
            .foregroundStyle(couleur)
    }

    private var couleur: Color {
        switch state {
        case .pending: return .afsrWarning
        case .published: return .afsrSuccess
        case .rejected: return .afsrEmergency
        }
    }
}

struct PlaceReviewRow: View {
    let avis: PlaceReview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(avis.author)
                    .font(AFSRFont.headline(15))
                Spacer(minLength: 0)
                PlaceRatingView(rating: Double(avis.rating), count: 1)
            }

            if let mois = PlaceFormat.month(avis.visitedOn) {
                Text("Visite en \(mois)")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
            }

            if let commentaire = avis.comment, !commentaire.isEmpty {
                Text(commentaire).font(AFSRFont.body())
            }
        }
    }
}

/// Les dates propres aux lieux.
enum PlaceFormat {
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static let display: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f
    }()

    /// « août 2026 » depuis « 2026-08 ».
    ///
    /// Un mois, et non une date : la saisie ne porte pas le jour, et
    /// l'afficher comme « 1er août » inventerait une précision que personne
    /// n'a donnée.
    static func month(_ raw: String?) -> String? {
        guard let raw, let date = parser.date(from: raw) else { return nil }
        return display.string(from: date)
    }
}
