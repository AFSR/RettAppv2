import SwiftUI
import UIKit

/// L'écran d'ouverture, et pourquoi il est en deux morceaux.
///
/// iOS lit l'écran de lancement (clé `UILaunchScreen` de l'`Info.plist`)
/// **avant** d'exécuter la moindre ligne de l'application. Il ne peut donc pas
/// suivre l'icône que la famille a choisie : au moment où il s'affiche,
/// personne n'a encore pu demander laquelle c'est. C'est une limite du
/// système, et elle n'a pas de contournement — c'est aussi pourquoi
/// `LaunchScreen.storyboard`, qui affichait un logo fixe, a été retiré : un
/// storyboard ne peut pas davantage lire un choix fait dans l'app.
///
/// D'où le découpage : le système affiche le **fond noir** (`LaunchBackground`),
/// puis l'application pose par-dessus ce **même** fond l'illustration de
/// l'icône en cours, avec le nom de l'association. Les deux fonds viennent du
/// même jeu de couleurs du catalogue : le raccord ne se voit pas, et seule
/// l'illustration apparaît — celle de l'icône choisie.
///
/// Le contenu est repris du storyboard précédent (logo, nom de l'association,
/// mention de copyright) pour que l'ouverture ne change pas d'aspect : seul le
/// logo fixe devient l'icône du moment.
/// Les mesures de l'écran d'ouverture, hors du type générique `LaunchSplash` :
/// `LaunchSplashView` les lit aussi, et `LaunchSplash.artworkSide` y aurait
/// demandé d'écrire un paramètre générique qui n'a rien à voir avec une taille.
enum LaunchSplashMetrics {

    /// Attention : c'est du temps AJOUTÉ au lancement. L'écran du système,
    /// lui, ne durait que le temps réel du démarrage. 600 ms suffisent à voir
    /// l'illustration ; au-delà, on fait attendre une famille qui ouvre l'app
    /// pour noter une crise en cours. C'est le seul réglage à toucher si
    /// l'ouverture paraît traîner.
    static let hold: Duration = .milliseconds(600)
    static let fade: TimeInterval = 0.25

    /// 112 pt : près du double d'une icône d'écran d'accueil (60 pt), donc
    /// reconnaissable sans occuper l'écran. Les aperçus du catalogue font
    /// 512 px, ce qui couvre cette taille jusqu'en @3x sans agrandissement.
    static let artworkSide: CGFloat = 112
}

struct LaunchSplashView: View {

    /// Apparaît une fois le fond du système déjà à l'écran : sans ce fondu,
    /// l'illustration surgirait d'un coup sur le noir.
    @State private var shown = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Lu dans `body`, donc sur le MainActor, et non dans un initialiseur
        // de propriété : `UIApplication` y est isolée.
        //
        // La source de vérité est `alternateIconName`, pas une copie rangée
        // dans les réglages : une copie qui dériverait afficherait ici une
        // illustration que l'écran d'accueil ne porte pas.
        let option = AppIconOption(alternateIconName: UIApplication.shared.alternateIconName)

        return ZStack {
            Color.launchBackground
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(option.previewName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: LaunchSplashMetrics.artworkSide,
                           height: LaunchSplashMetrics.artworkSide)
                    // 22 % du côté : la proportion d'un coin d'icône iOS.
                    .clipShape(RoundedRectangle(cornerRadius: LaunchSplashMetrics.artworkSide * 0.22,
                                                style: .continuous))

                Text("Association Française du Syndrome de Rett")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            VStack {
                Spacer()
                Text("© AFSR, 2026")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 28)
            }
        }
        // Un seul libellé pour tout l'écran : VoiceOver annonce l'application,
        // pas trois éléments décoratifs successifs.
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

/// Garde l'écran d'ouverture au-dessus du contenu le temps qu'il s'installe,
/// puis l'efface en fondu.
///
/// Le contenu est construit **dessous** pendant ce temps : l'attente sert à
/// montrer l'illustration, elle ne retarde pas le travail de lancement
/// (vérification iCloud, ouverture du magasin SwiftData).
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
    ///
    /// Noir dans les deux apparences, comme l'était le storyboard : les
    /// illustrations d'icônes y tiennent toutes, claires comme sombres.
    static let launchBackground = Color("LaunchBackground")
}

#Preview("Ouverture") {
    LaunchSplashView()
}
