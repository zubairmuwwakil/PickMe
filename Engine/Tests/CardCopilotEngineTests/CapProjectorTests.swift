import XCTest
@testable import CardCopilotEngine

/// Cap-burn projection from declared recurring spend. Every case defends one claim: this is a
/// forecast built on numbers nobody verified, and it must never read as an observation.
final class CapProjectorTests: XCTestCase {

    private func projector() throws -> CapProjector {
        CapProjector(catalogue: try SeedLoader.loadCatalogue(),
                     ownerState: try SeedLoader.loadPinnedOwnerState())
    }

    private func onScotia(_ amountCad: Double, cadence: Cadence = .monthly,
                          nextChargeMonth: String? = nil) -> PlacedPayment {
        PlacedPayment(payment: RecurringPayment(id: "insurance", label: "Insurance",
                                                amountCad: amountCad, cadence: cadence,
                                                category: "recurring", mcc: 6300,
                                                placement: .offWallet,
                                                nextChargeMonth: nextChargeMonth),
                      cardId: "scotia-momentum-vi-plus", assumeFlagged: true)
    }

    private func scotia4pct(_ outcomes: [CapProjectionOutcome]) throws -> CapProjection {
        let projected: [CapProjection] = outcomes.compactMap {
            if case .projected(let projection) = $0 { return projection }
            return nil
        }
        return try XCTUnwrap(projected.first { $0.capId == "momentum-4pct-accountYear" })
    }

    /// $200/month of flagged insurance against the seeded $12,500 of a $25,000 account-year cap.
    /// The window runs April 2026 → March 2027, and burn starts at the audit date, not at the
    /// window's start — the seeded figure already accounts for everything before today.
    ///   August through March is 8 charges → $1,600 → $14,100 of $25,000. No crossing.
    func testProjectionAccumulatesDeclaredBurnFromTheAuditDateToTheWindowEnd() throws {
        let outcomes = try projector().project([onScotia(200)], asOf: "2026-08-16")
        let projection = try scotia4pct(outcomes)

        XCTAssertEqual(projection.window, CapWindow.Window(startMonth: "2026-04", endMonth: "2027-03"))
        XCTAssertEqual(projection.startingUsageCad, 12_500, accuracy: 0.01)
        XCTAssertEqual(projection.cumulativeAtWindowEndCad, 14_100, accuracy: 0.01)
        XCTAssertNil(projection.crossingMonth)
    }

    /// $2,000/month crosses: $12,500 + seven charges = $26,500 by February 2027.
    func testProjectionNamesTheMonthTheCapIsCrossed() throws {
        let outcomes = try projector().project([onScotia(2_000)], asOf: "2026-08-16")

        XCTAssertEqual(try scotia4pct(outcomes).crossingMonth, "2027-02")
    }

    /// The starting figure is the seeded `capProgress`, which carries no as-of date and is
    /// flagged suspect in owner-state.json. A projection that quietly treats it as current is
    /// building a date on sand, so the projection says the start is unanchored.
    func testStartingUsageIsReportedAsUnanchoredWhenNoAsOfDateBacksIt() throws {
        let outcomes = try projector().project([onScotia(200)], asOf: "2026-08-16")

        XCTAssertFalse(try scotia4pct(outcomes).startingUsageIsAnchored)
    }

    /// Scotia's $25,000 cap is shared by grocery *and* recurring under one rule. Declared
    /// recurring spend therefore understates the burn, so the crossing month is the latest one
    /// possible rather than an estimate — and the projection names the categories that make it so.
    func testRecurringOnlyProjectionIsALatestPossibleBoundAndNamesWhy() throws {
        let outcomes = try projector().project([onScotia(200)], asOf: "2026-08-16")
        let projection = try scotia4pct(outcomes)

        XCTAssertEqual(projection.basis, .declaredRecurringOnly)
        XCTAssertEqual(projection.coverage, .categories(["grocery", "recurring"]))
        XCTAssertEqual(projection.undeclaredCategories, ["grocery"],
                       "grocery shares this cap and no declared bill touches it — which is "
                       + "exactly what makes the crossing month a bound, not an estimate")
    }

    /// An undated annual premium could land in any month of the window. Placing it in the last
    /// one is what keeps the crossing month a genuine "no later than": any real charge date
    /// moves the crossing earlier, never later.
    func testUndatedAnnualChargeIsPlacedAsLateAsTheWindowAllows() throws {
        let outcomes = try projector().project([onScotia(20_000, cadence: .annual)],
                                               asOf: "2026-08-16")

        XCTAssertEqual(try scotia4pct(outcomes).crossingMonth, "2027-03")
    }

    /// The same premium, dated. The owner's own answer beats the conservative placement.
    func testDatedAnnualChargeBurnsInTheMonthTheOwnerDeclared() throws {
        let outcomes = try projector().project([onScotia(20_000, cadence: .annual,
                                                         nextChargeMonth: "2026-10")],
                                               asOf: "2026-08-16")

        XCTAssertEqual(try scotia4pct(outcomes).crossingMonth, "2026-10")
    }

    /// The anchor is owner-declared and this one isn't answered. No window, no date — and the
    /// refusal names the field that would unblock it rather than defaulting to a calendar year.
    func testProjectionIsRefusedWhenTheAccountYearAnchorIsUnresolved() throws {
        var ownerState = try SeedLoader.loadPinnedOwnerState()
        ownerState.cardStates["scotia-momentum-vi-plus"]?.scotiaAccountYearAnchorMonth = nil
        let projector = CapProjector(catalogue: try SeedLoader.loadCatalogue(),
                                     ownerState: ownerState)

        let outcomes = projector.project([onScotia(200)], asOf: "2026-08-16")

        guard case .refused(let cardId, let capId, let reason) = try XCTUnwrap(outcomes.first) else {
            return XCTFail("expected a refusal, got \(outcomes)")
        }
        XCTAssertEqual(cardId, "scotia-momentum-vi-plus")
        XCTAssertEqual(capId, "momentum-4pct-accountYear")
        XCTAssertTrue(reason.contains("scotiaAccountYearAnchorMonth"), reason)
    }

    /// Detect, don't solve. When declared demand exceeds the room left in a shared cap, the
    /// owner is told which categories are competing for it — the engine does not silently
    /// reallocate the room on their behalf.
    func testContentionIsReportedWhenDeclaredDemandExceedsTheRoomLeft() throws {
        let outcomes = try projector().project([onScotia(2_000)], asOf: "2026-08-16")
        let contention = try XCTUnwrap(try scotia4pct(outcomes).contention)

        XCTAssertEqual(contention.roomCad, 12_500, accuracy: 0.01)
        XCTAssertEqual(contention.declaredDemandCad, 16_000, accuracy: 0.01)
        XCTAssertEqual(contention.competingCategories, ["grocery", "recurring"])
    }

    /// A bill whose card earns no capped rate on it burns no cap at all. An unflagged insurance
    /// charge falls to Scotia's uncapped 1% base rule, so it must not appear in the 4% bucket.
    func testUnflaggedBillDoesNotBurnTheFlaggedCategorysCap() throws {
        let unflagged = PlacedPayment(
            payment: RecurringPayment(id: "insurance", label: "Insurance", amountCad: 2_000,
                                      cadence: .monthly, category: "recurring", mcc: 6300,
                                      placement: .offWallet),
            cardId: "scotia-momentum-vi-plus", assumeFlagged: false)

        let outcomes = try projector().project([unflagged], asOf: "2026-08-16")

        XCTAssertTrue(outcomes.isEmpty, "expected no cap to be burned, got \(outcomes)")
    }

    /// A cap whose rule has no category clause is burned by *every* purchase on the card. An
    /// empty category list cannot say that, and rendering it as one printed "covers " with
    /// nothing after it.
    func testCapOnAnUncategorisedRuleReportsThatItCoversAllSpendOnTheCard() throws {
        let membership = PlacedPayment(
            payment: RecurringPayment(id: "costco", label: "Costco membership", amountCad: 65,
                                      cadence: .annual, category: "wholesaleClub",
                                      placement: .card("rogers-red-we"),
                                      declaredAcceptedNetworks: [.mastercard]),
            cardId: "rogers-red-we", assumeFlagged: true)

        let outcomes = try projector().project([membership], asOf: "2026-08-16")
        guard case .projected(let projection) = try XCTUnwrap(outcomes.first) else {
            return XCTFail("expected a projection, got \(outcomes)")
        }

        XCTAssertEqual(projection.coverage, .allSpendOnCard)
    }

    /// The flag is only load-bearing when losing it would change which cap the bill burns.
    /// MBNA's 5x utilities rule doesn't look at the flag, so a projection of that cap must not
    /// warn about unverified flags — a warning that always fires is one the owner learns to skip.
    func testCapUnaffectedByTheRecurringFlagDoesNotWarnAboutUnverifiedFlags() throws {
        let phone = PlacedPayment(
            payment: RecurringPayment(id: "phone", label: "Phone", amountCad: 85,
                                      cadence: .monthly, category: "householdUtilities",
                                      mcc: 4814, placement: .offWallet),
            cardId: "mbna-rewards-we", assumeFlagged: true)

        let outcomes = try projector().project([phone], asOf: "2026-08-16")
        guard case .projected(let projection) = try XCTUnwrap(outcomes.first) else {
            return XCTFail("expected a projection, got \(outcomes)")
        }

        XCTAssertEqual(projection.capId, "mbna-utilities-annual")
        XCTAssertFalse(projection.restsOnAssumedFlags,
                       "MBNA's utilities 5x does not depend on the network flag")
    }

    /// Scotia's 4% bucket is the opposite case: without the flag the charge falls to the
    /// uncapped 1% base rule and burns nothing at all, so the whole projection rests on it.
    func testCapThatOnlyExistsBecauseOfTheFlagSaysSo() throws {
        let outcomes = try projector().project([onScotia(200)], asOf: "2026-08-16")

        XCTAssertTrue(try scotia4pct(outcomes).restsOnAssumedFlags)
    }
}
