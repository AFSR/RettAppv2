import UIKit
import CloudKit
import SwiftUI
import UserNotifications

/// AppDelegate minimal — sert :
///   1. à intercepter les invitations de partage CloudKit reçues via Messages /
///      Mail / AirDrop (`UISceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)`)
///   2. à recevoir les callbacks `UNUserNotificationCenterDelegate` pour que les
///      notifications **s'affichent même quand l'app est au premier plan** (sinon
///      iOS les masque silencieusement par défaut).
final class RettAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    static let didReceiveShareMetadata = Notification.Name("RettAppDidReceiveShareMetadata")

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        StripeBootstrap.configure()
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = RettAppSceneDelegate.self
        return config
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Notification reçue alors que l'app est au premier plan : on demande à iOS
    /// de l'afficher quand même (banner + son + badge), sinon le rappel
    /// médicament n'est jamais visible si l'utilisateur est en train d'utiliser
    /// l'app à l'heure planifiée.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    /// L'utilisateur a tapé sur la notification — on accepte simplement le retour.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
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
