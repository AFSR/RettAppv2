import SwiftUI
import PassKit

/// Écran de don à l'AFSR.
///
/// Deux modes selon `DonationService.isApplePayEnabled` :
///   - **Désactivé** (état actuel) : présentation simple avec un seul bouton
///     qui renvoie vers le formulaire de don sur le site de l'AFSR.
///   - **Activé** (futur, quand Stripe + backend Vercel + SDK seront branchés) :
///     montants préréglés, paiement Apple Pay natif, historique de dons.
struct DonationView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPreset: Decimal? = 25
    @State private var customAmount: String = ""
    @State private var coordinator: ApplePayDonationCoordinator?
    @State private var statusMessage: StatusMessage?
    @State private var showHistory = false

    private var amount: Decimal {
        if let p = selectedPreset { return p }
        let normalized = customAmount.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized) ?? 0
    }

    private var amountIsValid: Bool {
        amount >= 1 && amount <= 10_000
    }

    var body: some View {
        Form {
            heroSection

            if DonationService.isApplePayEnabled {
                amountSection
                paymentSection
                if !DonationLedger.all().isEmpty {
                    Section {
                        Button {
                            showHistory = true
                        } label: {
                            Label("Historique de mes dons", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
            } else {
                websiteDonationSection
            }

            taxBenefitSection
            disclaimerSection
        }
        .navigationTitle("Soutenir l'AFSR")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $statusMessage) { msg in
            Alert(
                title: Text(msg.title),
                message: Text(msg.body),
                dismissButton: .default(Text("OK")) {
                    if msg.dismissAfter { dismiss() }
                }
            )
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack { DonationHistoryView() }
        }
    }

    // MARK: - Don via le site (mode actuel — Apple Pay désactivé)

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
            Text("Le paiement Apple Pay intégré à l'application sera disponible dans une prochaine version. En attendant, le formulaire en ligne de l'AFSR accepte carte bancaire, virement et prélèvement, et vous adresse automatiquement votre reçu fiscal.")
        }
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

    private var amountSection: some View {
        Section("Montant du don") {
            // Boutons préréglés
            HStack(spacing: 8) {
                ForEach(DonationService.presetAmounts, id: \.self) { value in
                    Button {
                        selectedPreset = value
                        customAmount = ""
                    } label: {
                        Text(formatCurrency(value))
                            .font(AFSRFont.headline(14))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedPreset == value ? .afsrPurpleAdaptive : .secondary)
                    .controlSize(.regular)
                }
            }
            .listRowSeparator(.hidden)

            // Saisie libre
            HStack {
                Text("Autre montant")
                Spacer()
                TextField("0", text: $customAmount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .onChange(of: customAmount) { _, newValue in
                        if !newValue.isEmpty { selectedPreset = nil }
                    }
                Text("€")
            }
        }
    }

    @ViewBuilder
    private var paymentSection: some View {
        let availability = DonationService.availability()
        Section {
            switch availability {
            case .ready:
                ApplePayButtonRepresentable(type: .donate) {
                    Task { await presentApplePay() }
                }
                .frame(height: 50)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .disabled(!amountIsValid)
                .opacity(amountIsValid ? 1 : 0.5)
                fallbackButton
            case .noEligibleCard:
                Label(availability.userMessage, systemImage: "creditcard.trianglebadge.exclamationmark")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                Button {
                    if let url = URL(string: "shoebox://") { UIApplication.shared.open(url) }
                } label: {
                    Label("Ouvrir Wallet pour ajouter une carte", systemImage: "wallet.pass")
                }
                fallbackButton
            case .noWalletConfigured, .unavailable:
                Label(availability.userMessage, systemImage: "info.circle")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                fallbackButton
            }
        } header: {
            Text("Paiement")
        } footer: {
            Text("Le paiement est sécurisé par Apple Pay (3-D Secure / SCA). Aucune information bancaire ne transite par RettApp. Tant que le traitement bancaire n'est pas activé côté AFSR, votre intention de don est consignée dans l'historique et l'AFSR vous contactera pour la finaliser.")
        }
    }

    private var fallbackButton: some View {
        Button {
            UIApplication.shared.open(DonationService.fallbackURL)
        } label: {
            Label("Faire un don sur le site de l'AFSR", systemImage: "safari")
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
                if DonationService.isApplePayEnabled && amountIsValid {
                    Divider().padding(.vertical, 2)
                    HStack {
                        Text("Coût réel après réduction :")
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatCurrency(amount * Decimal(0.34)))
                            .font(AFSRFont.headline(14))
                            .foregroundStyle(.afsrPurpleAdaptive)
                            .monospacedDigit()
                    }
                } else if !DonationService.isApplePayEnabled {
                    Divider().padding(.vertical, 2)
                    Text("Exemple : un don de 50 € ne vous coûte réellement que 17 € après déduction.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.afsrPurpleAdaptive)
                }
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

    // MARK: - Actions

    @MainActor
    private func presentApplePay() async {
        guard amountIsValid else { return }
        let coord = ApplePayDonationCoordinator(amount: amount) { outcome in
            switch outcome {
            case .success(let amount):
                statusMessage = StatusMessage(
                    title: "Merci !",
                    body: "Votre don de \(formatCurrency(amount)) a bien été pris en compte. Un reçu fiscal vous sera envoyé par l'AFSR.",
                    dismissAfter: true
                )
            case .failed(let message):
                statusMessage = StatusMessage(
                    title: "Paiement échoué",
                    body: message,
                    dismissAfter: false
                )
            case .cancelled:
                break
            }
            coordinator = nil
        }
        coordinator = coord
        let presented = await coord.present()
        if !presented {
            statusMessage = StatusMessage(
                title: "Apple Pay indisponible",
                body: "La feuille de paiement n'a pas pu s'afficher. Vous pouvez utiliser le formulaire web ci-dessous.",
                dismissAfter: false
            )
            coordinator = nil
        }
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = DonationService.currencyCode
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.maximumFractionDigits = 0
        if value.isLess(than: 10) { formatter.maximumFractionDigits = 2 }
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value) €"
    }

    private struct StatusMessage: Identifiable {
        let id = UUID()
        let title: String
        let body: String
        let dismissAfter: Bool
    }
}

// MARK: - History view

struct DonationHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DonationLedger.Entry] = DonationLedger.all()

    var body: some View {
        List {
            if entries.isEmpty {
                Text("Aucun don enregistré pour l'instant.")
                    .font(AFSRFont.body(13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.date, format: .dateTime.day().month().year())
                                .font(AFSRFont.body(14))
                            Text(entry.network)
                                .font(AFSRFont.caption())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(format(entry.amount))
                            .font(AFSRFont.headline(15))
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Mes dons")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fermer") { dismiss() }
            }
        }
    }

    private func format(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = DonationService.currencyCode
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: value as NSDecimalNumber) ?? "\(value) €"
    }
}

#Preview {
    NavigationStack { DonationView() }
}
