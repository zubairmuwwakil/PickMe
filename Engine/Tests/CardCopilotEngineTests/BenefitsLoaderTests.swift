import XCTest
@testable import CardCopilotEngine

final class BenefitsLoaderTests: XCTestCase {
    func testLoadsBenefitsCatalogue() throws {
        let benefits = try SeedLoader.loadBenefitsCatalogue()
        XCTAssertEqual(benefits.cards.count, 46)
        XCTAssertGreaterThan(benefits.triggers.bigTicketThresholdCad, 0)
        XCTAssertFalse(benefits.triggers.consumableCategories.isEmpty)
    }

    /// Once the catalogue became every supported product (2026-08-24) this could no longer be an
    /// equality: 14 researched products have no insurance certificate read yet. The promise that
    /// still has to hold is the one a user can actually notice — a card they HOLD always has
    /// benefits — plus a ratchet so a new product cannot quietly widen the uncovered set.
    func testEveryOwnedCardHasABenefitsEntry() throws {
        let benefits = Set(try SeedLoader.loadBenefitsCatalogue().cards.map(\.cardId))
        let owned = Set(try SeedLoader.loadOwnerState().ownedCardIds)
        XCTAssertTrue(owned.isSubset(of: benefits),
                      "owned cards with no benefits entry: \(owned.subtracting(benefits).sorted())")
    }

    /// The ratchet. Products without a benefits entry are listed by name, so adding one is a
    /// deliberate act with a reviewer, not a silent gap.
    func testProductsWithoutBenefitsAreExactlyTheKnownGap() throws {
        let knownGap: Set<String> = [
            "american-express-blue-business-plus", "american-express-gold-card",
            "american-express-the-platinum-card", "chase-freedom-flex",
            "chase-freedom-unlimited", "chase-sapphire-preferred-card",
            "chase-sapphire-reserve", "citi-double-cash-card",
            "walmart-rewards-mastercard",
            "neo-financial-neo-world-mastercard", "mbna-true-line-mastercard",
            "capital-one-canada-capital-one-guaranteed",
        ]
        // Published only: a draft has no benefits entry because nobody has read its issuer's
        // terms yet, which is the definition of a draft rather than a gap to track.
        let catalogue = Set(try SeedLoader.loadCatalogue().cards.filter(\.isPublished).map(\.cardId))
        let benefits = Set(try SeedLoader.loadBenefitsCatalogue().cards.map(\.cardId))
        XCTAssertEqual(catalogue.subtracting(benefits), knownGap)
    }

    func testBenefitsProvenanceIsHonest() throws {
        // Replaces testEveryShippedEntryIsStub, deleted per its own instruction: commit 8e75635
        // re-derived 9/10 cards from real issuer Certificates of Insurance (.issuerPage).
        // .issuerPage is an agent sourcing pass, not Zubair's own cardholder-document check —
        // see docs/research/2026-08-16-benefits-sourcing-agent-prompt.md — so certificateVerified
        // should still be empty, and every non-stub card must show its work.
        let benefits = try SeedLoader.loadBenefitsCatalogue()

        var statusCounts: [String: Int] = [:]
        for card in benefits.cards {
            let certificate = card.certificate
            statusCounts[certificate.verificationStatus.rawValue, default: 0] += 1

            guard certificate.verificationStatus != .stub else { continue }
            XCTAssertFalse((certificate.sourceUrl ?? "").isEmpty,
                           "\(card.cardId) is \(certificate.verificationStatus) but has no sourceUrl")
            XCTAssertFalse((certificate.lastVerifiedAt ?? "").isEmpty,
                           "\(card.cardId) is \(certificate.verificationStatus) but has no lastVerifiedAt")
        }

        XCTAssertEqual(statusCounts["stub", default: 0], 1,
                       "expected only cryptocom-royal-indigo to remain stub")
        XCTAssertEqual(statusCounts["issuerPage", default: 0], 45,
                       "expected the forty-five issuer-sourced cards to be issuerPage")
        XCTAssertEqual(statusCounts["certificateVerified", default: 0], 0,
                       "a card claims certificateVerified, but no card has had Zubair's own " +
                       "cardholder-document check yet — update this test's counts once one does")
    }

    func testEveryBenefitKindAndFamilyIsKnown() throws {
        // The shipped file uses only the ten known kinds; the OPEN vocabulary is for
        // future data, not for typos in our own stub.
        let benefits = try SeedLoader.loadBenefitsCatalogue()
        for card in benefits.cards {
            for benefit in card.benefits {
                XCTAssertNotNil(benefit.knownKind,
                                "\(card.cardId)/\(benefit.benefitId): unknown kind \(benefit.kind)")
                XCTAssertNotNil(benefit.knownFamily,
                                "\(card.cardId)/\(benefit.benefitId): unknown family \(benefit.family)")
            }
        }
    }

    func testConsumableCategoriesUseTheFrozenVocabulary() throws {
        // Spec B6: triggers reference existing earn categories only.
        let allowed: Set<String> = ["dining", "grocery", "foodDelivery", "gasStation",
                                    "transit", "drugStore", "entertainment", "fitness"]
        let benefits = try SeedLoader.loadBenefitsCatalogue()
        for category in benefits.triggers.consumableCategories {
            XCTAssertTrue(allowed.contains(category), "unexpected category \(category)")
        }
    }
}
