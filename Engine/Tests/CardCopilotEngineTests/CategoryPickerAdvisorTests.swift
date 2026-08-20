import XCTest
@testable import CardCopilotEngine

/// The category picker ("which card do I use for X?") is entirely data-driven: the pill set,
/// every label, and every amount band are derived from the loaded catalogue and owner state at
/// call time. These tests assert structure and invariants that must hold for *any* catalogue,
/// not that a particular card wins a particular category — the catalogue is expected to keep
/// growing, and a test pinned to today's winner would just rot.
final class CategoryPickerAdvisorTests: XCTestCase {
    let asOf = "2026-08-20"

    // MARK: - Pill derivation

    /// The derived pill set is exactly the formula the advisor documents: accelerator
    /// vocabulary, plus curated, minus excluded. This is a regression guard on the formula
    /// itself — if a future edit hardcodes or special-cases the list, this fails.
    func testDerivedCategoriesMatchTheDocumentedFormula() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let vocabulary = CategoryPickerAdvisor.acceleratedVocabulary(catalogue: catalogue)
        let curated = Set(CategoryPickerAdvisor.curatedCategories.map(\.category))
        let excluded = Set(CategoryPickerAdvisor.excludedCategories.map(\.category))
        let expected = vocabulary.union(curated).subtracting(excluded)

        let derived = Set(CategoryPickerAdvisor.derivedCategories(catalogue: catalogue))
        XCTAssertEqual(derived, expected)
        // No pill for a rule-side marker, ever.
        XCTAssertFalse(derived.contains("ownerSelectedTangerineCategory"))
    }

    /// Drift test: every category an accelerator predicate names must be answered for — either
    /// it has a pill, or it is named in the exclusion set with a reason. This is the test that
    /// must fail the build the day a catalogue expansion adds a category nobody accounted for.
    func testDriftEveryAcceleratedCategoryIsPilledOrExcludedWithAReason() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let vocabulary = CategoryPickerAdvisor.acceleratedVocabulary(catalogue: catalogue)
        let pills = Set(CategoryPickerAdvisor.derivedCategories(catalogue: catalogue))
        let excludedReasons = Dictionary(uniqueKeysWithValues:
            CategoryPickerAdvisor.excludedCategories.map { ($0.category, $0.reason) })

        for category in vocabulary {
            let isPilled = pills.contains(category)
            let isExcludedWithReason = excludedReasons[category]?.isEmpty == false
            XCTAssertTrue(isPilled || isExcludedWithReason,
                          "'\(category)' is named by an accelerator predicate but has neither a "
                          + "pill nor a reasoned entry in the exclusion set")
        }
    }

    /// The curated and excluded lists are hand-maintained, so their written reasons can go
    /// stale as the catalogue changes. A curated pill should still have no accelerator (its
    /// reason is "no accelerator names this"); an excluded id should still actually appear in
    /// the accelerator vocabulary (excluding something the catalogue no longer mentions is a
    /// silent no-op that would hide a real drift elsewhere).
    func testCuratedAndExcludedEntriesStayTrueToTheCatalogue() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let vocabulary = CategoryPickerAdvisor.acceleratedVocabulary(catalogue: catalogue)

        for entry in CategoryPickerAdvisor.curatedCategories {
            XCTAssertFalse(entry.reason.isEmpty, "'\(entry.category)' needs a written reason")
            XCTAssertFalse(vocabulary.contains(entry.category),
                           "'\(entry.category)' is curated as having no accelerator, but an "
                           + "accelerator now names it — the curated entry (and its reason) is "
                           + "stale")
        }
        for entry in CategoryPickerAdvisor.excludedCategories {
            XCTAssertFalse(entry.reason.isEmpty, "'\(entry.category)' needs a written reason")
            XCTAssertTrue(vocabulary.contains(entry.category),
                          "'\(entry.category)' is excluded as a rule-side marker, but no "
                          + "accelerator predicate names it any more — the exclusion is a "
                          + "no-op and may be hiding a real gap")
        }
    }

    // MARK: - Labels

    /// A category with no bucket and no curated override must still transform into words, not
    /// pass its raw catalogue id straight through.
    func testLabelNeverRendersARawIdentifierForAnUnlabeledCategory() {
        let distribution = SpendDistribution.placeholderCanadianHousehold
        let unlabeled = ["someBrandNewSpendCategory", "entertainment"]
        for category in unlabeled {
            let label = CategoryPickerAdvisor.label(for: category, distribution: distribution)
            XCTAssertNotEqual(label, category,
                              "'\(category)' rendered unchanged — a future user would see a raw "
                              + "engine identifier")
        }
    }

    /// Categories with a curated override or a SpendDistribution bucket must use that specific
    /// label, not the mechanical camelCase fallback.
    func testLabelUsesTheCuratedOrBucketLabelWhenOneExists() {
        let distribution = SpendDistribution.placeholderCanadianHousehold
        XCTAssertEqual(CategoryPickerAdvisor.label(for: "ctFamily", distribution: distribution),
                       "Canadian Tire family")
        XCTAssertEqual(CategoryPickerAdvisor.label(for: "dining", distribution: distribution),
                       "Restaurants & coffee")
        XCTAssertEqual(CategoryPickerAdvisor.label(for: "grocery", distribution: distribution),
                       "Groceries")
        // "other" deliberately does not inherit either ambiguous bucket's label.
        let otherLabel = CategoryPickerAdvisor.label(for: "other", distribution: distribution)
        XCTAssertNotEqual(otherLabel, "Foreign currency (USD online)")
        XCTAssertNotEqual(otherLabel, "Everything else")
    }

    // MARK: - Bands: structure holds for every derived pill

    func testEveryDerivedPillResolvesToAtLeastOneBandWithARealCard() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        let realCardIds = Set(catalogue.cards.map(\.cardId))

        for category in CategoryPickerAdvisor.derivedCategories(catalogue: catalogue) {
            let bands = CategoryPickerAdvisor.bands(for: category, catalogue: catalogue,
                                                    ownerState: owner, asOf: asOf)
            XCTAssertFalse(bands.isEmpty, "'\(category)' resolved to zero bands")
            for band in bands {
                let upperText: String = band.upperBoundCad.map { String($0) } ?? "∞"
                XCTAssertTrue(realCardIds.contains(band.cardId),
                              "'\(category)' band [\(band.lowerBoundCad), \(upperText)) names "
                              + "'\(band.cardId)', which isn't a card in the catalogue")
            }
        }
    }

    /// Also covers the single-band case: a category whose answer never changes with amount must
    /// resolve to exactly one band spanning $0 to open-ended, which is what "starts at 0" and
    /// "ends open-ended" already assert when there's nothing in between.
    func testBandBoundariesAreStrictlyIncreasingAndBandsAreContiguous() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()

        for category in CategoryPickerAdvisor.derivedCategories(catalogue: catalogue) {
            let bands = CategoryPickerAdvisor.bands(for: category, catalogue: catalogue,
                                                    ownerState: owner, asOf: asOf)
            XCTAssertEqual(bands.first?.lowerBoundCad, 0,
                           "'\(category)' bands must start at $0")
            XCTAssertNil(bands.last?.upperBoundCad,
                        "'\(category)' bands must end open-ended")
            for (index, band) in bands.enumerated() where index > 0 {
                let previous = bands[index - 1]
                guard let previousUpper = previous.upperBoundCad else {
                    XCTFail("'\(category)' has a band after an open-ended one")
                    continue
                }
                XCTAssertEqual(band.lowerBoundCad, previousUpper,
                               "'\(category)' has a gap or overlap between bands \(index - 1) "
                               + "and \(index)")
                XCTAssertGreaterThan(previousUpper, previous.lowerBoundCad,
                                     "'\(category)' band \(index - 1) has a non-increasing "
                                     + "boundary")
            }
        }
    }

    /// Where the lowest band's boundary is a soft switch-threshold crossing (the default card
    /// is a valid, accepted candidate), the lowest band must be the default — that's what the
    /// threshold means: not worth switching yet. Where the default isn't even an accepted
    /// candidate (Costco's Mastercard-only gate against a Visa default), the threshold never
    /// applied in the first place, so the invariant doesn't apply — `defaultNotAccepted` says
    /// so explicitly.
    func testLowestBandIsTheDefaultCardWhereASwitchThresholdBoundaryExists() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()

        for category in CategoryPickerAdvisor.derivedCategories(catalogue: catalogue) {
            let bands = CategoryPickerAdvisor.bands(for: category, catalogue: catalogue,
                                                    ownerState: owner, asOf: asOf)
            guard bands.count > 1 else { continue }
            let lowest = bands[0]
            XCTAssertTrue(lowest.cardId == owner.defaultCardId || lowest.recommendation.defaultNotAccepted,
                          "'\(category)' has multiple bands but its lowest-amount band is "
                          + "'\(lowest.cardId)', neither the default card ('\(owner.defaultCardId)') "
                          + "nor a defaultNotAccepted case")
        }
    }

    // MARK: - Enrichment

    /// A category with a SpendDistribution bucket must be swept using that bucket's context,
    /// not a bare category-only context — that's how Costco's Mastercard-only gate and MBNA's
    /// MCC-gated 5x actually get exercised.
    func testEnrichedTemplateUsesTheBucketContextWhenOneExists() {
        let distribution = SpendDistribution.placeholderCanadianHousehold
        let costco = CategoryPickerAdvisor.enrichedTemplate(for: "wholesaleClub", distribution: distribution)
        XCTAssertEqual(costco.acceptedNetworks, [.mastercard])
        XCTAssertEqual(costco.merchantBrand, "costco")

        let grocery = CategoryPickerAdvisor.enrichedTemplate(for: "grocery", distribution: distribution)
        XCTAssertEqual(grocery.mcc, 5411)
    }

    func testEnrichedTemplateForACategoryWithNoBucketIsMinimal() {
        let distribution = SpendDistribution.placeholderCanadianHousehold
        let context = CategoryPickerAdvisor.enrichedTemplate(for: "carRental", distribution: distribution)
        XCTAssertEqual(context.category, "carRental")
        XCTAssertNil(context.mcc)
        XCTAssertNil(context.merchantBrand)
    }

    // MARK: - Floating-point regime noise

    /// Regression. `amex-cobalt`'s `cobalt-gas-transit-2x` (2 points/$ at 1.0¢/point) and
    /// `scotia-momentum-vi-plus`'s `momentum-gas-ev-transit-2pct` (2% flat cashback) both earn
    /// exactly 2% on gas — but one gets there via `amountCad * 2 * (1.0 / 100)` and the other
    /// via `amountCad * 0.02`, which are not always bit-identical `Double`s. With the wallet's
    /// real default (`wealthsimple-vip`, also 2%) this never shows: ties always resolve to the
    /// default card. Swap in a default that doesn't also tie (`amex-platinum`, 1x here) and,
    /// without a floating-point tolerance, the sweep chased that single genuine tie into a dozen
    /// meaningless micro-bands — Cobalt, Momentum, Cobalt, Momentum — every few cents. This
    /// pins the fix: the tie must collapse to the one real boundary against the default.
    func testFloatingPointTiesBetweenEquallyRatedCardsDoNotProduceMicroBands() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        var owner = try SeedLoader.loadOwnerState()
        owner.defaultCardId = "amex-platinum"
        let bands = CategoryPickerAdvisor.bands(for: "gasStation", catalogue: catalogue,
                                                ownerState: owner, asOf: asOf)
        XCTAssertLessThanOrEqual(bands.count, 2,
                                 "gasStation produced \(bands.count) bands with amex-platinum as "
                                 + "default — a floating-point tie between amex-cobalt and "
                                 + "scotia-momentum-vi-plus (both earn exactly 2%) may be "
                                 + "leaking through as spurious boundaries again: \(bands)")
    }

    func testCategoryBandsOnlyRecommendOwnedCards() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        var owner = try SeedLoader.loadOwnerState()
        owner.ownedCardIds = ["amex-simplycash"]
        owner.defaultCardId = "amex-simplycash"
        // Canadian Tire family spend would normally switch to Triangle WE above $9.81 if unowned cards were evaluated.
        let bands = CategoryPickerAdvisor.bands(for: "ctFamily", catalogue: catalogue,
                                                ownerState: owner, asOf: asOf)
        XCTAssertEqual(bands.count, 1)
        XCTAssertEqual(bands.first?.cardId, "amex-simplycash")
    }
}
