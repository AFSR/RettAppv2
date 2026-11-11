import CoreLocation
import SwiftUI

/// Partager un lieu, depuis l'annuaire.
///
/// On commence par **chercher**, comme dans Google Maps : neuf fois sur dix le
/// lieu est déjà là, et le dire d'abord évite de créer un doublon que
/// l'association devra fusionner à la main. Le chemin « il n'y est pas » reste
/// visible en permanence, en bas de la liste — pas caché derrière un sélecteur
/// de mode qu'il fallait comprendre avant de commencer.
///
/// C'est le reproche qu'on pouvait faire à la première version : elle ouvrait
/// sur la question « ce lieu est-il déjà dans l'annuaire ? », à laquelle
/// personne ne peut répondre sans avoir cherché.
struct PlaceShareFlowView: View {
    let session: MemberSession
    let store: PlacesStore
    var onDone: (() async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var recherche = ""
    @State private var destination: Destination?

    private enum Destination: Hashable {
        case noter(Place)
        case proposer
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(resultats) { lieu in
                        NavigationLink(value: Destination.noter(lieu)) {
                            PlaceRow(lieu: lieu)
                        }
                    }
                } header: {
                    if !resultats.isEmpty {
                        Text(recherche.isEmpty ? "L'annuaire" : "Résultats")
                    }
                }

                Section {
                    NavigationLink(value: Destination.proposer) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ajouter un lieu absent de l'annuaire")
                                Text("Vous le ferez connaître aux autres familles")
                                    .font(AFSRFont.caption())
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            AFSRIconBadge(systemImage: "plus", color: .afsrPurple, size: 30)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $recherche, prompt: "Nom du lieu, ou ville")
            .overlay {
                if resultats.isEmpty, !recherche.isEmpty {
                    ContentUnavailableView {
                        Label("Aucun lieu trouvé", systemImage: "mappin.slash")
                    } description: {
                        Text("Il n'est peut-être pas encore dans l'annuaire. Vous pouvez l'ajouter.")
                    }
                }
            }
            .navigationTitle("Partager un lieu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .navigationDestination(for: Destination.self) { ou in
                switch ou {
                case .noter(let lieu):
                    PlaceReviewSheet(
                        session: session,
                        place: .init(
                            establishmentID: lieu.id,
                            name: lieu.name,
                            subtitle: lieu.subtitle,
                            criteria: store.criteres(pourType: lieu.type),
                            proposal: nil
                        ),
                        existing: nil
                    ) {
                        await terminer()
                    }

                case .proposer:
                    PlaceProposalView(session: session, store: store) {
                        await terminer()
                    }
                }
            }
        }
    }

    /// La recherche porte sur la liste déjà chargée : on ne relance pas
    /// l'annuaire pour trouver un lieu qu'on a sous les yeux.
    private var resultats: [Place] {
        let terme = recherche.trimmingCharacters(in: .whitespaces)
        guard !terme.isEmpty else { return store.places }

        return store.places.filter {
            $0.name.localizedCaseInsensitiveContains(terme)
                || ($0.city?.localizedCaseInsensitiveContains(terme) ?? false)
        }
    }

    private func terminer() async {
        await onDone?()
        await store.charger()
        dismiss()
    }
}

/// Le lieu qu'on fait connaître.
///
/// Un formulaire, ici, est le bon outil : ce sont des champs d'identité, et
/// c'est ainsi qu'iOS les présente partout — y compris dans « Ajouter un
/// lieu » de Plans. Ce qui ne devait pas être un formulaire, c'est l'avis
/// lui-même, qui vient à l'étape suivante.
struct PlaceProposalView: View {
    let session: MemberSession
    let store: PlacesStore
    var onDone: (() async -> Void)?

    @State private var nom = ""
    @State private var type: String?
    @State private var adresse = ""
    @State private var codePostal = ""
    @State private var commune = ""
    @State private var site = ""
    @State private var point: CLLocationCoordinate2D?
    @State private var placerSurCarte = false

    var body: some View {
        Form {
            Section {
                TextField("Nom du lieu", text: $nom)
                    .textInputAutocapitalization(.words)

                Picker("Type", selection: $type) {
                    Text("À choisir").tag(String?.none)
                    ForEach(store.meta?.types ?? []) { proposition in
                        Text(proposition.label).tag(Optional(proposition.key))
                    }
                }
            } footer: {
                Text("Le type décide des questions qu'on vous posera ensuite : on ne demande pas à un restaurant s'il y a une prise près du lit.")
            }

            Section {
                Button {
                    placerSurCarte = true
                } label: {
                    HStack(spacing: 12) {
                        AFSRIconBadge(
                            systemImage: point == nil ? "map" : "mappin.circle.fill",
                            color: point == nil ? .afsrPurpleLight : .afsrSuccess,
                            size: 30
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point == nil ? "Placer sur la carte" : "Placé sur la carte")
                                .foregroundStyle(.primary)
                            Text(point == nil
                                ? "Le plus simple si vous y êtes : une épingle, et l'adresse suit"
                                : "Touchez pour déplacer l'épingle")
                                .font(AFSRFont.caption())
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Un point posé situe le lieu exactement. Sans lui, l'association le placera d'après l'adresse — souvent au centre de la commune.")
            }

            Section("Où est-ce ?") {
                TextField("Adresse", text: $adresse)
                    .textInputAutocapitalization(.words)
                TextField("Code postal", text: $codePostal)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Commune", text: $commune)
                    .textInputAutocapitalization(.words)
            }

            Section {
                TextField("Site web", text: $site)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Facultatif")
            } footer: {
                Text("La commune suffit à situer le lieu sur la carte ; l'adresse le situe précisément.")
            }

            Section {
                NavigationLink {
                    PlaceReviewSheet(
                        session: session,
                        place: .init(
                            establishmentID: nil,
                            name: nom.trimmingCharacters(in: .whitespaces),
                            subtitle: [typeLibelle, commune].compactMap(\.self)
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "),
                            criteria: store.criteres(pourType: type),
                            proposal: .init(
                                type: type ?? "",
                                address: adresse,
                                postalCode: codePostal,
                                city: commune,
                                website: site,
                                latitude: point?.latitude,
                                longitude: point?.longitude
                            )
                        ),
                        existing: nil,
                        onDone: onDone
                    )
                } label: {
                    Text("Continuer vers mon avis")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .disabled(!complet)
            } footer: {
                Text("Le lieu sera créé en brouillon et n'apparaîtra dans l'annuaire qu'après relecture par l'association.")
            }
        }
        .navigationTitle("Un lieu de plus")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $placerSurCarte) {
            NavigationStack {
                PlacePinPickerView(depart: point) { resultat in
                    point = resultat.coordinate
                    // L'adresse trouvée ne remplace que les champs vides :
                    // ce que l'adhérent a tapé lui-même fait foi, le
                    // géocodage inverse se trompe parfois d'un numéro.
                    if adresse.isEmpty, let rue = resultat.address { adresse = rue }
                    if codePostal.isEmpty, let code = resultat.postalCode { codePostal = code }
                    if commune.isEmpty, let ville = resultat.city { commune = ville }
                }
            }
        }
    }

    private var typeLibelle: String? {
        guard let type else { return nil }
        return store.meta?.types.first { $0.key == type }?.label
    }

    private var complet: Bool {
        !nom.trimmingCharacters(in: .whitespaces).isEmpty
            && type != nil
            && !commune.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
