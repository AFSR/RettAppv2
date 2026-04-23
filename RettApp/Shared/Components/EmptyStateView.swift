import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "tray"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.afsrPurpleLight)
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
