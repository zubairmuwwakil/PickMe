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
