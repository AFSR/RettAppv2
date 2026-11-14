import SwiftUI
import UIKit

/// L'écran d'ouverture, et pourquoi il est en deux morceaux.
///
/// iOS lit l'écran de lancement (clé `UILaunchScreen` de l'`Info.plist`)
/// **avant** d'exécuter la moindre ligne de l'application. Il ne peut donc
/// porter qu'un fond uni : à cet instant, l'app n'a rien pu lui dire. C'est
/// aussi pourquoi `LaunchScreen.storyboard`, qui affichait un logo fixe, a
/// été retiré — un storyboard ne lit pas davantage l'état de l'app.
///
/// D'où le découpage : le système affiche le **fond blanc**
/// (`LaunchBackground`), puis l'application pose par-dessus ce **même** fond
/// le logo complet de l'association. Les deux fonds viennent du même jeu de
/// couleurs du catalogue : le raccord ne se voit pas, seul le logo apparaît.
///
/// Le logo est le **même pour toutes les familles**, quelle que soit l'icône
/// qu'elles ont choisie — décision de l'association, 14 novembre 2026, parmi
/// trois mises en page proposées. L'icône choisie se voit sur l'écran
/// d'accueil et en haut des Actualités, pas ici.
///
/// Blanc de jour comme de nuit, volontairement : le nom de l'association est
/// écrit en violet dans le logo et deviendrait illisible sur fond sombre. Un
/// logo en version claire rendrait le mode sombre possible ; il n'existe dans
/// aucun des deux dépôts.
struct LaunchSplashView: View {

    /// Apparaît une fois le fond du système déjà à l'écran : sans ce fondu,
    /// le logo surgirait d'un coup sur le blanc.
    @State private var shown = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.launchBackground
                .ignoresSafeArea()

            Image("AFSRLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: LaunchSplashMetrics.logoWidth)
                .padding(.horizontal, 40)

            VStack {
                Spacer()
                Text("© AFSR, 2026")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.55))
                    .padding(.bottom, 28)
            }
        }
        // Un seul libellé pour tout l'écran : VoiceOver annonce l'application,
        // pas deux éléments décoratifs successifs.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("RettApp, Association Française du Syndrome de Rett")
        .opacity(shown ? 1 : 0)
        .onAppear {
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.easeOut(duration: 0.25)) { shown = true }
            }
        }
    }
}

/// Les mesures de l'écran d'ouverture, hors du type générique `LaunchSplash` :
/// `LaunchSplashView` les lit aussi, et `LaunchSplash.logoWidth` y aurait
/// demandé d'écrire un paramètre générique qui n'a rien à voir avec une
/// largeur.
enum LaunchSplashMetrics {

    /// Attention : c'est du temps AJOUTÉ au lancement. L'écran du système,
    /// lui, ne durait que le temps réel du démarrage. 600 ms suffisent à voir
    /// le logo ; au-delà, on fait attendre une famille qui ouvre l'app pour
    /// noter une crise en cours. C'est le seul réglage à toucher si
    /// l'ouverture paraît traîner.
    static let hold: Duration = .milliseconds(600)
    static let fade: TimeInterval = 0.25

    /// 200 pt, et c'est une limite, pas un goût : le logo du catalogue fait
    /// 620 px de large, donc 206 pt au plus avant de s'agrandir et de perdre
    /// en netteté sur un écran @3x. L'augmenter demande un fichier source
    /// plus grand — le site en a une version vectorielle.
    static let logoWidth: CGFloat = 200
}

/// Garde l'écran d'ouverture au-dessus du contenu le temps qu'il s'installe,
/// puis l'efface en fondu.
///
/// Le contenu est construit **dessous** pendant ce temps : l'attente sert à
/// montrer le logo, elle ne retarde pas le travail de lancement (vérification
/// iCloud, ouverture du magasin SwiftData).
struct LaunchSplash<Content: View>: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var done = false

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .overlay {
                if !done {
                    LaunchSplashView()
                        .transition(.opacity)
                }
            }
            .task {
                try? await Task.sleep(for: LaunchSplashMetrics.hold)
                // Un fondu reste une animation : on s'en passe quand le
                // système demande de réduire les animations.
                if reduceMotion {
                    done = true
                } else {
                    withAnimation(.easeOut(duration: LaunchSplashMetrics.fade)) { done = true }
                }
            }
    }
}

extension Color {
    /// Le fond de l'écran de lancement, lu dans le catalogue — le même objet
    /// que la clé `UILaunchScreen` désigne. Les deux écrans ne peuvent donc
    /// pas diverger : changer la couleur ici la change des deux côtés.
    static let launchBackground = Color("LaunchBackground")
}

#Preview("Ouverture") {
    LaunchSplashView()
}
