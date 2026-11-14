import SwiftUI
import UIKit

/// Icônes de l'app proposées dans les Réglages. Les visuels dérivent de la
/// charte graphique AFSR (papillon, magenta `#9e1981`, violet `#3f266c`).
///
/// `assetName` est le nom du jeu d'icônes dans `Assets.xcassets`. Déposer les
/// images ne suffit pas : le nom doit **aussi** figurer dans le réglage de
/// compilation `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`. Sans lui, le
/// catalogue compile bien l'image mais ne la déclare pas comme icône de
/// rechange, et `setAlternateIconName` échoue sur l'appareil — sans que rien
/// ne le signale à la compilation.
///
/// C'est exactement ce qui a empêché le changement d'icône de fonctionner
/// jusqu'à la 1.9 : le réglage était absent du projet, et ce commentaire
/// renvoyait à un `project.yml` supprimé depuis.
///
/// `scripts/generate_xcodeproj.rb` construit désormais ce réglage en lisant
/// les `AppIcon-*.appiconset` du catalogue. Ajouter une icône, c'est donc :
/// déposer le jeu d'images, ajouter l'aperçu, ajouter un cas ici, régénérer.
///
/// `nil` désigne l'icône principale (`AppIcon`), celle qu'iOS rétablit quand
/// on appelle `setAlternateIconName(nil)`.
enum AppIconOption: String, CaseIterable, Identifiable {
    /// Le dégradé magenta et violet, devenu l'icône principale en novembre
    /// 2026. Le ruban qu'il remplace n'a pas disparu : il est passé dans les
    /// alternatives (`ruban`), pour que les familles qui le reconnaissent sur
    /// leur écran d'accueil puissent le garder.
    case defaut
    case clair, magenta, violet, ruban, aile, monogramme

    var id: String { rawValue }

    var assetName: String? {
        switch self {
        case .defaut: return nil
        case .clair: return "AppIcon-Clair"
        case .magenta: return "AppIcon-Magenta"
        case .violet: return "AppIcon-Violet"
        case .ruban: return "AppIcon-Ruban"
        case .aile: return "AppIcon-Aile"
        case .monogramme: return "AppIcon-Monogramme"
        }
    }

    var title: String {
        switch self {
        case .defaut: return "Dégradé magenta et violet"
        case .clair: return "Papillon, fond clair"
        case .magenta: return "Papillon blanc sur magenta"
        case .violet: return "Papillon sur violet"
        case .ruban: return "Ruban, l'icône précédente"
        case .aile: return "Aile seule"
        case .monogramme: return "Monogramme AFSR"
        }
    }

    /// Image d'aperçu (`IconPreview-…` dans `Assets.xcassets`).
    var previewName: String {
        "IconPreview-" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// Retrouve l'option correspondant au nom renvoyé par
    /// `UIApplication.alternateIconName` ; un nom inconnu retombe sur l'icône
    /// principale plutôt que de ne rien cocher.
    ///
    /// Ce repli sert aussi aux mises à jour : une famille qui avait choisi
    /// `AppIcon-Degrade`, retiré des alternatives puisqu'il est devenu
    /// l'icône principale, retombe ici sur `defaut` — et voit exactement le
    /// même visuel qu'avant.
    init(alternateIconName: String?) {
        self = Self.allCases.first { $0.assetName == alternateIconName } ?? .defaut
    }
}

/// L'icône en cours, sous une forme que SwiftUI peut observer.
///
/// `UIApplication.alternateIconName` reste la **source de vérité** — c'est
/// iOS qui décide, et l'app ne stocke aucune copie durable. Mais cette
/// propriété n'est pas observable : un écran qui la lit ne se redessine pas
/// quand l'icône change. D'où ce relais, qui part de ce qu'iOS dit au
/// lancement et n'est modifié qu'après un changement **accepté** par iOS.
///
/// Il existe parce que l'icône ne vit plus seulement dans les Réglages : le
/// haut des Actualités la montre aussi, et doit suivre sans qu'on ait à
/// relancer l'application. (L'écran d'ouverture, lui, porte le logo de
/// l'association et ne dépend pas de ce choix.)
@Observable
@MainActor
final class AppIconStore {
    static let shared = AppIconStore()

    private(set) var current: AppIconOption

    private init() {
        current = AppIconOption(alternateIconName: UIApplication.shared.alternateIconName)
    }

    var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }

    /// Demande le changement à iOS. `current` n'avance qu'en cas de succès :
    /// afficher une icône que l'écran d'accueil ne porte pas serait pire que
    /// de ne rien changer.
    func select(_ option: AppIconOption) async throws {
        guard option != current else { return }
        try await UIApplication.shared.setAlternateIconName(option.assetName)
        current = option
    }
}

/// L'icône de l'app, à la taille demandée, avec le coin des icônes iOS.
///
/// Partagée entre le sélecteur et la barre des Actualités : deux endroits
/// qui doivent montrer la même chose, et qui l'ont montrée différemment tant
/// que chacun dessinait la sienne.
struct AppIconThumbnail: View {
    let option: AppIconOption
    let side: CGFloat
    var bordered = false

    var body: some View {
        // 22 % du côté : la proportion d'un coin d'icône iOS.
        let shape = RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
        Image(option.previewName)
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .clipShape(shape)
            .overlay {
                if bordered {
                    // Un contour discret : sans lui, l'icône à fond clair se
                    // confond avec le fond de la liste.
                    shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                }
            }
            .accessibilityHidden(true)
    }
}

struct AppIconPickerView: View {
    @State private var errorMessage: String?

    var body: some View {
        // Lu dans `body`, donc sur le MainActor, et non dans un initialiseur
        // de propriété : `AppIconStore` y est isolée, comme `MemberSession`.
        let store = AppIconStore.shared

        return List {
            Section {
                ForEach(AppIconOption.allCases) { option in
                    Button {
                        choose(option)
                    } label: {
                        HStack(spacing: 14) {
                            AppIconThumbnail(option: option, side: 56, bordered: true)
                            Text(option.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if option == store.current {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityLabel("Sélectionnée")
                            }
                        }
                    }
                    .accessibilityAddTraits(option == store.current ? .isSelected : [])
                }
            } footer: {
                Text("L'icône change sur l'écran d'accueil et en haut des Actualités. L'écran d'ouverture, lui, porte le logo de l'association. iOS affiche une confirmation à chaque changement.")
            }
        }
        .navigationTitle("Icône de l'app")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Changement impossible", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func choose(_ option: AppIconOption) {
        let store = AppIconStore.shared
        guard store.supportsAlternateIcons else {
            errorMessage = "Cet appareil ne permet pas de changer l'icône."
            return
        }
        Task {
            do {
                try await store.select(option)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
