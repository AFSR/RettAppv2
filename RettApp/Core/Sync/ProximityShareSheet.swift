import SwiftUI
import UIKit

/// `UIActivityViewController` limité à AirDrop : tous les autres canaux iOS standards
/// (Messages, Mail, Copy, Print, Save…) sont exclus pour forcer un transfert **en
/// présentiel** entre les deux iPhones.
///
/// Limitation iOS : on ne peut pas garantir l'absence de partage tiers (apps installées
/// par l'utilisateur peuvent apparaître). Mais on rend AirDrop le seul canal Apple natif.
struct ProximityShareSheet: UIViewControllerRepresentable {
    let url: URL
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        // Liste explicite de tous les types Apple natifs à exclure.
        // AirDrop est volontairement ABSENT de cette liste → seule option Apple disponible.
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
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
