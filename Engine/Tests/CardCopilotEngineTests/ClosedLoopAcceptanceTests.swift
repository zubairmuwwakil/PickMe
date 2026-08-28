import XCTest
@testable import CardCopilotEngine

/// A private-label card runs on no payment network. `network` is required with a closed enum, so
/// before `privateLabel` existed the only way to land one was to guess — and a Kohl's card
/// recorded as `visa` would be recommended at a gas station, where it is declined at the till.
///
/// The inversion worth keeping in view: a closed-loop card is the SHARPEST possible answer to
/// "which card should I tap right now" — at exactly one merchant it is often unbeatable — and it
/// was the one card the schema could not describe.
final class ClosedLoopAcceptanceTests: XCTestCase {

    /// A real, valued catalogue card with its acceptance rewritten — the same trick
    /// `CapabilityGatingTests` uses, and for the same reason: it keeps `program`, `fee` and the
    /// valuation honest, so a closed-loop card that scores does so for real reasons rather than
    /// because a hand-built fixture was arranged to let it.
    private func card(cardId: String = "scotia-momentum-vi-plus",
                      network: Network, acceptance: Acceptance?) throws -> CardProduct {
        var card = try XCTUnwrap(SeedLoader.loadCatalogue().cards.first { $0.cardId == cardId })
        card.network = network
        card.acceptance = acceptance
        card.caps = []
        card.earnRules = [EarnRule(ruleId: "flat-2pct", status: .current,
                                   sourceType: .issuerConfirmed,
                                   earn: .cashback(rate: 0.02, rewardCurrency: nil),
                                   predicate: Predicate(), requires: nil, outOfScope: nil)]
        return card
    }

    private func closedLoopCard(merchants: [String]) throws -> CardProduct {
        try card(network: .privateLabel,
                 acceptance: Acceptance(scope: .closedLoop, merchants: merchants))
    }

    private func score(_ card: CardProduct, _ purchase: PurchaseContext) throws -> CandidateScore {
        Scorer.score(card: card, purchase: purchase,
                     ownerState: try SeedLoader.loadPinnedOwnerState(), asOf: "2026-08-27")
    }

    func testAClosedLoopCardIsExcludedAtAnotherMerchant() throws {
        let s = try score(closedLoopCard(merchants: ["kohls"]),
                          PurchaseContext(amountCad: 50, category: "gasStation",
                                          merchantBrand: "petro-canada"))
        XCTAssertTrue(s.excluded)
        XCTAssertTrue(s.warnings.contains(.merchantNotAccepted))
    }

    /// The product claim, not just the guard: at its own merchant the card scores a real number.
    /// Asserting only the absence of a warning would pass even if the card were excluded for some
    /// unrelated reason, which would hide exactly the regression this file exists to catch.
    func testAClosedLoopCardIsAcceptedAtItsOwnMerchant() throws {
        let s = try score(closedLoopCard(merchants: ["kohls"]),
                          PurchaseContext(amountCad: 50, category: "retail",
                                          merchantBrand: "kohls"))
        XCTAssertFalse(s.warnings.contains(.merchantNotAccepted))
        XCTAssertFalse(s.excluded, "exclusion reason: \(s.exclusionReason ?? "none")")
        XCTAssertEqual(s.netValueCad, 1.0, accuracy: 0.0001, "2% of $50, scored like any other card")
    }

    /// The safe failure direction: silence beats recommending a card that gets declined. These
    /// cards are only ever as good as brand resolution, which is a stated assumption, not a
    /// hidden one.
    func testAnUnknownMerchantExcludesAClosedLoopCard() throws {
        let s = try score(closedLoopCard(merchants: ["kohls"]),
                          PurchaseContext(amountCad: 50, category: "retail", merchantBrand: nil))
        XCTAssertTrue(s.excluded)
        XCTAssertTrue(s.warnings.contains(.merchantNotAccepted))
    }

    /// merchantNotAccepted is its own case because the two facts are different and the UI must
    /// not conflate them: "this card only works at Kohl's" is not "Visa isn't accepted here".
    func testTheNetworkWarningIsNotReusedForAMerchantRefusal() throws {
        let s = try score(closedLoopCard(merchants: ["kohls"]),
                          PurchaseContext(amountCad: 50, category: "retail",
                                          merchantBrand: "petro-canada"))
        XCTAssertFalse(s.warnings.contains(.networkNotAccepted))
    }

    /// Fail-closed: an open-loop card is untouched by any of this.
    func testAnOpenLoopCardStillGuardsOnNetwork() throws {
        let s = try score(card(network: .visa, acceptance: nil),
                          PurchaseContext(amountCad: 50, category: "retail",
                                          acceptedNetworks: [.mastercard]))
        XCTAssertTrue(s.excluded)
        XCTAssertTrue(s.warnings.contains(.networkNotAccepted))
    }

    func testEveryExistingCatalogueCardIsOpenLoop() throws {
        let cards = try SeedLoader.loadCatalogue().cards
        let closedLoop = cards.filter { $0.acceptance?.scope == .closedLoop }.map(\.cardId)
        XCTAssertEqual(closedLoop, [],
            "no catalogue card declares closed-loop acceptance yet; landing one is a separate, "
            + "research-gated change.")
    }

    /// The Swift half of `card-catalogue.schema.json`'s if/then invariant, which nothing in CI
    /// validates the catalogue against — the same hole that let the `noRewards` model ship
    /// against a schema that did not know it (fixed 2026-08-27 for `programs.json`).
    ///
    /// Unlike the test above, this one SURVIVES the first closed-loop card: it is the assertion
    /// that stops a `privateLabel` card landing with no acceptance list (excluded everywhere) or
    /// a `closedLoop` acceptance landing on a real network (a restriction the openLoop branch of
    /// `Scorer` silently ignores).
    func testPrivateLabelAndClosedLoopAcceptanceAreInseparable() throws {
        var offenders: [String] = []
        for card in try SeedLoader.loadCatalogue().cards {
            let isPrivateLabel = card.network == .privateLabel
            let isClosedLoop = card.acceptance?.scope == .closedLoop
            if isPrivateLabel != isClosedLoop {
                offenders.append("\(card.cardId): network=\(card.network.rawValue), "
                    + "acceptance=\(card.acceptance.map { $0.scope.rawValue } ?? "absent")")
            }
            if isClosedLoop, card.acceptance?.merchants.isEmpty != false {
                offenders.append("\(card.cardId): closedLoop with no merchants — unpickable")
            }
        }
        XCTAssertEqual(offenders, [],
            "network: privateLabel and acceptance.scope: closedLoop must be declared together. "
            + "Either alone is a card that can never be recommended anywhere.")
    }
}
