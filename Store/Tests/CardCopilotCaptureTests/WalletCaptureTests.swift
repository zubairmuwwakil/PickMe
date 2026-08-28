import XCTest
import CardCopilotEngine
@testable import CardCopilotCapture

final class WalletCaptureTests: XCTestCase {
    func testForeignCurrencySymbolUsesCurrencyAwareDecodeInsteadOfSilentZero() {
        let result = WalletAmountDecoder.decode("EC$17.49", currencyCode: "XCD", locale: Locale(identifier: "en_CA"))
        XCTAssertEqual(result.status, .decoded)
        XCTAssertEqual(result.decimal, "17.49")
        XCTAssertEqual(result.raw, "EC$17.49")
    }

    func testLocaleFormatsAndUndecodableAmounts() {
        XCTAssertEqual(WalletAmountDecoder.decode("1 234,56 $", currencyCode: "CAD", locale: Locale(identifier: "fr_CA")).decimal, "1234.56")
        XCTAssertEqual(WalletAmountDecoder.decode("1.234,56 €", currencyCode: "EUR", locale: Locale(identifier: "de_DE")).decimal, "1234.56")
        XCTAssertEqual(WalletAmountDecoder.decode("not money", currencyCode: "XCD", locale: Locale(identifier: "en_CA")).status, .undecodable)
        XCTAssertEqual(WalletAmountDecoder.decode(nil, currencyCode: "XCD", locale: Locale(identifier: "en_CA")).status, .absent)
    }

    func testPersistencePrecedesReceiptAndOptionalEnrichment() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outbox = try WalletOutboxStore(root: root)
        let recorder = Recorder(outbox: outbox)
        let coordinator = WalletCaptureCoordinator(outbox: outbox, uploader: nil,
            locationProvider: { .init(location: await recorder.location(), outcome: .unavailable) },
            receiptPublisher: { receipt in await recorder.receipt(receipt.event.eventId) })
        let event = try await coordinator.capture(
            .init(merchant: "Store", amount: "EC$17.49", transactionName: "Store", currency: "XCD", card: "Visa", paymentMethod: "Store"),
            client: .init(appVersion: "1", buildNumber: "1", osVersion: "iOS", locale: "en_CA"),
            locale: Locale(identifier: "en_CA"), timezone: TimeZone(identifier: "America/St_Lucia")!)
        let observedOrder = await recorder.order()
        XCTAssertEqual(observedOrder, ["receiptSawPersisted", "locationSawPersisted"])
        let pending = try await outbox.captures(in: .pending)
        XCTAssertEqual(pending.first?.event.eventId, event.eventId)
        XCTAssertNil(pending.first?.event.transaction.paymentMethodRaw)
    }

    func testEmptyMappingIsRetainedInQuarantineAndNeverUploaded() async throws {
        let (root, outbox, diagnostics) = try makeStores()
        defer { try? FileManager.default.removeItem(at: root) }
        let uploader = ScriptedUploader([.init(.accepted)])
        let coordinator = WalletCaptureCoordinator(outbox: outbox, uploader: uploader, diagnostics: diagnostics)
        let event = try await coordinator.capture(.init(merchant: nil, amount: "", transactionName: nil,
            currency: nil, card: nil, paymentMethod: nil), client: client, locale: .current, timezone: .current)
        XCTAssertFalse(event.isMeaningful)
        let quarantined = try await outbox.captures(in: .quarantined)
        XCTAssertEqual(quarantined.first?.safeError, "automationMappingEmpty")
        let calls = await uploader.callCount(); XCTAssertEqual(calls, 0)
    }

    func testStaleInflightClaimRecoversWithoutLosingEvent() async throws {
        let (root, outbox, _) = try makeStores(); defer { try? FileManager.default.removeItem(at: root) }
        var value = queued(eventID: "stale", capturedAt: Date(timeIntervalSince1970: 1))
        try await outbox.persist(value)
        let claimed = try await outbox.claim("stale")
        value = try XCTUnwrap(claimed)
        try await outbox.recoverStaleInflight(olderThan: Date())
        let pending = try await outbox.captures(in: .pending)
        let inflight = try await outbox.captures(in: .inflight)
        XCTAssertEqual(pending.map(\.event.eventId), ["stale"])
        XCTAssertTrue(inflight.isEmpty)
    }

    func testOneRetryDoesNotBlockAnotherEvent() async throws {
        let (root, outbox, diagnostics) = try makeStores(); defer { try? FileManager.default.removeItem(at: root) }
        for id in ["one", "two"] { let item = queued(eventID: id); try await outbox.persist(item); try await diagnostics.begin(item) }
        let uploader = ScriptedUploader([.init(.retry, safeError: "offline"), .init(.accepted)])
        let summary = await WalletCaptureCoordinator(outbox: outbox, uploader: uploader, diagnostics: diagnostics).drain()
        XCTAssertEqual(summary.retainedForRetry, 1); XCTAssertEqual(summary.accepted, 1)
        let pending = try await outbox.captures(in: .pending); XCTAssertEqual(pending.count, 1)
    }

    func testAuthenticationBlockIsNotRetriedWithSameCredential() async throws {
        let (root, outbox, diagnostics) = try makeStores(); defer { try? FileManager.default.removeItem(at: root) }
        let item = queued(eventID: "auth"); try await outbox.persist(item); try await diagnostics.begin(item)
        let uploader = ScriptedUploader([.init(.authenticationRequired), .init(.accepted)])
        _ = await WalletCaptureCoordinator(outbox: outbox, uploader: uploader, diagnostics: diagnostics).drain()
        _ = await WalletCaptureCoordinator(outbox: outbox, uploader: uploader, diagnostics: diagnostics).drain()
        let calls = await uploader.callCount(); let pending = try await outbox.captures(in: .pending)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(pending.first?.deliveryState, .authenticationBlocked)
    }

    func testInvalidEventIsQuarantinedAndQueueContinues() async throws {
        let (root, outbox, diagnostics) = try makeStores(); defer { try? FileManager.default.removeItem(at: root) }
        for id in ["bad", "good"] { let item = queued(eventID: id); try await outbox.persist(item); try await diagnostics.begin(item) }
        let uploader = ScriptedUploader([.init(.invalid, safeError: "invalid"), .init(.accepted)])
        let summary = await WalletCaptureCoordinator(outbox: outbox, uploader: uploader, diagnostics: diagnostics).drain()
        XCTAssertEqual(summary.quarantined, 1); XCTAssertEqual(summary.accepted, 1)
        let quarantined = try await outbox.captures(in: .quarantined)
        XCTAssertEqual(quarantined.count, 1)
        XCTAssertEqual(quarantined.first?.safeError, "invalid")
    }

    func testFutureRetryAfterSkipsEventWithoutBusyLoop() async throws {
        let (root, outbox, _) = try makeStores(); defer { try? FileManager.default.removeItem(at: root) }
        var item = queued(eventID: "later"); item.nextRetryAt = Date().addingTimeInterval(3600); try await outbox.persist(item)
        let uploader = ScriptedUploader([.init(.accepted)])
        _ = await WalletCaptureCoordinator(outbox: outbox, uploader: uploader).drain()
        let calls = await uploader.callCount(); XCTAssertEqual(calls, 0)
    }

    func testStaleLocationIsRejectedAndRecorded() async throws {
        let (root, outbox, diagnostics) = try makeStores(); defer { try? FileManager.default.removeItem(at: root) }
        let stale = WalletCaptureLocation(latitude: 1, longitude: 2, horizontalAccuracyMeters: 10,
                                          capturedAt: Date().addingTimeInterval(-61))
        let coordinator = WalletCaptureCoordinator(outbox: outbox, uploader: nil, diagnostics: diagnostics,
            locationProvider: { .init(location: stale, outcome: .captured) })
        let event = try await coordinator.capture(input, client: client, locale: .current, timezone: .current)
        let pending = try await outbox.captures(in: .pending)
        let diagnosticRecords = try await diagnostics.records()
        XCTAssertNil(pending.first?.event.location)
        let record = diagnosticRecords.first { $0.eventID == event.eventId }
        XCTAssertEqual(record?.timeline.last(where: { $0.stage == "locationUnavailable" })?.detail, "staleFix")
    }

    func testDiagnosticReportIsRedactedUnlessOwnerOptsIn() async throws {
        let (root, _, diagnostics) = try makeStores(); defer { try? FileManager.default.removeItem(at: root) }
        let item = queued(eventID: "secret-event"); try await diagnostics.begin(item)
        let redacted = try await diagnostics.prepareReport(eventID: "secret-event", includeTransactionDetails: false)
        XCTAssertNil(redacted.transactionDetails); XCTAssertEqual(redacted.eventID, "secret-e")
        let included = try await diagnostics.prepareReport(eventID: "secret-event", includeTransactionDetails: true)
        XCTAssertEqual((included.transactionDetails?["merchant"] ?? nil), "Store")
    }

    func testShortcutRunLogRecordsFieldPresenceWithoutRawTransactionDetails() async throws {
        let documents = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: documents) }
        let logs = try WalletCaptureShortcutRunLogStore(documentsDirectory: documents)
        let run = WalletCaptureShortcutRunLog(runID: "run", startedAt: Date(),
                                              input: input, client: client, captureEnabled: true)
        try await logs.begin(run)
        let diagnostic = WalletCaptureDiagnosticRecord(eventID: "event", createdAt: Date(), completedAt: nil,
            deliveryState: .pending, amountDecodeStatus: .decoded, missingFields: [], attemptCount: 1,
            safeError: "offline", httpStatus: nil, serverEventID: nil, timeline: [], event: nil)
        try await logs.finish(runID: "run", outcome: "savedLocally", event: queued(eventID: "event").event,
                              diagnostic: diagnostic)

        let records = try await logs.records()
        let saved = try XCTUnwrap(records.first)
        XCTAssertTrue(saved.input.merchantPresent)
        XCTAssertTrue(saved.input.amountPresent)
        XCTAssertTrue(saved.input.cardPresent)
        XCTAssertEqual(saved.outcome, "savedLocally")
        XCTAssertEqual(saved.deliveryState, "pending")
        XCTAssertEqual(saved.safeError, "offline")
        XCTAssertNotNil(saved.finishedAt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: documents
            .appendingPathComponent(WalletCaptureShortcutRunLogStore.directoryName)
            .appendingPathComponent("run.json").path))
        let encoded = try String(contentsOf: documents
            .appendingPathComponent(WalletCaptureShortcutRunLogStore.directoryName)
            .appendingPathComponent("run.json"), encoding: .utf8)
        XCTAssertFalse(encoded.contains("Store"))
        XCTAssertFalse(encoded.contains("$1.00"))
        XCTAssertFalse(encoded.contains("Card"))

        let accepted = WalletCaptureDiagnosticRecord(eventID: "event", createdAt: Date(), completedAt: Date(),
            deliveryState: .accepted, amountDecodeStatus: .decoded, missingFields: [], attemptCount: 2,
            safeError: nil, httpStatus: 201, serverEventID: "server-event", timeline: [], event: nil)
        try await logs.refreshDelivery(eventID: "event", diagnostic: accepted)
        let refreshedRecords = try await logs.records()
        let refreshed = try XCTUnwrap(refreshedRecords.first)
        XCTAssertEqual(refreshed.outcome, "savedAndDelivered")
        XCTAssertEqual(refreshed.deliveryState, "accepted")
        XCTAssertEqual(refreshed.httpStatus, 201)
        XCTAssertEqual(refreshed.serverEventID, "server-event")
        XCTAssertNil(refreshed.safeError)
    }

    func testShortcutRunLogExpiresOldRecords() async throws {
        let documents = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: documents) }
        let now = Date(timeIntervalSince1970: 40 * 24 * 60 * 60)
        let logs = try WalletCaptureShortcutRunLogStore(documentsDirectory: documents, now: { now })
        let old = WalletCaptureShortcutRunLog(runID: "old", startedAt: .init(timeIntervalSince1970: 1),
                                              input: input, client: client, captureEnabled: true)
        try await logs.begin(old)

        let retained = try await logs.records()
        XCTAssertTrue(retained.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: documents
            .appendingPathComponent(WalletCaptureShortcutRunLogStore.directoryName)
            .appendingPathComponent("old.json").path))
    }

    func testShortcutRunLogMigratesLegacyRawFieldsToPresenceOnly() async throws {
        let documents = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: documents) }
        let startedAt = Date()
        let logs = try WalletCaptureShortcutRunLogStore(documentsDirectory: documents, now: { startedAt })
        let original = WalletCaptureShortcutRunLog(runID: "legacy", startedAt: startedAt,
                                                   input: input, client: client, captureEnabled: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(original)) as? [String: Any])
        object["input"] = ["merchant": "Private Merchant", "amount": "EC$30.00", "card": "Private Card"]
        let directory = documents.appendingPathComponent(WalletCaptureShortcutRunLogStore.directoryName)
        let file = directory.appendingPathComponent("legacy.json")
        try JSONSerialization.data(withJSONObject: object).write(to: file)

        let migrated = try await logs.records()
        XCTAssertTrue(try XCTUnwrap(migrated.first).input.merchantPresent)
        let rewritten = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(rewritten.contains("Private Merchant"))
        XCTAssertFalse(rewritten.contains("EC$30.00"))
        XCTAssertFalse(rewritten.contains("Private Card"))
        XCTAssertTrue(rewritten.contains("merchantPresent"))
    }

    func testStatusUsesUnassignedOutboxWhenDiagnosticsAreMissing() async throws {
        let (root, outbox, diagnostics) = try makeStores(); defer { try? FileManager.default.removeItem(at: root) }
        let capturedAt = Date(timeIntervalSince1970: 1234)
        try await outbox.persist(queued(eventID: "unassigned", capturedAt: capturedAt), to: .unassigned)

        let status = await diagnostics.status(outbox: outbox)

        XCTAssertEqual(status.lastTriggerAt, capturedAt)
        XCTAssertEqual(status.oldestPendingAt, capturedAt)
        XCTAssertEqual(status.unassignedCount, 1)
    }

    func testCompletedDiagnosticsExpireButPendingDiagnosticsRemain() async throws {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let diagnostics = try WalletCaptureDiagnosticsStore(root: root, completedRetention: -1, now: { now })
        var old = queued(eventID: "old", capturedAt: now.addingTimeInterval(-100)); try await diagnostics.begin(old)
        try await diagnostics.complete(eventID: "old", disposition: .accepted)
        old = queued(eventID: "pending", capturedAt: now.addingTimeInterval(-100)); try await diagnostics.begin(old)
        let records = try await diagnostics.records()
        XCTAssertEqual(Set(records.map(\.eventID)), Set(["pending"]))
    }

    func testCompletedDiagnosticsKeepOnlyNewestLimitWithoutDeletingPending() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let clock = TestClock(Date(timeIntervalSince1970: 10_000_000))
        let diagnostics = try WalletCaptureDiagnosticsStore(root: root, completedLimit: 2, now: { clock.value })
        for id in ["one", "two", "three"] {
            try await diagnostics.begin(queued(eventID: id, capturedAt: clock.value))
            try await diagnostics.complete(eventID: id, disposition: .accepted)
            clock.advance()
        }
        try await diagnostics.begin(queued(eventID: "pending", capturedAt: clock.value))
        let records = try await diagnostics.records()
        XCTAssertEqual(Set(records.map(\.eventID)), Set(["two", "three", "pending"]))
    }

    func testNotificationDecisionUsesStableEventIDAndForegroundRoute() {
        let event = queued(eventID: "event-id").event
        let receipt = WalletCaptureReceipt(event: event, kind: .savedOffline, verdict: .init())
        let decision = WalletCaptureNotificationDecision.currentEvent(receipt: receipt, appIsActive: true, recommendedCardName: nil)
        XCTAssertEqual(decision.identifier, "event-id"); XCTAssertEqual(decision.route, .inApp)
        XCTAssertTrue(decision.body.contains("offline"))
    }

    func testOfflineVerdictUsesTheOwnersSwitchThreshold() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        var state = try SeedLoader.loadOwnerState()
        var event = queued(eventID: "verdict").event
        event.transaction.amountDecimal = "100"
        event.transaction.currencyRaw = "CAD"

        let recommended = WalletCaptureVerdictEvaluator.evaluate(event: event, catalogue: catalogue,
            ownerState: state, usedCardID: "wealthsimple-vip", category: "dining")
        XCTAssertNotNil(recommended)

        state.switchThreshold = .init(minAdvantagePercentagePoints: 100, minAdvantageCad: 100,
                                      semantics: "both")
        let suppressed = WalletCaptureVerdictEvaluator.evaluate(event: event, catalogue: catalogue,
            ownerState: state, usedCardID: "wealthsimple-vip", category: "dining")
        XCTAssertNil(suppressed)
    }

    func testDrainCountsOnlyOldEventsAsBacklogForCurrentCapture() async throws {
        let (root, outbox, diagnostics) = try makeStores(); defer { try? FileManager.default.removeItem(at: root) }
        for id in ["old", "current"] { let item = queued(eventID: id); try await outbox.persist(item); try await diagnostics.begin(item) }
        let uploader = ScriptedUploader([.init(.accepted), .init(.accepted)])
        let summary = await WalletCaptureCoordinator(outbox: outbox, uploader: uploader, diagnostics: diagnostics)
            .drain(currentEventID: "current")
        XCTAssertEqual(summary.uploadedCount, 2)
        XCTAssertEqual(summary.backlogUploaded, 1)
    }

    func testAccountRoutingContinuesOnSignOutButIsolatesDifferentAccount() {
        XCTAssertEqual(WalletCaptureAccountRouting.decide(credentialBoundUserID: "a", signedInUserID: nil), .boundAccount)
        XCTAssertEqual(WalletCaptureAccountRouting.decide(credentialBoundUserID: "a", signedInUserID: "a"), .boundAccount)
        XCTAssertEqual(WalletCaptureAccountRouting.decide(credentialBoundUserID: "a", signedInUserID: "b"), .unassigned)
        XCTAssertEqual(WalletCaptureAccountRouting.decide(credentialBoundUserID: nil, signedInUserID: "a"), .unassigned)
    }

    func testUnverifiedCredentialKeepsKnownAccountButWaitsToUpload() {
        let decision = WalletCaptureDeliveryDecision.decide(
            credentialBoundUserID: "a",
            connection: .init(isEnabled: true, connectionVerifiedAt: nil, boundUserID: "a"),
            signedInUserID: "a")

        XCTAssertEqual(decision.accountRouting, .boundAccount)
        XCTAssertFalse(decision.canUpload)
    }

    func testVerifiedCredentialUploadsOnlyForItsBoundAccount() {
        let verified = WalletCaptureConnectionState(
            isEnabled: true, connectionVerifiedAt: Date(), boundUserID: "a")

        let matching = WalletCaptureDeliveryDecision.decide(
            credentialBoundUserID: "a", connection: verified, signedInUserID: "a")
        XCTAssertEqual(matching.accountRouting, .boundAccount)
        XCTAssertTrue(matching.canUpload)

        let different = WalletCaptureDeliveryDecision.decide(
            credentialBoundUserID: "a", connection: verified, signedInUserID: "b")
        XCTAssertEqual(different.accountRouting, .unassigned)
        XCTAssertFalse(different.canUpload)
    }

    func testRelinkRequiresAccountChoiceForPreviouslyAssignedCaptures() async throws {
        let (root, outbox, _) = try makeStores(); defer { try? FileManager.default.removeItem(at: root) }
        let pending = queued(eventID: "pending")
        var inflight = queued(eventID: "inflight")
        inflight.deliveryState = .inflight
        try await outbox.persist(pending, to: .pending)
        try await outbox.persist(inflight, to: .inflight)

        try await outbox.requireAccountChoiceForAssignedCaptures()

        let remainingPending = try await outbox.captures(in: .pending)
        let remainingInflight = try await outbox.captures(in: .inflight)
        XCTAssertTrue(remainingPending.isEmpty)
        XCTAssertTrue(remainingInflight.isEmpty)
        let unassigned = try await outbox.captures(in: .unassigned)
        XCTAssertEqual(Set(unassigned.map(\.event.eventId)), Set(["pending", "inflight"]))
        XCTAssertTrue(unassigned.allSatisfy { capture in
            capture.deliveryState == .pending &&
                capture.timeline.contains { $0.stage == "accountChoiceRequiredAfterRelink" }
        })
    }

    func testPaymentMethodEqualToNameIsRemovedButDistinctValueSurvives() async throws {
        let (root, outbox, _) = try makeStores(); defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = WalletCaptureCoordinator(outbox: outbox, uploader: nil)
        _ = try await coordinator.capture(.init(merchant: "Store", amount: "1", transactionName: "Purchase",
            currency: "CAD", card: nil, paymentMethod: "Purchase"), client: client, locale: .current, timezone: .current)
        _ = try await coordinator.capture(.init(merchant: "Store", amount: "2", transactionName: "Purchase",
            currency: "CAD", card: nil, paymentMethod: "Secondary Card"), client: client, locale: .current, timezone: .current)
        let values = try await outbox.captures(in: .pending)
        XCTAssertEqual(values.filter { $0.event.transaction.paymentMethodRaw == nil }.count, 1)
        XCTAssertEqual(values.filter { $0.event.transaction.paymentMethodRaw == "Secondary Card" }.count, 1)
    }

    private var client: WalletCaptureClient { .init(appVersion: "1", buildNumber: "1", osVersion: "iOS", locale: "en_CA") }
    private var input: WalletCaptureInput { .init(merchant: "Store", amount: "$1.00", transactionName: "Store", currency: "CAD", card: "Visa", paymentMethod: nil) }
    private func makeStores() throws -> (URL, WalletOutboxStore, WalletCaptureDiagnosticsStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (root, try WalletOutboxStore(root: root), try WalletCaptureDiagnosticsStore(root: root))
    }
    private func queued(eventID: String, capturedAt: Date = Date()) -> WalletQueuedCapture {
        let event = WalletCaptureEvent(schemaVersion: 2, captureVersion: 1, source: "apple_wallet_automation",
            transport: "pickme_app_intent", eventId: eventID, capturedAt: capturedAt, timezone: "UTC",
            transaction: .init(merchantRaw: "Store", transactionNameRaw: "Store", amountRaw: "$1.00",
                amountDecimal: "1", amountDecodeStatus: .decoded, currencyRaw: "CAD", cardRaw: "Visa", paymentMethodRaw: nil),
            location: nil, client: client)
        return .init(event: event, deliveryState: .pending, attemptCount: 0, lastAttemptAt: nil,
                     nextRetryAt: nil, safeError: nil, timeline: [.init(at: capturedAt, stage: "savedLocally")])
    }
}

private actor Recorder {
    let outbox: WalletOutboxStore
    var values: [String] = []
    init(outbox: WalletOutboxStore) { self.outbox = outbox }
    func location() async -> WalletCaptureLocation? {
        if (try? await outbox.captures(in: .pending).isEmpty) == false { values.append("locationSawPersisted") }
        return nil
    }
    func receipt(_ id: String) async {
        if (try? await outbox.captures(in: .pending).contains(where: { $0.event.eventId == id })) == true { values.append("receiptSawPersisted") }
    }
    func order() -> [String] { values }
}

private actor ScriptedUploader: WalletCaptureUploading {
    private var results: [WalletUploadResult]
    private var calls = 0
    init(_ results: [WalletUploadResult]) { self.results = results }
    func upload(_ event: WalletCaptureEvent) async -> WalletUploadResult {
        calls += 1
        return results.isEmpty ? .init(.retry) : results.removeFirst()
    }
    func callCount() -> Int { calls }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var value: Date { lock.withLock { date } }
    func advance() { lock.withLock { date = date.addingTimeInterval(1) } }
}
