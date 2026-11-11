import MapKit
import SwiftUI

/// L'onglet « Lieux » : l'annuaire des lieux Rett friendly, sur une carte ou en
/// liste, avec recherche instantanée, filtres et « Autour de moi ».
///
/// Public : chercher un hôtel où l'on sait accueillir n'exige ni compte ni
/// connexion. Donner son avis, en revanche, est réservé aux adhérents à jour.
struct PlacesView: View {
    @State private var store = PlacesStore()
    @State private var location = PlacesLocation()
    @State private var mode: Mode = .map
    @State private var selectedID: String?
    @State private var detail: PlaceSummary?
    @State private var camera: MapCameraPosition = .automatic
    @State private var showAddFlow = false

    enum Mode: String, CaseIterable, Identifiable {
        case map = "Carte"
        case list = "Liste"
        var id: String { rawValue }
    }

    var body: some View {
        let places = store.filtered(location: location)

        VStack(spacing: 0) {
            filterBar
            Group {
                if let message = store.errorMessage, store.places.isEmpty {
                    ContentUnavailableView {
                        Label("Annuaire indisponible", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Réessayer") { Task { await store.load(force: true) } }
                            .buttonStyle(.borderedProminent)
                    }
                } else if store.isLoading && store.places.isEmpty {
                    ProgressView("Chargement des lieux…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if mode == .map {
                    mapView(places)
                } else {
                    listView(places)
                }
            }
        }
        .background(Color.afsrBackground)
        .navigationTitle("Lieux Rett friendly")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $store.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Nom, ville, département")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Affichage", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddFlow = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Donner mon avis sur un lieu")
            }
        }
        .navigationDestination(item: $detail) { place in
            PlaceDetailView(place: place, store: store)
        }
        .sheet(isPresented: $showAddFlow) {
            PlaceChooserView(store: store) { showAddFlow = false }
        }
        .task { await store.load() }
        .refreshable { await store.load(force: true) }
    }

    // MARK: - Filtres

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                nearMeChip

                chip("Tous", systemImage: "square.grid.2x2", isOn: store.typeFilter == nil) {
                    store.typeFilter = nil
                }
                ForEach(store.meta?.types ?? []) { type in
                    chip(type.label, systemImage: PlaceKind.symbol(for: type.key), isOn: store.typeFilter == type.key) {
                        store.typeFilter = store.typeFilter == type.key ? nil : type.key
                    }
                }

                if !store.departments.isEmpty {
                    Menu {
                        Button("Tous les départements") { store.departmentFilter = nil }
                        ForEach(store.departments) { department in
                            Button(department.name) { store.departmentFilter = department.name }
                        }
                    } label: {
                        chipLabel(store.departmentFilter ?? "Département", systemImage: "map", isOn: store.departmentFilter != nil)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var nearMeChip: some View {
        chip(
            location.isDenied ? "Position refusée" : "Autour de moi",
            systemImage: "location.fill",
            isOn: store.sortByDistance && location.location != nil
        ) {
            if location.isDenied {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                return
            }
            store.sortByDistance.toggle()
            if store.sortByDistance {
                location.request()
                camera = .userLocation(fallback: .automatic)
            }
        }
    }

    private func chip(_ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, systemImage: systemImage, isOn: isOn) }
            .buttonStyle(.plain)
    }

    private func chipLabel(_ title: String, systemImage: String, isOn: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(AFSRFont.caption())
            .fontWeight(.medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(isOn ? Color.afsrPurple : Color(.secondarySystemBackground), in: Capsule())
    }

    // MARK: - Carte

    private func mapView(_ places: [PlaceSummary]) -> some View {
        let located = places.filter { $0.coordinate != nil }
        let missing = places.count - located.count

        return Map(position: $camera, selection: $selectedID) {
            UserAnnotation()
            ForEach(located) { place in
                if let coordinate = place.coordinate {
                    Marker(place.name, systemImage: PlaceKind.symbol(for: place.type), coordinate: coordinate)
                        .tint(Color.afsrPurple)
                        .tag(place.id)
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .top) {
            if places.isEmpty {
                emptyBanner
            } else if missing > 0 {
                Text("\(missing) lieu\(missing > 1 ? "x" : "") sans position : voir la liste")
                    .font(AFSRFont.caption())
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let id = selectedID, let place = places.first(where: { $0.id == id }) {
                Button { detail = place } label: { PlaceCard(place: place, distance: location.distance(to: place)) }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedID)
    }

    private var emptyBanner: some View {
        Text("Aucun lieu ne correspond.")
            .font(AFSRFont.caption())
            .padding(8)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 8)
    }

    // MARK: - Liste

    private func listView(_ places: [PlaceSummary]) -> some View {
        List {
            if places.isEmpty {
                ContentUnavailableView.search(text: store.query)
                    .listRowBackground(Color.clear)
            }
            ForEach(places) { place in
                Button { detail = place } label: {
                    PlaceRow(place: place, distance: location.distance(to: place))
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Éléments

struct StarRating: View {
    let value: Double
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: symbol(for: index))
                    .font(.system(size: size))
                    .foregroundStyle(.yellow)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Note \(String(format: "%.1f", value)) sur 5")
    }

    private func symbol(for index: Int) -> String {
        if value >= Double(index) { return "star.fill" }
        if value >= Double(index) - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// La note et le nombre d'avis, toujours ensemble : 5 sur 5 fondé sur un seul
/// avis n'est pas une note, et la fiche doit le laisser voir.
struct PlaceRatingLine: View {
    let rating: Double?
    let count: Int

    var body: some View {
        if let rating, count > 0 {
            HStack(spacing: 6) {
                StarRating(value: rating)
                Text("\(String(format: "%.1f", rating).replacingOccurrences(of: ".", with: ",")) · \(count) avis")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Pas encore d'avis")
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
        }
    }
}

struct PlaceRow: View {
    let place: PlaceSummary
    let distance: CLLocationDistance?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: PlaceKind.symbol(for: place.type))
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.afsrPurple, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name).font(AFSRFont.headline(16)).lineLimit(2)
                Text([place.typeLabel, place.city].compactMap { $0 }.joined(separator: " · "))
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                PlaceRatingLine(rating: place.rating, count: place.reviewCount)
            }
            Spacer(minLength: 8)
            if let distance {
                Text(PlaceDistance.label(distance))
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Carte affichée en bas de l'écran quand on touche un repère.
struct PlaceCard: View {
    let place: PlaceSummary
    let distance: CLLocationDistance?

    var body: some View {
        PlaceRow(place: place, distance: distance)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AFSRTokens.cornerRadius))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}
