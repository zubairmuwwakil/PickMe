import XCTest
@testable import CardCopilotEngine

final class CreditStateEditorTests: XCTestCase {
    private let credit = CardCredit(
        creditId: "monthly-credit", label: "Monthly credit",
        value: Money(amount: 10, currency: .cad),
        schedule: CreditSchedule(basis: .calendar, unit: .month),
        sourceType: .issuerConfirmed, lastVerifiedAt: "2026-08-24"
    )

    func testPendingUseAndPostingRemainDistinct() throws {
        let pending = try XCTUnwrap(CreditStateEditor.applying(
            .markConsumed(), to: owner(), cardId: "card", credit: credit, asOf: "2026-08-25"
        ))
        let pendingOpportunity = try XCTUnwrap(CreditAdvisor.opportunity(
            cardId: "card", credit: credit, cardState: pending.cardStates["card"]!,
            asOf: "2026-08-25"
        ))
        XCTAssertEqual(pendingOpportunity.status, .used)
        XCTAssertEqual(pendingOpportunity.consumedAmount, 10)
        XCTAssertEqual(pendingOpportunity.realizedAmount, 0)

        let posted = try XCTUnwrap(CreditStateEditor.applying(
            .confirmRealized(), to: pending, cardId: "card", credit: credit,
            asOf: "2026-08-26"
        ))
        let postedOpportunity = try XCTUnwrap(CreditAdvisor.opportunity(
            cardId: "card", credit: credit, cardState: posted.cardStates["card"]!,
            asOf: "2026-08-26"
        ))
        XCTAssertEqual(postedOpportunity.realizedAmount, 10)
    }

    func testUnresolvedAnniversaryWindowCannotBeMarkedUsed() {
        let annual = CardCredit(
            creditId: "annual", label: "Annual",
            value: Money(amount: 100, currency: .cad),
            schedule: CreditSchedule(basis: .accountAnniversary, intervalMonths: 12),
            sourceType: .issuerConfirmed, lastVerifiedAt: "2026-08-24"
        )
        XCTAssertNil(CreditStateEditor.applying(
            .markConsumed(), to: owner(), cardId: "card", credit: annual,
            asOf: "2026-08-25"
        ))
    }

    func testInferredCatalogueCreditNeverBecomesAnOwnerOpportunity() {
        var inferred = credit
        inferred.sourceType = .inferred
        XCTAssertNil(CreditAdvisor.opportunity(
            cardId: "card", credit: inferred, cardState: CardState(), asOf: "2026-08-25"
        ))
    }

    func testPortfolioCountsPostedCreditButOnlyDisclosesUnspentPotential() throws {
        let initial = owner()
        let before = CreditPortfolioRecoveryCalculator.recovery(
            cardId: "card", credits: [credit], cardState: initial.cardStates["card"]!,
            asOf: "2026-08-25"
        )
        XCTAssertEqual(before.realizedCad, 0)
        XCTAssertEqual(before.unspentPotentialCad, 10)

        let posted = try XCTUnwrap(CreditStateEditor.applying(
            .confirmRealized(), to: initial, cardId: "card", credit: credit,
            asOf: "2026-08-25"
        ))
        let after = CreditPortfolioRecoveryCalculator.recovery(
            cardId: "card", credits: [credit], cardState: posted.cardStates["card"]!,
            asOf: "2026-08-25"
        )
        XCTAssertEqual(after.realizedCad, 10)
        XCTAssertEqual(after.unspentPotentialCad, 0)
    }

    private func owner() -> OwnerState {
        OwnerState(
            ownerStateVersion: "1.0", ownedCardIds: ["card"], defaultCardId: "card",
            switchThreshold: SwitchThreshold(minAdvantagePercentagePoints: 0,
                                             minAdvantageCad: 0, semantics: "either"),
            carry: Carry(drawerCards: []), cardStates: ["card": CardState()],
            valuationsCad: Valuations()
        )
    }
}
