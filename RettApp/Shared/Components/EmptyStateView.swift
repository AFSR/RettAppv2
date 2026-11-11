import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "tray"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.afsrPurpleAdaptive.opacity(0.08))
                    .frame(width: 128, height: 128)
                Circle()
                    .fill(Color.afsrPurpleAdaptive.opacity(0.14))
                    .frame(width: 92, height: 92)
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.afsrPurpleAdaptive)
            }
            .accessibilityHidden(true)
            .padding(.bottom, 4)
            Text(title)
                .font(AFSRFont.headline())
            Text(message)
                .font(AFSRFont.body())
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let actionTitle, let action {
                AFSRPrimaryButton(title: actionTitle, action: action)
                    .padding(.top, 8)
                    .frame(maxWidth: 300)
            }
        }
        .padding(AFSRTokens.spacingLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView(
        title: "Aucune actualité",
        message: "Aucun article disponible pour le moment.",
        systemImage: "newspaper",
        actionTitle: "Actualiser"
    ) {}
}
