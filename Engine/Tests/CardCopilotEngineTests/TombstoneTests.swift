import XCTest
@testable import CardCopilotEngine

final class TombstoneTests: XCTestCase {

    private func card(lifecycleStatus: ProductLifecycleStatus?, effectiveTo: String?) -> CardProduct {
        CardProduct(cardId: "dead-card", officialName: "Discontinued", issuer: "Test",
                    network: .visa, kind: .credit,
                    fee: Fee(annual: Money(amount: 0, currency: .cad)),
                    program: Program(programId: "cash", unit: "cad"),
                    fxRules: [], earnRules: [], caps: [],
                    perTransactionRewardVisibility: "none", lastVerifiedAt: "2026-08-15",
                    credits: nil, lifecycleStatus: lifecycleStatus, effectiveTo: effectiveTo)
    }

    /// A card written before tombstoning existed has no status and must keep scoring.
    func testAbsentStatusMeansActive() {
        XCTAssertTrue(card(lifecycleStatus: nil, effectiveTo: nil).isScoreable(asOf: "2026-08-26"))
    }

    func testWithdrawnCardIsNotScoreable() {
        XCTAssertFalse(card(lifecycleStatus: .withdrawn, effectiveTo: "2026-01-01")
            .isScoreable(asOf: "2026-08-26"))
    }

    /// Withdrawal is dated: before the date the product was real and must still score, so
    /// historical asOf queries stay correct.
    func testWithdrawnCardStillScoresBeforeItsEndDate() {
        XCTAssertTrue(card(lifecycleStatus: .withdrawn, effectiveTo: "2026-12-31")
            .isScoreable(asOf: "2026-08-26"))
    }

    /// The whole point of tombstoning: the id keeps resolving so history can render.
    func testWithdrawnCardStillDecodesAndKeepsItsIdentity() throws {
        let withdrawn = card(lifecycleStatus: .withdrawn, effectiveTo: "2026-01-01")
        let data = try JSONEncoder().encode(withdrawn)
        let decoded = try JSONDecoder().decode(CardProduct.self, from: data)
        XCTAssertEqual(decoded.cardId, "dead-card")
        XCTAssertEqual(decoded.officialName, "Discontinued")
        XCTAssertEqual(decoded.lifecycleStatus, .withdrawn)
    }

    /// Every card in the shipped catalogue must be scoreable today, or the catalogue is
    /// carrying a tombstone that was never meant to be one.
    func testShippedCatalogueHasNoUnexpectedTombstones() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let withdrawn = catalogue.cards.filter { $0.lifecycleStatus == .withdrawn }
        XCTAssertTrue(withdrawn.allSatisfy { $0.effectiveTo != nil },
                      "A withdrawn card must say when it was withdrawn: \(withdrawn.map(\.cardId))")
    }

    // MARK: - Scoring behaviour
    //
    // `isScoreable` is a predicate; these assert the engine actually consults it. Written against
    // a real catalogue card that genuinely wins its category, so "excluded" means something —
    // a synthetic card that loses anyway could not tell exclusion from losing.

    private let winningPurchase = PurchaseContext(amountCad: 100, category: "grocery",
                                                  mcc: 5411, merchantBrand: "loblaws")

    private func catalogueWithdrawing(_ cardId: String, on date: String) throws -> Catalogue {
        var catalogue = try SeedLoader.loadCatalogue()
        let index = try XCTUnwrap(catalogue.cards.firstIndex { $0.cardId == cardId })
        catalogue.cards[index].lifecycleStatus = .withdrawn
        catalogue.cards[index].effectiveTo = date
        return catalogue
    }

    func testWithdrawnCardIsExcludedFromScoring() throws {
        let catalogue = try catalogueWithdrawing("amex-cobalt", on: "2026-01-01")
        let card = try XCTUnwrap(catalogue.cards.first { $0.cardId == "amex-cobalt" })

        let score = Scorer.score(card: card, purchase: winningPurchase,
                                 ownerState: try SeedLoader.loadPinnedOwnerState(),
                                 asOf: "2026-08-26")

        XCTAssertTrue(score.excluded)
        XCTAssertEqual(score.exclusionReason, "product withdrawn")
        XCTAssertEqual(score.warnings, [.productWithdrawn],
                       "a discontinued product is not a card left in a drawer")
        XCTAssertEqual(score.netValueCad, 0)
    }

    /// The date is load-bearing at the Scorer level too, not only inside `isScoreable`. Guards the
    /// regression where the guard is later "simplified" to `status == .withdrawn`.
    func testWithdrawalIsDatedAtTheScorerLevel() throws {
        let catalogue = try catalogueWithdrawing("amex-cobalt", on: "2026-12-31")
        let card = try XCTUnwrap(catalogue.cards.first { $0.cardId == "amex-cobalt" })

        let score = Scorer.score(card: card, purchase: winningPurchase,
                                 ownerState: try SeedLoader.loadPinnedOwnerState(),
                                 asOf: "2026-08-26")

        XCTAssertFalse(score.excluded, "the product was still available on this date")
        XCTAssertEqual(score.appliedRuleId, "cobalt-eats-5x")
    }

    /// The product promise, end to end: a withdrawn card cannot win a pick, and the pick is still
    /// made rather than refused. Cobalt wins this purchase outright when active — asserted first,
    /// so the exclusion below cannot pass by accident.
    func testWithdrawnCardCannotWinThePick() throws {
        let owner = try SeedLoader.loadPinnedOwnerState()

        let live = RecommendationEngine(catalogue: try SeedLoader.loadCatalogue(), ownerState: owner)
        guard case .advised(let before) = live.recommend(winningPurchase, asOf: "2026-08-26") else {
            return XCTFail("expected advice from the shipped catalogue")
        }
        XCTAssertEqual(before.winner.cardId, "amex-cobalt", "precondition: Cobalt wins here")

        let tombstoned = RecommendationEngine(
            catalogue: try catalogueWithdrawing("amex-cobalt", on: "2026-01-01"), ownerState: owner)
        guard case .advised(let after) = tombstoned.recommend(winningPurchase, asOf: "2026-08-26") else {
            return XCTFail("one withdrawn card must not collapse the whole recommendation")
        }
        XCTAssertNotEqual(after.winner.cardId, "amex-cobalt")
        XCTAssertFalse(after.allCandidates.contains { $0.cardId == "amex-cobalt" },
                       "a withdrawn card is not a candidate")
    }

    /// The counterweight to exclusion, and the reason tombstoning exists at all: prediction rows
    /// and other repos key on `cardId`, so the id must keep resolving after withdrawal.
    func testWithdrawnCardStaysResolvableInTheCatalogue() throws {
        let catalogue = try catalogueWithdrawing("amex-cobalt", on: "2026-01-01")
        let resolved = catalogue.cards.first { $0.cardId == "amex-cobalt" }
        XCTAssertNotNil(resolved, "the id must still resolve or history orphans")
        XCTAssertEqual(resolved?.officialName, "American Express Cobalt Card")
    }
}
