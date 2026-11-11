import Foundation
import Observation

/// Charge l'annuaire des lieux et tient l'état des filtres.
///
/// Un magasin plutôt que `MemberResourceView` parce que le chemin change :
/// chaque filtre et chaque frappe dans la recherche produit une autre requête.
/// Le filtrage se fait **côté serveur**, et non sur une liste tout entière
/// rapatriée une fois — c'est `Directory::filtered` qui en décide, et la
/// recherche porte sur des champs que l'application n'a pas tous.
///
/// Deux précautions valent d'être nommées. La frappe est **temporisée** : sans
/// cela, « gîte » lancerait quatre requêtes dont trois pour rien, et la
/// dernière arrivée gagnerait, pas la dernière demandée. Et une requête qui
/// échoue **n'effleure pas** ce qui est déjà affiché : on garde la liste
/// précédente et on signale l'échec à côté, parce qu'une liste qui disparaît
/// parce que le réseau a hésité est pire qu'une liste un peu vieille.
@Observable
@MainActor
final class PlacesStore {

    enum Phase {
        case loading
        case loaded
        case failed(MemberAPIError)
    }

    private(set) var phase: Phase = .loading

    private(set) var places: [Place] = []

    /// Le total de l'annuaire, pour dire « 12 lieux sur 148 » après un filtre.
    private(set) var total: Int = 0

    private(set) var meta: PlaceMeta?

    // Les filtres. Toute modification relance une recherche.

    var query: String = "" {
        didSet { if query != oldValue { planifier() } }
    }

    var type: String? {
        didSet { if type != oldValue { Task { await charger() } } }
    }

    var department: String? {
        didSet { if department != oldValue { Task { await charger() } } }
    }

    var filtresActifs: Bool {
        type != nil || department != nil || !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Les lieux que la carte peut montrer. Les autres existent, ils n'ont
    /// simplement pas de coordonnées — l'écran le dit, pour qu'on ne les
    /// croie pas disparus.
    var situes: [Place] { places.filter(\.hasCoordinates) }

    var sansCoordonnees: Int { places.count - situes.count }

    private let session: MemberSession
    private var temporisation: Task<Void, Never>?
    private var chargement: Task<Void, Never>?

    init(session: MemberSession) {
        self.session = session
    }

    func chargerSiNecessaire() async {
        guard meta == nil else { return }
        await chargerMeta()
        await charger()
    }

    /// Le référentiel : types, critères par type, départements présents.
    /// Son échec n'est pas bloquant — l'annuaire se lit sans filtres.
    private func chargerMeta() async {
        meta = try? await session.client.get("/lieux/meta")
    }

    func charger() async {
        // Une recherche en cours devient inutile dès qu'une autre part.
        chargement?.cancel()

        let tache = Task { @MainActor in
            if places.isEmpty { phase = .loading }

            do {
                let reponse: PlaceListResponse = try await session.client.get("/lieux", query: [
                    "type": type,
                    "departement": department,
                    "q": query.trimmingCharacters(in: .whitespaces),
                ])

                guard !Task.isCancelled else { return }

                places = reponse.establishments
                total = reponse.total
                phase = .loaded
            } catch is CancellationError {
                return
            } catch let erreur as MemberAPIError {
                guard !Task.isCancelled else { return }
                // On ne vide pas l'écran pour une requête qui a échoué.
                phase = places.isEmpty ? .failed(erreur) : .loaded
                if !places.isEmpty { derniereErreur = erreur.localizedDescription }
            } catch {
                guard !Task.isCancelled else { return }
                phase = places.isEmpty ? .failed(.unreadable) : .loaded
            }
        }

        chargement = tache
        await tache.value
    }

    /// Le message d'un échec survenu alors qu'une liste était déjà affichée.
    var derniereErreur: String?

    func effacerFiltres() {
        temporisation?.cancel()
        type = nil
        department = nil
        // `query` déclenche sa propre temporisation ; on charge une seule fois.
        if !query.isEmpty {
            query = ""
        }
    }

    /// Attend que la frappe se calme avant d'interroger le serveur.
    private func planifier() {
        temporisation?.cancel()
        temporisation = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await charger()
        }
    }

    /// Les critères à poser pour un type de lieu, d'après le référentiel.
    func criteres(pourType type: String?) -> [PlaceCriterion] {
        guard let type, let meta else { return [] }
        return meta.types.first { $0.key == type }?.criteria ?? []
    }
}
