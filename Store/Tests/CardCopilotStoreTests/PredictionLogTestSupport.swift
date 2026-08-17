import Foundation
@testable import CardCopilotStore

extension PredictionLog {
    /// Records the till facts and the statement in one call — the shape most tests here need,
    /// since they predate the three-record model and are asserting things unrelated to it.
    ///
    /// `actualAmountCad` defaults to the prediction's *scored* amount. **Production code must
    /// never do that**: the entire point of the split is that the figure the owner tapped before
    /// paying and the figure the terminal charged are different facts. Defaulting is safe here
    /// only because these tests assert category accuracy, arithmetic tolerance, and merchant
    /// promotion, none of which turn on the difference. Tests that DO turn on it pass an explicit
    /// figure and live in `PurchaseRecordTests`.
    ///
    /// Provenance is `.recalledLater` throughout, which is what a reconcile-time entry actually is.
    func settle(_ prediction: StoredPrediction,
                cardUsed: String,
                actualAmountCad: Double? = nil,
                observedCategory: String,
                observedRewardUnits: Double? = nil,
                missClass: MissClass? = nil,
                note: String? = nil,
                confirmedAt: Date = Date()) throws {
        let purchase = try recordPurchase(for: prediction, cardUsedId: cardUsed,
                                          cardSource: .recalledLater)
        if let amount = actualAmountCad ?? prediction.scoredAmountCad {
            try recordAmount(amount, source: .recalledLater, on: purchase)
        }
        try confirm(purchase, observedCategory: observedCategory,
                    observedRewardUnits: observedRewardUnits,
                    missClass: missClass, note: note, confirmedAt: confirmedAt)
    }
}
