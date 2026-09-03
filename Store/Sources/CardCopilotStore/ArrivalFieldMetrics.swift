import Foundation
import CardCopilotEngine

/// How long after an arrival a Wallet capture may still be that arrival's purchase.
///
/// Ninety minutes. A charge that lands the next morning is a different trip, and joining it would
/// invent an accuracy figure out of a coincidence.
public let arrivalReceiptWindow: TimeInterval = 90 * 60

/// Attaches each Wallet capture to the arrival it most plausibly belongs to, and names which
/// candidate the owner was actually standing in.
///
/// Pure, and separate from capture, because it is the join every derived metric rests on: top-1
/// accuracy, containment, and card equivalence are all readings of `receiptCandidateIndex`. A
/// receipt joins at most one arrival — the nearest one preceding it inside the window — so a
/// single coffee cannot inflate two arrivals' figures.
public func joinReceipts(_ records: [ArrivalFieldRecord], receipts: [ArrivalReceipt],
                         window: TimeInterval = arrivalReceiptWindow) -> [ArrivalFieldRecord] {
    var joined = records
    var claimed = Set<Int>()

    for receipt in receipts.sorted(by: { $0.capturedAt < $1.capturedAt }) {
        // A charge cannot precede the arrival that produced it, so the search is one-sided.
        let best = joined.indices
            .filter { !claimed.contains($0) }
            .filter {
                let elapsed = receipt.capturedAt.timeIntervalSince(joined[$0].recordedAt)
                return elapsed >= 0 && elapsed <= window
            }
            .min { receipt.capturedAt.timeIntervalSince(joined[$0].recordedAt)
                    < receipt.capturedAt.timeIntervalSince(joined[$1].recordedAt) }
        guard let best else { continue }
        claimed.insert(best)
        joined[best].receipt = receipt
        // Nil here is not a failure to join — the purchase happened. It means the true store was
        // never in the candidate set, which is the containment ceiling and a different finding
        // from "we ranked the set wrong".
        joined[best].receiptCandidateIndex = matchingCandidateIndex(
            descriptor: receipt.merchantDescriptor, candidates: joined[best].candidates)
    }
    return joined
}

/// Which candidate a Wallet descriptor names, by the same identity notion the wallet join uses.
func matchingCandidateIndex(descriptor: String,
                            candidates: [ArrivalCandidateRecord]) -> Int? {
    let captured = compactMerchantIdentity(descriptor)
    guard captured.count >= 4 else { return nil }
    return candidates.indices.first { index in
        let name = compactMerchantIdentity(candidates[index].name)
        guard name.count >= 4 else { return false }
        let shorter = captured.count <= name.count ? captured : name
        let longer = captured.count <= name.count ? name : captured
        return longer.contains(shorter)
            && Double(shorter.count) / Double(longer.count) >= 0.60
    }
}

/// Replays one arrival's gate decision against the amount that actually got charged.
///
/// Two changes from what the gate saw, and only two. The advantage is recomputed at the real
/// basket — the percentage-point figure is what the engine's rate rules produce, so it carries
/// across baskets while the CAD figure does not — and the CAD floor is left unscaled, since the
/// question is what the *estimate* cost, not what the multiplier cost. The percentage floor keeps
/// its multiplier so the tier still means something.
///
/// The percentage-point carry is an approximation: a rule that caps or tiers within one basket
/// does not scale linearly. It is the honest one available without re-running the catalogue that
/// was current at the time, and it is why this is a replay rather than a verdict.
public func replayAtRealAmount(_ record: ArrivalFieldRecord) -> AmbientGateDecision? {
    // No gate input means no gate ran — a Radar scan. There is no decision to replay, and
    // synthesising one would report an alert the app was never in a position to suppress.
    guard let gateInput = record.gateInput, let policy = record.policy,
          let receipt = record.receipt, receipt.amountCad > 0 else { return nil }
    var input = gateInput
    let percentagePoints = gateInput.advantage.percentagePoints
    input.advantage = AmbientAdvantage(percentagePoints: percentagePoints,
                                       cad: percentagePoints / 100 * receipt.amountCad)
    let multiplier = policy.multiplier(for: gateInput.merchantConfidence)
    input.switchThreshold = SwitchThreshold(
        minAdvantagePercentagePoints: gateInput.switchThreshold
            .minAdvantagePercentagePoints * multiplier,
        minAdvantageCad: gateInput.switchThreshold.minAdvantageCad,
        semantics: gateInput.switchThreshold.semantics)
    input.unverifiedAdvantageMultiplier = 1
    input.frequentedAdvantageMultiplier = 1
    input.categoryAdvantageMultiplier = 1
    return AmbientGate.evaluate(input)
}

/// What a field week actually says.
public struct ArrivalFieldMetrics: Equatable, Sendable, Codable {
    public let arrivals: Int
    public let arrivalsWithAFix: Int
    public let arrivalsWithAReceipt: Int
    /// Of arrivals with a receipt, how often the chosen candidate was the true store.
    public let topOneStoreAccuracy: Double?
    /// Of arrivals with a receipt, how often the true store was in the candidate set at all. The
    /// ceiling: no ranking can beat it.
    public let candidateContainment: Double?
    /// Arrivals with a receipt where the true store was in the set and was not the one chosen.
    public let storeWrongArrivals: Int
    /// **The number that decides the rework.** Of `storeWrongArrivals`, how often the *card* was
    /// still right.
    ///
    /// High means the rework is "answer when it doesn't matter" — score every plausible candidate
    /// and speak when they agree — and per-store resolution never has to be solved. Low means it
    /// does, and the margins below say whether that is even possible on this hardware.
    public let cardEquivalenceAccuracy: Double?
    /// Arrivals whose nearest and runner-up candidates were further apart than the fix's own
    /// error circle. Anything else was unanswerable by any algorithm.
    public let resolvableArrivals: Int
    public let ambiguousArrivals: Int
    /// Arrivals that stayed quiet and would have fired replayed at the real basket with the CAD
    /// floor unscaled. How many alerts the guessed amount ate.
    public let alertsEatenByTheEstimate: Int
    public let engagementByAction: [ArrivalEngagement: Int]

    // MARK: - Radar
    //
    // Counted apart from arrivals throughout. Radar is tapped far more often than a geofence is
    // crossed, so pooling the two would let scans swamp the arrival denominator every accuracy
    // figure above rests on.

    public let radarScans: Int
    /// Scans in which at least one candidate resolved to a `CanadianMerchantPreIndex` row. The
    /// denominator for "was the anchor tenant returned at all".
    public let radarScansWithARecognisedChain: Int
    /// **The number that decides which of the two fixes is needed.** Scans where a recognised
    /// chain was present and something else was ranked first.
    ///
    /// High means pin geometry: the store is returned and outranked, and the fix is a different
    /// ranking. Low, against a high count of scans with no chain at all, means the result set is
    /// being truncated, and the fix is a second targeted query.
    public let radarScansWhereTopRankedMissedAChain: Int
}

public func arrivalFieldMetrics(_ records: [ArrivalFieldRecord]) -> ArrivalFieldMetrics {
    // One log holds both, because the question asked of a record — which storefronts were on the
    // table, which one was named — is the same in both directions. Every figure below is asked of
    // one population or the other, never of the union.
    let scans = records.filter { $0.source == .radar }
    let records = records.filter { $0.source != .radar }

    let withReceipt = records.filter { $0.receipt != nil }
    let contained = withReceipt.filter { $0.receiptCandidateIndex != nil }
    let topOne = contained.filter { $0.receiptCandidateIndex == $0.chosenCandidateIndex }
    let storeWrong = contained.filter { $0.receiptCandidateIndex != $0.chosenCandidateIndex }
    // Card equivalence asks only about arrivals the store guess got wrong. Arrivals guessed right
    // are excluded from the denominator rather than scored as successes: folding them in would
    // measure "how often is the card right", which is a different and much easier question.
    let cardStillRight = storeWrong.filter {
        guard let chosen = $0.chosenCandidate, let truth = $0.receiptCandidate else { return false }
        return chosen.recommendedCardId == truth.recommendedCardId
    }

    var engagement: [ArrivalEngagement: Int] = [:]
    for record in records {
        guard let action = record.engagement else { continue }
        engagement[action, default: 0] += 1
    }

    func ratio(_ numerator: Int, _ denominator: Int) -> Double? {
        denominator > 0 ? Double(numerator) / Double(denominator) : nil
    }

    return ArrivalFieldMetrics(
        arrivals: records.count,
        arrivalsWithAFix: records.filter { $0.fix != nil }.count,
        arrivalsWithAReceipt: withReceipt.count,
        topOneStoreAccuracy: ratio(topOne.count, withReceipt.count),
        candidateContainment: ratio(contained.count, withReceipt.count),
        storeWrongArrivals: storeWrong.count,
        cardEquivalenceAccuracy: ratio(cardStillRight.count, storeWrong.count),
        resolvableArrivals: records.filter { $0.discriminability?.isResolvable == true }.count,
        ambiguousArrivals: records.filter { $0.discriminability?.isResolvable == false }.count,
        alertsEatenByTheEstimate: records.filter { record in
            guard let gateInput = record.gateInput,
                  !AmbientGate.evaluate(gateInput).fires,
                  let replay = replayAtRealAmount(record) else { return false }
            return replay.fires
        }.count,
        engagementByAction: engagement,
        radarScans: scans.count,
        radarScansWithARecognisedChain: scans.filter(\.containsRecognisedChain).count,
        radarScansWhereTopRankedMissedAChain:
            scans.filter(\.topRankedMissedARecognisedChain).count)
}
