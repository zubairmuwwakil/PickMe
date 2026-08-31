import XCTest
@testable import CardCopilotEngine

private struct ApplicationRequirementFixtureFile: Decodable {
    let cases: [ApplicationRequirementFixtureCase]
}

private struct ApplicationRequirementFixtureCase: Decodable {
    let caseId: String
    let cardId: String
    let profile: ApplicantIncomeProfile
    let expectedStatus: IncomeRequirementAssessmentStatus
    let expectedMatchedType: IncomeRequirementType?
    let expectedClosestType: IncomeRequirementType?
    let expectedShortfall: Double?
    let expectedMissingTypes: [IncomeRequirementType]?
}

final class ApplicationRequirementTests: XCTestCase {
    func testSharedIncomeRequirementFixtures() throws {
        let catalogue = try SeedLoader.loadApplicationRequirements()
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "application-requirements-fixtures", withExtension: "json",
            subdirectory: "Fixtures"))
        let fixtures = try JSONDecoder().decode(
            ApplicationRequirementFixtureFile.self, from: Data(contentsOf: url))

        for fixture in fixtures.cases {
            let assessment = ApplicationRequirementEvaluator.assess(
                requirements: catalogue.requirement(for: fixture.cardId), profile: fixture.profile)
            XCTAssertEqual(assessment.status, fixture.expectedStatus, fixture.caseId)
            XCTAssertEqual(assessment.matchedType, fixture.expectedMatchedType, fixture.caseId)
            XCTAssertEqual(assessment.closestType, fixture.expectedClosestType, fixture.caseId)
            XCTAssertEqual(assessment.missingTypes, fixture.expectedMissingTypes ?? [], fixture.caseId)
            if let expected = fixture.expectedShortfall {
                XCTAssertEqual(try XCTUnwrap(assessment.closestPath?.shortfall?.amount),
                               expected, accuracy: 0.001, fixture.caseId)
            }
        }
    }

    func testEveryCandidateHasOneRequirementRecordAndIssuerSource() throws {
        let candidates = try SeedLoader.loadCandidateCatalogue().cardIds
        let requirements = try SeedLoader.loadApplicationRequirements()
        XCTAssertEqual(Set(requirements.requirements.map(\.cardId)), Set(candidates))
        XCTAssertEqual(requirements.requirements.count, candidates.count)
        XCTAssertTrue(requirements.requirements.allSatisfy { !$0.sources.isEmpty })
    }

    func testAcquisitionAnalysisSeparatesIncomeGroupsWithoutChangingEconomics() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let requirements = try SeedLoader.loadApplicationRequirements()
        let candidates = try SeedLoader.loadCandidateCatalogue().cardIds
        let owner = try SeedLoader.loadOwnerState()
        let profile = ApplicantIncomeProfile(
            individualAnnualIncome: Money(amount: 10_000, currency: .cad))
        let baseline = AcquisitionAnalyzer(catalogue: catalogue, candidateCardIds: candidates,
                                           ownerState: owner)
            .analyze(.placeholderCanadianHousehold, asOf: "2026-08-31")
        let screened = AcquisitionAnalyzer(
            catalogue: catalogue, candidateCardIds: candidates, ownerState: owner,
            applicationRequirements: requirements, applicantIncomeProfile: profile)
            .analyze(.placeholderCanadianHousehold, asOf: "2026-08-31")

        XCTAssertEqual(screened.candidates.map(\.netAnnualValueCad),
                       baseline.candidates.map(\.netAnnualValueCad))
        XCTAssertTrue(screened.incomeReadyCandidates.contains {
            $0.cardId == "amex-simplycash-preferred"
        })
        XCTAssertTrue(screened.incomeInformationNeeded.contains {
            $0.cardId == "bmo-cashback-world-elite"
        })
        XCTAssertTrue(screened.incomeCloseMatches.contains {
            $0.cardId == "home-trust-preferred-visa"
        })
    }
}
