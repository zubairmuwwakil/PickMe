import UIKit
@preconcurrency import UserNotifications

final class CardCopilotAppDelegate: NSObject, UIApplicationDelegate, @MainActor UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // Construct the one shared location runtime during launch, not when SwiftUI eventually
        // renders its root view. Core Location uses this path to relaunch a terminated app for a
        // queued significant-change or region event; the runtime retains an early arrival until
        // the catalogue and owner state finish loading.
        let ambient = AmbientLocationService.shared
        ambient.registerNotificationCategories()
        ambient.resumeMonitoringIfAuthorized()
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.userInfo["route"] as? String == "walletCaptureStatus" ||
           response.actionIdentifier == "OPEN_CAPTURE_STATUS" || response.actionIdentifier == "OPEN_DIAGNOSTIC" {
            WalletCaptureDeepLinkStore.markPending()
            NotificationCenter.default.post(name: .openWalletCaptureStatus, object: nil)
        } else if response.notification.request.content.userInfo["route"] as? String == "creditReminders" {
            NotificationCenter.default.post(name: .openCreditReminders, object: nil)
        } else {
            await MainActor.run {
                AmbientLocationService.shared.handleNotificationResponse(response)
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge, .list]
    }
}

extension Notification.Name {
    static let openWalletCaptureStatus = Notification.Name("openWalletCaptureStatus")
    static let openCreditReminders = Notification.Name("openCreditReminders")
}
