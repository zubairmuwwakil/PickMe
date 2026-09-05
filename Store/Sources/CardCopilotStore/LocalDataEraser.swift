import Foundation
import SwiftData

/// Erases everything the app keeps on this device.
///
/// Deleting a PickMe account removes what the server holds; it says nothing about the local
/// store, which never left the phone in the first place. That makes the local wipe a separate,
/// explicit choice rather than a side effect — the prediction log is the owner's own record of
/// what the app advised and what actually happened, and destroying it silently would destroy the
/// only evidence the experiment has.
///
/// The merchant rows go with the log deliberately: they carry the coordinates of places the owner
/// shopped, so a "wipe" that spared them would leave the most sensitive local data behind.
///
/// The discovery cache goes for the same reason, and more forcefully. It records every ~1 km cell
/// the owner has *passed through* — not merely shopped in — plus the coordinates of every shop
/// found in them. It is a broader location footprint than anything else here and exists purely as
/// a battery optimisation, so it has the weakest claim to surviving a wipe.
public struct LocalDataEraser {
    private let context: ModelContext
    private let metrics: CategoryResolutionMetricsStore
    private let rewardFeedbackStore: MerchantMCCRewardFeedbackStore
    private let importedEvidenceStore: MerchantMCCImportedEvidenceStore
    private let walletCaptureDeletionStore: WalletCaptureDeletionStore

    public init(context: ModelContext,
                metrics: CategoryResolutionMetricsStore = CategoryResolutionMetricsStore(),
                rewardFeedbackStore: MerchantMCCRewardFeedbackStore = .shared,
                importedEvidenceStore: MerchantMCCImportedEvidenceStore = .shared,
                walletCaptureDeletionStore: WalletCaptureDeletionStore = WalletCaptureDeletionStore()) {
        self.context = context
        self.metrics = metrics
        self.rewardFeedbackStore = rewardFeedbackStore
        self.importedEvidenceStore = importedEvidenceStore
        self.walletCaptureDeletionStore = walletCaptureDeletionStore
    }

    public func eraseLocalHistory() throws {
        // Cascades would cover the dependent rows, but each is deleted explicitly rather than
        // assumed impossible: an orphan here is a coordinate the owner asked us to forget.
        try context.delete(model: StoredObservation.self)
        try context.delete(model: StoredPurchase.self)
        try context.delete(model: StoredPrediction.self)
        try context.delete(model: StoredMerchant.self)
        try DiscoveryCache(context: context).eraseAll()
        // Derived from the rows just deleted or from issuer files the owner supplied locally.
        // A history wipe that left these ledgers standing would keep describing activity the owner
        // explicitly asked the app to forget.
        metrics.forgetAll()
        rewardFeedbackStore.forgetAll()
        importedEvidenceStore.forgetAll()
        walletCaptureDeletionStore.forgetAll()
        try context.save()
    }
}
