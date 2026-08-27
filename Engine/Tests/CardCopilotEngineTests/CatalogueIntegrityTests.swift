import XCTest
@testable import CardCopilotEngine

/// Data may not outrun code silently. Every catalogue value the engine dispatches on must have a
/// handler; anything that does not is listed here explicitly, so a reviewer sees the gap at
/// authoring time instead of an owner discovering it as a $0.00 recommendation months later.
///
/// These lists may only SHRINK. Adding an entry means shipping a card the engine cannot score —
/// if that is genuinely intended, say so in contracts/CHANGELOG.md in the same commit.
final class CatalogueIntegrityTests: XCTestCase {

    /// Programs with no valuation. Every card on one is EXCLUDED from scoring with
    /// Warning.unsupportedProgram — such a card used to score $0.00 and rank last, which read
    /// as advice. EMPTY since 2026-08-20: every programId the catalogue declares now carries a
    /// sourced default in contracts/programs.json. Keep it empty. Adding an entry here means
    /// shipping a card the engine cannot score, and the ratchet below is set to zero so that
    /// has to be an argued exception rather than a quiet one.
    static let knownUnvaluedPrograms: Set<String> = []

    /// Owner conditions declared in the catalogue with no case in RuleMatcher.
    /// Each fails closed silently. Deleted when CardState.flags lands (spec §3.2).
    static let knownUnhandledConditions: Set<String> = ["amazonEligiblePrimeLinked"]

    /// Mirrors RuleMatcher.conditionsResolveTrue's switch. Kept here rather than made internal
    /// so the test fails when the switch and this list drift, which is the point.
    static let handledConditions: Set<String> = [
        "rogersEligibleServiceLinked", "cryptoLevelUpProActive", "tangerineCategorySelected",
    ]

    /// Mirrors CapWindow.anchorMonth's switch.
    static let resolvableAnchors: Set<String> = [
        "ownerState.scotiaAccountYearAnchorMonth", "ownerState.rogersAccountAnniversaryMonth",
    ]

    /// Cap anchors declared in the catalogue with no case in CapWindow.anchorMonth.
    /// Their windows return nil today. Deleted when CardState.anchors lands (spec §3.3).
    static let knownUnresolvableAnchors: Set<String> = [
        "ownerState.amexAccountAnniversaryMonth", "ownerState.rbcAccountAnniversaryMonth",
    ]

    /// Every product, candidates included — they are the same corpus since 2026-08-24, so this
    /// gate can no longer miss a card by looking in only one of two files.
    /// Desjardins Odyssey WE shipped with EVERY rule disabled, base rate included, so the card sat
    /// in the catalogue earning literally nothing — visible only to someone reading the JSON. A
    /// card that cannot earn on any purchase is never intentional; it is a rule that was disabled
    /// and never re-enabled. This is the general form of that bug.
    func testEveryCardCanEarnSomething() throws {
        let asOf = "2026-08-20"
        let dead = try publishedCards()
            .filter { card in !card.earnRules.contains { RuleMatcher.isLive($0, asOf: asOf) } }
            .map(\.cardId)
        XCTAssertEqual(dead, [], "cards with no live earn rule — they can never earn anything")
    }

    private func allCards() throws -> [CardProduct] {
        try SeedLoader.loadCatalogue().cards
    }

    /// The invariants below are about VERIFIED PRODUCT FACTS, and a `draft` record has none by
    /// design: it carries `earnRules: []` and `fxRules: []` because it has not cleared D3's
    /// issuer-confirmed sourcing bar, and `Scorer` refuses to score it on the status guard before
    /// it reads a single rule. Asserting those invariants over drafts asks the catalogue to state
    /// facts nobody has verified, which is the one thing the draft lane exists to avoid.
    ///
    /// Catalogue 2.2 was the first release with drafts in it, and it turned five of these gates
    /// red at once — every one of them written before `status` existed, when "in the catalogue"
    /// and "issuer-confirmed" were the same thing. Same shape as the consumer-side leak that
    /// needed `publishedCards()` in MoneyTalks: `status` arrived as a Scorer concept and no other
    /// layer was taught about it.
    private func publishedCards() throws -> [CardProduct] {
        try allCards().filter(\.isPublished)
    }

    /// The valued set is read from programs.json, not mirrored here. A hand-copied list would be
    /// one more place for the catalogue to outrun the code — inside the very gate meant to catch
    /// that. Adding a sourced valuation to programs.json now tightens this test on its own.
    func testEveryProgramIdIsValuedOrKnownUnvalued() throws {
        let valued = Set(try SeedLoader.loadPrograms().defaults.keys)
        let unhandled = Set(try publishedCards().map(\.program.programId))
            .subtracting(valued)
            .subtracting(Self.knownUnvaluedPrograms)
        XCTAssertTrue(unhandled.isEmpty,
            "programId(s) with no valuation and not on the known-gap list: \(unhandled.sorted()). "
          + "Scorer.valueCad returns nil for these, excluding every card on them. Add a default "
          + "to contracts/programs.json, "
          + "or add to knownUnvaluedPrograms with a CHANGELOG entry saying why.")
    }

    /// The ratchet only ratchets if valuing a program also retires its allowlist entry. Without
    /// this, Task 7 could add aeroplan to programs.json, leave it listed as a known gap, and the
    /// suite would report the debt as unpaid forever while quietly passing.
    func testKnownUnvaluedListRetiresProgramsThatGainedAValuation() throws {
        let valued = Set(try SeedLoader.loadPrograms().defaults.keys)
        let stale = valued.intersection(Self.knownUnvaluedPrograms)
        XCTAssertTrue(stale.isEmpty,
            "programs.json now values \(stale.sorted()), which is still listed as a known gap. "
          + "Remove from knownUnvaluedPrograms.")
    }

    /// A default keyed to a programId no card declares values nothing and reads as coverage.
    /// A single typo in programs.json would otherwise be invisible.
    func testEveryProgramDefaultKeyIsARealCatalogueProgramId() throws {
        let declared = Set(try allCards().map(\.program.programId))
        let orphans = Set(try SeedLoader.loadPrograms().defaults.keys).subtracting(declared)
        XCTAssertTrue(orphans.isEmpty,
            "contracts/programs.json values programId(s) no card declares: \(orphans.sorted()). "
          + "Likely a typo — the valuation will never be used.")
    }

    func testEveryOwnerConditionHasAHandler() throws {
        let declared = Set(try allCards().flatMap { $0.earnRules.compactMap(\.ownerConditions).flatMap { $0 } })
        let unhandled = declared
            .subtracting(Self.handledConditions)
            .subtracting(Self.knownUnhandledConditions)
        XCTAssertTrue(unhandled.isEmpty,
            "ownerCondition(s) with no handler in RuleMatcher: \(unhandled.sorted()). "
          + "These fail closed silently.")
    }

    func testEveryCapAnchorIsResolvable() throws {
        let declared = Set(try allCards().flatMap { $0.caps.compactMap(\.anchor) })
        let unresolvable = declared
            .subtracting(Self.resolvableAnchors)
            .subtracting(Self.knownUnresolvableAnchors)
        XCTAssertTrue(unresolvable.isEmpty,
            "cap.anchor path(s) CapWindow cannot resolve: \(unresolvable.sorted()). "
          + "Their windows return nil and the cap never applies.")
    }

    /// The allowlists are debt, not design. This pins their size so growth is a deliberate,
    /// reviewed act rather than a quiet regression.
    func testKnownGapListsDoNotGrow() {
        XCTAssertLessThanOrEqual(Self.knownUnvaluedPrograms.count, 0)
        XCTAssertLessThanOrEqual(Self.knownUnhandledConditions.count, 1)
        XCTAssertLessThanOrEqual(Self.knownUnresolvableAnchors.count, 2)
    }

    /// The headline outcome: no card in the catalogue is structurally unable to be scored.
    ///
    /// Routed through RecommendationEngine rather than a hand-assembled `Valuations`, because
    /// the catalogue defaults are merged in the engine's init. Building the owner state with
    /// `Valuations(programs: loadPrograms().defaults)` here would assert that programs.json
    /// contains sixteen entries — which the tests above already do — while saying nothing about
    /// whether the scoring path ever reads them. That blind spot is the one this whole phase
    /// exists to close.
    func testNoCatalogueCardIsExcludedForAnUnvaluedProgram() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let engine = RecommendationEngine(
            catalogue: catalogue,
            ownerState: try OwnerState.seedWithAllCardsOwned(catalogue: catalogue))
        let purchase = PurchaseContext(amountCad: 100, category: "other")

        for card in catalogue.cards {
            let score = Scorer.score(card: card, purchase: purchase,
                                     ownerState: engine.ownerState, asOf: "2026-08-20")
            XCTAssertFalse(score.warnings.contains(.unsupportedProgram),
                           "\(card.cardId) still has no valuation")
        }
    }

    /// A card with NO fx rule is not a fee-free card — it is a card whose FX data is missing.
    ///
    /// `Scorer` reads "no active rule" as zero FX cost, so an empty `fxRules` ranks the card as
    /// well as Wealthsimple on every foreign-currency purchase. Three cards shipped that way
    /// (rbc-ion-plus-visa, bmo-ascend-world-elite, cibc-aventura-visa) and nobody saw it, because
    /// all three were unscorable until their programs gained valuations on 2026-08-20 — the gap
    /// was hidden behind another gap.
    ///
    /// The schema cannot catch this: `"fxRules": []` is valid JSON against it, and has to stay
    /// valid, because absence and zero are different claims. Genuinely fee-free cards say so out
    /// loud with `rate: 0.0` — wealthsimple-vip, scotia-gold-amex and scotia-passport all do —
    /// so requiring at least one rule costs nothing and closes the hole. No allowlist: there is
    /// no honest reason for a card to decline to state its FX terms.
    func testEveryCardDeclaresAnFxRule() throws {
        let silent = try publishedCards().filter { $0.fxRules.isEmpty }.map(\.cardId)
        XCTAssertTrue(silent.isEmpty,
            "card(s) declaring no fxRule: \(silent.sorted()). Scorer charges them $0.00 FX, so "
          + "they outrank every 2.5% card on foreign purchases. State the rate — a fee-free card "
          + "declares rate 0.0 rather than saying nothing.")
    }

    /// RuleMatcher.matches does an exact, case-sensitive `include.contains(brand)` against
    /// `PurchaseContext.merchantBrand`, and every producer of that value
    /// (CheckoutService.canonicalEngineBrand, SpendDistribution, CanadianMerchantPreIndex) emits
    /// lowercase kebab-case tokens ("costco", "canadian-tire"). A display-cased catalogue token
    /// ("Loblaws") can therefore never match and silently drops its rule out of scoring forever —
    /// the 2026-08-26 merchantInclude rules shipped this way and stayed invisible only because
    /// scoredInV1/requires separately gated them out of live scoring. This is the general form of
    /// that bug, pinned so no future rule can ship with a token RuleMatcher can never satisfy.
    func testMerchantBrandTokensAreLowercaseKebabCase() throws {
        let tokenPattern = try NSRegularExpression(pattern: "^[a-z0-9]+(-[a-z0-9]+)*$")
        func isValidToken(_ token: String) -> Bool {
            let range = NSRange(token.startIndex..., in: token)
            return tokenPattern.firstMatch(in: token, range: range) != nil
        }

        var offenders: [String] = []
        for card in try allCards() {
            for rule in card.earnRules {
                let tokens = (rule.predicate.merchantInclude ?? []) + (rule.predicate.merchantExclude ?? [])
                offenders += tokens.filter { !isValidToken($0) }.map { "\(card.cardId)/\(rule.ruleId): \($0)" }
            }
        }
        XCTAssertEqual(offenders, [],
            "merchantInclude/merchantExclude token(s) not lowercase kebab-case, so RuleMatcher's "
          + "exact-match predicate can never be satisfied by an app-produced brand (all lowercase "
          + "kebab-case: \"costco\", \"canadian-tire\").")
    }
}
