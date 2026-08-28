import XCTest
@testable import CardCopilotEngine

final class SeedLoaderTests: XCTestCase {
    func testCatalogueLoadsAllCards() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        // Every supported product, not just the seed owner's wallet (one corpus, 2026-08-24).
        // Counted as PUBLISHED rather than total since catalogue 2.2 added US drafts: a bare
        // total would move on every import and stop asserting anything about the corpus.
        XCTAssertEqual(catalogue.cards.filter(\.isPublished).count, 49)
        XCTAssertFalse(catalogue.cards.allSatisfy(\.isPublished), "expected drafts in 2.2+")
        let cobalt = try XCTUnwrap(catalogue.cards.first { $0.cardId == "amex-cobalt" })
        XCTAssertEqual(ReportingCurrency.toReporting(cobalt.fee.annual), 191.88, accuracy: 0.005)
        XCTAssertEqual(cobalt.network, .amex)
        XCTAssertEqual(cobalt.caps.first?.capId, "cobalt-eats-monthly")
        guard case .points(let ppc) = try XCTUnwrap(
            cobalt.earnRules.first { $0.ruleId == "cobalt-eats-5x" }).earn
        else { return XCTFail("expected points earn") }
        XCTAssertEqual(ppc, 5)
        let crypto = try XCTUnwrap(catalogue.cards.first { $0.cardId == "cryptocom-royal-indigo" })
        XCTAssertEqual(crypto.fxRules.count, 2, "current + announced FX records")
        XCTAssertEqual(crypto.kind, .prepaid)
    }

    /// Candidates are references into the one corpus. The property that matters is no longer
    /// "these are separate cards" — it is that every id resolves, so a candidate can never be a
    /// product the catalogue does not define.
    func testCandidateCatalogueIsIdReferencesThatAllResolve() throws {
        let candidates = try SeedLoader.loadCandidateCatalogue()
        let catalogue = try SeedLoader.loadCatalogue()
        let known = Set(catalogue.cards.map(\.cardId))

        XCTAssertEqual(candidates.cardIds.count, 6)
        XCTAssertEqual(Set(candidates.cardIds).count, candidates.cardIds.count, "no duplicate ids")
        let unresolved = candidates.cardIds.filter { !known.contains($0) }
        XCTAssertEqual(unresolved, [], "every candidate id must name a card in the catalogue")
    }

    func testOwnerStateLoads() throws {
        let state = try SeedLoader.loadOwnerState()
        XCTAssertEqual(state.defaultCardId, "wealthsimple-vip")
        XCTAssertEqual(state.ownedCardIds.count, 27)
        XCTAssertEqual(state.switchThreshold.semantics, "both")
        let mr = state.pointsValuation()
        XCTAssertEqual(mr.centsPerPoint, 1.0, accuracy: 0.005,
                       "MR ranks at the guaranteed cash floor — no redemption history to justify more")
        XCTAssertEqual(mr.floorCentsPerPoint ?? .nan, 1.0, accuracy: 0.005)
        XCTAssertEqual(mr.aspirationalCentsPerPoint ?? .nan, 2.2, accuracy: 0.005,
                       "published benchmark; used only as the disclosure ceiling, never for ranking")
        XCTAssertTrue(state.carry.drawerCards.contains("triangle-we"))
        XCTAssertEqual(state.cardStates["rogers-red-we"]?.rogersEligibleServiceLinked, false)
        XCTAssertEqual(state.cardStates["cryptocom-royal-indigo"]?.cryptoLevelUpProActive, false)
        XCTAssertNil(state.cardStates["cryptocom-royal-indigo"]?.croHandling,
                     "unset onboarding fields must decode as nil, never a default")
        XCTAssertEqual(state.cardStates["scotia-momentum-vi-plus"]?
            .capProgress?["momentum-4pct-accountYear"] ?? 0, 12500, accuracy: 0.005)
        XCTAssertEqual(state.cardStates["tangerine-moneyback-world"]?.selectedCategories?.count, 13,
                       "treat-as-all-selected: 13 eligible Tangerine categories")
    }

    func testCatalogueVersionRejectsAnUnknownMajor() {
        // 1.x was the last major before the 2026-08-26 multi-market bump (Money-shaped fees/
        // credits, market/billingCurrency, spendNative replacing spendCad, calendarQuarter) —
        // still a real shape this build can no longer decode correctly, so it must still throw.
        XCTAssertThrowsError(try SeedLoader.validate(catalogueVersion: "1.6")) { error in
            XCTAssertEqual(error as? SeedLoaderError, .unsupportedCatalogueVersion("1.6"))
        }
        XCTAssertThrowsError(try SeedLoader.validate(catalogueVersion: "3.0")) { error in
            XCTAssertEqual(error as? SeedLoaderError, .unsupportedCatalogueVersion("3.0"))
        }
    }

    func testCatalogueVersionAcceptsTheKnownMajorRegardlessOfMinor() {
        XCTAssertNoThrow(try SeedLoader.validate(catalogueVersion: "2.0"))
        XCTAssertNoThrow(try SeedLoader.validate(catalogueVersion: "2.7"))
    }

    func testCatalogueVersionRejectsAMalformedString() {
        XCTAssertThrowsError(try SeedLoader.validate(catalogueVersion: "not-a-version"))
    }
}

extension SeedLoaderTests {
    func testLoadsProgramDefaults() throws {
        let programs = try SeedLoader.loadPrograms()
        XCTAssertEqual(programs.programsVersion, "1.4")
        guard case .cashback(let cash) = try XCTUnwrap(programs.defaults["cashback"])
        else { return XCTFail("expected .cashback") }
        XCTAssertEqual(cash.cadPerDollar, 1.0)
    }

    /// Owner overrides win; catalogue defaults fill the gaps. Neither alone is enough:
    /// defaults-only ignores the owner's declared value, overrides-only leaves new programs unvalued.
    func testOwnerOverrideBeatsCatalogueDefault() throws {
        let defaults = try SeedLoader.loadPrograms().defaults
        var owner = Valuations(programs: defaults)
        owner["cashback"] = .cashback(CashBackValuation(cadPerDollar: 0.5))
        guard case .cashback(let cash) = try XCTUnwrap(owner["cashback"])
        else { return XCTFail("expected .cashback") }
        XCTAssertEqual(cash.cadPerDollar, 0.5)
    }

    /// A default is a number the engine will spend the owner's money on, so it has to say where
    /// it came from. The disclosure UI renders this string; an entry without one is a valuation
    /// presented as a fact.
    func testEveryProgramDefaultDisclosesItsBasis() throws {
        for (programId, valuation) in try SeedLoader.loadPrograms().defaults {
            let basis: String?
            switch valuation {
            case .points(let v):   basis = v.basis
            case .cashback(let v): basis = v.basis
            case .ctMoney(let v):  basis = v.basis
            case .cro(let v):      basis = v.basis
            case .noRewards(let v): basis = v.basis
            }
            XCTAssertFalse((basis ?? "").isEmpty,
                           "programs.json default '\(programId)' ships no basis disclosure")
        }
    }

    /// Every program the shipped owner state values must also be valued in programs.json, under
    /// the same model. A program the owner state values but the defaults do not means a fresh
    /// install with no owner state cannot score that program at all; a programId valued as
    /// points in one and cashback in the other is a data bug that only surfaces as a wrong
    /// number.
    ///
    /// A SUBSET, not an equality: since 2026-08-20 programs.json values all sixteen catalogue
    /// programIds while the owner state declares six. The defaults exceeding the owner state is
    /// the point of the file — the reverse is the bug.
    ///
    /// Deliberately does NOT assert the numbers agree. They do today, because programs.json was
    /// derived from the shipped owner state — but a valuation is a personal forecast of
    /// redemption behaviour, and the owner is entitled to declare one that differs from the
    /// catalogue's default. That is the whole point of the override. Pinning the numbers here
    /// would turn a preference change into a test failure.
    func testProgramDefaultsCoverTheShippedOwnerStateUnderTheSameModels() throws {
        let defaults = try SeedLoader.loadPrograms().defaults
        let owner = try SeedLoader.loadOwnerState().valuationsCad

        XCTAssertTrue(Set(owner.programs.keys).isSubset(of: Set(defaults.keys)),
            "owner-state.json values program(s) programs.json does not: "
          + "\(Set(owner.programs.keys).subtracting(defaults.keys).sorted()). A fresh install "
          + "with no owner state cannot score those at all.")

        for (programId, ownerValuation) in owner.programs {
            switch (ownerValuation, try XCTUnwrap(defaults[programId], programId)) {
            case (.points, .points), (.cashback, .cashback),
                 (.ctMoney, .ctMoney), (.cro, .cro):
                continue
            default:
                XCTFail("'\(programId)' is valued under different models in owner state and defaults")
            }
        }
    }
}
