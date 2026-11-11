import CoreLocation
import MapKit
import SwiftUI

/// Poser le lieu sur la carte, et en déduire son adresse.
///
/// ## Pourquoi un point plutôt qu'une adresse tapée
///
/// Une famille qui découvre un gîte accueillant est le plus souvent **sur
/// place** quand elle y pense. Taper « 14 chemin des Noues, 44210 Pornic » sur
/// un téléphone, debout, est une corvée — et une adresse mal recopiée produit
/// une fiche que le géocodeur du site placera au centre de la commune, ou pas
/// du tout. Poser un point est plus juste et plus rapide : les coordonnées
/// partent telles quelles, et le serveur ne les remplace que si l'adresse
/// permet de mieux faire.
///
/// ## Le point est au centre, pas sous le doigt
///
/// C'est l'idiome de Plans et de Google Maps : l'épingle reste fixe au milieu
/// de l'écran et la carte glisse dessous. Un point qu'on dépose d'une touche
/// se place sous le doigt, c'est-à-dire sous ce qu'on ne voit pas — et se
/// corrige mal. Ici on voit toujours ce qu'on vise.
struct PlacePinPickerView: View {
    /// Ce que l'écran rapporte : un point, et ce que la rue en dit.
    struct Resultat {
        var coordinate: CLLocationCoordinate2D
        var address: String?
        var postalCode: String?
        var city: String?
        var country: String?
    }

    /// Le cadrage de départ : le point déjà choisi, sinon la position de
    /// l'appareil si elle est connue, sinon la France.
    var depart: CLLocationCoordinate2D?
    let onChoix: (Resultat) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var camera: MapCameraPosition
    @State private var centre: CLLocationCoordinate2D
    @State private var adresse: Resultat?
    @State private var resolution = false
    @State private var localisationRefusee = false
    @State private var locateur = OneShotLocator()
    @State private var tacheAdresse: Task<Void, Never>?

    init(depart: CLLocationCoordinate2D? = nil, onChoix: @escaping (Resultat) -> Void) {
        self.depart = depart
        self.onChoix = onChoix

        let centreInitial = depart ?? CLLocationCoordinate2D(latitude: 46.6, longitude: 2.4)
        _centre = State(initialValue: centreInitial)
        _camera = State(initialValue: .region(MKCoordinateRegion(
            center: centreInitial,
            // Serré quand on sait où on est, large quand on ne sait pas.
            span: depart == nil
                ? MKCoordinateSpan(latitudeDelta: 11, longitudeDelta: 11)
                : MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
        )))
    }

    var body: some View {
        ZStack {
            Map(position: $camera)
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .onMapCameraChange(frequency: .onEnd) { contexte in
                    centre = contexte.region.center
                    resoudre()
                }

            // L'épingle fixe. Elle ne reçoit aucun geste : la carte doit
            // pouvoir glisser sous elle.
            VStack(spacing: 0) {
                Image(systemName: "mappin")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.afsrPurple)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                // La pointe de l'épingle est en bas de l'image : on décale de
                // la moitié de sa hauteur pour qu'elle désigne le centre réel.
                    .offset(y: -17)
                Circle()
                    .fill(Color.afsrPurple.opacity(0.25))
                    .frame(width: 8, height: 8)
                    .offset(y: -17)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .safeAreaInset(edge: .bottom) { carte }
        .navigationTitle("Placer le lieu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await centrerSurMoi() }
                } label: {
                    Label("Ma position", systemImage: "location")
                }
            }
        }
        .task {
            // Si on ouvre sans point de départ, on tente la position de
            // l'appareil : c'est le cas le plus fréquent, puisqu'on partage
            // un lieu où l'on se trouve.
            if depart == nil { await centrerSurMoi(discret: true) }
            resoudre()
        }
        .alert("Position indisponible", isPresented: $localisationRefusee) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("RettApp n'a pas accès à votre position. Vous pouvez placer l'épingle à la main, ou l'autoriser dans Réglages → Confidentialité → Service de localisation.")
        }
    }

    // MARK: - La carte du bas

    private var carte: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if resolution {
                    ProgressView().controlSize(.small)
                    Text("Recherche de l'adresse…")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                } else if let adresse, let ligne = Self.ligne(adresse) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(Color.afsrPurple)
                    Text(ligne)
                        .font(AFSRFont.body())
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(.secondary)
                    Text("Aucune adresse connue à cet endroit. Le point suffit : il situera le lieu sur la carte.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Button {
                onChoix(adresse ?? Resultat(coordinate: centre))
                dismiss()
            } label: {
                Text("Utiliser ce point")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(16)
        .background(.regularMaterial)
    }

    // MARK: - Actions

    /// Le nom de rue du point visé.
    ///
    /// Temporisé, parce qu'un glissement de carte produit une rafale de
    /// changements et que le géocodeur d'Apple se bride de lui-même au-delà de
    /// quelques appels — se faire brider rendrait l'adresse muette alors que
    /// tout fonctionne.
    private func resoudre() {
        tacheAdresse?.cancel()
        tacheAdresse = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }

            resolution = true
            defer { resolution = false }

            let position = CLLocation(latitude: centre.latitude, longitude: centre.longitude)
            let reperes = try? await CLGeocoder().reverseGeocodeLocation(
                position,
                preferredLocale: Locale(identifier: "fr_FR")
            )

            guard !Task.isCancelled else { return }

            guard let repere = reperes?.first else {
                adresse = Resultat(coordinate: centre)
                return
            }

            adresse = Resultat(
                coordinate: centre,
                address: [repere.subThoroughfare, repere.thoroughfare]
                    .compactMap(\.self)
                    .joined(separator: " ")
                    .nilSiVide,
                postalCode: repere.postalCode,
                city: repere.locality,
                country: repere.country
            )
        }
    }

    /// Centre la carte sur l'appareil.
    ///
    /// `discret` sert à l'ouverture : on ne veut pas d'alerte si la personne a
    /// refusé la localisation une fois pour toutes — elle placera l'épingle à
    /// la main, ce qui marche aussi bien.
    private func centrerSurMoi(discret: Bool = false) async {
        guard let position = await locateur.position() else {
            if !discret { localisationRefusee = true }
            return
        }

        centre = position
        withAnimation(.snappy) {
            camera = .region(MKCoordinateRegion(
                center: position,
                span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
            ))
        }
        resoudre()
    }

    static func ligne(_ resultat: Resultat) -> String? {
        [
            resultat.address,
            [resultat.postalCode, resultat.city].compactMap(\.self).joined(separator: " ").nilSiVide,
        ]
        .compactMap(\.self)
        .joined(separator: ", ")
        .nilSiVide
    }
}

private extension String {
    var nilSiVide: String? {
        let net = trimmingCharacters(in: .whitespacesAndNewlines)
        return net.isEmpty ? nil : net
    }
}

// MARK: - La position, une fois

/// Demande la position de l'appareil une seule fois.
///
/// Une seule, et jamais en continu : l'application n'a pas à savoir où est la
/// famille, seulement où est le lieu qu'elle décrit. `requestLocation` demande
/// un relevé puis s'arrête de lui-même — il n'y a aucun suivi à oublier
/// d'éteindre, et rien qui tourne en arrière-plan.
@MainActor
final class OneShotLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var attente: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func position() async -> CLLocationCoordinate2D? {
        // Une demande déjà en cours : on ne superpose pas deux attentes.
        guard attente == nil else { return nil }

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            return nil
        default:
            break
        }

        return await withCheckedContinuation { suite in
            attente = suite
            manager.requestLocation()
        }
    }

    private func rendre(_ coordonnees: CLLocationCoordinate2D?) {
        attente?.resume(returning: coordonnees)
        attente = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordonnees = locations.last?.coordinate
        Task { @MainActor in self.rendre(coordonnees) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.rendre(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let statut = manager.authorizationStatus
        Task { @MainActor in
            switch statut {
            case .authorizedWhenInUse, .authorizedAlways:
                // L'autorisation vient d'être accordée : le relevé demandé
                // avant la réponse n'aurait rien donné, on le redemande.
                if self.attente != nil { manager.requestLocation() }
            case .denied, .restricted:
                self.rendre(nil)
            default:
                break
            }
        }
    }
}
