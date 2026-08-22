import AppIntents
import CardCopilotCapture
import CardCopilotEngine
import CardCopilotStore
@preconcurrency import CoreLocation
import Foundation
import UIKit
import UserNotifications
import ClerkKit

struct WalletCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Wallet Purchase to Inunity"
    static let description = IntentDescription("Saves a Wallet transaction locally, then securely syncs it to Inunity.")
    static let openAppWhenRun = false

    @Parameter(title: "Merchant") var merchant: String?
    @Parameter(title: "Amount") var amount: String?
    @Parameter(title: "Name") var transactionName: String?
    @Parameter(title: "Currency") var currency: String?
    @Parameter(title: "Card") var card: String?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ca.inunity.pickme")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outbox = try WalletOutboxStore(root: root)
        let credential = WalletCaptureCredentialStore().load()
        let signedInUserID = await MainActor.run { Clerk.shared.user?.id }
        let accountMismatch = credential.map { signedInUserID != nil && signedInUserID != $0.boundUserID } ?? false
        let uploader = accountMismatch ? nil : credential.flatMap { credential in
            MoneyTalksConfiguration.apiBaseURL.map { WalletCaptureHTTPUploader(baseURL: $0, token: credential.token) }
        }
        let catalogue = try? SeedLoader.loadCatalogue()
        let ownerState = OwnerStateLocalStore().load() ?? (try? SeedLoader.loadOwnerState())
        let coordinator = WalletCaptureCoordinator(
            outbox: outbox,
            uploader: uploader,
            locationProvider: { await WalletIntentLocationSampler.sample() },
            receiptPublisher: { event, offline in
                let verdict = catalogue.flatMap { catalogue in ownerState.flatMap { owner in
                    WalletCaptureIntent.localVerdict(event: event, catalogue: catalogue, ownerState: owner)
                }}
                await WalletCaptureReceiptPublisher.publish(eventID: event.eventId, offline: offline,
                                                             recommendedCard: verdict.flatMap { verdict in
                    catalogue?.cards.first(where: { $0.cardId == verdict.recommendedCardID })?.officialName
                })
            })
        let info = Bundle.main.infoDictionary ?? [:]
        let osVersion = await MainActor.run { UIDevice.current.systemVersion }
        let client = WalletCaptureClient(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: info["CFBundleVersion"] as? String ?? "unknown",
            osVersion: osVersion,
            locale: Locale.current.identifier)
        do {
            _ = try await coordinator.capture(
                .init(merchant: merchant, amount: amount, transactionName: transactionName,
                      currency: currency, card: card, paymentMethod: nil),
                client: client, locale: .current, timezone: .current,
                unassigned: credential == nil || accountMismatch)
            return .result(dialog: credential == nil || accountMismatch
                ? "Purchase saved on this iPhone. Connect Wallet Capture in PickMe to sync it."
                : "Purchase received and saved securely.")
        } catch WalletCaptureError.emptyInput {
            return .result(dialog: "No Wallet fields arrived. Check the automation mappings in Shortcuts.")
        } catch {
            await WalletCaptureReceiptPublisher.failure()
            return .result(dialog: "Purchase could not be saved. Open PickMe for capture status.")
        }
    }

    private static func localVerdict(event: WalletCaptureEvent, catalogue: Catalogue,
                                     ownerState: OwnerState) -> WalletCaptureVerdict? {
        let normalizedRaw = event.transaction.cardRaw?.lowercased().filter(\.isLetter)
        let used = catalogue.cards.first { $0.officialName.lowercased().filter(\.isLetter) == normalizedRaw }?.cardId
        let merchant = event.transaction.merchantRaw ?? event.transaction.transactionNameRaw ?? ""
        let category = CardCopilotStore.predict(poiCategoryRaw: nil, merchantName: merchant).category
        return WalletCaptureVerdictEvaluator.evaluate(event: event, catalogue: catalogue,
                                                      ownerState: ownerState, usedCardID: used,
                                                      category: category)
    }
}

private enum WalletCaptureReceiptPublisher {
    static func publish(eventID: String, offline: Bool, recommendedCard: String?) async {
        let content = UNMutableNotificationContent()
        content.title = "Purchase received"
        if let recommendedCard { content.body = "Saved securely. \(recommendedCard) would have earned more." }
        else { content.body = offline ? "Saved offline. It will sync automatically." : "Saved securely." }
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(.init(identifier: eventID, content: content, trigger: nil))
    }
    static func failure() async {
        let content = UNMutableNotificationContent(); content.title = "Purchase could not be saved"
        content.body = "Open PickMe to review Wallet Capture."; content.sound = .defaultCritical
        try? await UNUserNotificationCenter.current().add(.init(identifier: "wallet-capture-persistence-failure", content: content, trigger: nil))
    }
}

private enum WalletIntentLocationSampler {
    /// The real-device probe received no new fix inside the two-second budget. Reuse only an
    /// already-warm, fresh ambient fix; otherwise capture continues without location.
    @MainActor static func sample() -> WalletCaptureLocation? {
        let manager = CLLocationManager()
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse,
              let value = manager.location,
              Date().timeIntervalSince(value.timestamp) <= 60 else { return nil }
        return .init(latitude: value.coordinate.latitude, longitude: value.coordinate.longitude,
                     horizontalAccuracyMeters: value.horizontalAccuracy, capturedAt: value.timestamp)
    }
}
