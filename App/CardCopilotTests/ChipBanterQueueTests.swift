import XCTest
@testable import CardCopilot

/// Regression cover for the two worst bugs in Chip's first version. Both were view state, which
/// is why neither was caught: the crash needed a list that shrinks after the index was set, and
/// the stale tag needed a value nobody owned clearing. Both are pure logic now.
final class ChipBanterQueueTests: XCTestCase {

    private func item(_ tag: String) -> ChipBanterItem {
        ChipBanterItem(text: "text for \(tag)", mood: .idle, tag: tag)
    }

    private func queue(pinned: Int = 0, insights: Int = 0, standing: Int = 0, rotation: Int = 0) -> ChipBanterQueue {
        ChipBanterQueue(
            pinned: (0..<pinned).map { item("P\($0)") },
            insights: (0..<insights).map { item("I\($0)") },
            standing: (0..<standing).map { item("S\($0)") },
            rotation: (0..<rotation).map { item("R\($0)") })
    }

    // MARK: - Order

    func testPinnedAdvisoriesComeFirstAndRotationComesLast() {
        let q = queue(pinned: 1, insights: 2, standing: 2, rotation: 1)
        XCTAssertEqual(q.items.map(\.tag), ["P0", "I0", "I1", "S0", "S1", "R0"])
    }

    func testTheFirstQuipShownIsThePinnedAdvisory() {
        let q = queue(pinned: 1, insights: 3, standing: 5)
        XCTAssertEqual(q.item(at: 0)?.tag, "P0")
    }

    // MARK: - The crash

    /// The original bug exactly: advance deep into a long queue, then let `insights` empty — which
    /// happens whenever the engine has nothing to say, including for a wallet with no cards — and
    /// the surviving index pointed past the end of the shorter list.
    func testAnIndexLeftOverFromALongerQueueDoesNotTrap() {
        let long = queue(insights: 8, standing: 13)
        let index = 20
        XCTAssertNotNil(long.item(at: index))

        let shortened = queue(insights: 0, standing: 13)
        XCTAssertLessThan(shortened.items.count, index)
        XCTAssertNotNil(shortened.item(at: index), "a stale index must wrap, not trap")
        XCTAssertEqual(shortened.item(at: index)?.tag, "S7")
    }

    func testAnEmptyQueueYieldsNoItemRatherThanTrapping() {
        let empty = ChipBanterQueue()
        XCTAssertNil(empty.item(at: 0))
        XCTAssertNil(empty.item(at: 99))
        XCTAssertEqual(empty.advanced(from: 5), 0)
    }

    func testAdvancingWrapsAroundTheEnd() {
        let q = queue(standing: 3)
        XCTAssertEqual(q.advanced(from: 0), 1)
        XCTAssertEqual(q.advanced(from: 2), 0)
        // The guarantee is range, not a particular landing spot: (99 + 1) % 3 == 1.
        XCTAssertTrue((0..<q.items.count).contains(q.advanced(from: 99)),
                      "advancing from a stale index must still land in range")
    }

    func testEveryIndexInALongRunStaysInRange() {
        let q = queue(insights: 2, standing: 4)
        var index = 0
        for _ in 0..<50 {
            XCTAssertNotNil(q.item(at: index))
            index = q.advanced(from: index)
        }
    }

    // MARK: - The stale tag

    /// The original bug: the tag arrived from outside as a plain value, so it survived the
    /// reaction that set it and stamped itself on every quip that followed.
    func testClearingTheExternalTagFallsBackToTheQuipsOwnTag() {
        XCTAssertEqual(
            ChipBubbleTag.resolve(externalTag: "FOUNDER", reactionText: nil, fallback: "4TH WALL BREAK"),
            "FOUNDER")
        XCTAssertEqual(
            ChipBubbleTag.resolve(externalTag: nil, reactionText: nil, fallback: "4TH WALL BREAK"),
            "4TH WALL BREAK",
            "once the external tag is cleared the quip must wear its own")
    }

    func testAnEmptyExternalTagIsTreatedAsAbsent() {
        XCTAssertEqual(
            ChipBubbleTag.resolve(externalTag: "", reactionText: nil, fallback: "COSTCO RULE"),
            "COSTCO RULE")
    }

    func testAReactionIsTaggedFromItsOwnText() {
        let cases: [(String, String)] = [
            ("FOUNDER PROTOCOL UNLOCKED! Engineered by...", "FOUNDER PROTOCOL"),
            ("Maximum Effort mode engaged!", "MAXIMUM EFFORT"),
            ("All hail Amex Cobalt", "HOLY GRAIL"),
            ("Baby's first credit card: the BMO CashBack Mastercard", "FIRST CARD"),
            ("that $799 annual fee still gives me chills", "FEE TRAUMA"),
            ("this copilot runs on matcha", "ENERGY CHECK"),
            ("Why PickMe? Because life is too short", "ORIGIN STORY"),
            ("HEY! That's my face!", "CHIP REACTION"),
        ]
        for (text, expected) in cases {
            XCTAssertEqual(
                ChipBubbleTag.resolve(externalTag: nil, reactionText: text, fallback: "UNUSED"),
                expected,
                "\(text) should be tagged \(expected)")
        }
    }

    /// A tag derived from the reaction text cannot outlive it: clear the text and the fallback
    /// takes over with no separate value to reset.
    func testAReactionsTagDisappearsWithItsText() {
        let tagged = ChipBubbleTag.resolve(externalTag: nil, reactionText: "Amex Cobalt", fallback: "DCC TRAP")
        XCTAssertEqual(tagged, "HOLY GRAIL")

        let cleared = ChipBubbleTag.resolve(externalTag: nil, reactionText: nil, fallback: "DCC TRAP")
        XCTAssertEqual(cleared, "DCC TRAP")
    }
}
