import SwiftUI

/// Écran d'accueil de l'usage « découverte » : la porte d'entrée vers
/// l'association pour qui ne suit pas d'enfant.
///
/// Il ne rassemble pour l'instant que ce qui existe réellement dans l'app.
/// Les deux briques annoncées dans la cible — espace adhérent en vue intégrée
/// et information de fond sur la maladie et la recherche — n'y sont pas encore
/// et ne sont donc pas affichées : un écran ne promet rien qu'il ne tienne.
/// Elles viendront se loger ici.
struct DiscoveryHomeView: View {
    @Environment(UsageModeStore.self) private var usageStore
    @State private var showStartSuiviConfirm = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Association Française du Syndrome de Rett")
                        .font(AFSRFont.headline(16))
                    Text("L'AFSR accompagne les familles, informe sur le syndrome de Rett et soutient la recherche.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section {
                NavigationLink {
                    MemberAreaView()
                } label: {
                    Label("Espace adhérent", systemImage: "person.text.rectangle.fill")
                }
            } header: {
                Text("Adhésion")
            } footer: {
                Text("Votre adhésion, vos dons et attestations fiscales, les publications et communications réservées aux adhérents. Connexion par code reçu en SMS ou par e-mail, sans mot de passe.")
            }

            Section {
                NavigationLink {
                    DonationView()
                } label: {
                    Label("Soutenir l'AFSR", systemImage: "heart.circle.fill")
                }
            } header: {
                Text("Soutien")
            }

            Section {
                NavigationLink {
                    AboutSubView()
                } label: {
                    Label("À propos et mentions légales", systemImage: "info.circle.fill")
                }
            } header: {
                Text("Informations")
            }

            Section {
                Button {
                    showStartSuiviConfirm = true
                } label: {
                    Label("Créer un suivi pour un enfant", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Suivi médical")
            } footer: {
                Text("Ouvre l'application complète : journal quotidien, plan médicamenteux, bilan, documents pour le médecin et partage avec l'autre parent.")
            }
        }
        .navigationTitle("AFSR")
        .confirmationDialog(
            "Créer un suivi ?",
            isPresented: $showStartSuiviConfirm,
            titleVisibility: .visible
        ) {
            Button("Créer un suivi") { usageStore.startSuivi() }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Vous allez configurer le profil de l'enfant suivi. L'application passera en mode complet.")
        }
    }
}

#Preview {
    NavigationStack { DiscoveryHomeView() }
        .environment(UsageModeStore.shared)
}
