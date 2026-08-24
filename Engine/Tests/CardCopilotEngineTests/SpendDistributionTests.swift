import XCTest
@testable import CardCopilotEngine

/// The placeholder profile is the weakest link in the whole keep/cancel layer: no real spend data
/// exists yet. These tests keep it honest — labelled as an assumption, and complete enough that no
/// card is starved by an accidental omission.
final class SpendDistributionTests: XCTestCase {

    func testPlaceholderProfileSaysOutLoudThatItIsAnAssumption() {
        let profile = SpendDistribution.placeholderCanadianHousehold
        XCTAssertTrue(profile.basis.lowercased().contains("assumption"),
                      "a guessed distribution that doesn't say so will be read as data: \(profile.basis)")
        XCTAssertEqual(profile.totalAnnualCad, 40_200, accuracy: 0.01)
    }

    /// Leaving a category out of the profile is indistinguishable from the owner spending nothing
    /// on it — and it silently zeroes whichever card accelerates it. So every category the wallet
    /// can accelerate must appear, and anything left out must be left out on purpose.
    func testPlaceholderProfileCoversEveryCategoryTheWalletAccelerates() throws {
        let deliberatelyOmitted = [
            "evCharging": "no EV assumed in this household",
            "carRental": "Cobalt's only carRental rule is the amexTravel channel bonus, outOfScope",
            "ownerSelectedTangerineCategory": "synthetic marker, resolved against the real categories",
        ]

        // The catalogue is every supported product since 2026-08-24, so scanning all of it would
        // demand the placeholder profile cover categories no card the owner HOLDS accelerates.
        // The claim this test makes is about the owner's wallet, so it reads the owner's wallet.
        let catalogue = try SeedLoader.loadCatalogue()
        let owned = Set(try SeedLoader.loadOwnerState().ownedCardIds)
        let accelerated = Set(catalogue.cards.filter { owned.contains($0.cardId) }.flatMap { card in
            card.earnRules
                .filter { RuleMatcher.isLive($0, asOf: "2026-08-20") }
                .flatMap { $0.predicate.categories ?? [] }
        })
        let profile = SpendDistribution.placeholderCanadianHousehold
        let covered = Set(profile.buckets.map { $0.context.category })
            .union(profile.buckets.contains { $0.context.recurringIndicator } ? ["recurring"] : [])

        for category in accelerated.sorted() where deliberatelyOmitted[category] == nil {
            XCTAssertTrue(covered.contains(category),
                          "\(category) is accelerated by a card in this wallet but absent from the "
                          + "profile — that card's marginal value is understated by construction")
        }
    }

    func testFrugalStudentAndFrequentTravelerProfiles() {
        let student = SpendDistribution.frugalStudent
        XCTAssertEqual(student.profileId, "frugal-student-2026")
        XCTAssertEqual(student.totalAnnualCad, 18_500, accuracy: 0.01)

        let traveler = SpendDistribution.frequentTraveler
        XCTAssertEqual(traveler.profileId, "frequent-traveler-2026")
        XCTAssertEqual(traveler.totalAnnualCad, 84_000, accuracy: 0.01)
    }

    func testApplyingOverridesModifiesTargetBuckets() {
        let base = SpendDistribution.placeholderCanadianHousehold
        let modified = base.applyingOverrides(["dining": 20_000, "grocery": 15_000], profileId: "custom-test")
        XCTAssertEqual(modified.profileId, "custom-test")

        let diningBucket = modified.buckets.first { $0.context.category == "dining" }
        XCTAssertNotNil(diningBucket)
        XCTAssertEqual(diningBucket!.annualCad, 20_000)

        let groceryBucket = modified.buckets.first { $0.context.category == "grocery" }
        XCTAssertNotNil(groceryBucket)
        XCTAssertEqual(groceryBucket!.annualCad, 15_000)
    }
}
