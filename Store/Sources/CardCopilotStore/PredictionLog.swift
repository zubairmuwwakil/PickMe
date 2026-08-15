import Foundation
import SwiftData

/// Whether a confirmed row can be — and was — checked against the catalogue math.
public enum ArithmeticVerdict: Equatable, Sendable {
    /// Not enough evidence to judge, or judging it would measure something other than the
    /// catalogue. Counted on neither side of the ratio.
    case notEligible
    case matches
    case mismatch
}

/// How far a posted reward may sit from the predicted one before it counts as a math error.
///
/// Points post as whole units — an engine figure of 46.47 posts as 46 — so a points row gets
/// 1.0 unit of slack. Cash back and CT Money post to the cent and their "units" ARE dollars,
/// where that same slack would wave through a dollar of error on a two-dollar reward. An
/// unrecorded unit kind takes the strict tolerance on purpose: a false miss shows up on the
/// dashboard and gets reviewed, a false pass never does.
func rewardUnitTolerance(_ unitKind: String?) -> Double {
    unitKind == "point" ? 1.0 : 0.01
}

extension StoredPrediction {
    /// ELIGIBILITY RULE for the arithmetic bar (design §3, metric #2). A confirmed row enters
    /// the check ONLY when all four hold:
    ///
    /// 1. The category was right — `observedCategory == predictedCategory`. Deliberately NOT
    ///    "carries no miss class": a `capExceeded` row has the right category and the wrong
    ///    math, which is precisely the failure this metric exists to catch.
    /// 2. `amountCad != nil` — the engine scored a real amount, not a category estimate. Units
    ///    predicted from a guessed basket cannot meaningfully disagree with a statement.
    /// 3. The card tapped is the card recommended. The predicted units belong to the winner;
    ///    another card's posting is a different sum, not a catalogue error.
    /// 4. Both reward-unit figures exist. Missing means unknown, never assumed-correct — rows
    ///    predating the fields drop out instead of inflating the numerator.
    ///
    /// The comparison uses THIS prediction's snapshotted units. Re-running today's engine
    /// against an old row would measure today's catalogue and today's valuation, not the advice
    /// that was actually given — which is the entire reason the snapshot exists.
    public var arithmeticVerdict: ArithmeticVerdict {
        guard let observation,
              observation.observedCategory == predictedCategory,
              observation.cardUsed == winnerCardId,
              amountCad != nil,
              let predicted = predictedRewardUnits,
              let observed = observation.observedRewardUnits else { return .notEligible }
        let tolerance = rewardUnitTolerance(predictedRewardUnitKind)
        // 1e-9 absorbs binary-floating-point noise (2.00 - 1.99 is not exactly 0.01), not
        // reward error.
        return abs(predicted - observed) <= tolerance + 1e-9 ? .matches : .mismatch
    }
}

/// The two numbers the personal MVP exists to measure, plus the reconcile queue that feeds them.
public struct ExperimentMetrics: Equatable, Sendable {
    public let confirmedCount: Int
    public let categoryCorrectCount: Int
    public let missBreakdown: [MissClass: Int]
    public let targetCheckouts: Int
    /// Confirmed rows that cleared the eligibility rule above — the arithmetic denominator.
    public let arithmeticEligibleCount: Int
    public let arithmeticCorrectCount: Int

    /// Nil rather than zero when there is no evidence — an unmeasured experiment is not a
    /// failing one, and a dashboard showing "0%" on day one would be a lie.
    public var categoryAccuracy: Double? {
        confirmedCount > 0 ? Double(categoryCorrectCount) / Double(confirmedCount) : nil
    }

    /// Nil when no confirmed row could be checked. A dashboard that printed "0%" here would be
    /// reporting a failure the evidence does not support.
    public var arithmeticCorrectRate: Double? {
        arithmeticEligibleCount > 0
            ? Double(arithmeticCorrectCount) / Double(arithmeticEligibleCount) : nil
    }

    public var progressToTarget: Int { confirmedCount }
    public var meetsCategoryBar: Bool? { categoryAccuracy.map { $0 >= 0.85 } }
    /// The bar is 100%: one row of wrong catalogue math fails the metric (design §3).
    public var meetsArithmeticBar: Bool? { arithmeticCorrectRate.map { $0 == 1.0 } }
}

/// Append-only store for predictions and their later confirmations.
///
/// The API deliberately offers no way to edit a prediction. `confirm` attaches an
/// observation instead, so the record of what the app said survives being wrong.
public struct PredictionLog {
    public static let targetCheckouts = 30

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func record(_ prediction: StoredPrediction) throws -> StoredPrediction {
        context.insert(prediction)
        try context.save()
        return prediction
    }

    public func confirm(_ prediction: StoredPrediction, cardUsed: String,
                        observedCategory: String, observedRewardUnits: Double? = nil,
                        missClass: MissClass?,
                        note: String?, confirmedAt: Date = Date()) throws {
        let observation = StoredObservation(cardUsed: cardUsed, observedCategory: observedCategory,
                                            observedRewardUnits: observedRewardUnits,
                                            missClass: missClass, note: note,
                                            confirmedAt: confirmedAt)
        context.insert(observation)
        observation.prediction = prediction
        try promoteMerchant(for: prediction, observedCategory: observedCategory)
        try context.save()
    }

    /// Terminal-level promotion, never brand-wide. The dossier (§6) is explicit: the owner's
    /// reconciled outcome is the only source that can promote a merchant to "verified", and it
    /// promotes THAT location — a confirmation at one Walmart says nothing about another.
    private func promoteMerchant(for prediction: StoredPrediction,
                                 observedCategory: String) throws {
        guard let identifier = prediction.merchantIdentifier else { return }
        let matches = try context.fetch(FetchDescriptor<StoredMerchant>(
            predicate: #Predicate { $0.identifier == identifier }))
        guard let merchant = matches.first else { return }

        // The count is a streak, not a total: it answers "how many times has this same result
        // repeated here", which is the claim `.repeatedTerminal` makes. A terminal that re-codes
        // starts over rather than accruing confidence its own evidence contradicts.
        merchant.confirmationCount = merchant.confirmedCategory == observedCategory
            ? merchant.confirmationCount + 1
            : 1
        merchant.confirmedCategory = observedCategory
    }

    public func allPredictions() throws -> [StoredPrediction] {
        try context.fetch(FetchDescriptor<StoredPrediction>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]))
    }

    /// Predictions still waiting on a statement — the weekly reconcile queue.
    public func awaitingConfirmation() throws -> [StoredPrediction] {
        try allPredictions().filter { $0.observation == nil }
    }

    public func metrics() throws -> ExperimentMetrics {
        let predictions = try allPredictions()
        let confirmed = predictions.compactMap(\.observation)
        var breakdown: [MissClass: Int] = [:]
        for miss in confirmed.compactMap(\.missClass) {
            breakdown[miss, default: 0] += 1
        }
        let verdicts = predictions.map(\.arithmeticVerdict)
        return ExperimentMetrics(confirmedCount: confirmed.count,
                                 categoryCorrectCount: confirmed.filter(\.wasCorrect).count,
                                 missBreakdown: breakdown,
                                 targetCheckouts: Self.targetCheckouts,
                                 arithmeticEligibleCount: verdicts.filter { $0 != .notEligible }.count,
                                 arithmeticCorrectCount: verdicts.filter { $0 == .matches }.count)
    }

    public func valueRecovered() throws -> Double {
        try allPredictions().reduce(0) { total, prediction in
            guard prediction.observation != nil,
                  prediction.amountCad != nil,
                  let defaultCardValueCad = prediction.defaultCardValueCad else {
                return total
            }
            return total + (prediction.winnerValueCad - defaultCardValueCad)
        }
    }
}
