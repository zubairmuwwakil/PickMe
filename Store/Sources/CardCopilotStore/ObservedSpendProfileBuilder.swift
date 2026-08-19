import Foundation
import CardCopilotEngine

/// Transforms on-device recorded purchase history into an individualized `SpendDistribution`.
///
/// If transaction history covers only a few categories (e.g. only coffee and groceries), it
/// blends those observed annual rates with baseline amounts for unobserved categories so that
/// portfolio keep/cancel and acquisition decisions remain grounded.
public struct ObservedSpendProfileBuilder: Sendable {
    public let minimumObservationDays: Double

    public init(minimumObservationDays: Double = 30) {
        self.minimumObservationDays = minimumObservationDays
    }

    /// Builds a dynamic `SpendDistribution` from historical predictions and purchases.
    ///
    /// - Parameters:
    ///   - predictions: The stored predictions and associated purchases on this device.
    ///   - baseline: The reference distribution to blend unobserved categories against.
    ///   - asOf: Current date for calculating elapsed days.
    public func build(from predictions: [StoredPrediction],
                      baseline: SpendDistribution = .placeholderCanadianHousehold,
                      asOf: Date = Date()) -> SpendDistribution {
        var categoryTotals: [String: Double] = [:]
        var earliestDate: Date = asOf
        var totalPurchasesCount = 0

        for prediction in predictions {
            guard let purchase = prediction.purchase else { continue }
            let amount = purchase.amountCad ?? prediction.scoredAmountCad
            guard let amount, amount > 0 else { continue }

            let category = purchase.observation?.observedCategory ?? prediction.predictedCategory
            categoryTotals[category, default: 0] += amount
            totalPurchasesCount += 1

            if prediction.recordedAt < earliestDate {
                earliestDate = prediction.recordedAt
            }
        }

        // If no purchase data has been captured yet, return the baseline.
        guard totalPurchasesCount > 0 else {
            return baseline
        }

        let daysSpan = max(minimumObservationDays,
                           max(1, asOf.timeIntervalSince(earliestDate) / 86400.0))
        let annualMultiplier = 365.0 / daysSpan

        var annualizedObserved: [String: Double] = [:]
        for (category, total) in categoryTotals {
            annualizedObserved[category] = total * annualMultiplier
        }

        // Map baseline buckets, substituting observed annual spend when available
        let updatedBuckets = baseline.buckets.map { bucket -> SpendDistribution.Bucket in
            let category = bucket.context.category
            if let observedAnnual = annualizedObserved[category] {
                // If this bucket matches the category, apply observed spend
                return SpendDistribution.Bucket(
                    label: bucket.label,
                    annualCad: observedAnnual,
                    context: bucket.context
                )
            }
            return bucket
        }

        let basis = "OBSERVED SPEND: derived from \(totalPurchasesCount) confirmed checkouts over \(Int(daysSpan)) days (annualized ×\(String(format: "%.1f", annualMultiplier))). Unobserved categories blended from baseline."

        return SpendDistribution(
            profileId: "observed-spend-profile",
            basis: basis,
            buckets: updatedBuckets
        )
    }
}
