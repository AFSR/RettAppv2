import XCTest
@testable import RettApp

/// Les noms d'icônes sont des chaînes : une faute de frappe ne casse pas la
/// compilation, elle fait échouer `setAlternateIconName` chez l'utilisateur.
final class AppIconOptionTests: XCTestCase {

    func test_sixIconesAlternativesPlusCelleParDefaut() {
        XCTAssertEqual(AppIconOption.allCases.count, 7)
        XCTAssertEqual(AppIconOption.allCases.filter { $0.assetName == nil }, [.defaut])
        // L'icône par défaut vient en tête : c'est celle que porte l'app tant
        // qu'on n'a rien choisi, et la liste se lit à partir de là.
        XCTAssertEqual(AppIconOption.allCases.first, .defaut)
    }

    func test_nomsUniques() {
        let names = AppIconOption.allCases.compactMap(\.assetName)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func test_retrouveLOptionDepuisLeNomIOS() {
        for option in AppIconOption.allCases {
            XCTAssertEqual(AppIconOption(alternateIconName: option.assetName), option)
        }
        XCTAssertEqual(AppIconOption(alternateIconName: "inconnu"), .defaut)
    }

    /// Le dégradé était une alternative ; il est devenu l'icône principale en
    /// novembre 2026, et `AppIcon-Degrade` a disparu du catalogue. Une famille
    /// qui l'avait choisi garde ce nom enregistré par iOS : il doit retomber
    /// sur l'icône par défaut — qui porte exactement le même visuel — et non
    /// laisser la liste sans aucune coche.
    func test_lAncienNomDuDegradeRetombeSurLIconeParDefaut() {
        XCTAssertEqual(AppIconOption(alternateIconName: "AppIcon-Degrade"), .defaut)
    }

    /// Le ruban était l'icône publiée jusqu'à la 1.9. Il n'a pas été supprimé
    /// mais déplacé dans les alternatives : une famille qui le reconnaît sur
    /// son écran d'accueil doit pouvoir le remettre.
    func test_leRubanResteDisponibleCommeAlternative() {
        XCTAssertEqual(AppIconOption.ruban.assetName, "AppIcon-Ruban")
        XCTAssertEqual(AppIconOption(alternateIconName: "AppIcon-Ruban"), .ruban)
    }

    func test_chaqueIconeADesImagesDansLeCatalogue() {
        for option in AppIconOption.allCases {
            XCTAssertNotNil(UIImage(named: option.previewName), "aperçu manquant : \(option.previewName)")
        }
    }

    // MARK: - Ce que le catalogue seul ne garantit pas

    /// Le test qui manquait.
    ///
    /// Les sept visuels étaient dans `Assets.xcassets` depuis le début, et le
    /// changement d'icône ne fonctionnait pas pour autant : il manquait
    /// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` dans le projet. Sans ce
    /// réglage, le compilateur de catalogue n'écrit pas les entrées ci-dessous
    /// et iOS refuse `setAlternateIconName` — sans que rien n'échoue à la
    /// compilation, ni qu'aucun test d'alors ne s'en aperçoive.
    ///
    /// On interroge donc le bundle construit, pas le catalogue source : c'est
    /// la seule chose que l'appareil regarde.
    func test_chaqueIconeAlternativeEstDeclareeDansLeBundle() throws {
        let icons = try XCTUnwrap(
            Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            "CFBundleIcons absent : aucune icône n'est déclarée dans le bundle"
        )
        let alternates = icons["CFBundleAlternateIcons"] as? [String: Any] ?? [:]

        for option in AppIconOption.allCases {
            guard let name = option.assetName else { continue }
            XCTAssertNotNil(
                alternates[name],
                """
                Icône de rechange non déclarée dans le bundle : \(name).
                Vérifiez ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES, puis
                relancez `ruby scripts/generate_xcodeproj.rb`.
                """
            )
        }
    }

    // MARK: - L'écran d'ouverture

    /// Les aperçus sont agrandis depuis le catalogue, et deviennent flous en
    /// dessous de la taille affichée en @3x. Le plus exigeant des deux
    /// usages est le sélecteur, à 56 pt — la barre des Actualités n'en
    /// demande que 28.
    func test_lesApercusCouvrentLePlusGrandUsageEnTroisX() {
        let requis: CGFloat = 56 * 3
        for option in AppIconOption.allCases {
            let image = UIImage(named: option.previewName)
            XCTAssertGreaterThanOrEqual(
                image?.size.width ?? 0, requis,
                "aperçu trop petit : \(option.previewName)"
            )
        }
    }

    /// L'écran d'ouverture porte le logo complet de l'association, le même
    /// pour toutes les familles. Sans ce fichier, il s'ouvrirait sur un
    /// rectangle blanc vide — et rien ne le signalerait à la compilation.
    func test_leLogoDeLAssociationEstDansLeCatalogue() throws {
        let logo = try XCTUnwrap(UIImage(named: "AFSRLogo"), "AFSRLogo absent du catalogue")
        // Le logo est agrandi jusqu'à `logoWidth` : en dessous de trois fois
        // cette largeur, il est flou sur un écran @3x.
        XCTAssertGreaterThanOrEqual(logo.size.width, LaunchSplashMetrics.logoWidth * 3)
    }

    /// L'écran de lancement du système et celui de l'app doivent partager le
    /// même fond, sinon le raccord se voit au démarrage. Le fond vient du
    /// catalogue justement pour que les deux lisent le même objet.
    func test_lEcranDeLancementEtLAppPartagentLeMemeFond() throws {
        let infos = try XCTUnwrap(Bundle.main.infoDictionary)

        // Un storyboard l'emporterait sur `UILaunchScreen` : sa présence
        // ramènerait le logo fixe, qui ne peut pas suivre l'icône choisie.
        XCTAssertNil(infos["UILaunchStoryboardName"])

        let launch = infos["UILaunchScreen"] as? [String: Any]
        XCTAssertEqual(launch?["UIColorName"] as? String, "LaunchBackground")
        XCTAssertNotNil(UIColor(named: "LaunchBackground"),
                        "fond de lancement absent du catalogue : iOS ouvrirait sur du blanc")
    }
}
