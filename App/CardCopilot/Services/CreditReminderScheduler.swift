import Foundation
@preconcurrency import UserNotifications
import CardCopilotEngine

@MainActor
enum CreditReminderScheduler {
    private static let identifierPrefix = "credit.reminder."

    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    static func enableAndRefresh(_ opportunities: [CreditOpportunity]) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        guard allowed else { return false }
        await refresh(opportunities)
        return true
    }

    static func refresh(_ opportunities: [CreditOpportunity]) async {
        guard await isAuthorized() else { return }
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)

        // iOS caps pending notifications. Two reminders for the 24 soonest credits leaves room
        // for Wallet Capture and ambient alerts owned by other product surfaces.
        for opportunity in opportunities
            .filter({ $0.remainingAmount > 0 && ($0.status == .available || $0.status == .needsEnrollment) })
            .prefix(24) {
            guard let expiresOn = opportunity.window.expiresOn else { continue }
            for leadDays in [7, 1] {
                guard let components = triggerComponents(expiresOn: expiresOn,
                                                         leadDays: leadDays) else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Card credit expires soon"
                content.body = opportunity.status == .needsEnrollment
                    ? "Open PickMe to enroll and review an unused card credit."
                    : "Open PickMe to review an unused card credit."
                content.sound = .default
                content.userInfo["route"] = "creditReminders"
                let identifier = identifierPrefix
                    + "\(opportunity.cardId).\(opportunity.creditId).\(leadDays)"
                try? await center.add(UNNotificationRequest(
                    identifier: identifier, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                ))
            }
        }
    }

    private static func triggerComponents(expiresOn: String, leadDays: Int) -> DateComponents? {
        let parts = expiresOn.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let expiry = calendar.date(from: DateComponents(year: parts[0], month: parts[1],
                                                               day: parts[2], hour: 9)),
              let fire = calendar.date(byAdding: .day, value: -leadDays, to: expiry),
              fire > Date() else { return nil }
        return calendar.dateComponents([.year, .month, .day, .hour], from: fire)
    }
}
