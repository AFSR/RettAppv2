import SwiftUI

/// Écran d'accueil de l'usage « découverte » : la porte d'entrée vers
/// l'association pour qui ne suit pas d'enfant.
///
/// Il ne rassemble que ce qui existe réellement dans l'app : l'espace adhérent
/// (écrans natifs, voir `MemberAreaView`), le don et les mentions légales.
/// L'information de fond sur la maladie et la recherche n'y est pas encore et
/// n'est donc pas affichée : un écran ne promet rien qu'il ne tienne.
struct DiscoveryHomeView: View {
    @Environment(UsageModeStore.self) private var usageStore
    @State private var showStartSuiviConfirm = false

    var body: some View {
        List {
            Section {
                AFSRHeroHeader(
                    title: "Association Française du Syndrome de Rett",
                    subtitle: "L'AFSR accompagne les familles, informe sur le syndrome de Rett et soutient la recherche.",
                    systemImage: "heart.fill"
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // Connecté, l'espace adhérent a son propre onglet.
            if !MemberSession.shared.isSignedIn {
                Section {
                    NavigationLink {
                        MemberAreaView()
                    } label: {
                        AFSRRowLabel(title: "Espace adhérent", systemImage: "person.text.rectangle.fill", color: .afsrPurple)
                    }
                } header: {
                    Text("Adhésion")
                } footer: {
                    Text("Votre adhésion, vos dons et attestations fiscales, les publications et communications réservées aux adhérents. Connexion par code reçu en SMS ou par e-mail, sans mot de passe.")
                }
            }

            Section {
                NavigationLink {
                    DonationView()
                } label: {
                    AFSRRowLabel(title: "Soutenir l'AFSR", systemImage: "heart.fill", color: .afsrEmergency)
                }
            } header: {
                Text("Soutien")
            }

            Section {
                NavigationLink {
                    AboutSubView()
                } label: {
                    AFSRRowLabel(title: "À propos et mentions légales", systemImage: "info.circle.fill", color: Color(hex: "#8E8E93"))
                }
            } header: {
                Text("Informations")
            }

            Section {
                Button {
                    showStartSuiviConfirm = true
                } label: {
                    AFSRRowLabel(title: "Créer un suivi pour un enfant", systemImage: "plus", color: .afsrSuccess)
                }
            } header: {
                Text("Suivi médical")
            } footer: {
                Text("Ouvre l'application complète : journal quotidien, plan médicamenteux, bilan, documents pour le médecin et partage avec l'autre parent.")
            }
        }
        .afsrListBackground()
        .navigationTitle("AFSR")
        .navigationBarTitleDisplayMode(.inline)
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
