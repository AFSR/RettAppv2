import MapKit
import SwiftUI

/// La fiche d'un lieu : adresse, itinéraire, ce que les adhérents ont constaté,
/// leurs avis — et le moyen de donner le sien.
struct PlaceDetailView: View {
    let place: PlaceSummary
    let store: PlacesStore

    @State private var response: PlaceDetailResponse?
    @State private var errorMessage: String?
    @State private var showReview = false

    var body: some View {
        Group {
            if let response {
                content(response)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Fiche indisponible", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Réessayer") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.afsrBackground)
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showReview) {
            if let response {
                NavigationStack {
                    PlaceReviewForm(
                        target: .existing(placeID: place.id, name: place.name, criteria: response.establishment.criteria),
                        editing: response.myReview,
                        store: store
                    ) {
                        showReview = false
                        Task { await load() }
                    }
                }
            }
        }
    }

    // MARK: - Contenu

    private func content(_ response: PlaceDetailResponse) -> some View {
        let detail = response.establishment

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(detail)
                actions(detail)
                if let description = detail.description, !description.isEmpty {
                    MemberHTMLText(html: description)
                }
                findings(detail)
                reply(detail)
                reviews(detail, response: response)
                reviewButton(response)
            }
            .padding()
        }
        .refreshable { await load() }
    }

    private func header(_ detail: PlaceDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(detail.typeLabel, systemImage: PlaceKind.symbol(for: detail.type))
                .font(AFSRFont.caption())
                .foregroundStyle(.afsrPurpleAdaptive)
            Text(detail.name).font(AFSRFont.title(24))
            if !detail.fullAddress.isEmpty {
                Text(detail.fullAddress).font(AFSRFont.body(15)).foregroundStyle(.secondary)
            }
            PlaceRatingLine(rating: detail.rating, count: detail.reviewCount)
        }
    }

    private func actions(_ detail: PlaceDetail) -> some View {
        HStack(spacing: 10) {
            if let coordinate = detail.coordinate {
                actionButton("Itinéraire", systemImage: "arrow.triangle.turn.up.right.diamond.fill") {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                    item.name = detail.name
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                }
            }
            if let phone = detail.phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                actionButton("Appeler", systemImage: "phone.fill") { UIApplication.shared.open(url) }
            }
            if let site = detail.website, let url = URL(string: site) {
                actionButton("Site", systemImage: "safari.fill") { UIApplication.shared.open(url) }
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 18))
                Text(title).font(AFSRFont.caption())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func findings(_ detail: PlaceDetail) -> some View {
        if !detail.findings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ce que les adhérents ont constaté").font(AFSRFont.headline(17))
                ForEach(detail.findings) { finding in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: finding.isConfirmed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(finding.isConfirmed ? Color.afsrSuccess : Color.afsrWarning)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(finding.constat).font(AFSRFont.body(15))
                            Text(finding.phrase).font(AFSRFont.caption()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .afsrCard()
        }
    }

    @ViewBuilder
    private func reply(_ detail: PlaceDetail) -> some View {
        if let reply = detail.reply, !reply.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Réponse de l'établissement", systemImage: "text.bubble")
                    .font(AFSRFont.caption()).fontWeight(.semibold)
                Text(reply).font(AFSRFont.body(14)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.afsrPurple.opacity(0.08), in: RoundedRectangle(cornerRadius: AFSRTokens.cornerRadiusSmall))
        }
    }

    @ViewBuilder
    private func reviews(_ detail: PlaceDetail, response: PlaceDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Avis").font(AFSRFont.headline(17))

            if detail.reviewsReadable {
                if detail.reviews.isEmpty {
                    Text("Aucun avis rédigé pour l'instant.").font(AFSRFont.caption()).foregroundStyle(.secondary)
                }
                ForEach(detail.reviews) { review in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            StarRating(value: Double(review.rating))
                            Spacer()
                            if let visited = review.visitedOn, let date = Self.monthLabel(visited) {
                                Text(date).font(AFSRFont.caption()).foregroundStyle(.secondary)
                            }
                        }
                        if let comment = review.comment {
                            Text(comment).font(AFSRFont.body(14)).fixedSize(horizontal: false, vertical: true)
                        }
                        Text(review.author).font(AFSRFont.caption()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .afsrCard()
                }
            } else {
                // La note et les constats sont publics ; le texte des avis reste
                // dans l'espace adhérent, où une famille raconte son séjour.
                Label(readabilityHint, systemImage: "lock.fill")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @MainActor
    private var readabilityHint: String {
        let session = MemberSession.shared
        if !session.isSignedIn { return "Le texte des avis est réservé aux adhérents. Connectez-vous à votre espace adhérent pour le lire." }
        if !session.isUnlocked { return "Déverrouillez votre espace adhérent pour lire le texte des avis." }
        return "Le texte des avis est réservé aux adhérents dont l'adhésion est à jour."
    }

    @ViewBuilder
    private func reviewButton(_ response: PlaceDetailResponse) -> some View {
        VStack(spacing: 8) {
            if let mine = response.myReview {
                Label("Votre avis : \(mine.statusLabel)", systemImage: mine.status == "published" ? "checkmark.seal.fill" : "clock")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                if let note = mine.moderationNote {
                    Text(note).font(AFSRFont.caption()).foregroundStyle(.afsrWarning)
                }
                Button { showReview = true } label: {
                    Label("Modifier mon avis", systemImage: "pencil").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if response.canReview {
                Button { showReview = true } label: {
                    Label("Donner mon avis", systemImage: "star.bubble.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Text("Donner un avis est réservé aux adhérents à jour. Connectez-vous à votre espace adhérent, ou adhérez sur afsr.fr.")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Données

    @MainActor
    private func load() async {
        errorMessage = nil
        do {
            response = try await MemberSession.shared.client.get("/lieux/\(place.slug)")
        } catch {
            if response == nil { errorMessage = error.localizedDescription }
        }
    }

    /// « mai 2026 » depuis « 2026-05 ».
    static func monthLabel(_ raw: String) -> String? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM"
        guard let date = parser.date(from: raw) else { return nil }
        let display = DateFormatter()
        display.locale = Locale(identifier: "fr_FR")
        display.dateFormat = "LLLL yyyy"
        return display.string(from: date)
    }
}
