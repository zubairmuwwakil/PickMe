import XCTest
@testable import CardCopilotEngine

final class BenefitsLoaderTests: XCTestCase {
    func testLoadsBenefitsCatalogue() throws {
        let benefits = try SeedLoader.loadBenefitsCatalogue()
        XCTAssertEqual(benefits.cards.count, 27)
        XCTAssertGreaterThan(benefits.triggers.bigTicketThresholdCad, 0)
        XCTAssertFalse(benefits.triggers.consumableCategories.isEmpty)
    }

    func testEveryWalletCardHasABenefitsEntry() throws {
        // Cross-file consistency: the benefits catalogue mirrors the earn catalogue's wallet.
        let wallet = try SeedLoader.loadCatalogue().cards.map(\.cardId)
        let benefits = try SeedLoader.loadBenefitsCatalogue()
        XCTAssertEqual(Set(benefits.cards.map(\.cardId)), Set(wallet))
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
        XCTAssertEqual(statusCounts["issuerPage", default: 0], 26,
                       "expected the twenty-six issuer-sourced cards to be issuerPage")
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
