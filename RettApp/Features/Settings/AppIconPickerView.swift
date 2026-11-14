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
    case actuelle, clair, magenta, violet, degrade, aile, monogramme

    var id: String { rawValue }

    var assetName: String? {
        switch self {
        case .actuelle: return nil
        case .clair: return "AppIcon-Clair"
        case .magenta: return "AppIcon-Magenta"
        case .violet: return "AppIcon-Violet"
        case .degrade: return "AppIcon-Degrade"
        case .aile: return "AppIcon-Aile"
        case .monogramme: return "AppIcon-Monogramme"
        }
    }

    var title: String {
        switch self {
        case .actuelle: return "Icône actuelle"
        case .clair: return "Papillon, fond clair"
        case .magenta: return "Papillon blanc sur magenta"
        case .violet: return "Papillon sur violet"
        case .degrade: return "Dégradé magenta et violet"
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
    init(alternateIconName: String?) {
        self = Self.allCases.first { $0.assetName == alternateIconName } ?? .actuelle
    }
}

struct AppIconPickerView: View {
    @State private var selected = AppIconOption(
        alternateIconName: UIApplication.shared.alternateIconName
    )
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(AppIconOption.allCases) { option in
                    Button {
                        choose(option)
                    } label: {
                        HStack(spacing: 14) {
                            Image(option.previewName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                                )
                                .accessibilityHidden(true)
                            Text(option.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if option == selected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityLabel("Sélectionnée")
                            }
                        }
                    }
                    .accessibilityAddTraits(option == selected ? .isSelected : [])
                }
            } footer: {
                Text("L'icône change sur l'écran d'accueil et sur l'écran d'ouverture de l'application. iOS affiche une confirmation à chaque changement.")
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

    private func choose(_ option: AppIconOption) {
        guard option != selected else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = "Cet appareil ne permet pas de changer l'icône."
            return
        }
        UIApplication.shared.setAlternateIconName(option.assetName) { error in
            DispatchQueue.main.async {
                if let error {
                    errorMessage = error.localizedDescription
                } else {
                    selected = option
                }
            }
        }
    }
}
