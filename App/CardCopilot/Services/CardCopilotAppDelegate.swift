import UIKit
@preconcurrency import UserNotifications

final class CardCopilotAppDelegate: NSObject, UIApplicationDelegate, @MainActor UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current(); center.delegate = self
        let open = UNNotificationAction(identifier: "OPEN_CAPTURE_STATUS", title: "Open Capture Status", options: [.foreground])
        let diagnostic = UNNotificationAction(identifier: "OPEN_DIAGNOSTIC", title: "Prepare Diagnostic", options: [.foreground])
        center.setNotificationCategories([
            .init(identifier: "WALLET_CAPTURE_RECONNECT", actions: [open], intentIdentifiers: []),
            .init(identifier: "WALLET_CAPTURE_REVIEW", actions: [open, diagnostic], intentIdentifiers: []),
        ])
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
