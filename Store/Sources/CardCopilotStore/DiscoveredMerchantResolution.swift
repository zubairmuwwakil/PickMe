import Foundation
import CardCopilotEngine

/// What a discovered POI is, and how much of that the app is willing to act on.
public struct DiscoveredMerchantResolution: Equatable, Sendable {
    public let prediction: CategoryPrediction
    public let confidence: AmbientMerchantConfidence
    /// The indexed merchant category code, when the name resolved to a known merchant. Better
    /// evidence than a MapKit POI category, which describes a *kind of place* rather than how a
    /// charge will actually code.
    public let mcc: Int?
}

/// Rung 2 of the arrival ladder: a POI the owner has no history with.
///
/// This used to ask `canonicalEngineBrand`, a six-token vocabulary — costco, walmart,
/// canadian-tire, marriott, loblaws, netflix — that exists to join a purchase to the catalogue's
/// scoring predicates. Borrowing it to answer "do we know what this store is" made every other
/// merchant in Canada `.unknown`, which `AmbientGate` suppresses unconditionally and which no
/// multiplier can reach. Two different questions were sharing one answer.
///
/// Recognition now runs against `CanadianMerchantPreIndex` (127 rows, each carrying a category
/// and an MCC), which is what that question actually needs.
/// `frequentedKeys` carries the merchants the owner has paid at on several separate days, keyed
/// by `PreIndexedMerchant.id`. Passed in rather than read here so this stays a pure decision: the
/// caller reads the counter once per arrival, not once per candidate name.
public func resolveDiscoveredMerchant(name: String,
                                      poiCategoryRaw: String?,
                                      frequentedKeys: Set<String> = []) -> DiscoveredMerchantResolution {
    let fromPoi = predict(poiCategoryRaw: poiCategoryRaw, merchantName: name)

    guard let indexed = MerchantRecognizer.recognise(name) else {
        // A seed prior in `CategoryMapper` is the same class of evidence as an index row — a
        // name resolving to a known brand — so it reaches the same tier. Which of the two lists
        // happens to hold a brand is an implementation detail and must not decide whether the
        // app is allowed to speak.
        return DiscoveredMerchantResolution(
            prediction: fromPoi,
            confidence: fromPoi.confidenceSource == .brandPrior ? .brandMatched : .unknown,
            mcc: nil)
    }

    // An index row categorised "other" names the brand without settling how it codes — the
    // Walmart case the 2026-08-15 dossier deliberately leaves forked, since a Supercentre codes
    // grocery and a discount store codes general merchandise. Identity is still established, so
    // the tier stands; the category question goes back to the POI signal and keeps its fork.
    guard indexed.category != "other" else {
        // Patronage deliberately does not lift this branch. `.frequented` fires at the owner's
        // own threshold, which is only defensible while the category is checkable; a forked row
        // leaves the coding to a POI guess, so identity is established and the bar stays where
        // an unverified guess belongs.
        return DiscoveredMerchantResolution(prediction: fromPoi, confidence: .brandMatched,
                                            mcc: indexed.mcc)
    }

    return DiscoveredMerchantResolution(
        prediction: CategoryPrediction(category: indexed.category,
                                       confidenceSource: .brandPrior,
                                       candidates: [indexed.category]),
        confidence: frequentedKeys.contains(indexed.id) ? .frequented : .brandMatched,
        mcc: indexed.mcc)
}

/// Rung 1 of the arrival ladder: a merchant already stored on this device.
///
/// Reconciliation against a statement is still the only route to `.verified` — the truth graph's
/// terminal-specific promotion rule is untouched. What changes is the fallback. A stored merchant
/// the owner has never reconciled used to resolve to `.unknown`, which `AmbientGate` suppresses
/// unconditionally; and because `rotateRegions` spends one of twenty geofence slots on each
/// uncovered stored merchant, that slot bought a guaranteed silence. Absent reconciliation, a
/// stored merchant should be worth at least what the same name is worth as a discovered POI.
public func resolveStoredMerchant(name: String, poiCategoryRaw: String?,
                                  confirmedCategory: String?,
                                  confirmationCount: Int,
                                  frequentedKeys: Set<String> = []) -> DiscoveredMerchantResolution {
    guard let confirmedCategory else {
        return resolveDiscoveredMerchant(name: name, poiCategoryRaw: poiCategoryRaw,
                                         frequentedKeys: frequentedKeys)
    }
    return DiscoveredMerchantResolution(
        prediction: CategoryPrediction(
            category: confirmedCategory,
            confidenceSource: confirmationCount >= 2 ? .repeatedTerminal : .ownerConfirmedTerminal,
            candidates: [confirmedCategory]),
        confidence: .verified,
        mcc: MerchantRecognizer.recognise(name)?.mcc)
}
