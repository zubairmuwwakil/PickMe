import XCTest
@testable import CardCopilot

/// Chip's keyword beats are the one place a joke can hijack a real merchant search, so the
/// trigger table gets pinned down here rather than trusted to read correctly.
final class ChipEasterEggTests: XCTestCase {

    // MARK: - Matching

    func testMatchesAWholeTriggerWord() {
        XCTAssertEqual(ChipEasterEgg.match("cobalt"), .cobalt)
        XCTAssertEqual(ChipEasterEgg.match("bmo"), .bmo)
        XCTAssertEqual(ChipEasterEgg.match("platinum"), .platinum)
        XCTAssertEqual(ChipEasterEgg.match("deadpool"), .maximumEffort)
        XCTAssertEqual(ChipEasterEgg.match("overclock"), .overclock)
        XCTAssertEqual(ChipEasterEgg.match("turbo"), .overclock)
    }

    func testMatchingIgnoresCaseAndSurroundingWords() {
        XCTAssertEqual(ChipEasterEgg.match("  Amex COBALT card "), .cobalt)
        XCTAssertEqual(ChipEasterEgg.match("who is the Founder"), .founder)
    }

    func testMatchesMultiWordPhrases() {
        XCTAssertEqual(ChipEasterEgg.match("maximum effort"), .maximumEffort)
        XCTAssertEqual(ChipEasterEgg.match("why pick me"), .origin)
        XCTAssertEqual(ChipEasterEgg.match("overclock chip"), .overclock)
    }

    func testPunctuationDoesNotBlockAMatch() {
        XCTAssertEqual(ChipEasterEgg.match("why pickme?"), .origin)
        XCTAssertEqual(ChipEasterEgg.match("tim's"), .matcha)
    }

    func testLongTriggersStillMatchAWordsPrefix() {
        XCTAssertEqual(ChipEasterEgg.match("platinums"), .platinum)
        XCTAssertEqual(ChipEasterEgg.match("founders"), .founder)
    }

    // MARK: - The false positives that motivated word matching

    /// "PC Optimum" is a real Canadian loyalty program and it contains "tim". Under the substring
    /// matching this replaced, searching for it served the coffee joke instead of the merchant.
    func testShortTriggersDoNotMatchInsideALongerWord() {
        XCTAssertNil(ChipEasterEgg.match("optimum"))
        XCTAssertNil(ChipEasterEgg.match("PC Optimum"))
        XCTAssertNil(ChipEasterEgg.match("maritime"))
        XCTAssertNil(ChipEasterEgg.match("ultimate"))
    }

    func testOrdinaryMerchantSearchesAreNotEasterEggs() {
        for query in ["Loblaws", "Real Canadian Superstore", "Shoppers Drug Mart", "Costco", "Esso"] {
            XCTAssertNil(ChipEasterEgg.match(query), "\(query) should be an ordinary search")
        }
    }

    func testEmptyAndWhitespaceQueriesMatchNothing() {
        XCTAssertNil(ChipEasterEgg.match(""))
        XCTAssertNil(ChipEasterEgg.match("   \n\t"))
        XCTAssertNil(ChipEasterEgg.match("!!!"))
    }

    // MARK: - Presentation

    func testEveryBeatCarriesCompleteCopy() {
        for egg in ChipEasterEgg.allCases {
            XCTAssertFalse(egg.title.isEmpty, "\(egg) needs a title")
            XCTAssertFalse(egg.subtitle.isEmpty, "\(egg) needs a subtitle")
            XCTAssertFalse(egg.tag.isEmpty, "\(egg) needs a tag")
            XCTAssertFalse(egg.iconName.isEmpty, "\(egg) needs an icon")
            XCTAssertFalse(egg.dialogue.isEmpty, "\(egg) needs dialogue")
        }
    }

    /// The founder is named by name only behind a deliberate gesture — the long press, the
    /// five-poke streak, or searching for him outright — never in a beat a stranger trips over.
    func testFounderIsNamedOnlyWhenDeliberatelyAskedFor() {
        for egg in ChipEasterEgg.allCases where egg != .founder {
            XCTAssertFalse(egg.dialogue.contains("Zubair"), "\(egg) dialogue should not name the founder")
            XCTAssertFalse(egg.subtitle.contains("Zubair"), "\(egg) subtitle should not name the founder")
            XCTAssertFalse(egg.title.contains("Zubair"), "\(egg) title should not name the founder")
        }
        XCTAssertTrue(ChipEasterEgg.founder.dialogue.contains("Zubair Muwwakil"))
    }
}
