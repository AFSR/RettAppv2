import CoreLocation
import MapKit
import SwiftUI

extension Place {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension PlaceDetail {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// L'annuaire des lieux qui accueillent bien.
///
/// Deux façons de le parcourir, et ce ne sont pas deux goûts : on cherche un
/// lieu par son nom quand on l'a en tête, et sur une carte quand on prépare un
/// séjour dans une région. La liste est donc l'entrée par défaut, la carte un
/// basculement — et les deux partagent la recherche et les filtres, pour qu'un
/// filtre posé dans l'une se retrouve dans l'autre.
struct PlacesDirectoryView: View {
    let session: MemberSession

    @State private var store: PlacesStore
    @State private var affichage: Affichage = .liste
    @State private var selection: String?
    @State private var camera: MapCameraPosition = .region(Self.france)
    @State private var proposer = false

    init(session: MemberSession) {
        self.session = session
        _store = State(initialValue: PlacesStore(session: session))
    }

    enum Affichage: String, CaseIterable, Identifiable {
        case liste = "Liste"
        case carte = "Carte"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .liste: return "list.bullet"
            case .carte: return "map"
            }
        }
    }

    /// La France métropolitaine, le cadrage de départ quand aucun lieu n'est
    /// encore choisi. Le même que la carte du site.
    private static let france = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 46.6, longitude: 2.4),
        span: MKCoordinateSpan(latitudeDelta: 11, longitudeDelta: 11)
    )

    var body: some View {
        Group {
            switch store.phase {
            case .loading:
                ProgressView("Chargement de l'annuaire…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed(.membershipRequired(let message)):
                MemberLockedView(message: message)

            case .failed(let erreur):
                ContentUnavailableView {
                    Label("Impossible de charger l'annuaire", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(erreur.localizedDescription)
                } actions: {
                    Button("Réessayer") { Task { await store.charger() } }
                        .buttonStyle(.borderedProminent)
                }

            case .loaded:
                contenu
            }
        }
        .background(Color.afsrBackground)
        .navigationTitle("Lieux Rett friendly")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $store.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Un nom, une ville, un département"
        )
        .toolbar { barre }
        .navigationDestination(for: Place.self) { lieu in
            PlaceDetailView(session: session, slug: lieu.slug, nom: lieu.name)
        }
        .sheet(isPresented: $proposer) {
            NavigationStack {
                PlaceReviewFormView(session: session, store: store, lieu: nil, existant: nil)
            }
        }
        .task { await store.chargerSiNecessaire() }
    }

    // MARK: - Barre d'outils

    @ToolbarContentBuilder
    private var barre: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Affichage", selection: $affichage) {
                ForEach(Affichage.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Type de lieu", selection: $store.type) {
                    Text("Tous les types").tag(String?.none)
                    ForEach(store.meta?.types ?? []) { type in
                        Text(type.label).tag(Optional(type.key))
                    }
                }

                Picker("Département", selection: $store.department) {
                    Text("Tous les départements").tag(String?.none)
                    ForEach(store.meta?.departments ?? []) { dept in
                        Text("\(dept.code) — \(dept.name)").tag(Optional(dept.code))
                    }
                }

                if store.filtresActifs {
                    Divider()
                    Button("Effacer les filtres", systemImage: "xmark.circle") {
                        store.effacerFiltres()
                        Task { await store.charger() }
                    }
                }
            } label: {
                Label("Filtrer", systemImage: store.filtresActifs
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                proposer = true
            } label: {
                Label("Partager un lieu", systemImage: "plus")
            }
        }
    }

    // MARK: - Contenu

    @ViewBuilder
    private var contenu: some View {
        if store.places.isEmpty {
            ContentUnavailableView {
                Label("Aucun lieu ne correspond", systemImage: "mappin.slash")
            } description: {
                Text(store.filtresActifs
                    ? "Essayez avec moins de filtres, ou proposez ce lieu : l'annuaire se construit par les familles."
                    : "L'annuaire est encore vide.")
            } actions: {
                if store.filtresActifs {
                    Button("Effacer les filtres") {
                        store.effacerFiltres()
                        Task { await store.charger() }
                    }
                }
                Button("Partager un lieu") { proposer = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            switch affichage {
            case .liste: liste
            case .carte: carte
            }
        }
    }

    private var liste: some View {
        List {
            Section {
                ForEach(store.places) { lieu in
                    NavigationLink(value: lieu) {
                        PlaceRow(lieu: lieu)
                    }
                }
            } header: {
                Text(decompte)
            } footer: {
                if let erreur = store.derniereErreur {
                    Text(erreur).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.charger() }
    }

    private var carte: some View {
        Map(position: $camera, selection: $selection) {
            ForEach(store.situes) { lieu in
                Marker(lieu.name, systemImage: "mappin", coordinate: lieu.coordinate!)
                    .tint(.afsrPurple)
                    .tag(lieu.id)
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let choisi = store.situes.first(where: { $0.id == selection }) {
                    NavigationLink(value: choisi) {
                        PlaceMapCard(lieu: choisi)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Les fiches sans coordonnées ne sont pas sur la carte. Le
                // dire, sinon on les croit disparues de l'annuaire.
                if store.sansCoordonnees > 0 {
                    Text(store.sansCoordonnees == 1
                        ? "1 lieu n'est pas situé sur la carte. Il figure dans la liste."
                        : "\(store.sansCoordonnees) lieux ne sont pas situés sur la carte. Ils figurent dans la liste.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .animation(.snappy, value: selection)
        }
    }

    private var decompte: String {
        let montres = store.places.count

        if !store.filtresActifs || montres == store.total {
            return montres == 1 ? "1 lieu" : "\(montres) lieux"
        }

        return "\(montres) lieu\(montres == 1 ? "" : "x") sur \(store.total)"
    }
}

// MARK: - Une ligne de l'annuaire

struct PlaceRow: View {
    let lieu: Place

    var body: some View {
        HStack(spacing: 12) {
            AFSRIconBadge(systemImage: symbole, color: .afsrPurpleLight, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(lieu.name)
                    .font(AFSRFont.body())
                    .foregroundStyle(.primary)

                Text(lieu.subtitle)
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)

                PlaceRatingView(rating: lieu.rating, count: lieu.reviewCount)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    /// Un symbole par type de lieu : on reconnaît un hôtel d'un restaurant
    /// avant d'avoir lu la ligne.
    private var symbole: String {
        switch lieu.type {
        case "hotel": return "bed.double"
        case "restaurant": return "fork.knife"
        case "hebergement": return "house"
        case "loisir": return "ticket"
        default: return "mappin.and.ellipse"
        }
    }
}

/// La note de l'accueil, et le nombre d'avis qui la fondent.
///
/// Sans aucun avis, on n'affiche **pas** zéro étoile : une absence de
/// témoignage n'est pas un mauvais accueil, et c'est exactement ce qu'un
/// « 0 / 5 » laisserait croire.
struct PlaceRatingView: View {
    let rating: Double?
    let count: Int

    var body: some View {
        if let rating, count > 0 {
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { cran in
                    Image(systemName: Double(cran) <= rating.rounded() ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundStyle(.afsrWarning)
                }
                Text(count == 1 ? "1 avis" : "\(count) avis")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Accueil noté \(rating.formatted(.number.precision(.fractionLength(1)))) sur 5, \(count) avis")
        } else {
            Text("Pas encore d'avis")
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
        }
    }
}

/// La carte posée au-dessus de la carte quand on touche un point.
struct PlaceMapCard: View {
    let lieu: Place

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lieu.name)
                    .font(AFSRFont.headline(16))
                    .foregroundStyle(.primary)
                Text(lieu.subtitle)
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                PlaceRatingView(rating: lieu.rating, count: lieu.reviewCount)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.afsrSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .afsrShadow, radius: 8, y: 2)
    }
}
