import XCTest
@testable import CardCopilotEngine

final class BenefitsComparisonTests: XCTestCase {

    private func benefit(_ id: String, family: String, kind: String,
                         configure: (inout BenefitCoverage) -> Void = { _ in }) -> Benefit {
        var coverage = BenefitCoverage()
        configure(&coverage)
        return Benefit(benefitId: id, family: family, kind: kind, coverage: coverage,
                       conditions: [], exclusions: nil, certificateQuote: nil, notes: nil)
    }

    private func card(_ cardId: String, status: BenefitVerification = .stub,
                      benefits: [Benefit]) -> CardBenefits {
        CardBenefits(cardId: cardId,
                     certificate: CertificateProvenance(underwriter: nil, sourceUrl: nil,
                                                        certificateDate: nil, lastVerifiedAt: nil,
                                                        verificationStatus: status),
                     benefits: benefits)
    }

    private func catalogue(_ cards: [CardBenefits]) -> BenefitsCatalogue {
        BenefitsCatalogue(benefitsCatalogueVersion: "test",
                          triggers: BenefitsTriggers(bigTicketThresholdCad: 150,
                                                     consumableCategories: []),
                          cards: cards)
    }

    // MARK: - Context → relevant kinds (spec §5 table)

    func testFlightContextPullsDisruptionKindsOnly() {
        let context = BenefitContext(kind: .flight)
        XCTAssertEqual(context.relevantKinds, [.flightDelay, .baggageDelay, .baggageLoss,
                                               .tripCancellation, .tripInterruption])
    }

    func testAbroadAddsTravelMedical() {
        XCTAssertTrue(BenefitContext(kind: .trip, abroad: true).relevantKinds.contains(.travelMedical))
        XCTAssertEqual(BenefitContext(kind: .carRental, abroad: true).relevantKinds,
                       [.rentalCdw, .travelMedical])
    }

    func testDeviceContextsPullShoppingKinds() {
        XCTAssertEqual(BenefitContext(kind: .electronics).relevantKinds,
                       [.purchaseProtection, .extendedWarranty])
        XCTAssertEqual(BenefitContext(kind: .mobileDevice).relevantKinds,
                       [.purchaseProtection, .extendedWarranty, .mobileDeviceInsurance])
    }

    // MARK: - Column assembly

    func testOnlyCardsWithRelevantCoverageBecomeColumns() {
        let flighty = card("flighty", benefits: [
            benefit("f-fd", family: "travelDisruption", kind: "flightDelay") { $0.delayHours = 4 }])
        let shopper = card("shopper", benefits: [
            benefit("s-pp", family: "shopping", kind: "purchaseProtection") { $0.windowDays = 90 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["flighty", "shopper"],
                                                    catalogue: catalogue([flighty, shopper]))
        XCTAssertEqual(comparison.columns.map(\.cardId), ["flighty"])
        XCTAssertEqual(comparison.absent.map(\.cardId), ["shopper"])
    }

    func testAbsentCardsCarryVerificationStatus() {
        // Spec B8: absence at stub = "unknown"; absence at certificateVerified = "no coverage".
        // The engine reports the status; the UI renders the difference.
        let covered = card("covered", benefits: [
            benefit("c-fd", family: "travelDisruption", kind: "flightDelay") { $0.delayHours = 4 }])
        let verified = card("verifiedEmpty", status: .certificateVerified, benefits: [])
        let stubby = card("stubEmpty", status: .stub, benefits: [])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["covered", "verifiedEmpty", "stubEmpty"],
                                                    catalogue: catalogue([covered, verified, stubby]))
        XCTAssertEqual(comparison.absent.map(\.cardId), ["verifiedEmpty", "stubEmpty"])
        XCTAssertEqual(comparison.absent.map(\.verification), [.certificateVerified, .stub])
    }

    // MARK: - Dominance (spec B7)

    func testUniqueDominantGetsBadge() {
        let strong = card("strong", benefits: [
            benefit("st-fd", family: "travelDisruption", kind: "flightDelay") {
                $0.delayHours = 4; $0.maxCad = 1000 }])
        let weak = card("weak", benefits: [
            benefit("w-fd", family: "travelDisruption", kind: "flightDelay") {
                $0.delayHours = 4; $0.maxCad = 500 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["strong", "weak"],
                                                    catalogue: catalogue([strong, weak]))
        XCTAssertEqual(comparison.dominantCardId, "strong")
    }

    func testIdenticalCoverageIsATieAndNoBadge() {
        let a = card("a", benefits: [
            benefit("a-fd", family: "travelDisruption", kind: "flightDelay") { $0.delayHours = 4 }])
        let b = card("b", benefits: [
            benefit("b-fd", family: "travelDisruption", kind: "flightDelay") { $0.delayHours = 4 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["a", "b"],
                                                    catalogue: catalogue([a, b]))
        XCTAssertNil(comparison.dominantCardId)
    }

    func testGenuineTradeoffIsNoBadge() {
        // a pays out sooner (3h); b pays out more ($1000). Neither dominates.
        let a = card("a", benefits: [
            benefit("a-fd", family: "travelDisruption", kind: "flightDelay") {
                $0.delayHours = 3; $0.maxCad = 500 }])
        let b = card("b", benefits: [
            benefit("b-fd", family: "travelDisruption", kind: "flightDelay") {
                $0.delayHours = 6; $0.maxCad = 1000 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["a", "b"],
                                                    catalogue: catalogue([a, b]))
        XCTAssertNil(comparison.dominantCardId)
    }

    func testLowerDelayHoursIsBetter() {
        let fast = card("fast", benefits: [
            benefit("f-fd", family: "travelDisruption", kind: "flightDelay") {
                $0.delayHours = 3; $0.maxCad = 500 }])
        let slow = card("slow", benefits: [
            benefit("s-fd", family: "travelDisruption", kind: "flightDelay") {
                $0.delayHours = 6; $0.maxCad = 500 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["fast", "slow"],
                                                    catalogue: catalogue([fast, slow]))
        XCTAssertEqual(comparison.dominantCardId, "fast")
    }

    func testLowerDeductibleIsBetter() {
        let cheap = card("cheap", benefits: [
            benefit("c-md", family: "shopping", kind: "mobileDeviceInsurance") {
                $0.maxCad = 1000; $0.deductibleCad = 50 }])
        let dear = card("dear", benefits: [
            benefit("d-md", family: "shopping", kind: "mobileDeviceInsurance") {
                $0.maxCad = 1000; $0.deductibleCad = 100 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .mobileDevice),
                                                    wallet: ["cheap", "dear"],
                                                    catalogue: catalogue([cheap, dear]))
        XCTAssertEqual(comparison.dominantCardId, "cheap")
    }

    // MARK: - Compared fields must be displayed fields (spec B7)

    func testOriginalWarrantyCeilingDoesNotDecideDominance() {
        // maxOriginalWarrantyYears is an ELIGIBILITY CEILING, not a coverage magnitude, so its
        // absence cannot be ranked: a certificate stating no ceiling plausibly means "no
        // restriction" (the best case), not "worst". Scoring nil as -infinity ranked the four
        // cards carrying 5 above the five carrying null — possibly backwards. It no longer votes.
        let capped = card("capped", benefits: [
            benefit("c-ew", family: "shopping", kind: "extendedWarranty") {
                $0.extraYears = 1; $0.maxOriginalWarrantyYears = 5 }])
        let uncapped = card("uncapped", benefits: [
            benefit("u-ew", family: "shopping", kind: "extendedWarranty") {
                $0.extraYears = 1 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .electronics),
                                                    wallet: ["capped", "uncapped"],
                                                    catalogue: catalogue([capped, uncapped]))
        XCTAssertNil(comparison.dominantCardId,
                     "cards differing only on the warranty ceiling must tie, not badge")
    }

    func testWarrantyExtensionRuleDoesNotDecideDominance() {
        // warrantyExtensionRule qualifies how extraYears should be READ; it is a string, not a
        // magnitude, so it cannot be ranked and must never vote. Two cards with the same cap and
        // different verification states describe the same coverage ceiling and must tie.
        let verified = card("verified", benefits: [
            benefit("v-ew", family: "shopping", kind: "extendedWarranty") {
                $0.extraYears = 1; $0.warrantyExtensionRule = "matchesOriginalCapped" }])
        let unverified = card("unverified", benefits: [
            benefit("u2-ew", family: "shopping", kind: "extendedWarranty") {
                $0.extraYears = 1 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .electronics),
                                                    wallet: ["verified", "unverified"],
                                                    catalogue: catalogue([verified, unverified]))
        XCTAssertNil(comparison.dominantCardId,
                     "the extension rule describes how to read the cap, so it must not badge")
    }

    func testShippedCatalogueMarksVerifiedExtendedWarrantiesAsCapped() throws {
        // The nine cards re-read against their own certificates in the 2026-09-05 extraction all
        // grant the LESSER of the original manufacturer warranty and the cap. Publishing
        // extraYears alone claimed a flat extra year, which overstated every warranty shorter
        // than the cap. Pins the corrected records so a future edit cannot silently drop them.
        let verifiedIds: Set<String> = [
            "platinum-extended-warranty", "cobalt-extended-warranty", "bonvoy-extended-warranty",
            "mbna-extended-warranty", "scotia-extended-warranty", "tangerine-extended-warranty",
            "rogers-extended-warranty", "td-aeroplan-extended-warranty",
            "bmo-cashback-we-extended-warranty",
        ]
        let shipped = try SeedLoader.loadBenefitsCatalogue()
        var seen: Set<String> = []
        for card in shipped.cards {
            for benefit in card.benefits where verifiedIds.contains(benefit.benefitId) {
                seen.insert(benefit.benefitId)
                XCTAssertEqual(benefit.coverage.warrantyExtensionRule, "matchesOriginalCapped",
                               "\(benefit.benefitId) was verified against its certificate")
            }
        }
        XCTAssertEqual(seen, verifiedIds, "a verified extended-warranty record went missing")
    }

    func testAnnualMaximumStillDecidesDominance() {
        // The mirror of the test above: maxAnnualCad IS a magnitude (higher is plainly better)
        // and is now rendered by factsLine, so it keeps its vote. Pins that the B7 fix removed
        // the eligibility ceiling and nothing else.
        let generous = card("generous", benefits: [
            benefit("g-pp", family: "shopping", kind: "purchaseProtection") {
                $0.windowDays = 90; $0.maxAnnualCad = 10_000 }])
        let plain = card("plain", benefits: [
            benefit("p-pp", family: "shopping", kind: "purchaseProtection") {
                $0.windowDays = 90 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .electronics),
                                                    wallet: ["generous", "plain"],
                                                    catalogue: catalogue([generous, plain]))
        XCTAssertEqual(comparison.dominantCardId, "generous")
    }

    func testMissingKindIsWorstSoFullerCardDominates() {
        let full = card("full", benefits: [
            benefit("f-fd", family: "travelDisruption", kind: "flightDelay") { $0.delayHours = 4 },
            benefit("f-bl", family: "travelDisruption", kind: "baggageLoss") { $0.maxCad = 500 }])
        let partial = card("partial", benefits: [
            benefit("p-fd", family: "travelDisruption", kind: "flightDelay") { $0.delayHours = 4 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["full", "partial"],
                                                    catalogue: catalogue([full, partial]))
        XCTAssertEqual(comparison.dominantCardId, "full")
    }

    func testOnlyCoveredCardGetsBadge() {
        let only = card("only", benefits: [
            benefit("o-cdw", family: "rentalCdw", kind: "rentalCdw") { $0.maxRentalDays = 48 }])
        let none = card("none", benefits: [])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .carRental),
                                                    wallet: ["only", "none"],
                                                    catalogue: catalogue([only, none]))
        XCTAssertEqual(comparison.dominantCardId, "only")
    }

    func testNoCoverageAnywhereMeansNoColumnsNoBadge() {
        let a = card("a", benefits: [])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["a"], catalogue: catalogue([a]))
        XCTAssertTrue(comparison.columns.isEmpty)
        XCTAssertNil(comparison.dominantCardId)
    }

    func testUnknownKindEntriesNeverEnterComparison() {
        let a = card("a", benefits: [
            benefit("a-x", family: "travelDisruption", kind: "teleportationDelay") { $0.maxCad = 9999 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["a"], catalogue: catalogue([a]))
        XCTAssertTrue(comparison.columns.isEmpty)
    }
}
