import XCTest
@testable import CardCopilotEngine

final class BenefitsLoaderTests: XCTestCase {
    func testLoadsBenefitsCatalogue() throws {
        let benefits = try SeedLoader.loadBenefitsCatalogue()
        XCTAssertEqual(benefits.cards.count, 10)
        XCTAssertGreaterThan(benefits.triggers.bigTicketThresholdCad, 0)
        XCTAssertFalse(benefits.triggers.consumableCategories.isEmpty)
    }

    func testEveryWalletCardHasABenefitsEntry() throws {
        // Cross-file consistency: the benefits catalogue mirrors the earn catalogue's wallet.
        let wallet = try SeedLoader.loadCatalogue().cards.map(\.cardId)
        let benefits = try SeedLoader.loadBenefitsCatalogue()
        XCTAssertEqual(Set(benefits.cards.map(\.cardId)), Set(wallet))
    }

    func testEveryShippedEntryIsStub() throws {
        // Spec B4: the shipped file is scaffolding. The day this test fails is the day
        // Zubair's verified dossier landed — then DELETE this test, don't weaken it.
        let benefits = try SeedLoader.loadBenefitsCatalogue()
        for card in benefits.cards {
            XCTAssertEqual(card.certificate.verificationStatus, .stub,
                           "\(card.cardId) must remain stub until the certificate dossier lands")
        }
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
