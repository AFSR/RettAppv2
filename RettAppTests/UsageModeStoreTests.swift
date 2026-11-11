import XCTest
@testable import RettApp

/// L'usage décide de ce que l'app montre. Deux invariants comptent plus que
/// les autres, et ce sont ceux qui coûteraient cher s'ils cassaient :
///
/// 1. une famille qui met à jour depuis une version antérieure ne doit
///    **jamais** voir apparaître l'écran de choix — elle a déjà un profil,
///    donc elle est en usage suivi, point ;
/// 2. le choix doit survivre au redémarrage de l'app, sinon la question
///    reviendrait à chaque lancement.
@MainActor
final class UsageModeStoreTests: XCTestCase {

    /// Un `UserDefaults` isolé par test : on ne touche jamais aux préférences
    /// réelles, et deux tests ne peuvent pas se marcher dessus.
    private func makeDefaults(function: String = #function) -> UserDefaults {
        let suite = "UsageModeStoreTests.\(function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - Premier lancement

    func test_premierLancement_aucunUsageEnregistre() {
        let store = UsageModeStore(defaults: makeDefaults())
        XCTAssertNil(store.usage, "sans choix enregistré, RootView doit poser la question")
    }

    // MARK: - Persistance

    func test_choixSurvitAuRedemarrage() {
        let defaults = makeDefaults()

        let first = UsageModeStore(defaults: defaults)
        first.set(.decouverte)

        // Deuxième instance sur le même stockage = relancement de l'app.
        let afterRelaunch = UsageModeStore(defaults: defaults)
        XCTAssertEqual(afterRelaunch.usage, .decouverte,
                       "la question ne doit pas revenir au lancement suivant")
    }

    func test_valeurInconnueEstTraiteeCommeAbsente() {
        let defaults = makeDefaults()
        defaults.set("mode-dun-futur-build", forKey: UsageModeStore.key)

        let store = UsageModeStore(defaults: defaults)
        XCTAssertNil(store.usage, "une valeur illisible ne doit pas planter ni verrouiller un usage")
    }

    // MARK: - Migration depuis une version antérieure

    func test_adoptSuivi_poseLUsageQuandIlEstAbsent() {
        let store = UsageModeStore(defaults: makeDefaults())
        store.adoptSuiviIfUnset()
        XCTAssertEqual(store.usage, .suivi,
                       "un utilisateur qui a déjà un profil enfant est en usage suivi, sans question")
    }

    /// RÉGRESSION : `adoptSuiviIfUnset` est appelé à chaque apparition de
    /// RootView. Il ne doit jamais écraser un choix délibéré — sans quoi
    /// quelqu'un en découverte qui accepte un partage, ou dont un profil
    /// arrive par iCloud, basculerait en suivi de force.
    func test_adoptSuivi_nEcrasePasUnChoixExistant() {
        let store = UsageModeStore(defaults: makeDefaults())
        store.set(.decouverte)

        store.adoptSuiviIfUnset()
        store.adoptSuiviIfUnset()

        XCTAssertEqual(store.usage, .decouverte, "adoptSuiviIfUnset doit rester un no-op")
    }

    // MARK: - Bascule

    func test_startSuivi_basculeDepuisDecouverte() {
        let defaults = makeDefaults()
        let store = UsageModeStore(defaults: defaults)
        store.set(.decouverte)

        store.startSuivi()

        XCTAssertEqual(store.usage, .suivi)
        XCTAssertEqual(UsageModeStore(defaults: defaults).usage, .suivi,
                       "la bascule doit être persistée, pas seulement en mémoire")
    }
}
