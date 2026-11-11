import SwiftUI

/// Première question du premier lancement : suivez-vous un enfant ?
///
/// Pourquoi une question explicite plutôt qu'une déduction silencieuse de
/// l'absence de profil : personne ne doit accepter un avertissement médical
/// pour lire une actualité ou faire un don. L'avertissement et la création du
/// profil appartiennent à la branche « suivi » ; ils ne sont plus le péage de
/// tout le monde.
///
/// Cet écran n'apparaît **jamais** à quelqu'un qui a déjà un profil enfant —
/// voir `UsageModeStore.adoptSuiviIfUnset()` et `RootView`.
struct UsageChoiceView: View {
    /// Appelé avec l'usage retenu. La persistance est faite par l'appelant,
    /// pour que cette vue reste purement présentationnelle et testable.
    let onChoice: (AppUsage) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image("RettLogo")
                        .resizable().scaledToFit()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                        .padding(.top, 40)

                    Text("Bienvenue sur RettApp")
                        .font(AFSRFont.title())
                        .multilineTextAlignment(.center)

                    Text("L'application de l'Association Française du Syndrome de Rett.")
                        .font(AFSRFont.body())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Text("Qu'est-ce qui vous amène ?")
                    .font(AFSRFont.headline(17))
                    .padding(.top, 8)

                VStack(spacing: 14) {
                    ForEach(AppUsage.allCases) { usage in
                        Button {
                            onChoice(usage)
                        } label: {
                            choiceCard(usage)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Text("Vous pourrez changer d'avis à tout moment depuis les réglages.")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
            }
        }
        .background(Color.afsrBackground.ignoresSafeArea())
    }

    private func choiceCard(_ usage: AppUsage) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: usage.systemImage)
                .font(.title2)
                .foregroundStyle(.afsrPurpleAdaptive)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(usage.label)
                    .font(AFSRFont.headline(16))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(usage.detailedLabel)
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AFSRTokens.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AFSRTokens.cornerRadius)
                .stroke(Color.afsrPurpleAdaptive.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    UsageChoiceView { _ in }
}
