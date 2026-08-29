import XCTest
@testable import CardCopilotEngine

final class BenefitsModelsTests: XCTestCase {
    private let sampleJSON = """
    {
      "benefitsCatalogueVersion": "0.1.0",
      "_provenance": "test fixture",
      "triggers": {
        "bigTicketThresholdCad": 150,
        "consumableCategories": ["dining", "grocery"]
      },
      "cards": [
        {
          "cardId": "amex-cobalt",
          "certificate": {
            "underwriter": "Royal & Sun Alliance",
            "sourceUrl": "https://example.com/cert.pdf",
            "certificateDate": null,
            "lastVerifiedAt": null,
            "verificationStatus": "stub"
          },
          "benefits": [
            {
              "benefitId": "cobalt-purchase-protection",
              "family": "shopping",
              "kind": "purchaseProtection",
              "coverage": { "windowDays": 90, "maxPerOccurrenceCad": 1000 },
              "conditions": ["Full purchase charged to the card"],
              "exclusions": ["Jewellery left unattended"],
              "certificateQuote": null,
              "notes": null
            },
            {
              "benefitId": "cobalt-future-benefit",
              "family": "someFutureFamily",
              "kind": "cellPlanInsurance",
              "coverage": {},
              "conditions": []
            }
          ]
        }
      ]
    }
    """

    private func decodeSample() throws -> BenefitsCatalogue {
        try JSONDecoder().decode(BenefitsCatalogue.self,
                                 from: Data(sampleJSON.utf8))
    }

    func testDecodesRootAndTriggers() throws {
        let catalogue = try decodeSample()
        XCTAssertEqual(catalogue.benefitsCatalogueVersion, "0.1.0")
        XCTAssertEqual(catalogue.triggers.bigTicketThresholdCad, 150, accuracy: 0.005)
        XCTAssertEqual(catalogue.triggers.consumableCategories, ["dining", "grocery"])
    }

    func testDecodesCardCertificateAndBenefit() throws {
        let catalogue = try decodeSample()
        let card = try XCTUnwrap(catalogue.card("amex-cobalt"))
        XCTAssertTrue(card.documents.isEmpty, "Legacy catalogue entries should decode without documents")
        XCTAssertEqual(card.certificate.verificationStatus, .stub)
        XCTAssertEqual(card.certificate.underwriter, "Royal & Sun Alliance")
        XCTAssertNil(card.certificate.certificateDate)

        let benefit = try XCTUnwrap(card.benefits.first)
        XCTAssertEqual(benefit.kind, "purchaseProtection")
        XCTAssertEqual(benefit.knownKind, .purchaseProtection)
        XCTAssertEqual(benefit.family, "shopping")
        XCTAssertEqual(benefit.coverage.windowDays, 90)
        XCTAssertEqual(benefit.coverage.maxPerOccurrenceCad ?? -1, 1000, accuracy: 0.005)
        XCTAssertNil(benefit.coverage.maxAnnualCad)
        XCTAssertEqual(benefit.conditions, ["Full purchase charged to the card"])
        XCTAssertEqual(benefit.exclusions, ["Jewellery left unattended"])
    }

    func testUnknownKindAndFamilySurviveDecoding() throws {
        // Forward compatibility (spec §4): future families must not break old builds.
        let catalogue = try decodeSample()
        let card = try XCTUnwrap(catalogue.card("amex-cobalt"))
        let future = try XCTUnwrap(card.benefits.last)
        XCTAssertEqual(future.kind, "cellPlanInsurance")
        XCTAssertNil(future.knownKind)
        XCTAssertEqual(future.family, "someFutureFamily")
    }

    func testRoundTripPreservesEverything() throws {
        let catalogue = try decodeSample()
        let data = try JSONEncoder().encode(catalogue)
        let again = try JSONDecoder().decode(BenefitsCatalogue.self, from: data)
        XCTAssertEqual(catalogue, again)
    }

    func testCardDocumentsRoundTripAndPreserveMetadata() throws {
        var catalogue = try decodeSample()
        let document = CardDocument(
            documentId: "cobalt-cardholder-agreement",
            kind: CardDocumentKind.cardholderAgreement.rawValue,
            title: "Cardholder agreement",
            url: "https://example.com/agreement.pdf",
            effectiveDate: "2026-01",
            jurisdiction: "Canada",
            verificationStatus: .issuerPage,
            lastVerifiedAt: "2026-08-29",
            notes: "Issuer-published source")
        catalogue.cards[0].documents = [document]

        let data = try JSONEncoder().encode(catalogue)
        let decoded = try JSONDecoder().decode(BenefitsCatalogue.self, from: data)
        XCTAssertEqual(decoded.cards[0].documents, [document])
    }

    func testUnknownCardLookupReturnsNil() throws {
        let catalogue = try decodeSample()
        XCTAssertNil(catalogue.card("no-such-card"))
    }

    /// Destination.protectionLens carries a BenefitContext through a SwiftUI NavigationPath,
    /// which requires Hashable. Pinned here so an Engine change cannot silently break App
    /// navigation — the App target is a consumer the Engine's own tests cannot see.
    func testBenefitContextIsHashable() {
        let flight = BenefitContext(kind: .flight)
        let flightAbroad = BenefitContext(kind: .flight, abroad: true)
        XCTAssertEqual(Set([flight, flight]).count, 1)
        XCTAssertEqual(Set([flight, flightAbroad]).count, 2)
    }
}
