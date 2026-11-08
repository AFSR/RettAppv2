import SwiftUI

/// Espace adhérent : coordonnées, famille, adhésion, dons et attestations
/// fiscales, publications et communications réservées aux adhérents.
///
/// Tout cela existe déjà sur afsr.fr et y vit très bien : l'adhésion, les
/// droits selon que l'adhésion est à jour, la génération des attestations.
/// Le refaire en natif reviendrait à le maintenir deux fois, pour un résultat
/// qui divergerait au premier changement de statuts. L'app affiche donc les
/// pages du site, dans une mise en page que le site rend sans son propre
/// chrome quand il reconnaît l'application.
///
/// La connexion se fait par code reçu en SMS ou par e-mail, sans mot de passe,
/// directement dans la page — rien à stocker côté app.
struct MemberAreaView: View {
    /// Point d'entrée. Le site redirige vers la connexion si la session n'est
    /// pas ouverte, puis revient ici.
    static let entryURL = URL(string: "https://afsr.fr/mon-compte")!
    static let logoutURL = URL(string: "https://afsr.fr/mon-compte/deconnexion")!

    @State private var isLoading = true
    @State private var canGoBack = false
    @State private var goBackRequested = false
    @State private var errorMessage: String?
    @State private var destination: URL = MemberAreaView.entryURL
    @State private var showLogoutConfirm = false

    var body: some View {
        ZStack(alignment: .top) {
            AFSRWebView(
                url: destination,
                isLoading: $isLoading,
                canGoBack: $canGoBack,
                goBackRequested: $goBackRequested,
                errorMessage: $errorMessage
            )
            .ignoresSafeArea(edges: .bottom)
            // Recharger la vue entière quand la destination change (connexion
            // ou déconnexion) : plus sûr que de piloter la navigation à
            // distance, et ça repart d'une page propre.
            .id(destination)

            if isLoading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.afsrPurpleAdaptive)
            }

            if let errorMessage {
                offlineBanner(errorMessage)
            }
        }
        .navigationTitle("Espace adhérent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if canGoBack {
                    Button {
                        goBackRequested = true
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel("Page précédente")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        destination = MemberAreaView.entryURL
                    } label: {
                        Label("Mon compte", systemImage: "person.crop.circle")
                    }
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.forward")
                    }
                    Divider()
                    Link(destination: MemberAreaView.entryURL) {
                        Label("Ouvrir dans Safari", systemImage: "safari")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Actions du compte")
            }
        }
        .confirmationDialog(
            "Se déconnecter de votre compte AFSR ?",
            isPresented: $showLogoutConfirm,
            titleVisibility: .visible
        ) {
            Button("Se déconnecter", role: .destructive) {
                destination = MemberAreaView.logoutURL
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            // Lever l'ambiguïté : le compte AFSR n'a rien à voir avec les
            // données de suivi, qui vivent sur l'appareil et dans l'iCloud
            // personnel. Se déconnecter ici n'y touche pas.
            Text("Vos données de suivi ne sont pas concernées : elles restent sur cet appareil et dans votre iCloud.")
        }
    }

    private func offlineBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.afsrWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Page indisponible")
                    .font(AFSRFont.caption())
                    .fontWeight(.semibold)
                Text(message)
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Réessayer") {
                // Forcer un rechargement en repassant par la même URL : on
                // remplace la valeur pour que `.id(destination)` change.
                let current = destination
                destination = MemberAreaView.entryURL
                if current != MemberAreaView.entryURL { destination = current }
            }
            .font(AFSRFont.caption())
        }
        .padding(12)
        .background(Color.afsrWarning.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

#Preview {
    NavigationStack { MemberAreaView() }
}
