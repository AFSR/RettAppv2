import SwiftUI
import UIKit

/// `UIActivityViewController` limité à AirDrop : tous les autres canaux iOS standards
/// (Messages, Mail, Copy, Print, Save…) sont exclus pour forcer un transfert **en
/// présentiel** entre les deux iPhones.
///
/// **Présentation directe sur la window** : dans la V1, on utilisait un `.sheet`
/// SwiftUI imbriqué dans un autre sheet (`InvitationCardView`) — empilement que
/// SwiftUI gère mal, le second sheet ne s'affichait jamais. On contourne en
/// présentant le VC directement sur le `keyWindow` via le rootViewController.
@MainActor
enum ProximityShare {
    static func present(url: URL, onComplete: (() -> Void)? = nil) {
        let vc = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        var excluded: [UIActivity.ActivityType] = [
            .postToFacebook, .postToTwitter, .postToWeibo,
            .postToFlickr, .postToTencentWeibo, .postToVimeo,
            .message, .mail, .print, .copyToPasteboard,
            .assignToContact, .saveToCameraRoll, .addToReadingList,
            .markupAsPDF, .openInIBooks
        ]
        if #available(iOS 15.4, *) {
            excluded.append(.sharePlay)
        }
        if #available(iOS 16.0, *) {
            excluded.append(contentsOf: [
                .collaborationCopyLink, .collaborationInviteWithLink
            ])
        }
        if #available(iOS 16.4, *) {
            excluded.append(.addToHomeScreen)
        }
        vc.excludedActivityTypes = excluded
        vc.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        // iPad : popover obligatoire — on ancre au centre de la window.
        if let pop = vc.popoverPresentationController {
            pop.sourceView = topMostWindow()
            if let v = topMostWindow() {
                pop.sourceRect = CGRect(x: v.bounds.midX, y: v.bounds.midY, width: 0, height: 0)
            }
            pop.permittedArrowDirections = []
        }
        topMostController()?.present(vc, animated: true)
    }

    /// Retourne le UIViewController le plus haut dans la hiérarchie pour pouvoir
    /// présenter au-dessus de tous les sheets / popovers en cours.
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
}
