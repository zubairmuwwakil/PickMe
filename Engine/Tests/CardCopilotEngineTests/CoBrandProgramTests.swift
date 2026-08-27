import XCTest
@testable import CardCopilotEngine

/// Co-brand reward currencies: `programId` values that name a real currency, carry no valuation,
/// and are therefore safe ONLY because every card on them is a draft.
///
/// Catalogue 2.4 opened the enum to co-brand currencies the US market is mostly made of — Avios,
/// AAdvantage, SkyMiles, Atmos Rewards. The 2026-08-27 Option 1 ruling refused to map those onto a
/// near-enough existing value, because a Delta card recorded as `amexMembershipRewardsUs` is not
/// approximately right: it values the card in a currency it does not earn, with the schema's
/// authority behind the claim. Option 2 is that refusal paid off — name the currency, and value it
/// later or not at all.
///
/// **The invariant these tests exist to hold.** None of these programmes has an entry in
/// programs.json, because `centsPerPoint` is a DISCLOSED ASSUMPTION and there is no honest source
/// for one yet. An unvalued programme is not inert: `Scorer.valueCad` answers nil for it and
/// `Scorer.score` excludes the card with `.unsupportedProgram`. What makes shipping them safe is
/// that a draft never gets that far — and it turns out it is stopped three separate times, which
/// is worth knowing precisely because it is easy to mistake for one guard doing the work:
///
///   1. `isPublished`      — the guard that is meant to do this, and the only one that is about
///                           provenance rather than a side effect of the record being empty.
///   2. `earnRules: []`    — `RuleMatcher.resolve` can match nothing, so the card is excluded two
///                           checks before any valuation is read. This is why no draft can
///                           exercise the valuation guard at all.
///   3. `valueCad != nil`  — the check that would catch it if the first two ever stopped.
///
/// The risk is not that a draft leaks today. It is that (1) could silently stop mattering while
/// (2) keeps the suite green, and then someone gives one of these cards real earn rules on the way
/// to publishing it and both safety nets are gone at once. So the tests below pin each layer to
/// the reason it exists, rather than asserting the outcome and accepting any cause.
///
/// `testEveryProgramIdIsValuedOrKnownUnvalued` already catches a published-and-unvalued card — but
/// only after the fact, by name, in a different file. These tests state the rule itself.
///
/// Nothing here hardcodes the new programIds. The set is DERIVED as "declared by a card, absent
/// from programs.json", so it maintains itself as the remaining co-brand currencies land. A
/// hand-copied list would be one more place for the catalogue to outrun the code — inside the very
/// gate meant to catch that.
final class CoBrandProgramTests: XCTestCase {

    /// Programmes some card declares and programs.json does not value.
    private func unvaluedDeclaredPrograms() throws -> Set<String> {
        let declared = Set(try SeedLoader.loadCatalogue().cards.map(\.program.programId))
        return declared.subtracting(try SeedLoader.loadPrograms().defaults.keys)
    }

    /// The load-bearing one. A card on an unvalued programme MUST be a draft, because `published`
    /// plus no valuation means `Scorer` excludes it from every recommendation it belongs in — the
    /// 11-of-16 unvalued-programs bug, which shipped for months looking like nothing at all.
    func testEveryCardOnAnUnvaluedProgramIsADraft() throws {
        let unvalued = try unvaluedDeclaredPrograms()
        let leaked = try SeedLoader.loadCatalogue().cards
            .filter { unvalued.contains($0.program.programId) && $0.isPublished }
            .map { "\($0.cardId) (\($0.program.programId))" }
        XCTAssertEqual(leaked.sorted(), [],
            "published card(s) on a programme with no valuation. Scorer excludes these with "
          + ".unsupportedProgram, so they vanish from every recommendation rather than ranking "
          + "badly. Either add a sourced default to contracts/programs.json, or leave the card a "
          + "draft until one exists — never publish it unvalued.")
    }

    /// A draft on one of these programmes is refused on STATUS, ahead of everything else.
    ///
    /// Worth pinning separately from the valuation behaviour below, because these drafts are in
    /// fact protected three times over — `isPublished`, then an empty `earnRules` set that
    /// `RuleMatcher.resolve` cannot satisfy, and only then the valuation check. Redundancy is not
    /// the same as intent: `status` is the guard that is SUPPOSED to be doing this work, and if it
    /// stopped, the other two would keep the suite green while the reason had quietly changed.
    func testADraftIsRefusedOnStatusAndNotOnSomethingElse() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let unvalued = try unvaluedDeclaredPrograms()
        let draft = try XCTUnwrap(
            catalogue.cards.first { unvalued.contains($0.program.programId) && !$0.isPublished },
            "expected at least one draft on an unvalued programme")

        let engine = RecommendationEngine(
            catalogue: catalogue,
            ownerState: try OwnerState.seedWithAllCardsOwned(catalogue: catalogue))
        let score = Scorer.score(card: draft, purchase: PurchaseContext(amountCad: 100, category: "other"),
                                 ownerState: engine.ownerState, asOf: "2026-08-27")

        XCTAssertTrue(score.excluded)
        XCTAssertEqual(score.warnings, [.draftProduct],
            "a draft must be refused on status ALONE. Any other warning here means the status "
          + "guard stopped running first and something downstream is doing its job by accident.")
    }

    /// What happens if one of these currencies ever reaches a real, rule-bearing published card
    /// without a valuation: `Scorer` must REFUSE it, not score it at zero.
    ///
    /// This is the guard the whole change rests on, and no draft can exercise it — a draft carries
    /// no earn rules, so `RuleMatcher.resolve` excludes it two checks earlier and the valuation
    /// code is never reached. So the test builds the case that cannot occur today: a published card
    /// that scores normally, with nothing changed but its `programId`.
    ///
    /// Routed through `RecommendationEngine` rather than a bare `OwnerState` because the catalogue
    /// defaults are merged in the engine's init. Without that merge NOTHING would be valued and the
    /// assertion would pass for the wrong reason — the same blind spot
    /// `testNoCatalogueCardIsExcludedForAnUnvaluedProgram` documents.
    func testAPublishedCardOnAnUnvaluedProgramIsRefusedRatherThanScoredAtZero() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let engine = RecommendationEngine(
            catalogue: catalogue,
            ownerState: try OwnerState.seedWithAllCardsOwned(catalogue: catalogue))
        let purchase = PurchaseContext(amountCad: 100, category: "other")
        let unvalued = try XCTUnwrap(unvaluedDeclaredPrograms().sorted().first,
                                     "expected at least one unvalued co-brand programme")

        // A card that already scores cleanly, so every guard ahead of the valuation check passes
        // and the swap below isolates exactly one variable.
        let healthy = try XCTUnwrap(
            catalogue.cards.first { card in
                card.isPublished && !Scorer.score(card: card, purchase: purchase,
                                                  ownerState: engine.ownerState,
                                                  asOf: "2026-08-27").excluded
            },
            "expected at least one published card that scores on an ordinary purchase")

        var reprogrammed = healthy
        reprogrammed.program = Program(programId: unvalued, unit: "point")
        let score = Scorer.score(card: reprogrammed, purchase: purchase,
                                 ownerState: engine.ownerState, asOf: "2026-08-27")

        XCTAssertTrue(score.warnings.contains(.unsupportedProgram),
            "changing ONLY the programId to \(unvalued) must exclude the card. If it scores "
          + "instead, an unvalued currency is being silently treated as worth something.")
        XCTAssertTrue(score.excluded)
        XCTAssertEqual(score.netValueCad, 0,
                       "an excluded card must not carry a number anyone could rank on")
    }

    /// An unvalued programme must stay distinct from a valued-at-zero one. `noRewards` answers 0.0
    /// and the card is scored; a co-brand currency answers nil and the card is excluded. Collapsing
    /// them would rank "we cannot value this" as "this is worth nothing" — the exact inversion
    /// `noRewards` was introduced to keep impossible.
    func testAnUnvaluedProgramAnswersNilNotZero() throws {
        let valuations = try Valuations(programs: SeedLoader.loadPrograms().defaults)
        for program in try unvaluedDeclaredPrograms() {
            XCTAssertNil(Scorer.valueCad(units: 100, program: program,
                                         valuations: valuations, state: CardState()),
                         "\(program) must answer nil, keeping it distinct from noRewards' 0.0")
        }
    }

    // MARK: - Avios, the first co-brand currency and the only one spanning both markets

    /// Avios is the shared IAG currency: British Airways, Aer Lingus and Iberia all earn it, and
    /// RBC's Canadian British Airways card earns it into the same Executive Club account. One
    /// programId across two markets is INTENDED here, on the same 2026-08-27 side-ruling that keeps
    /// `marriottBonvoy` and `aeroplan` cross-market — valuation is keyed on programId alone, so
    /// sharing one is correct precisely when the currency is genuinely the same. It is not correct
    /// for currencies that merely rhyme, which is why the Costco certificates were left out: the
    /// CIBC one is CAD and spends only in Canadian warehouses, the Citi one is USD and spends only
    /// in US ones.
    func testAviosSpansBothMarketsOnOneProgramId() throws {
        let avios = try SeedLoader.loadCatalogue().cards.filter { $0.program.programId == "avios" }
        XCTAssertEqual(avios.count, 4, "Aer Lingus, British Airways, Iberia (US) and RBC BA (CA)")
        XCTAssertEqual(Set(avios.map(\.market)), [.us, .ca],
                       "the cross-market case is the point — do not let this collapse to one market")
        XCTAssertTrue(avios.allSatisfy { $0.program.unit == "point" },
                      "airline currencies use the catalogue's generic point unit, as aeroplan does")
    }

    /// A draft states identity and fee and claims NOTHING about how the card earns. Pinned here
    /// because the temptation on a co-brand is to write the marketed "3x on airfare" from an
    /// aggregator's prose, which is the drift the draft lane exists to prevent.
    func testCoBrandDraftsClaimNoEarnStructure() throws {
        let unvalued = try unvaluedDeclaredPrograms()
        for card in try SeedLoader.loadCatalogue().cards
            where unvalued.contains(card.program.programId) {
            XCTAssertTrue(card.earnRules.isEmpty, "\(card.cardId) must claim no earn rules")
            XCTAssertTrue(card.fxRules.isEmpty, "\(card.cardId) must claim no FX terms")
            XCTAssertTrue(card.caps.isEmpty, "\(card.cardId) must claim no caps")
        }
    }
}
