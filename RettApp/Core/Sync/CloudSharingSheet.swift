import SwiftUI
import CloudKit

/// Wrapper SwiftUI autour de `UICloudSharingController`, l'UI native Apple pour partager
/// un CKShare. Présente :
/// - les destinataires actuels et leur statut (en attente / accepté)
/// - les permissions (lecture / lecture+écriture)
/// - le bouton « Copier le lien »
/// - le partage via Messages, Mail, AirDrop
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    var onSaveCompleted: (() -> Void)?
    var onStopSharing: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSaveCompleted: onSaveCompleted, onStopSharing: onStopSharing)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onSaveCompleted: (() -> Void)?
        let onStopSharing: (() -> Void)?

        init(onSaveCompleted: (() -> Void)?, onStopSharing: (() -> Void)?) {
            self.onSaveCompleted = onSaveCompleted
            self.onStopSharing = onStopSharing
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            // Ignore silencieusement (Apple gère l'affichage de l'erreur native)
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            csc.share?[CKShare.SystemFieldKey.title] as? String ?? "Suivi RettApp"
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onSaveCompleted?()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onStopSharing?()
        }
    }
}
