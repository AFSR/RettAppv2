import SwiftUI

/// Bandeau non intrusif affiché en haut de l'app quand une version plus
/// récente que celle installée est disponible sur l'App Store.
///
/// Design :
/// - Pastille compacte (une seule ligne + une icône) pour ne pas
///   « manger » l'écran des parents.
/// - Toute la surface est un bouton — tap → ouvre la fiche App Store en
///   `itms-apps://` (deep link direct dans l'app App Store, sans passer
///   par Safari).
/// - Croix (x) pour dismisser : le bandeau ne se réaffiche qu'à la sortie
///   d'une version encore plus récente (persistance dans UserDefaults côté
///   `UpdateAvailabilityService`).
struct UpdateAvailabilityBanner: View {
    let info: UpdateAvailabilityService.UpdateInfo
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mise à jour disponible")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Version \(info.latestVersion) sur l'App Store")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer(minLength: 8)

            Button {
                openURL(info.appStoreURL)
            } label: {
                Text("Mettre à jour")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(.white.opacity(0.22))
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ignorer la mise à jour")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.afsrPurpleAdaptive, Color.afsrPurpleAdaptive.opacity(0.85)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre la fiche RettApp sur l'App Store pour installer la version \(info.latestVersion)")
    }
}

#Preview {
    UpdateAvailabilityBanner(
        info: .init(
            latestVersion: "1.6.0",
            currentVersion: "1.5.0",
            appStoreURL: URL(string: "https://apps.apple.com/app/id0000000000")!,
            releaseNotes: nil
        ),
        onDismiss: {}
    )
}
