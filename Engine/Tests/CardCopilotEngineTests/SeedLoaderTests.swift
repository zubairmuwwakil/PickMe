import XCTest
@testable import CardCopilotEngine

final class SeedLoaderTests: XCTestCase {
    func testCatalogueLoadsAllCards() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        XCTAssertEqual(catalogue.cards.count, 27)
        let cobalt = try XCTUnwrap(catalogue.cards.first { $0.cardId == "amex-cobalt" })
        XCTAssertEqual(cobalt.fee.annualCad ?? 0, 191.88, accuracy: 0.005)
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

    func testCandidateCatalogueLoadsSeparately() throws {
        let candidates = try SeedLoader.loadCandidateCatalogue()
        XCTAssertEqual(candidates.cards.count, 6)
        XCTAssertTrue(candidates.cards.allSatisfy {
            $0.lastVerifiedAt == "2026-08-16"
        })
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
        XCTAssertThrowsError(try SeedLoader.validate(catalogueVersion: "2.0")) { error in
            XCTAssertEqual(error as? SeedLoaderError, .unsupportedCatalogueVersion("2.0"))
        }
    }

    func testCatalogueVersionAcceptsTheKnownMajorRegardlessOfMinor() {
        XCTAssertNoThrow(try SeedLoader.validate(catalogueVersion: "1.0"))
        XCTAssertNoThrow(try SeedLoader.validate(catalogueVersion: "1.7"))
    }

    func testCatalogueVersionRejectsAMalformedString() {
        XCTAssertThrowsError(try SeedLoader.validate(catalogueVersion: "not-a-version"))
    }
}

extension SeedLoaderTests {
    func testLoadsProgramDefaults() throws {
        let programs = try SeedLoader.loadPrograms()
        XCTAssertEqual(programs.programsVersion, "1.0")
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
            }
            XCTAssertFalse((basis ?? "").isEmpty,
                           "programs.json default '\(programId)' ships no basis disclosure")
        }
    }

    /// programs.json and the shipped owner state must value the same programs under the same
    /// models. A program the owner state values but the defaults do not means a fresh install
    /// with no owner state cannot score that program at all; a programId valued as points in one
    /// and cashback in the other is a data bug that only surfaces as a wrong number.
    ///
    /// Deliberately does NOT assert the numbers agree. They do today, because programs.json was
    /// derived from the shipped owner state — but a valuation is a personal forecast of
    /// redemption behaviour, and the owner is entitled to declare one that differs from the
    /// catalogue's default. That is the whole point of the override. Pinning the numbers here
    /// would turn a preference change into a test failure.
    func testProgramDefaultsCoverTheShippedOwnerStateUnderTheSameModels() throws {
        let defaults = try SeedLoader.loadPrograms().defaults
        let owner = try SeedLoader.loadOwnerState().valuationsCad

        XCTAssertEqual(Set(defaults.keys), Set(owner.programs.keys),
                       "programs.json and owner-state.json value different program sets")

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
