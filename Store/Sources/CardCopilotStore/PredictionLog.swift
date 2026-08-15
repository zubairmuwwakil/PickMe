import Foundation
import SwiftData

/// The two numbers the personal MVP exists to measure, plus the reconcile queue that feeds them.
public struct ExperimentMetrics: Equatable, Sendable {
    public let confirmedCount: Int
    public let categoryCorrectCount: Int
    public let missBreakdown: [MissClass: Int]
    public let targetCheckouts: Int

    /// Nil rather than zero when there is no evidence — an unmeasured experiment is not a
    /// failing one, and a dashboard showing "0%" on day one would be a lie.
    public var categoryAccuracy: Double? {
        confirmedCount > 0 ? Double(categoryCorrectCount) / Double(confirmedCount) : nil
    }

    public var progressToTarget: Int { confirmedCount }
    public var meetsCategoryBar: Bool? { categoryAccuracy.map { $0 >= 0.85 } }
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
                        observedCategory: String, missClass: MissClass?,
                        note: String?, confirmedAt: Date = Date()) throws {
        let observation = StoredObservation(cardUsed: cardUsed, observedCategory: observedCategory,
                                            missClass: missClass, note: note,
                                            confirmedAt: confirmedAt)
        context.insert(observation)
        observation.prediction = prediction
        try context.save()
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
        let confirmed = try allPredictions().compactMap(\.observation)
        var breakdown: [MissClass: Int] = [:]
        for miss in confirmed.compactMap(\.missClass) {
            breakdown[miss, default: 0] += 1
        }
        return ExperimentMetrics(confirmedCount: confirmed.count,
                                 categoryCorrectCount: confirmed.filter(\.wasCorrect).count,
                                 missBreakdown: breakdown,
                                 targetCheckouts: Self.targetCheckouts)
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
