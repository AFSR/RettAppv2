import MapKit
import SwiftUI

// MARK: - Accès réservé

/// N'affiche son contenu qu'à un adhérent connecté, déverrouillé et à jour.
///
/// Les autres cas ont chacun leur écran — connexion, Face ID, « réservé aux
/// adhérents » — pour qu'on ne soit jamais devant un bouton qui ne fait rien.
struct MemberGate<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        // Lu dans `body`, isolé sur le MainActor.
        let session = MemberSession.shared
        Group {
            if !session.isSignedIn {
                MemberLoginView(session: session)
            } else if !session.isUnlocked {
                MemberLockView(session: session)
            } else if session.profile?.membership.active == false {
                MemberLockedView(message: "Donner un avis est réservé aux adhérents dont l'adhésion est à jour.")
            } else {
                content()
            }
        }
    }
}

// MARK: - Choisir le lieu

/// Étape « Quel lieu ? » : on le cherche d'abord dans l'annuaire, puis sur Plans.
///
/// Plans connaît presque tous les lieux : la personne n'a rien à ressaisir —
/// nom, adresse, ville et position viennent avec le résultat. Elle n'a qu'à
/// vérifier le type, que l'app déduit de la catégorie.
struct PlaceChooserView: View {
    let store: PlacesStore
    let onClose: () -> Void

    @State private var query = ""
    @State private var applePlaces: [MKMapItem] = []
    @State private var isSearching = false
    @State private var chosen: ReviewTarget?

    var body: some View {
        NavigationStack {
            MemberGate {
                chooser
            }
            .navigationTitle("Donner mon avis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Fermer", action: onClose) }
            }
        }
    }

    private var inDirectory: [PlaceSummary] {
        let needle = PlacesStore.fold(query)
        guard needle.count >= 2 else { return [] }
        return store.places.filter {
            PlacesStore.fold([$0.name, $0.city].compactMap { $0 }.joined(separator: " ")).contains(needle)
        }
        .prefix(8)
        .map { $0 }
    }

    private var chooser: some View {
        List {
            Section {
                TextField("Nom du lieu, ville…", text: $query)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
            } footer: {
                Text("Cherchez le lieu que vous avez visité. S'il n'est pas encore dans l'annuaire de l'AFSR, choisissez-le sur Plans : nous le proposerons à l'association.")
            }

            if !inDirectory.isEmpty {
                Section("Dans l'annuaire Rett friendly") {
                    ForEach(inDirectory) { place in
                        Button {
                            chosen = .existing(placeID: place.id, name: place.name, criteria: store.criteria(forType: place.type))
                        } label: {
                            PlaceRow(place: place, distance: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !applePlaces.isEmpty {
                Section("Sur Plans — à proposer à l'association") {
                    ForEach(applePlaces, id: \.self) { item in
                        Button {
                            chosen = .proposed(ProposedPlace(item: item))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Lieu").foregroundStyle(.primary)
                                Text(ProposedPlace.subtitle(for: item))
                                    .font(AFSRFont.caption())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else if isSearching {
                Section { ProgressView() }
            }
        }
        .task(id: query) { await search() }
        .navigationDestination(item: $chosen) { target in
            PlaceReviewForm(target: target, editing: nil, store: store) { onClose() }
        }
    }

    /// Recherche sur Plans, après une courte pause : pas d'appel à chaque lettre.
    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 3 else {
            applePlaces = []
            return
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        // Cadré sur la France : « Hôtel de la Plage » n'a de sens qu'avec son contexte.
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 46.6, longitude: 2.4),
            span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 14)
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            applePlaces = Array(response.mapItems.prefix(8))
        } catch {
            if !Task.isCancelled { applePlaces = [] }
        }
    }
}

// MARK: - Lieu proposé

/// Un lieu choisi sur Plans, prêt à être proposé à l'association.
struct ProposedPlace: Hashable {
    var name: String
    var type: String
    var address: String?
    var postalCode: String?
    var city: String
    var country: String
    var website: String?
    var latitude: Double
    var longitude: Double

    init(item: MKMapItem) {
        let mark = item.placemark
        name = item.name ?? "Lieu"
        type = PlaceKind.type(for: item.pointOfInterestCategory)
        let street = [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        address = street.isEmpty ? nil : street
        postalCode = mark.postalCode
        city = mark.locality ?? ""
        country = mark.country ?? "France"
        website = item.url?.absoluteString
        latitude = mark.coordinate.latitude
        longitude = mark.coordinate.longitude
    }

    static func subtitle(for item: MKMapItem) -> String {
        let mark = item.placemark
        let street = [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let town = [mark.postalCode, mark.locality].compactMap { $0 }.joined(separator: " ")
        return [street, town].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Ce sur quoi porte l'avis : un lieu de l'annuaire, ou un lieu à proposer.
enum ReviewTarget: Hashable, Identifiable {
    case existing(placeID: String, name: String, criteria: [PlaceCriterion])
    case proposed(ProposedPlace)

    var id: String {
        switch self {
        case .existing(let id, _, _): return "existing-\(id)"
        case .proposed(let place): return "proposed-\(place.name)-\(place.latitude)"
        }
    }

    var title: String {
        switch self {
        case .existing(_, let name, _): return name
        case .proposed(let place): return place.name
        }
    }

    static func == (lhs: ReviewTarget, rhs: ReviewTarget) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Le formulaire d'avis

/// Donner ou modifier son avis : une note, des constats oui/non, quelques mots.
///
/// Ce sont des constats et non des appréciations : « Avez-vous pu entrer sans
/// marche ? » et non « Est-ce accessible ? ». « Je ne sais pas » n'est pas une
/// réponse mais son absence — elle ne laisse aucune trace côté site.
struct PlaceReviewForm: View {
    let target: ReviewTarget
    let editing: MyPlaceReview?
    let store: PlacesStore
    let onDone: () -> Void

    @State private var rating = 0
    @State private var answers: [String: String] = [:]
    @State private var comment = ""
    @State private var visitedOn = Date()
    @State private var includeVisitDate = true
    @State private var showArea = false
    @State private var engagement = false
    @State private var proposedType = "autre"

    @State private var isSending = false
    @State private var fieldErrors: [String: String] = [:]
    @State private var errorMessage: String?
    @State private var confirmation: String?
    @State private var showDeleteConfirm = false

    init(target: ReviewTarget, editing: MyPlaceReview?, store: PlacesStore, onDone: @escaping () -> Void) {
        self.target = target
        self.editing = editing
        self.store = store
        self.onDone = onDone

        if let editing {
            _rating = State(initialValue: editing.rating)
            _answers = State(initialValue: editing.answers)
            _comment = State(initialValue: editing.comment ?? "")
            _showArea = State(initialValue: editing.showArea)
            if let raw = editing.visitedOn, let date = Self.monthParser.date(from: raw) {
                _visitedOn = State(initialValue: date)
            } else {
                _includeVisitDate = State(initialValue: false)
            }
        }
        if case .proposed(let place) = target {
            _proposedType = State(initialValue: place.type)
        }
    }

    private static let monthParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private var criteria: [PlaceCriterion] {
        switch target {
        case .existing(_, _, let criteria): return criteria
        case .proposed: return store.criteria(forType: proposedType)
        }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.title).font(AFSRFont.headline(17))
                    if case .proposed(let place) = target {
                        Text("Ce lieu n'est pas encore dans l'annuaire : l'association le relira avant de le publier.")
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                        Text([place.address, place.postalCode, place.city].compactMap { $0 }.joined(separator: ", "))
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }
                }
                if case .proposed = target {
                    Picker("Type de lieu", selection: $proposedType) {
                        ForEach(store.meta?.types ?? []) { type in
                            Label(type.label, systemImage: PlaceKind.symbol(for: type.key)).tag(type.key)
                        }
                    }
                }
            }

            Section {
                HStack {
                    Text("Accueil").font(AFSRFont.body(16))
                    Spacer()
                    starPicker
                }
                fieldError("rating")
            } header: {
                Text("Votre note")
            } footer: {
                Text("De 1 à 5, pour l'accueil réservé à votre enfant et à vous.")
            }

            if !criteria.isEmpty {
                Section {
                    ForEach(criteria) { criterion in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(criterion.question).font(AFSRFont.body(15))
                            Picker(criterion.question, selection: answerBinding(criterion.handle)) {
                                Text("Oui").tag("oui")
                                Text("Non").tag("non")
                                Text("Je ne sais pas").tag("")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Ce que vous avez pu faire")
                } footer: {
                    Text("Répondez seulement à ce dont vous êtes sûr : « Je ne sais pas » ne compte pas.")
                }
            }

            Section {
                TextEditor(text: $comment)
                    .frame(minHeight: 110)
                Text("\(comment.count)/2000").font(AFSRFont.caption()).foregroundStyle(comment.count > 2000 ? Color.afsrEmergency : Color.secondary)
                fieldError("comment")
            } header: {
                Text("Votre témoignage (facultatif)")
            } footer: {
                Text("Le texte n'est lisible que par les adhérents, et relu avant publication.")
            }

            Section {
                Toggle("Préciser le mois de ma visite", isOn: $includeVisitDate)
                if includeVisitDate {
                    DatePicker("Visite", selection: $visitedOn, in: ...Date(), displayedComponents: .date)
                }
                fieldError("visited_on")
                Toggle("Afficher mon département", isOn: $showArea)
            } footer: {
                Text("Votre avis est signé de votre prénom, et du département si vous le souhaitez — jamais de votre nom.")
            }

            Section {
                Toggle(isOn: $engagement) {
                    Text("Je confirme avoir visité ce lieu, et j'accepte que mon prénom apparaisse sur mon avis.")
                        .font(AFSRFont.caption())
                }
                fieldError("engagement")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.afsrEmergency)
                }
            }
            if let confirmation {
                Section {
                    Label(confirmation, systemImage: "checkmark.circle.fill").foregroundStyle(.afsrSuccess)
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if isSending { ProgressView() } else { Text(editing == nil ? "Envoyer mon avis" : "Enregistrer").fontWeight(.semibold) }
                        Spacer()
                    }
                }
                .disabled(isSending || rating == 0 || !engagement)

                if editing != nil {
                    Button("Retirer mon avis", role: .destructive) { showDeleteConfirm = true }
                        .disabled(isSending)
                }
            } footer: {
                if editing != nil {
                    Text("Un avis modifié repasse en relecture avant d'être republié.")
                }
            }
        }
        .navigationTitle(editing == nil ? "Mon avis" : "Modifier mon avis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editing != nil {
                ToolbarItem(placement: .topBarLeading) { Button("Fermer", action: onDone) }
            }
        }
        .confirmationDialog("Retirer votre avis ?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Retirer mon avis", role: .destructive) { Task { await remove() } }
            Button("Annuler", role: .cancel) { }
        }
        .interactiveDismissDisabled(isSending)
    }

    // MARK: - Éléments

    private var starPicker: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { index in
                Button {
                    rating = rating == index ? 0 : index
                } label: {
                    Image(systemName: index <= rating ? "star.fill" : "star")
                        .font(.system(size: 26))
                        .foregroundStyle(.yellow)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(index) étoile\(index > 1 ? "s" : "")")
            }
        }
    }

    private func answerBinding(_ handle: String) -> Binding<String> {
        Binding(
            get: { answers[handle] ?? "" },
            set: { answers[handle] = $0.isEmpty ? nil : $0 }
        )
    }

    @ViewBuilder
    private func fieldError(_ key: String) -> some View {
        if let message = fieldErrors[key] {
            Text(message).font(AFSRFont.caption()).foregroundStyle(.afsrEmergency)
        }
    }

    // MARK: - Envoi

    private func payload() -> [String: Any] {
        var body: [String: Any] = [
            "rating": rating,
            "criteres": answers,
            "show_area": showArea,
            "engagement": engagement
        ]
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { body["comment"] = trimmed }
        if includeVisitDate { body["visited_on"] = Self.monthParser.string(from: visitedOn) }

        switch target {
        case .existing(let id, _, _):
            body["mode"] = "existant"
            body["establishment_id"] = id
        case .proposed(let place):
            body["mode"] = "nouveau"
            body["name"] = place.name
            body["establishment_type"] = proposedType
            body["city"] = place.city
            if let address = place.address { body["address"] = address }
            if let postal = place.postalCode { body["postal_code"] = postal }
            body["country"] = place.country
            if let website = place.website { body["website"] = website }
            body["latitude"] = place.latitude
            body["longitude"] = place.longitude
        }
        return body
    }

    @MainActor
    private func submit() async {
        isSending = true
        errorMessage = nil
        fieldErrors = [:]
        defer { isSending = false }

        do {
            let client = MemberSession.shared.client
            let result: PlaceReviewSubmitResponse
            if let editing {
                result = try await client.postJSON("/avis/\(editing.id)", body: payload())
            } else {
                result = try await client.postJSON("/avis", body: payload())
            }
            confirmation = result.message
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            onDone()
        } catch let MemberAPIError.validation(summary, fields) {
            fieldErrors = fields
            if fields.isEmpty { errorMessage = summary }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func remove() async {
        guard let editing else { return }
        isSending = true
        defer { isSending = false }
        do {
            let _: EmptyResponse = try await MemberSession.shared.client.postJSON("/avis/\(editing.id)/retirer", body: [:])
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Mes avis

/// Les avis déposés par l'adhérent, avec leur état : en relecture, publié, refusé.
struct MyPlaceReviewsView: View {
    @State private var store = PlacesStore()
    @State private var editing: MyPlaceReview?

    var body: some View {
        MemberGate {
            MemberResourceView<MyPlaceReviewsResponse, MyReviewsContent>(
                session: MemberSession.shared,
                path: "/mes-avis"
            ) { response, reload in
                MyReviewsContent(reviews: response.reviews, onEdit: { editing = $0 }, reload: reload)
            }
        }
        .navigationTitle("Mes avis sur les lieux")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { review in
            NavigationStack {
                PlaceReviewForm(
                    target: .existing(
                        placeID: review.establishmentId,
                        name: review.establishmentName ?? "Lieu",
                        criteria: review.criteria
                    ),
                    editing: review,
                    store: store
                ) { editing = nil }
            }
        }
    }
}

private struct MyReviewsContent: View {
    let reviews: [MyPlaceReview]
    let onEdit: (MyPlaceReview) -> Void
    let reload: () async -> Void

    var body: some View {
        List {
            if reviews.isEmpty {
                ContentUnavailableView(
                    "Aucun avis",
                    systemImage: "star.bubble",
                    description: Text("Vos avis sur les lieux Rett friendly apparaîtront ici, avec leur état de relecture.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(reviews) { review in
                Button { onEdit(review) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(review.establishmentName ?? "Lieu").font(AFSRFont.headline(16)).foregroundStyle(.primary)
                            Spacer()
                            statusBadge(review)
                        }
                        StarRating(value: Double(review.rating))
                        if let comment = review.comment {
                            Text(comment).font(AFSRFont.caption()).foregroundStyle(.secondary).lineLimit(2)
                        }
                        if let note = review.moderationNote {
                            Text(note).font(AFSRFont.caption()).foregroundStyle(.afsrWarning)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .refreshable { await reload() }
    }

    private func statusBadge(_ review: MyPlaceReview) -> some View {
        let color: Color = review.status == "published" ? .afsrSuccess : (review.status == "rejected" ? .afsrEmergency : .afsrWarning)
        return Text(review.statusLabel)
            .font(AFSRFont.caption())
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}
