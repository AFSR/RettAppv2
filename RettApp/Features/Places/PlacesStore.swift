import CoreLocation
import MapKit
import Observation
import SwiftUI

/// Position de l'appareil, pour centrer la carte et classer les lieux par distance.
///
/// La position ne quitte jamais l'appareil : le site renvoie tous les lieux et
/// c'est ici qu'on mesure les distances. L'autorisation n'est demandée qu'au
/// premier appui sur « Autour de moi », jamais à l'ouverture de l'onglet.
///
/// Volontairement non isolée : la vue la crée dans un `@State`, hors du
/// MainActor. L'état n'est modifié que depuis les rappels, qui y reviennent.
@Observable
final class PlacesLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private(set) var location: CLLocation?
    private(set) var status: CLAuthorizationStatus

    override init() {
        status = CLLocationManager().authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool { status == .denied || status == .restricted }
    var isAuthorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }

    /// Demande l'autorisation si besoin, puis une position.
    func request() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.status = manager.authorizationStatus
            if self.isAuthorized { manager.requestLocation() }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.location = last }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Pas de position : la carte reste centrée sur la France, rien n'est cassé.
    }

    func distance(to place: PlaceSummary) -> CLLocationDistance? {
        guard let location, let coordinate = place.coordinate else { return nil }
        return location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}

/// L'annuaire des lieux, chargé une fois puis filtré en mémoire.
///
/// Tout l'annuaire tient en une réponse : filtrer et chercher localement rend
/// la recherche instantanée, sans appel réseau à chaque lettre tapée.
///
/// Volontairement non isolée, pour la même raison ; seul `load`, qui parle au
/// réseau et modifie l'état, l'est.
@Observable
final class PlacesStore {
    private(set) var places: [PlaceSummary] = []
    private(set) var meta: PlacesMeta?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasLoaded = false

    var query = ""
    var typeFilter: String?
    var departmentFilter: String?
    var sortByDistance = false

    @MainActor
    func load(force: Bool = false) async {
        guard force || !hasLoaded else { return }
        let session = MemberSession.shared
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let metaTask: PlacesMeta = session.client.get("/lieux/meta")
            async let listTask: PlacesResponse = session.client.get("/lieux")
            let (loadedMeta, list) = try await (metaTask, listTask)
            meta = loadedMeta
            places = list.establishments
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Les lieux qui répondent à la recherche et aux filtres.
    ///
    /// La recherche ignore la casse et les accents, et porte sur le nom, la
    /// commune et le département : on cherche « nantes » comme « Nantes ».
    func filtered(location: PlacesLocation) -> [PlaceSummary] {
        let needle = Self.fold(query)
        var result = places.filter { place in
            if let typeFilter, place.type != typeFilter { return false }
            if let departmentFilter, place.department != departmentFilter { return false }
            guard !needle.isEmpty else { return true }
            let haystack = Self.fold([place.name, place.city, place.department, place.typeLabel]
                .compactMap { $0 }.joined(separator: " "))
            return haystack.contains(needle)
        }

        if sortByDistance, location.location != nil {
            result.sort { (location.distance(to: $0) ?? .greatestFiniteMagnitude) < (location.distance(to: $1) ?? .greatestFiniteMagnitude) }
        }
        return result
    }

    var departments: [PlaceDepartment] { meta?.departments ?? [] }

    func criteria(forType type: String?) -> [PlaceCriterion] {
        meta?.types.first(where: { $0.key == type })?.criteria ?? meta?.types.first?.criteria ?? []
    }

    /// Minuscules, sans accents ni diacritiques.
    nonisolated static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
