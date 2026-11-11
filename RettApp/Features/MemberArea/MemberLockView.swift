import SwiftUI

/// Écran affiché tant que l'espace adhérent est verrouillé.
///
/// Aucune donnée personnelle n'y figure : ni nom, ni adhésion. L'invite Face ID
/// s'ouvre d'elle-même à l'arrivée ; si on l'annule, l'écran attend qu'on la
/// relance — il ne la ré-ouvre pas en boucle.
struct MemberLockView: View {
    let session: MemberSession

    @State private var showSignOutConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "faceid")
                    .font(.system(size: 56))
                    .foregroundStyle(.afsrPurpleAdaptive)
                    .padding(.top, 32)
                    .accessibilityHidden(true)

                Text("Espace adhérent verrouillé")
                    .font(AFSRFont.title(22))

                Text("Vos informations d'adhérent, vos dons et vos attestations fiscales sont protégés. Déverrouillez avec Face ID, Touch ID ou le code de votre iPhone.")
                    .font(AFSRFont.body(15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let message = session.lockMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.afsrEmergency)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await session.unlock() }
                } label: {
                    Label("Déverrouiller", systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(session.isUnlocking)

                Button("Se déconnecter", role: .destructive) { showSignOutConfirm = true }
                    .font(AFSRFont.caption())

                MemberPrivacyNotice()
                    .padding(.top, 8)
            }
            .padding()
        }
        .background(Color.afsrBackground)
        .navigationTitle("Espace adhérent")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.unlock() }
        .confirmationDialog(
            "Se déconnecter de votre compte AFSR ?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Se déconnecter", role: .destructive) { Task { await session.signOut() } }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Vos données de suivi ne sont pas concernées : elles restent sur cet appareil et dans votre iCloud.")
        }
    }
}

/// Cadre et confidentialité de l'espace adhérent.
///
/// Affiché sur l'écran de verrouillage et en pied de l'accueil : la personne
/// doit pouvoir lire ce qui est fait de ses données avant comme après s'être
/// déverrouillée.
struct MemberPrivacyNotice: View {
    private static let privacyURL = AFSRLinks.confidentialite

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill").foregroundStyle(.afsrPurpleAdaptive)
                Text("Confidentialité de l'espace adhérent")
                    .font(AFSRFont.headline(16))
            }

            point("Un service de l'AFSR",
                  "L'espace adhérent est géré par l'Association Française du Syndrome de Rett, qui est responsable du traitement de ces données. RettApp n'est pas un dispositif médical et ne remplace pas l'avis d'un professionnel de santé ; en cas d'urgence, appelez le 15 ou le 112.")
            point("Rien n'est conservé dans l'app",
                  "Votre identité, votre adhésion, vos dons et votre famille viennent d'afsr.fr au moment où vous ouvrez un écran. L'app n'en garde pas de copie.")
            point("Une session protégée",
                  "Seul un jeton de connexion est gardé, dans le trousseau de cet iPhone, protégé par Face ID, Touch ID ou votre code. Il ne quitte jamais cet appareil et n'est pas synchronisé par iCloud.")
            point("Face ID reste dans iOS",
                  "L'app reçoit seulement « accepté » ou « refusé » : jamais d'image de votre visage ni de donnée biométrique.")
            point("Verrouillage automatique",
                  "L'espace se referme quand vous quittez l'app plus d'une minute. Après \(MemberSession.maxFailures) refus de déverrouillage, vous êtes déconnecté et la session est révoquée. Les documents ouverts sont effacés à chaque verrouillage.")
            point("Sans lien avec votre suivi",
                  "Votre journal, les crises, les médicaments et les documents médicaux n'ont aucun rapport avec ce compte : ils ne sont jamais envoyés à l'AFSR et restent sur cet appareil et dans votre iCloud.")
            point("Vos droits",
                  "Accès, rectification, effacement : écrivez à contact@afsr.fr.")

            Link(destination: Self.privacyURL) {
                Label("Politique de confidentialité complète", systemImage: "arrow.up.right.square")
                    .font(AFSRFont.caption())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.afsrPurple.opacity(0.08), in: RoundedRectangle(cornerRadius: AFSRTokens.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AFSRTokens.cornerRadius)
                .stroke(Color.afsrPurple.opacity(0.25), lineWidth: 1)
        )
    }

    private func point(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(AFSRFont.caption()).fontWeight(.semibold)
            Text(text)
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
