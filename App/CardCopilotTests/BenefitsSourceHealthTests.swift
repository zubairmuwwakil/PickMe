import XCTest
import CardCopilotEngine
@testable import CardCopilot

final class BenefitsSourceHealthTests: XCTestCase {
    func testHealthCountsSourcesAndFlagsStaleRecords() {
        let catalogue = try! JSONDecoder().decode(BenefitsCatalogue.self, from: Data("""
        {
          "benefitsCatalogueVersion": "test",
          "triggers": { "bigTicketThresholdCad": 500, "consumableCategories": [] },
          "cards": [
            {
              "cardId": "fresh",
              "certificate": {
                "underwriter": null,
                "sourceUrl": "https://issuer.example/certificate.pdf",
                "certificateDate": null,
                "lastVerifiedAt": "2026-08-29",
                "verificationStatus": "issuerPage"
              },
              "benefits": [],
              "documents": [
                {
                  "documentId": "fresh-terms",
                  "kind": "cardholderAgreement",
                  "title": "Terms",
                  "url": "https://issuer.example/terms.pdf",
                  "verificationStatus": "issuerPage",
                  "lastVerifiedAt": "2026-08-29"
                }
              ]
            },
            {
              "cardId": "stale",
              "certificate": {
                "underwriter": null,
                "sourceUrl": null,
                "certificateDate": null,
                "lastVerifiedAt": "2024-01-01",
                "verificationStatus": "stub"
              },
              "benefits": []
            }
          ]
        }
        """.utf8))

        let health = BenefitsSourceHealth(
            catalogue: catalogue,
            now: Date(timeIntervalSince1970: 1_800_000_000))

        XCTAssertEqual(health.cardCount, 2)
        XCTAssertEqual(health.cardsWithSources, 1)
        XCTAssertEqual(health.documentCount, 1)
        XCTAssertEqual(health.staleCards, 1)
        XCTAssertEqual(health.staleDocuments, 0)
    }
}
