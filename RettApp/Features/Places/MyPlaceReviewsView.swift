import SwiftUI

/// Les avis que j'ai déposés, et où ils en sont.
///
/// Cet écran existe pour une raison simple : sans lui, déposer un avis
/// ressemble à le perdre. Rien ne se publie avant relecture, donc rien
/// n'apparaît sur la fiche dans l'heure — et un adhérent qui ne voit pas son
/// témoignage le redépose, ou croit que l'application l'a mangé. Ici, il voit
/// « en relecture », et il sait.
struct MyPlaceReviewsView: View {
    let session: MemberSession

    var body: some View {
        MemberResourceView<MyPlaceReviewsResponse, AnyView>(
            session: session,
            path: "/mes-avis"
        ) { reponse, _ in
            AnyView(contenu(reponse))
        }
        .navigationTitle("Mes avis sur les lieux")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func contenu(_ reponse: MyPlaceReviewsResponse) -> some View {
        if reponse.reviews.isEmpty {
            ContentUnavailableView {
                Label("Aucun avis déposé", systemImage: "text.bubble")
            } description: {
                Text("L'annuaire se construit par les familles : le lieu que vous avez trouvé accueillant n'y figurera que si quelqu'un le dit.")
            }
        } else {
            List {
                ForEach(reponse.reviews) { avis in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(avis.establishmentName)
                                .font(AFSRFont.headline(16))
                            Spacer(minLength: 8)
                            MyReviewStatusBadge(state: avis.state)
                        }

                        PlaceRatingView(rating: Double(avis.rating), count: 1)

                        if let mois = PlaceFormat.month(avis.visitedOn) {
                            Text("Visite en \(mois)")
                                .font(AFSRFont.caption())
                                .foregroundStyle(.secondary)
                        }

                        if let commentaire = avis.comment, !commentaire.isEmpty {
                            Text(commentaire)
                                .font(AFSRFont.body())
                                .lineLimit(4)
                        }

                        // Le motif d'un refus se lit ici, et nulle part
                        // ailleurs : c'est à son auteur qu'il est dû.
                        if avis.state == .rejected, let note = avis.moderationNote, !note.isEmpty {
                            Text(note)
                                .font(AFSRFont.caption())
                                .foregroundStyle(.secondary)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.afsrEmergency.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}
