import SwiftUI
import UIKit
import CloudKit

/// Présentation native du partage CKShare via `UICloudSharingController`.
///
/// C'est l'API officielle Apple pour partager un CKShare : elle propose AirDrop
/// de façon fluide (les destinataires apparaissent dès qu'ils sont à portée),
/// gère l'invitation Messages/Mail si activé, l'affichage du QR-code partagé,
/// l'ajout/suppression de participants, et déclenche `accept(_:)` côté receveur
/// quand on tape sur le lien.
///
/// La V1 utilisait `UIActivityViewController` avec une simple URL — iOS la
/// traitait comme un lien quelconque, AirDrop mettait du temps à apparaître,
/// et il fallait parfois recliquer plusieurs fois sur la cible. Ce wrapper
/// corrige ces problèmes.
struct CloudShareSheet: UIViewControllerRepresentable {

    /// Préparation asynchrone du `CKShare` à présenter. iOS appellera ce closure
    /// au bon moment du flow et attendra le résultat avant d'afficher la
    /// feuille d'options de partage.
    let prepareShare: () async -> Result<(CKShare, CKContainer), Error>

    /// Nom à afficher dans la feuille système (« iPhone de Marc voudrait
    /// partager … » — l'utilisateur destinataire voit ce texte avant
    /// d'accepter).
    let title: String

    /// Callbacks pour informer la vue parente de l'issue de la session de
    /// partage. Tous optionnels.
    var onSaved: ((CKShare) -> Void)? = nil
    var onStopped: (() -> Void)? = nil
    var onFailed: ((Error) -> Void)? = nil

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController { _, completion in
            Task { @MainActor in
                let result = await prepareShare()
                switch result {
                case .success(let (share, container)):
                    completion(share, container, nil)
                case .failure(let error):
                    completion(nil, nil, error)
                }
            }
        }
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        // iPad : popover obligatoire. On laisse iOS choisir la sourceView
        // par défaut puisque cette vue est présentée via .sheet SwiftUI.
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(title: title, onSaved: onSaved, onStopped: onStopped, onFailed: onFailed)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String
        let onSaved: ((CKShare) -> Void)?
        let onStopped: (() -> Void)?
        let onFailed: ((Error) -> Void)?

        init(title: String,
             onSaved: ((CKShare) -> Void)?,
             onStopped: (() -> Void)?,
             onFailed: ((Error) -> Void)?) {
            self.title = title
            self.onSaved = onSaved
            self.onStopped = onStopped
            self.onFailed = onFailed
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onFailed?(error)
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            if let share = csc.share { onSaved?(share) }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onStopped?()
        }
    }
}
