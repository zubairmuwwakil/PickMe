import Foundation

/// Converts a high-confidence Wallet-to-MapKit resolution into merchant-identity evidence.
///
/// `resolveWalletMerchant` already enforces the expensive identity checks: captured GPS is close
/// to the POI, the descriptor and place name strongly overlap, and the POI produces an actionable
/// category. This helper deliberately runs only after that resolver has succeeded. It does not
/// perform fuzzy matching itself and it cannot invent a merchant outside the canonical 500-row
/// seed.
///
/// The Wallet event id is the source fingerprint. That gives this signal the same idempotence as
/// strict checkout learning: replaying a sync, reopening the app, or qualifying through both the
/// checkout and GPS paths still counts as one observation for that transaction.
@discardableResult
public func learnMerchantAliasFromGPSResolution(
    purchase: StoredPurchase,
    resolution: WalletMerchantResolution,
    identityStore: MerchantMCCIdentityLearningStore = .shared
) -> Bool {
    guard purchase.isAutoLogged,
          let eventID = purchase.walletEventId?.trimmingCharacters(in: .whitespacesAndNewlines),
          !eventID.isEmpty,
          let canonical = MerchantMCCSeedCatalogue.canonicalMatch(
            merchantName: resolution.merchant.name)
    else { return false }

    return identityStore.record(
        alias: purchase.displayMerchant,
        merchantID: canonical.merchant.id,
        sourceFingerprint: "wallet:\(eventID)",
        observedAt: purchase.createdAt)
}
