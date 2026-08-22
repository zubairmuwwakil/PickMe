import XCTest
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
            locationProvider: { await recorder.location() },
            receiptPublisher: { event, _ in await recorder.receipt(event.eventId) })
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
