import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

/// Recognition is not search. `CanadianMerchantPreIndex.search` serves a human typing into a
/// field and may return many loose candidates. Recognition answers "which merchant IS this
/// MapKit place name", must return at most one, and must return nothing rather than a guess —
/// its answer decides whether the app interrupts someone.
final class MerchantRecognizerTests: XCTestCase {
    func testRecognisesAMerchantNameCarryingALocationSuffix() {
        let match = MerchantRecognizer.recognise("Metro Plus Ottawa")
        XCTAssertEqual(match?.name, "Metro")
        XCTAssertEqual(match?.category, "grocery")
    }

    // MARK: - Alias forms the index actually contains

    func testRecognisesOneHalfOfASlashSeparatedCompoundName() {
        // The index stores "Couche-Tard / Circle K" as one row; MapKit says "Circle K".
        XCTAssertEqual(MerchantRecognizer.recognise("Circle K")?.category, "gasStation")
    }

    func testRecognisesAnAcronymStoredWithItsExpansionInParentheses() {
        // Index row: "TTC (Toronto Transit Commission)". Signage and MapKit say "TTC".
        XCTAssertEqual(MerchantRecognizer.recognise("TTC")?.category, "transit")
    }

    func testRecognisesABrandStoredWithACountrySuffix() {
        // Index row: "A&W Canada". No storefront in the country is signed that way.
        XCTAssertEqual(MerchantRecognizer.recognise("A&W")?.category, "dining")
    }

    func testFoldsDiacriticsInBothDirections() {
        // Index row: "Rona / Réno-Dépôt". MapKit frequently returns the unaccented form.
        XCTAssertNotNil(MerchantRecognizer.recognise("Reno-Depot"))
    }

    // MARK: - Collisions the index invites

    /// "Bell Canada" is indexed as a utility; "Taco Bell" is not indexed at all. Stripping the
    /// country suffix to reach "A&W" must not also turn every Taco Bell into a hydro bill.
    func testDoesNotRecogniseTacoBellAsBellCanada() {
        XCTAssertNil(MerchantRecognizer.recognise("Taco Bell"))
    }

    /// The index holds "Metro", "IGA", "Esso" and "Shell". On raw substring matching each of
    /// these is a false positive, and a false positive here fires a notification.
    func testDoesNotRecogniseNamesThatMerelyContainAShortBrandAsASubstring() {
        XCTAssertNil(MerchantRecognizer.recognise("Metropolitan Hotel"))
        XCTAssertNil(MerchantRecognizer.recognise("Rigatoni's Pizza"))
        XCTAssertNil(MerchantRecognizer.recognise("Shelley's Bakery"))
        XCTAssertNil(MerchantRecognizer.recognise("Essential Oils Co"))
    }

    func testPrefersTheMoreSpecificOfTwoIndexedNames() {
        // "Walmart" (other, 5310) and "Walmart Supercentre" (grocery, 5411) are both indexed.
        XCTAssertEqual(MerchantRecognizer.recognise("Walmart Supercentre")?.mcc, 5411)
    }

    func testReturnsNothingForAnUnknownMerchant() {
        XCTAssertNil(MerchantRecognizer.recognise("Bob's Hardware"))
        XCTAssertNil(MerchantRecognizer.recognise(""))
    }

    // MARK: - Payment descriptors (the pack's curated matchKeys)

    /// The reason the pack is loaded at all. A storefront name and a payment descriptor are
    /// different strings, and until 2026-09-01 recognition only ever saw the first kind — so an
    /// Apple Pay capture of Amazon resolved to nothing and landed in Activity uncategorized.
    func testRecognisesAPaymentDescriptorThatIsNotTheStorefrontName() {
        XCTAssertEqual(MerchantRecognizer.recognise("AMZN MKTP CA")?.name, "Amazon.ca")
        XCTAssertEqual(MerchantRecognizer.recognise("APPLE COM BILL")?.category, "digitalMedia")
    }

    func testRecognisesADescriptorCarryingAStoreNumberAndCity() {
        XCTAssertEqual(MerchantRecognizer.recognise("TIM HORTONS #4021 TORONTO ON")?.name,
                       "Tim Hortons")
    }

    /// A city is never a merchant needle. The index holds "STM (Montréal)" and
    /// "OC Transpo (Ottawa)"; a bare city token would register every business in those cities as
    /// a transit merchant. The old name-derived alias logic refused to derive these on purpose —
    /// the pack must not reintroduce them as curated keys.
    func testDoesNotRecogniseACityNameAsItsTransitAgency() {
        XCTAssertNil(MerchantRecognizer.recognise("Bank of Montreal"))
        XCTAssertNil(MerchantRecognizer.recognise("Ottawa Bagel Shop"))
    }

    // MARK: - Invariants over the whole index

    /// Every row must be reachable from its own name. A row the recognizer cannot find is a row
    /// that silently never fires, which is exactly the failure this whole change exists to fix.
    func testEveryIndexedMerchantRecognisesItself() {
        var unreachable: [String] = []
        for merchant in CanadianMerchantPreIndex.all
        where MerchantRecognizer.recognise(merchant.name) == nil {
            unreachable.append(merchant.name)
        }
        XCTAssertEqual(unreachable, [], "index rows unreachable by recognition")
    }

    /// Recognition must be stable under the decorations MapKit adds to real listings.
    func testRecognisesNamesCarryingStoreNumbersAndBranchSuffixes() {
        XCTAssertEqual(MerchantRecognizer.recognise("Tim Hortons #4521")?.name, "Tim Hortons")
        XCTAssertEqual(MerchantRecognizer.recognise("Shoppers Drug Mart 1234")?.category, "drugStore")
        XCTAssertEqual(MerchantRecognizer.recognise("Real Canadian Superstore Barrhaven")?.category, "grocery")
    }
}
