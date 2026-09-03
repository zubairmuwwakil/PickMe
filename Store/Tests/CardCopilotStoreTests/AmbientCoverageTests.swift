import XCTest
@testable import CardCopilotStore

/// The third of the three Phase-3 gate criteria — `fired`/`suppressed`/**`coverage`**.
///
/// `SuppressionLog` counts what happened once a geofence fired. It is structurally blind to a
/// merchant that never got a region in the first place: no entry event, no resolution, no gate
/// decision, no counter. Slot pressure is a *silence*, and until this file existed nothing in the
/// app counted silences. Every rule here is pure so the CoreLocation adapter keeps deciding
/// nothing.
final class RegionBudgetTests: XCTestCase {
    private func candidate(_ id: String, _ tier: AmbientRegionTier,
                           _ distance: Double) -> RegionCandidate {
        RegionCandidate(id: id, tier: tier, distanceMeters: distance)
    }

    // MARK: - The budget itself

    func testEverythingFitsWhenUnderTheLimit() {
        let allocation = allocateRegionBudget([
            candidate("a", .discoveredArea, 300),
            candidate("b", .confirmedMerchant, 100),
        ], limit: 20)

        XCTAssertEqual(allocation.granted.map(\.id), ["b", "a"])
        XCTAssertTrue(allocation.evicted.isEmpty)
        XCTAssertFalse(allocation.isAtCapacity)
    }

    func testTheLimitIsHardAndTheRemainderIsReportedAsEvicted() {
        let candidates = (0..<25).map { candidate("area\($0)", .discoveredArea, Double($0) * 10) }

        let allocation = allocateRegionBudget(candidates, limit: 20)

        XCTAssertEqual(allocation.granted.count, 20)
        XCTAssertEqual(allocation.evicted.count, 5)
        XCTAssertTrue(allocation.isAtCapacity)
        // The five furthest are the ones dropped.
        XCTAssertEqual(allocation.evicted.map(\.id),
                       ["area20", "area21", "area22", "area23", "area24"])
    }

    /// This test exists to pin the CURRENT shipping policy, not a better one. `rotateRegions`
    /// sorts purely by distance, so a plaza the owner has never entered outranks a weekly grocery
    /// run that is further away. Measuring a policy the app does not run would produce a week of
    /// data describing nothing, so the instrument has to reproduce this exactly.
    func testDistanceOutranksTierToday() {
        let allocation = allocateRegionBudget([
            candidate("weekly-grocery", .frequentedMerchant, 400),
            candidate("never-entered-plaza", .discoveredArea, 200),
        ], limit: 1)

        XCTAssertEqual(allocation.granted.map(\.id), ["never-entered-plaza"])
        XCTAssertEqual(allocation.evicted.map(\.id), ["weekly-grocery"])
        XCTAssertEqual(allocation.evicted.map(\.tier), [.frequentedMerchant])
    }

    /// Tier breaks exact ties, which is what the adapter's "confirmed merchants were appended
    /// first" comment was reaching for.
    func testTierBreaksAnExactDistanceTie() {
        let allocation = allocateRegionBudget([
            candidate("area", .discoveredArea, 250),
            candidate("saved", .savedMerchant, 250),
            candidate("confirmed", .confirmedMerchant, 250),
            candidate("frequented", .frequentedMerchant, 250),
        ], limit: 4)

        XCTAssertEqual(allocation.granted.map(\.id),
                       ["frequented", "confirmed", "saved", "area"])
    }

    /// `rotateRegions` builds its candidate array from two SwiftData fetches whose order is not
    /// guaranteed, and `Array.sorted` in Swift is introsort — not stable. So today two rotations
    /// over an unchanged world can disagree about which of two equidistant candidates keeps the
    /// last slot, tearing down and re-registering a region that did not change. A total order
    /// makes the allocation a pure function of the candidate SET.
    func testAllocationIsIndependentOfInputOrder() {
        let candidates = [
            candidate("a", .discoveredArea, 100),
            candidate("b", .savedMerchant, 100),
            candidate("c", .confirmedMerchant, 100),
        ]

        let forward = allocateRegionBudget(candidates, limit: 2)
        let reversed = allocateRegionBudget(candidates.reversed(), limit: 2)
        let shuffled = allocateRegionBudget([candidates[1], candidates[2], candidates[0]], limit: 2)

        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward, shuffled)
    }

    func testAnEmptyWorldAllocatesNothingAndIsNotAtCapacity() {
        let allocation = allocateRegionBudget([], limit: 20)

        XCTAssertTrue(allocation.granted.isEmpty)
        XCTAssertTrue(allocation.evicted.isEmpty)
        XCTAssertFalse(allocation.isAtCapacity)
    }

    /// Exactly filling the budget is at capacity with nothing evicted. The distinction matters to
    /// the read-out: "we used all 20 and wanted no more" is a healthy steady state, while "we
    /// used all 20 and dropped 9" is the finding that would justify frequency-aware ranking.
    func testExactlyFillingTheBudgetIsAtCapacityWithNoEvictions() {
        let allocation = allocateRegionBudget(
            (0..<20).map { candidate("area\($0)", .discoveredArea, Double($0)) }, limit: 20)

        XCTAssertTrue(allocation.isAtCapacity)
        XCTAssertTrue(allocation.evicted.isEmpty)
    }

    // MARK: - Labelling a stored merchant

    /// Presence, not coding. A confirmed terminal proves how a charge *codes*; repeated payment
    /// proves the owner is actually there, which is the only thing a geofence slot buys.
    func testFrequentedOutranksConfirmedForTheSameMerchant() {
        XCTAssertEqual(storedMerchantRegionTier(confirmedCategory: "grocery", isFrequented: true),
                       .frequentedMerchant)
    }

    func testAConfirmedMerchantOutranksAMerelySavedOne() {
        XCTAssertEqual(storedMerchantRegionTier(confirmedCategory: "grocery", isFrequented: false),
                       .confirmedMerchant)
        XCTAssertEqual(storedMerchantRegionTier(confirmedCategory: nil, isFrequented: false),
                       .savedMerchant)
    }

    /// A saved merchant the owner keeps paying at, but has never reconciled, still earns the top
    /// tier — the patronage evidence stands on its own.
    func testFrequencyAloneReachesTheTopTier() {
        XCTAssertEqual(storedMerchantRegionTier(confirmedCategory: nil, isFrequented: true),
                       .frequentedMerchant)
    }
}

/// The counters themselves. Persisted, so the Codable round trip is part of the contract.
final class AmbientCoverageLogTests: XCTestCase {
    private func candidate(_ id: String, _ tier: AmbientRegionTier,
                           _ distance: Double) -> RegionCandidate {
        RegionCandidate(id: id, tier: tier, distanceMeters: distance)
    }

    func testARotationUnderTheCapCountsAsARotationAndNothingElse() {
        var log = AmbientCoverageLog()
        log.record(allocateRegionBudget([candidate("a", .discoveredArea, 10)], limit: 20))

        XCTAssertEqual(log.rotations, 1)
        XCTAssertEqual(log.rotationsAtCapacity, 0)
        XCTAssertTrue(log.evictedByTier.isEmpty)
    }

    func testEvictionsAreCountedByTheTierThatLostTheSlot() {
        var log = AmbientCoverageLog()
        log.record(allocateRegionBudget([
            candidate("near-plaza", .discoveredArea, 10),
            candidate("grocery", .frequentedMerchant, 900),
            candidate("pharmacy", .confirmedMerchant, 800),
            candidate("other-grocery", .frequentedMerchant, 950),
        ], limit: 1))

        XCTAssertEqual(log.rotations, 1)
        XCTAssertEqual(log.rotationsAtCapacity, 1)
        XCTAssertEqual(log.evictedByTier[.frequentedMerchant], 2)
        XCTAssertEqual(log.evictedByTier[.confirmedMerchant], 1)
        XCTAssertNil(log.evictedByTier[.discoveredArea])
    }

    /// The arrival funnel. Both of these are `return`s that record nothing today, so the
    /// explainer currently reports a background wake that produced no advice as though it never
    /// happened at all.
    func testTheArrivalFunnelSeparatesItsTwoSilentDropouts() {
        var log = AmbientCoverageLog()
        log.recordArrival(.resolved)
        log.recordArrival(.resolved)
        log.recordArrival(.unresolved)
        log.recordArrival(.notAdvised)

        XCTAssertEqual(log.arrivals, 4)
        XCTAssertEqual(log.arrivalsUnresolved, 1)
        XCTAssertEqual(log.arrivalsNotAdvised, 1)
        XCTAssertEqual(log.arrivalsReachingTheGate, 2)
    }

    func testMergeIsAdditiveAcrossEveryCounter() {
        var first = AmbientCoverageLog()
        first.record(allocateRegionBudget([
            candidate("a", .discoveredArea, 10), candidate("b", .frequentedMerchant, 20),
        ], limit: 1))
        first.recordArrival(.resolved)

        var second = AmbientCoverageLog()
        second.record(allocateRegionBudget([
            candidate("c", .discoveredArea, 10), candidate("d", .frequentedMerchant, 20),
        ], limit: 1))
        second.recordArrival(.unresolved)

        first.merge(second)

        XCTAssertEqual(first.rotations, 2)
        XCTAssertEqual(first.rotationsAtCapacity, 2)
        XCTAssertEqual(first.evictedByTier[.frequentedMerchant], 2)
        XCTAssertEqual(first.arrivals, 2)
        XCTAssertEqual(first.arrivalsUnresolved, 1)
    }

    func testItSurvivesACodableRoundTrip() throws {
        var log = AmbientCoverageLog()
        log.record(allocateRegionBudget([
            candidate("a", .discoveredArea, 10), candidate("b", .confirmedMerchant, 20),
        ], limit: 1))
        log.recordArrival(.notAdvised)

        let decoded = try JSONDecoder().decode(
            AmbientCoverageLog.self, from: JSONEncoder().encode(log))

        XCTAssertEqual(decoded, log)
    }

    /// The one number the T6 decision turns on: of the rotations that hit the cap, how much of
    /// what was dropped was evidence the owner actually shops there. Zero here means the cap
    /// costs nothing and frequency-aware ranking is solving a problem the app does not have.
    func testEvictedPatronageIsReadableWithoutSummingTiersAtTheCallSite() {
        var log = AmbientCoverageLog()
        log.record(allocateRegionBudget([
            candidate("plaza", .discoveredArea, 10),
            candidate("grocery", .frequentedMerchant, 900),
            candidate("pharmacy", .confirmedMerchant, 800),
            candidate("saved", .savedMerchant, 700),
        ], limit: 1))

        XCTAssertEqual(log.evictedWithStanding, 2)
        XCTAssertEqual(log.evicted, 3)
    }
}

/// An area inherits the standing of what it covers. Without this the instrument reports "dropped
/// a nearby shopping area" about the plaza holding the owner's weekly grocery run, and
/// `evictedWithStanding` reads zero while the cap is doing real damage.
final class AreaStandingTests: XCTestCase {
    func testAnEmptyPlazaIsJustADiscoveredArea() {
        XCTAssertEqual(areaRegionTier(coveringStandings: []), .discoveredArea)
    }

    func testAPlazaInheritsTheHighestStandingItCovers() {
        XCTAssertEqual(
            areaRegionTier(coveringStandings: [.savedMerchant, .frequentedMerchant, .confirmedMerchant]),
            .frequentedMerchant)
    }

    /// One frequented shop among many unremarkable units is still worth the slot — a count or an
    /// average would let the empty units dilute it away.
    func testOneFrequentedShopCarriesThePlaza() {
        XCTAssertEqual(
            areaRegionTier(coveringStandings: [.savedMerchant, .savedMerchant, .frequentedMerchant]),
            .frequentedMerchant)
    }

    func testAPlazaOfMerelySavedShopsDoesNotClaimStanding() {
        let tier = areaRegionTier(coveringStandings: [.savedMerchant, .savedMerchant])
        XCTAssertEqual(tier, .savedMerchant)
        XCTAssertFalse(tier.carriesStanding)
    }
}

/// Arrivals iOS never delivered, and the counter that measures whether asking for them helped.
///
/// `didEnterRegion` fires only on a boundary crossing, so a region registered while the owner is
/// already standing inside it cannot fire for the visit that created it — and `rotateRegions`
/// runs off a significant location change, which is roughly the event that happens when someone
/// arrives somewhere new. The first visit to any newly discovered place was silent by
/// construction, and invisible to `arrivals`, which counts wakes that happened.
final class SynthesisedArrivalCountingTests: XCTestCase {
    func testADeliveredWakeIsNotCountedAsSynthesised() {
        var log = AmbientCoverageLog()
        log.recordArrival(.resolved)
        XCTAssertEqual(log.arrivals, 1)
        XCTAssertEqual(log.arrivalsSynthesised, 0)
    }

    /// Counted in both totals: it is an arrival, and it is one that only exists because the app
    /// asked. Leaving it out of `arrivals` would break `arrivalsReachingTheGate` against
    /// `SuppressionLog`.
    func testASynthesisedArrivalIsCountedInBothTotals() {
        var log = AmbientCoverageLog()
        log.recordArrival(.resolved, source: .alreadyInside)
        XCTAssertEqual(log.arrivals, 1)
        XCTAssertEqual(log.arrivalsSynthesised, 1)
    }

    /// The difference between the two totals is the size of the problem this fixes. Pooling them
    /// would erase the only evidence that asking changed anything.
    func testTheTwoTotalsStaySeparableAcrossADay() {
        var log = AmbientCoverageLog()
        log.recordArrival(.resolved)
        log.recordArrival(.unresolved, source: .alreadyInside)
        log.recordArrival(.notAdvised, source: .alreadyInside)
        XCTAssertEqual(log.arrivals, 3)
        XCTAssertEqual(log.arrivalsSynthesised, 2)
        XCTAssertEqual(log.arrivalsUnresolved, 1)
        XCTAssertEqual(log.arrivalsNotAdvised, 1)
    }

    func testTheSevenDaySumCarriesTheSynthesisedTotal() {
        var week = AmbientCoverageLog()
        var today = AmbientCoverageLog()
        today.recordArrival(.resolved, source: .alreadyInside)
        week.merge(today)
        week.merge(today)
        XCTAssertEqual(week.arrivalsSynthesised, 2)
    }

    /// Persisted per day in `UserDefaults`, so a counter added by an update must not make the
    /// days already recorded undecodable. Losing them would delete the baseline this counter
    /// exists to be compared against.
    func testADayRecordedBeforeThisCounterExistedStillDecodes() throws {
        let legacy = """
        {"rotations":4,"rotationsAtCapacity":1,"evictedByTier":[],
         "arrivals":6,"arrivalsUnresolved":0,"arrivalsNotAdvised":0}
        """
        let decoded = try JSONDecoder().decode(AmbientCoverageLog.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.arrivals, 6)
        XCTAssertEqual(decoded.arrivalsSynthesised, 0)
        XCTAssertTrue(decoded.notificationDeliveryByOutcome.isEmpty)
    }

}

/// Delivery truth, counted.
///
/// "Fired" only ever counted that iOS accepted a request, which is why an owner who saw nothing
/// and a policy that never spoke looked identical in the weekly read-out.
final class NotificationDeliveryCountingTests: XCTestCase {

    /// "Fired" counted only that iOS accepted a request. These four say what became of it, which
    /// is the difference between a delivery bug, a policy that never speaks, and an alert the
    /// owner simply missed.
    func testEachDeliveryOutcomeIsCountedSeparately() {
        var log = AmbientCoverageLog()
        log.recordNotificationDelivery(.neverRequested)
        log.recordNotificationDelivery(.neverRequested)
        log.recordNotificationDelivery(.requestFailed)
        log.recordNotificationDelivery(.acceptedThenAbsent)
        log.recordNotificationDelivery(.acceptedAndPresent)

        XCTAssertEqual(log.notificationDeliveryByOutcome[.neverRequested], 2)
        XCTAssertEqual(log.notificationDeliveryByOutcome[.requestFailed], 1)
        XCTAssertEqual(log.notificationDeliveryByOutcome[.acceptedThenAbsent], 1)
        XCTAssertEqual(log.notificationDeliveryByOutcome[.acceptedAndPresent], 1)
    }

    /// **The number the investigation turns on.** Of the alerts iOS accepted, how many were
    /// actually in Notification Center.
    func testAlertsAskedForAndAlertsThatLandedAreBothDerived() {
        var log = AmbientCoverageLog()
        log.recordNotificationDelivery(.neverRequested)
        log.recordNotificationDelivery(.acceptedThenAbsent)
        log.recordNotificationDelivery(.acceptedAndPresent)
        log.recordNotificationDelivery(.acceptedAndPresent)

        XCTAssertEqual(log.notificationsRequested, 3)
        XCTAssertEqual(log.notificationsThatLanded, 2)
    }

    func testDeliveryCountsSumOverTheWeek() {
        var week = AmbientCoverageLog()
        var today = AmbientCoverageLog()
        today.recordNotificationDelivery(.acceptedAndPresent)
        week.merge(today)
        week.merge(today)

        XCTAssertEqual(week.notificationDeliveryByOutcome[.acceptedAndPresent], 2)
    }
}
