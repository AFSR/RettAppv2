import SwiftUI
import SwiftData

/// Bandeau global signalant à l'utilisateur qu'une synchro CloudKit est en
/// erreur ou qu'il reste des écritures locales non poussées vers le nuage.
///
/// Design :
/// - Rouge quand le service est en `.error(...)` — même sémantique que le
///   bandeau d'update, on le veut visible sans être bloquant.
/// - Orange quand tout est OK mais le buffer contient encore des écritures
///   (ex. device offline, resté en local, seront poussées dès que possible).
/// - Rien quand tout est vert et le buffer est vide.
///
/// L'utilisateur peut tap pour forcer une resynchro immédiate.
struct SyncStatusBanner: View {
    @Environment(CloudKitSyncService.self) private var sync
    @Environment(\.modelContext) private var modelContext

    /// Re-observé à chaque changement d'état de sync pour rafraîchir le
    /// compteur d'écritures en attente.
    @State private var isRetrying: Bool = false

    var body: some View {
        if let state = currentState {
            HStack(spacing: 12) {
                Image(systemName: state.icon)
                    .font(.title3)
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(state.detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button {
                    Task {
                        isRetrying = true
                        await sync.syncNow(context: modelContext)
                        isRetrying = false
                    }
                } label: {
                    if isRetrying {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                            .frame(width: 60)
                    } else {
                        Text("Réessayer")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.white.opacity(0.22)))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRetrying)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: state.gradientColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }

    private var currentState: BannerState? {
        if case .error(let msg) = sync.syncState {
            return BannerState(
                icon: "exclamationmark.triangle.fill",
                title: "Synchro iCloud en échec",
                detail: msg,
                gradientColors: [Color(uiColor: .systemRed), Color(uiColor: .systemRed).opacity(0.8)]
            )
        }
        let pending = sync.pendingWriteCount
        if pending > 0 && sync.role != .none {
            return BannerState(
                icon: "arrow.triangle.2.circlepath.icloud",
                title: pending == 1 ? "1 modification en attente" : "\(pending) modifications en attente",
                detail: "Elles partiront dès que la connexion sera stable.",
                gradientColors: [Color(uiColor: .systemOrange), Color(uiColor: .systemOrange).opacity(0.85)]
            )
        }
        return nil
    }

    private struct BannerState {
        let icon: String
        let title: String
        let detail: String
        let gradientColors: [Color]
    }
}
