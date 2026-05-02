import UIKit
import CloudKit
import SwiftUI

/// AppDelegate minimal — sert uniquement à intercepter les invitations de partage CloudKit
/// reçues via Messages/Mail/AirDrop. SwiftUI App lifecycle ne propose pas encore d'API
/// directe pour ça (besoin de UISceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)).
///
/// Le metadata accepté est posté via `NotificationCenter` ; l'app racine l'observe et
/// délègue à `CloudKitSyncService.acceptShare(_:)`.
final class RettAppDelegate: NSObject, UIApplicationDelegate {

    static let didReceiveShareMetadata = Notification.Name("RettAppDidReceiveShareMetadata")

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = RettAppSceneDelegate.self
        return config
    }
}

/// Scene delegate qui réceptionne les invitations CloudKit.
final class RettAppSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        NotificationCenter.default.post(
            name: RettAppDelegate.didReceiveShareMetadata,
            object: cloudKitShareMetadata
        )
    }
}
