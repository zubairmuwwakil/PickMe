import XCTest
import SwiftData
@testable import CardCopilotStore

/// Matching a Wallet capture to the checkout it belongs to (design §8, Path B).
///
/// The Shortcut uploads an observation with no idea which prediction it answers, so the join is
/// inferred from merchant and time. Every rule here is deliberately conservative: a wrong match
/// writes a fabricated fact into the evidence log, which is worse than asking the owner again.
final class CaptureMatcherTests: XCTestCase {
    var container: ModelContainer!
    var log: PredictionLog!

    /// 2026-08-19T12:00:00Z. Fixed so window arithmetic reads as minutes, not epoch seconds.
    private let noon = Date(timeIntervalSince1970: 1_787_140_800)

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: StoredPrediction.self, StoredPurchase.self, StoredObservation.self,
            StoredMerchant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        log = PredictionLog(context: ModelContext(container))
    }

    // MARK: - Builders

    private func prediction(merchant: String = "Starbucks",
                            at recordedAt: Date? = nil) throws -> StoredPrediction {
        let stored = try log.record(StoredPrediction(
            merchantName: merchant, merchantIdentifier: "poi-\(merchant)",
            predictedCategory: "dining", confidenceSource: .brandPrior,
            winnerCardId: "amex-cobalt", winnerValueCad: 0.32,
            defaultCardValueCad: 0.06, winnerRuleId: "cobalt-eats-5x",
            scoredAmountCad: 6.00, valuationCentsPerPoint: 1.0,
            headline: "Use American Express Cobalt Card.",
            recordedAt: recordedAt ?? noon))
        _ = try log.recordPurchase(for: stored, at: recordedAt ?? noon)
        return stored
    }

    private func capture(eventId: String = "evt-1",
                         merchantRaw: String? = "STARBUCKS #1234",
                         merchantNormalized: String? = nil,
                         amountMinor: Int? = 642,
                         currency: String? = "CAD",
                         resolvedCardId: String? = "amex-cobalt",
                         at capturedAt: Date? = nil) -> WalletFeedback {
        WalletFeedback(eventId: eventId,
                       capturedAt: capturedAt ?? noon.addingTimeInterval(120),
                       merchantRaw: merchantRaw,
                       merchantNormalized: merchantNormalized,
                       amountMinor: amountMinor,
                       currency: currency,
                       cardRaw: "American Express Cobalt",
                       resolvedCardId: resolvedCardId,
                       verdict: "best",
                       warning: nil)
    }

    // MARK: - The happy path

    func testProposesBothFactsForACaptureAtTheSameMerchantMinutesLater() throws {
        let stored = try prediction()

        let proposals = CaptureMatcher.proposals(for: [stored], from: [capture()])

        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposals.first?.predictionId, stored.id)
        XCTAssertEqual(proposals.first?.amountCad, 6.42)
        XCTAssertEqual(proposals.first?.cardUsedId, "amex-cobalt")
    }

    /// Apple's raw string carries a store number and a processor prefix that MapKit's name never
    /// has. Matching on the untouched strings would never fire in the real world.
    func testMatchesThroughStoreNumbersAndProcessorPrefixes() throws {
        let stored = try prediction(merchant: "Starbucks")

        let proposals = CaptureMatcher.proposals(for: [stored],
                                                 from: [capture(merchantRaw: "SQ *STARBUCKS #1234")])

        XCTAssertEqual(proposals.count, 1)
    }

    /// The server's normalized name is better evidence than Apple's raw string when present.
    func testPrefersTheServerNormalisedMerchantName() throws {
        let stored = try prediction(merchant: "Tim Hortons")

        let proposals = CaptureMatcher.proposals(
            for: [stored],
            from: [capture(merchantRaw: "TIMHO 4471 Q", merchantNormalized: "Tim Hortons")])

        XCTAssertEqual(proposals.count, 1)
    }

    // MARK: - Automatic completion threshold

    func testCompleteExplicitCADCaptureIsEligibleForAutomaticCompletion() throws {
        let stored = try prediction()

        let automatic = CaptureMatcher.automaticProposals(for: [stored], from: [capture()])

        XCTAssertEqual(automatic.count, 1)
    }

    func testCaptureWithoutExplicitCurrencyStillRequiresOwnerConfirmation() throws {
        let stored = try prediction()

        XCTAssertTrue(CaptureMatcher.automaticProposals(
            for: [stored], from: [capture(currency: nil)]).isEmpty)
        XCTAssertEqual(CaptureMatcher.proposals(
            for: [stored], from: [capture(currency: nil)]).count, 1,
                       "the capture remains useful in Finish Purchases")
    }

    func testZeroAmountCaptureStillRequiresOwnerConfirmation() throws {
        let stored = try prediction()

        XCTAssertTrue(CaptureMatcher.automaticProposals(
            for: [stored], from: [capture(amountMinor: 0)]).isEmpty)
    }

    // MARK: - The time window

    func testDoesNotMatchACaptureLongAfterTheCheckout() throws {
        let stored = try prediction()
        let late = capture(at: noon.addingTimeInterval(31 * 60))

        XCTAssertTrue(CaptureMatcher.proposals(for: [stored], from: [late]).isEmpty)
    }

    func testDoesNotMatchACaptureThatPrecedesTheCheckout() throws {
        let stored = try prediction()
        let early = capture(at: noon.addingTimeInterval(-10 * 60))

        XCTAssertTrue(CaptureMatcher.proposals(for: [stored], from: [early]).isEmpty)
    }

    /// A small backward grace absorbs device clock skew between the Shortcut and the app.
    func testAllowsASmallBackwardGraceForClockSkew() throws {
        let stored = try prediction()
        let slightlyEarly = capture(at: noon.addingTimeInterval(-60))

        XCTAssertEqual(CaptureMatcher.proposals(for: [stored], from: [slightlyEarly]).count, 1)
    }

    // MARK: - Ambiguity refuses to guess

    /// Asked twice at the same shop, then paid once — both checkouts precede the tap and both
    /// fit the window. Either assignment is a coin flip, and a coin flip written into the
    /// evidence log is indistinguishable from a measurement.
    func testProposesNothingWhenOneCaptureFitsTwoCheckouts() throws {
        let first = try prediction(at: noon)
        let second = try prediction(at: noon.addingTimeInterval(5 * 60))
        let tap = capture(at: noon.addingTimeInterval(10 * 60))

        let proposals = CaptureMatcher.proposals(for: [first, second], from: [tap])

        XCTAssertTrue(proposals.isEmpty)
    }

    func testProposesNothingWhenTwoCapturesFitOneCheckout() throws {
        let stored = try prediction()
        let captures = [capture(eventId: "evt-1", at: noon.addingTimeInterval(60)),
                        capture(eventId: "evt-2", at: noon.addingTimeInterval(180))]

        XCTAssertTrue(CaptureMatcher.proposals(for: [stored], from: captures).isEmpty)
    }

    func testDoesNotMatchADifferentMerchant() throws {
        let stored = try prediction(merchant: "Loblaws")

        XCTAssertTrue(CaptureMatcher.proposals(for: [stored], from: [capture()]).isEmpty)
    }

    // MARK: - Proposing only what is missing

    func testProposesOnlyTheAmountWhenTheCardIsAlreadyKnown() throws {
        let stored = try prediction()
        _ = try log.recordPurchase(for: stored, cardUsedId: "td-aeroplan", cardSource: .atTill)

        let proposals = CaptureMatcher.proposals(for: [stored], from: [capture()])

        XCTAssertEqual(proposals.first?.amountCad, 6.42)
        XCTAssertNil(proposals.first?.cardUsedId,
                     "a card stated at the till outranks a capture and must not be overwritten")
    }

    func testProposesNothingForAPurchaseThatIsAlreadyComplete() throws {
        let stored = try prediction()
        let purchase = try log.recordPurchase(for: stored, cardUsedId: "td-aeroplan",
                                              cardSource: .atTill)
        try log.recordAmount(6.42, source: .atTill, on: purchase)

        XCTAssertTrue(CaptureMatcher.proposals(for: [stored], from: [capture()]).isEmpty)
    }

    // MARK: - Refusing to invent

    /// The alias table lives on the server. An unresolved card is left blank rather than guessed
    /// at from `cardRaw`, which the capture spec forbids.
    func testProposesTheAmountAloneWhenTheServerCouldNotResolveTheCard() throws {
        let stored = try prediction()

        let proposals = CaptureMatcher.proposals(for: [stored],
                                                 from: [capture(resolvedCardId: nil)])

        XCTAssertEqual(proposals.first?.amountCad, 6.42)
        XCTAssertNil(proposals.first?.cardUsedId)
    }

    func testProposesTheCardAloneForAForeignCurrencyCharge() throws {
        let stored = try prediction()

        let proposals = CaptureMatcher.proposals(for: [stored],
                                                 from: [capture(currency: "USD")])

        XCTAssertNil(proposals.first?.amountCad, "converting USD here would invent an FX rate")
        XCTAssertEqual(proposals.first?.cardUsedId, "amex-cobalt")
    }

    func testProposesNothingWhenTheCaptureCarriesNeitherFact() throws {
        let stored = try prediction()

        let proposals = CaptureMatcher.proposals(
            for: [stored], from: [capture(amountMinor: nil, resolvedCardId: nil)])

        XCTAssertTrue(proposals.isEmpty, "a proposal that offers nothing is not a proposal")
    }

    // MARK: - unclaimedCaptures: logging taps with no checkout behind them

    func testAnUnrelatedMerchantIsUnclaimed() throws {
        let stored = try prediction(merchant: "Loblaws")
        let tap = capture(merchantRaw: "TIM HORTONS #4021")

        let unclaimed = CaptureMatcher.unclaimedCaptures(from: [tap], openPredictions: [stored])

        XCTAssertEqual(unclaimed.map(\.eventId), [tap.eventId])
    }

    func testATapWithNoOpenCheckoutAtAllIsUnclaimed() {
        let tap = capture()

        let unclaimed = CaptureMatcher.unclaimedCaptures(from: [tap], openPredictions: [])

        XCTAssertEqual(unclaimed.map(\.eventId), [tap.eventId])
    }

    func testATapThatPlausiblyMatchesAnOpenCheckoutIsNotUnclaimed() throws {
        let stored = try prediction()

        let unclaimed = CaptureMatcher.unclaimedCaptures(for: stored, tap: capture())
        XCTAssertTrue(unclaimed.isEmpty,
                     "this tap belongs to Finish Purchases, not a second standalone log entry")
    }

    /// The safety property `unclaimedCaptures`'s doc comment names: an AMBIGUOUS pairing (the one
    /// case `proposals(for:from:)` itself refuses to resolve) must still be excluded here, not
    /// treated as available for standalone logging. Otherwise the owner could see the same tap
    /// twice — once as an auto-logged purchase, once later as the Finish Purchases answer for the
    /// checkout it actually belonged to.
    func testAnAmbiguousPairingIsNeitherProposedNorUnclaimed() throws {
        let first = try prediction(at: noon)
        let second = try prediction(at: noon.addingTimeInterval(5 * 60))
        let tap = capture(at: noon.addingTimeInterval(10 * 60))

        XCTAssertTrue(CaptureMatcher.proposals(for: [first, second], from: [tap]).isEmpty)
        XCTAssertTrue(CaptureMatcher.unclaimedCaptures(from: [tap], openPredictions: [first, second]).isEmpty)
    }

    func testAnUnclaimedCaptureCarriesTheNormalisedMerchantAndConvertedAmount() {
        let tap = capture(merchantRaw: "SQ *TIM HORTONS #4021", merchantNormalized: "Tim Hortons")

        let unclaimed = CaptureMatcher.unclaimedCaptures(from: [tap], openPredictions: [])

        XCTAssertEqual(unclaimed.first?.merchant, "Tim Hortons")
        XCTAssertEqual(unclaimed.first?.amountCad, 6.42)
        XCTAssertEqual(unclaimed.first?.cardUsedId, "amex-cobalt")
    }

    func testAnUnclaimedCaptureRefusesToConvertAForeignCurrency() {
        let tap = capture(currency: "USD")

        let unclaimed = CaptureMatcher.unclaimedCaptures(from: [tap], openPredictions: [])

        XCTAssertNil(unclaimed.first?.amountCad, "converting USD here would invent an FX rate")
        XCTAssertEqual(unclaimed.first?.cardUsedId, "amex-cobalt")
    }
}

private extension CaptureMatcher {
    /// Test-only convenience matching the fixtures' single-prediction, single-capture shape.
    static func unclaimedCaptures(for prediction: StoredPrediction, tap: WalletFeedback) -> [UnclaimedCapture] {
        unclaimedCaptures(from: [tap], openPredictions: [prediction])
    }
}

/// Provenance of a saved fact (design §3: `CaptureSource`).
///
/// A proposal that the owner edits is no longer the capture's claim — it is the owner's. Getting
/// this backwards would let a typed correction be filed as machine evidence, and the whole reason
/// provenance is stored per field is so the two can be told apart later.
final class CaptureProvenanceTests: XCTestCase {
    private let proposal = CaptureProposal(
        eventId: "evt-1", predictionId: UUID(), amountCad: 6.42, cardUsedId: "amex-cobalt",
        capturedAt: Date(timeIntervalSince1970: 1_787_140_800), merchantLabel: "Starbucks")

    func testAnAmountAcceptedUneditedIsCreditedToTheCapture() {
        XCTAssertEqual(proposal.amountProvenance(forSaved: 6.42), .walletCapture)
    }

    func testAnEditedAmountIsTheOwnersRecollection() {
        XCTAssertEqual(proposal.amountProvenance(forSaved: 8.15), .recalledLater)
    }

    /// Cent-level equality, because the field round-trips through a formatted string.
    func testAnAmountRetypedIdenticallyStillCountsAsTheCapture() {
        XCTAssertEqual(proposal.amountProvenance(forSaved: 6.4200000001), .walletCapture)
    }

    func testACardAcceptedUneditedIsCreditedToTheCapture() {
        XCTAssertEqual(proposal.cardProvenance(forSaved: "amex-cobalt"), .walletCapture)
    }

    func testASwitchedCardIsTheOwnersRecollection() {
        XCTAssertEqual(proposal.cardProvenance(forSaved: "td-aeroplan"), .recalledLater)
    }

    /// A proposal that offered no card cannot be the source of one, even by coincidence.
    func testAProposalThatOfferedNoCardNeverClaimsOne() {
        let amountOnly = CaptureProposal(eventId: "evt-2", predictionId: UUID(), amountCad: 6.42,
                                         cardUsedId: nil, capturedAt: Date(), merchantLabel: nil)
        XCTAssertEqual(amountOnly.cardProvenance(forSaved: "amex-cobalt"), .recalledLater)
    }
}
