import XCTest
@testable import CardCopilotStore

final class MerchantMCCExactImportTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: MerchantMCCImportedEvidenceStore!

    override func setUp() {
        super.setUp()
        let suite = "MerchantMCCExactImportTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        store = MerchantMCCImportedEvidenceStore(defaults: defaults, storageKey: "test.imports")
    }

    func testVisaBusinessReportingCSVImportsLiteralMCCWithoutPersistingTransactionFields() throws {
        let csv = """
        Merchant Name,MCC,Transaction Date,Billing Amount,Card Account Number
        Metro,5411,09/01/2026,42.17,4111111111111111
        """

        let summary = try store.importCSV(Data(csv.utf8), source: .visaBusinessReporting)

        XCTAssertEqual(summary.totalRows, 1)
        XCTAssertEqual(summary.importedRows, 1)
        let evidence = try XCTUnwrap(store.evidence().first)
        XCTAssertEqual(evidence.kind, .ownerImportedMcc)
        XCTAssertEqual(evidence.mcc, 5411)
        XCTAssertEqual(evidence.network, "visa")
        XCTAssertNil(evidence.latitude)
        XCTAssertNil(evidence.longitude)
        XCTAssertFalse(evidence.sourceReference?.contains("42.17") == true)
        XCTAssertFalse(evidence.sourceReference?.contains("411111") == true)
    }

    func testImportIsIdempotentAcrossTheSameExport() throws {
        let csv = "Merchant,MCC,Posting Date\nMetro,5411,09/01/2026\n"

        XCTAssertEqual(try store.importCSV(Data(csv.utf8)).importedRows, 1)
        let second = try store.importCSV(Data(csv.utf8))

        XCTAssertEqual(second.importedRows, 0)
        XCTAssertEqual(second.duplicateRows, 1)
        XCTAssertEqual(store.evidence().count, 1)
    }

    func testSameMerchantMCCDayDoesNotGainWeightFromAmountOrCardDifferences() throws {
        let csv = """
        Merchant,MCC,Transaction Date,Billing Amount,Card Account Number
        Metro,5411,09/01/2026,10.00,4111111111111111
        Metro,5411,09/01/2026,85.40,4999999999999999
        """

        let summary = try store.importCSV(Data(csv.utf8), source: .visaBusinessReporting)

        XCTAssertEqual(summary.importedRows, 1)
        XCTAssertEqual(summary.duplicateRows, 1)
        XCTAssertEqual(store.evidence().count, 1,
                       "transaction frequency and sensitive fields must not inflate corroboration")
    }

    func testCategoryOnlyCSVIsRejectedInsteadOfFabricatingAnMCC() {
        let csv = "Merchant,Category,Transaction Date\nMetro,Grocery,09/01/2026\n"

        XCTAssertThrowsError(try store.importCSV(Data(csv.utf8))) { error in
            XCTAssertEqual(error as? MerchantMCCExactImportError, .missingRequiredColumns)
        }
        XCTAssertTrue(store.evidence().isEmpty)
    }

    func testSICIsNotAcceptedAsMCC() {
        let csv = "Merchant,SIC,Transaction Date\nMetro,5411,09/01/2026\n"

        XCTAssertThrowsError(try store.importCSV(Data(csv.utf8))) { error in
            XCTAssertEqual(error as? MerchantMCCExactImportError, .missingRequiredColumns)
        }
    }

    func testInvalidMCCAndMissingDateAreSkipped() throws {
        let csv = """
        Merchant,MCC,Transaction Date
        Metro,Grocery,09/01/2026
        Metro,5411,
        """

        let summary = try store.importCSV(Data(csv.utf8))

        XCTAssertEqual(summary.importedRows, 0)
        XCTAssertEqual(summary.invalidMCCRows, 1)
        XCTAssertEqual(summary.missingDateRows, 1)
    }

    func testUnknownMerchantDoesNotCreateGlobalIdentity() throws {
        let csv = "Merchant,MCC,Transaction Date\nTotally Unknown Shop,5411,09/01/2026\n"

        let summary = try store.importCSV(Data(csv.utf8))

        XCTAssertEqual(summary.importedRows, 0)
        XCTAssertEqual(summary.unrecognizedMerchantRows, 1)
        XCTAssertTrue(store.evidence().isEmpty)
    }

    func testUnlocatedOwnerImportCanMovePriorButCannotBecomeObservedOrTrusted() throws {
        let csv = "Merchant,MCC,Transaction Date\nMetro,5411,09/01/2026\n"
        _ = try store.importCSV(Data(csv.utf8), source: .visaBusinessReporting)
        let evidence = store.evidence(for: "Metro")
        XCTAssertEqual(evidence.count, 1)

        let prediction = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "Metro", channel: .inStore),
            seedMCC: 5311,
            evidence: evidence,
            now: ISO8601DateFormatter().date(from: "2026-09-04T12:00:00Z")!)

        XCTAssertEqual(prediction.bestMCC, 5411)
        XCTAssertFalse(prediction.isObserved,
                       "an issuer export with no store location must not claim terminal observation")
        XCTAssertFalse(prediction.isTrusted)
        XCTAssertEqual(prediction.directObservationCount, 0)
    }
}
