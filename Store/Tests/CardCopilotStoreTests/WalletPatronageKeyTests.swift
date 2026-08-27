import XCTest
@testable import CardCopilotStore

/// The seam between a Wallet capture and the patronage counter.
///
/// Apple's transaction descriptor and the index's display name are written by different systems
/// for different purposes — "SQ *STARBUCKS #1234" and "Starbucks" are the same shop — so the
/// capture path needs one place that decides whether a captured string names a merchant we can
/// count, and returns nothing rather than a guess when it does not.
final class WalletPatronageKeyTests: XCTestCase {

    func testAProcessorPrefixedDescriptorResolvesToTheMerchant() {
        XCTAssertEqual(patronageKey(forCapturedMerchant: "SQ *STARBUCKS #1234",
                                    transactionName: nil), "starbucks")
    }

    func testAStoreNumberSuffixDoesNotPreventRecognition() {
        XCTAssertEqual(patronageKey(forCapturedMerchant: "LOBLAWS #1234",
                                    transactionName: nil), "loblaws")
    }

    func testTheTransactionNameIsUsedWhenTheMerchantFieldIsAbsent() {
        XCTAssertEqual(patronageKey(forCapturedMerchant: nil,
                                    transactionName: "Tim Hortons"), "tim hortons")
    }

    /// Standing decides whether the app interrupts someone. An unplaceable string must produce
    /// no key at all rather than one derived from the raw text, which would accrue standing for
    /// a merchant nothing can later recognise on arrival.
    func testAnUnplaceableStringYieldsNoKey() {
        XCTAssertNil(patronageKey(forCapturedMerchant: "PAYPAL *XJ4T2", transactionName: nil))
    }

    func testAnEmptyCaptureYieldsNoKey() {
        XCTAssertNil(patronageKey(forCapturedMerchant: nil, transactionName: nil))
        XCTAssertNil(patronageKey(forCapturedMerchant: "   ", transactionName: ""))
    }
}
