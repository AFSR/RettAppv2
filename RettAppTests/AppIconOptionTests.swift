import XCTest
@testable import RettApp

/// Les noms d'icônes sont des chaînes : une faute de frappe ne casse pas la
/// compilation, elle fait échouer `setAlternateIconName` chez l'utilisateur.
final class AppIconOptionTests: XCTestCase {

    func test_sixIconesAlternativesPlusLActuelle() {
        XCTAssertEqual(AppIconOption.allCases.count, 7)
        XCTAssertEqual(AppIconOption.allCases.filter { $0.assetName == nil }, [.actuelle])
    }

    func test_nomsUniques() {
        let names = AppIconOption.allCases.compactMap(\.assetName)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func test_retrouveLOptionDepuisLeNomIOS() {
        for option in AppIconOption.allCases {
            XCTAssertEqual(AppIconOption(alternateIconName: option.assetName), option)
        }
        XCTAssertEqual(AppIconOption(alternateIconName: "inconnu"), .actuelle)
    }

    func test_chaqueIconeADesImagesDansLeCatalogue() {
        for option in AppIconOption.allCases {
            XCTAssertNotNil(UIImage(named: option.previewName), "aperçu manquant : \(option.previewName)")
        }
    }
}
