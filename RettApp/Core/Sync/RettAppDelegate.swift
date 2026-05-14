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
    /// Émis quand l'app reçoit un silent push d'une `CKDatabaseSubscription`
    /// (changement distant sur la base privée ou partagée). Écouté dans
    /// `RettAppApp` pour déclencher un `quickPull` immédiat.
    static let cloudKitRemoteChange = Notification.Name("RettAppCloudKitRemoteChange")

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Enregistrement pour les silent push CloudKit. Ne demande PAS de
        // permission utilisateur — `content-available` est invisible.
        application.registerForRemoteNotifications()
        return true
    }

    // MARK: - Silent push (CloudKit subscriptions)

    /// Wakeup en arrière-plan : appelé par iOS quand un silent push arrive.
    /// On vérifie que c'est bien une notification CloudKit (sinon on ignore)
    /// puis on poste une notification interne — `RettAppApp` la capte et
    /// déclenche un pull silencieux qui rafraîchit l'UI via `@Query`.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            completionHandler(.noData)
            return
        }
        // On accepte tous les types CloudKit (.database, .recordZone, .query)
        // — la plus utile est .database, postée par CKDatabaseSubscription.
        _ = notification
        NotificationCenter.default.post(name: Self.cloudKitRemoteChange, object: nil)
        completionHandler(.newData)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Sandbox / simulateur sans Apple ID : non bloquant, on log.
        print("⚠️ registerForRemoteNotifications a échoué : \(error.localizedDescription)")
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
