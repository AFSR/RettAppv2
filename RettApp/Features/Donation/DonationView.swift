import SwiftUI

/// Écran « Soutenir l'AFSR ».
///
/// Apple Pay est temporairement désactivé (cf. `DonationService` et
/// `disabled-features/donation-applepay/README.md`). L'utilisateur est dirigé
/// vers le formulaire de don du site afsr.fr, qui accepte CB, virement et
/// prélèvement et envoie automatiquement le reçu fiscal.
struct DonationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            heroSection
            websiteDonationSection
            taxBenefitSection
            disclaimerSection
        }
        .navigationTitle("Soutenir l'AFSR")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.afsrEmergency)
                    Text("Faire un don à l'AFSR")
                        .font(AFSRFont.title(20))
                }
                Text("L'Association Française du Syndrome de Rett accompagne les familles, finance la recherche et porte la voix des personnes atteintes du syndrome de Rett en France.")
                    .font(AFSRFont.body(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    private var websiteDonationSection: some View {
        Section {
            Button {
                UIApplication.shared.open(DonationService.fallbackURL)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.afsrEmergency)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Faire un don sur le site de l'AFSR")
                            .font(AFSRFont.headline(15))
                            .foregroundStyle(.primary)
                        Text("Ouvre afsr.fr dans Safari")
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Faire un don")
        } footer: {
            Text("Le formulaire en ligne de l'AFSR accepte carte bancaire, virement et prélèvement, et vous adresse automatiquement votre reçu fiscal.")
        }
    }

    private var taxBenefitSection: some View {
        Section("Réduction d'impôt") {
            VStack(alignment: .leading, spacing: 6) {
                Text("L'AFSR est une association loi 1901 reconnue d'intérêt général.")
                    .font(AFSRFont.body(13))
                Text("Vos dons sont déductibles à 66 % de votre impôt sur le revenu, dans la limite de 20 % de votre revenu imposable. Un reçu fiscal vous sera adressé par e-mail.")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().padding(.vertical, 2)
                Text("Exemple : un don de 50 € ne vous coûte réellement que 17 € après déduction.")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.afsrPurpleAdaptive)
            }
        }
    }

    private var disclaimerSection: some View {
        Section {
            Text("RettApp facilite votre don mais le traitement comptable est réalisé par l'AFSR via son prestataire de paiement. En cas de question concernant un don, contactez l'AFSR à contact@afsr.fr.")
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack { DonationView() }
}
