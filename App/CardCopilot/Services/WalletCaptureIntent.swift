import AppIntents
import CardCopilotCapture
import CardCopilotEngine
import CardCopilotStore
import Foundation
import UIKit
import ClerkKit

struct WalletCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Wallet Purchase to In Unity"
    static let description = IntentDescription("Saves a Wallet transaction locally, then securely syncs it to In Unity.")
    static let openAppWhenRun = false

    @Parameter(title: "Merchant") var merchant: String?
    @Parameter(title: "Amount") var amount: String?
    @Parameter(title: "Name") var transactionName: String?
    @Parameter(title: "Currency") var currency: String?
    @Parameter(title: "Card") var card: String?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let info = Bundle.main.infoDictionary ?? [:]
        let osVersion = await MainActor.run { UIDevice.current.systemVersion }
        let client = WalletCaptureClient(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: info["CFBundleVersion"] as? String ?? "unknown",
            osVersion: osVersion,
            locale: Locale.current.identifier)
        let input = WalletCaptureInput(merchant: merchant, amount: amount, transactionName: transactionName,
                                       currency: currency, card: card, paymentMethod: nil)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let runLogs = try? WalletCaptureShortcutRunLogStore(documentsDirectory: documents)
        let enabled = WalletCaptureSettingsStore().load().isEnabled
        let run = WalletCaptureShortcutRunLog(input: input, client: client, captureEnabled: enabled)
        try? await runLogs?.begin(run)

        guard enabled else {
            try? await runLogs?.finish(runID: run.runID, outcome: "captureDisabled")
            return .result(dialog: "Wallet Capture is disabled. Open PickMe to enable it again.")
        }
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ca.inunity.pickme")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outbox: WalletOutboxStore
        do {
            outbox = try WalletOutboxStore(root: root)
        } catch {
            try? await runLogs?.finish(runID: run.runID, outcome: "captureFailed",
                                       safeError: "localStoreUnavailable")
            await WalletCaptureNotificationCoordinator.persistenceFailure()
            return .result(dialog: "Purchase could not be saved. Open PickMe for capture status.")
        }
        let diagnostics = try? WalletCaptureDiagnosticsStore(root: root)
        let credential = WalletCaptureCredentialStore().load()
        let connection = WalletCaptureSettingsStore().load()
        let signedInUserID = await MainActor.run { ClerkSession.currentUserID }
        let delivery = WalletCaptureDeliveryDecision.decide(
            credentialBoundUserID: credential?.boundUserID,
            connection: connection,
            signedInUserID: signedInUserID)
        let usableCredential = delivery.canUpload ? credential : nil
        let uploader = usableCredential.flatMap { credential in
            MoneyTalksConfiguration.apiBaseURL.map { WalletCaptureHTTPUploader(baseURL: $0, token: credential.token) }
        }
        let catalogue = try? SeedLoader.loadCatalogue()
        let ownerState = OwnerStateLocalStore().loadForRecommendation()
        let aliases = WalletCardAliasStore()
        let capSyncAt = usableCredential.flatMap { SyncMetadataStore().lastSyncedAt(forUserID: $0.boundUserID) }
        let coordinator = WalletCaptureCoordinator(
            outbox: outbox,
            uploader: uploader,
            diagnostics: diagnostics,
            locationProvider: { await WalletIntentLocationSampler.sample() },
            verdictProvider: { event in
                guard let catalogue, let ownerState else { return .init(issue: "ownerStateUnavailable", capDataIsStale: true) }
                return WalletCaptureIntent.localVerdict(event: event, catalogue: catalogue,
                                                        ownerState: ownerState, aliases: aliases,
                                                        capSyncAt: capSyncAt)
            },
            receiptPublisher: { receipt in
                let name = receipt.verdict.verdict.flatMap { verdict in
                    catalogue?.cards.first(where: { $0.cardId == verdict.recommendedCardID })?.officialName
                }
                await WalletCaptureNotificationCoordinator.publish(receipt, catalogueCardName: name)
            },
            drainObserver: { summary in await WalletCaptureNotificationCoordinator.publishDrain(summary) },
            isOffline: { WalletCaptureNetworkMonitor.shared.isOffline })
        do {
            let event = try await coordinator.capture(
                input,
                client: client, locale: .current, timezone: .current,
                unassigned: delivery.accountRouting == .unassigned)
            let diagnostic = try? await diagnostics?.record(eventID: event.eventId)
            if !event.isMeaningful {
                try? await runLogs?.finish(runID: run.runID, outcome: "mappingIncomplete", event: event,
                                            diagnostic: diagnostic)
                return .result(dialog: "No Wallet fields arrived. The trigger was retained for review; check the automation mappings in PickMe.")
            }
            // A tap is the strongest evidence there is that the owner shops here, and it is
            // the only such evidence that arrives without asking them for anything. Recorded
            // from the merchant string alone: the coordinate never leaves the outbox, and brand
            // standing does not need it.
            if let key = patronageKey(forCapturedMerchant: event.transaction.merchantRaw,
                                      transactionName: event.transaction.transactionNameRaw) {
                MerchantPatronageStore().recordVisit(
                    merchantKey: key,
                    displayName: event.transaction.merchantRaw ?? event.transaction.transactionNameRaw,
                    at: event.capturedAt)
            }
            try? await runLogs?.finish(runID: run.runID,
                                        outcome: diagnostic?.deliveryState == .accepted || diagnostic?.deliveryState == .duplicate
                                            ? "savedAndDelivered" : "savedLocally",
                                        event: event, diagnostic: diagnostic)
            return .result(dialog: delivery.accountRouting == .unassigned
                ? "Purchase saved on this iPhone. Connect Wallet Capture in PickMe to sync it."
                : "Purchase received and saved securely.")
        } catch {
            try? await runLogs?.finish(runID: run.runID, outcome: "captureFailed",
                                        safeError: "localPersistenceFailed")
            await WalletCaptureNotificationCoordinator.persistenceFailure()
            return .result(dialog: "Purchase could not be saved. Open PickMe for capture status.")
        }
    }

    private static func localVerdict(event: WalletCaptureEvent, catalogue: Catalogue,
                                     ownerState: OwnerState, aliases: WalletCardAliasStore,
                                     capSyncAt: Date?) -> WalletCaptureVerdictEvaluation {
        let normalizedRaw = event.transaction.cardRaw?.lowercased().filter(\.isLetter)
        let exactOfficial = catalogue.cards.first { $0.officialName.lowercased().filter(\.isLetter) == normalizedRaw }?.cardId
        let used = aliases.cardID(for: event.transaction.cardRaw) ?? exactOfficial
        guard used != nil else { return .init(issue: "cardAliasUnresolved", capDataIsStale: isStale(capSyncAt)) }
        let merchant = event.transaction.merchantRaw ?? event.transaction.transactionNameRaw ?? ""
        let category = CardCopilotStore.predict(poiCategoryRaw: nil, merchantName: merchant).category
        let verdict = WalletCaptureVerdictEvaluator.evaluate(event: event, catalogue: catalogue,
                                                             ownerState: ownerState, usedCardID: used,
                                                             category: category)
        return .init(verdict: verdict, capDataIsStale: isStale(capSyncAt))
    }

    private static func isStale(_ date: Date?) -> Bool {
        guard let date else { return true }
        return Date().timeIntervalSince(date) > 24 * 60 * 60
    }
}
