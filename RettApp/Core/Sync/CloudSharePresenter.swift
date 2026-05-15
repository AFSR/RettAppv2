import UIKit
import SwiftUI
import CloudKit

/// Présente `UICloudSharingController` **directement** sur le rootViewController
/// de la window active, sans passer par un `.sheet` SwiftUI.
///
/// Pourquoi : `UICloudSharingController` ne survit pas au hosting controller
/// de SwiftUI quand on l'enveloppe dans un `UIViewControllerRepresentable`
/// dans un `.sheet`. Symptôme : page totalement blanche au présent. C'est un
/// bug iOS bien connu — la solution officielle Apple est de présenter le
/// controller directement via `present(_:animated:)` sur un UIViewController
/// natif. On reproduit ici le pattern qu'on avait déjà pour AirDrop via
/// `ProximityShare.present(url:)`.
@MainActor
enum CloudSharePresenter {

    /// Deux modes selon qu'on partage pour la première fois ou qu'on gère un
    /// partage existant. UICloudSharingController a deux initialiseurs avec
    /// des UIs différentes (cf. doc Apple).
    enum Mode {
        case prepare(() async -> Result<(CKShare, CKContainer), Error>)
        case existing(CKShare, CKContainer)
    }

    static func present(
        mode: Mode,
        title: String,
        onSaved: ((CKShare) -> Void)? = nil,
        onStopped: (() -> Void)? = nil,
        onFailed: ((Error) -> Void)? = nil
    ) {
        let coordinator = Coordinator(
            title: title,
            onSaved: onSaved,
            onStopped: onStopped,
            onFailed: onFailed
        )

        let controller: UICloudSharingController
        switch mode {
        case .prepare(let prepareShare):
            controller = UICloudSharingController { _, completion in
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
        case .existing(let share, let container):
            controller = UICloudSharingController(share: share, container: container)
        }
        // `.allowPublic` est INDISPENSABLE pour qu'AirDrop apparaisse dans la
        // feuille de partage : sans ça, iOS considère que le share ne peut
        // cibler que des participants nommément invités (Mail/Messages avec
        // contact), or AirDrop ne connaît le destinataire qu'au moment du
        // transfert. `.allowPrivate` reste utile pour l'option « Inviter une
        // personne précise » via Messages/Mail.
        controller.availablePermissions = [.allowReadWrite, .allowPrivate, .allowPublic]
        controller.delegate = coordinator
        // UICloudSharingController ne retient son delegate qu'en weak — sans
        // cette association forte, le coordinator est libéré dès la sortie
        // de cette fonction et plus aucun callback ne se déclenche.
        objc_setAssociatedObject(controller, &delegateAssociationKey, coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // iPad : popover obligatoire, on ancre au centre de la window.
        if let pop = controller.popoverPresentationController, let window = topMostWindow() {
            pop.sourceView = window
            pop.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }

        topMostController()?.present(controller, animated: true)
    }

    // MARK: - Internals

    private static var delegateAssociationKey: UInt8 = 0

    private static func topMostController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return nil }
        guard var root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }
        while let presented = root.presentedViewController {
            root = presented
        }
        return root
    }

    private static func topMostWindow() -> UIView? {
        let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        return scene?.windows.first(where: { $0.isKeyWindow })
    }

    private final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String
        let onSaved: ((CKShare) -> Void)?
        let onStopped: (() -> Void)?
        let onFailed: ((Error) -> Void)?

        init(
            title: String,
            onSaved: ((CKShare) -> Void)?,
            onStopped: (() -> Void)?,
            onFailed: ((Error) -> Void)?
        ) {
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
