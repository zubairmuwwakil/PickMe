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

/// A high-confidence join between a Wallet merchant descriptor and a nearby MapKit POI.
/// Automatic capture may act on this result because both identity and category are settled:
/// the names strongly agree, the POI is close to the captured coordinate, and MapKit maps it to
/// one unambiguous engine category.
public struct WalletMerchantResolution: Equatable, Sendable {
    public let merchant: NearbyPlace
    public let prediction: CategoryPrediction

    public init(merchant: NearbyPlace, prediction: CategoryPrediction) {
        self.merchant = merchant
        self.prediction = prediction
    }
}

/// Resolves an otherwise-unknown Wallet descriptor against places surrounding its captured GPS
/// fix. A loose keyword guess is deliberately insufficient: auto-assignment requires a strong
/// name overlap, a POI within the capture radius, and a single non-fallback category.
public func resolveWalletMerchant(capturedName: String,
                                  nearbyMerchants: [NearbyPlace],
                                  maximumDistanceMeters: Double = 150)
-> WalletMerchantResolution? {
    let captured = compactMerchantIdentity(capturedName)
    guard captured.count >= 4 else { return nil }

    let candidates = nearbyMerchants.compactMap { merchant -> WalletMerchantResolution? in
        guard let distance = merchant.distanceMeters,
              distance <= maximumDistanceMeters else { return nil }
        let nearby = compactMerchantIdentity(merchant.name)
        guard nearby.count >= 4 else { return nil }

        let shorter = captured.count <= nearby.count ? captured : nearby
        let longer = captured.count <= nearby.count ? nearby : captured
        let overlap = Double(shorter.count) / Double(longer.count)
        guard longer.contains(shorter), overlap >= 0.60 else { return nil }

        let prediction = predict(poiCategoryRaw: merchant.poiCategoryRaw,
                                 merchantName: merchant.name)
        // Deliberately does NOT require a single candidate. `CategoryMapper` forks the two
        // commonest place types on purpose — gasstation yields ["gasStation", "other"] because
        // snacks bought inside code differently — and demanding one candidate read that honesty
        // as "not confident enough", making every gas-station capture permanently unenrichable.
        // The engine already scores every candidate and collapses the fork when the branches
        // agree, so a two-element set is an answer, not a failure.
        //
        // A PRIMARY of "other" is still refused: `MKPOICategoryStore` genuinely tells us nothing,
        // and storing "other" would dress up an absence of evidence as a categorization. The
        // distance ceiling and name-overlap floor above are untouched — they bound *identity*,
        // which must stay strict. Only the category-confidence gate relaxes.
        guard prediction.confidenceSource != .fallback,
              prediction.category != "other" else { return nil }
        return WalletMerchantResolution(merchant: merchant, prediction: prediction)
    }

    return candidates.min {
        ($0.merchant.distanceMeters ?? .greatestFiniteMagnitude)
            < ($1.merchant.distanceMeters ?? .greatestFiniteMagnitude)
    }
}

/// Internal rather than private: the field log's receipt join needs the same identity notion the
/// wallet join uses, and a second normaliser is a second place for "SHOPPERS DRUG MART #1234" to
/// stop matching "Shoppers Drug Mart".
func compactMerchantIdentity(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .unicodeScalars
        .filter { CharacterSet.alphanumerics.contains($0) }
        .map(String.init)
        .joined()
        .lowercased()
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
        return DiscoveredMerchantResolution(prediction: fromPoi,
                                            confidence: unindexedConfidence(fromPoi),
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
                                       candidates: [indexed.category],
                                       merchantCategoryCode: indexed.mcc),
        confidence: frequentedKeys.contains(indexed.id) ? .frequented : .brandMatched,
        mcc: indexed.mcc)
}

/// What a POI earns when the recogniser cannot place its name.
///
/// This used to lift only `.brandPrior` out of `predict` and call everything else `.unknown` —
/// which `AmbientGate` suppresses unconditionally, so no multiplier could reach it. `predict`
/// carries a whole `.mapKitCategory` tier that maps pharmacy to drugStore, restaurant to dining,
/// gasstation to gasStation; a POI Apple confidently classifies as a pharmacy was being called
/// unknown. Meanwhile `resolveWalletMerchant`, twenty lines up this same file, already treats
/// that evidence as sufficient to categorise a real logged purchase. One file, two verdicts, one
/// class of evidence.
///
/// The tier it earns is `.categoryMatched`, not `.brandMatched`, because the two make different
/// claims: we know what kind of place this is, and we do not know which store it is. Conflating
/// those is the defect, not the fix for it.
///
/// A place type that only yields "other" is refused, on the same grounds `resolveWalletMerchant`
/// refuses it: `MKPOICategoryStore` genuinely tells us nothing, and a tier that claims the
/// category is known must not be granted on the strength of a category that says "unclassified".
private func unindexedConfidence(_ prediction: CategoryPrediction) -> AmbientMerchantConfidence {
    switch prediction.confidenceSource {
    case .brandPrior:
        return .brandMatched
    case .mapKitCategory:
        return prediction.category == "other" ? .unknown : .categoryMatched
    default:
        return .unknown
    }
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

/// What category a merchant is, from whatever evidence the app actually holds. The single entry
/// point every caller uses, so no two screens can disagree about the same purchase.
///
/// Ordered strongest-first. A literal transaction MCC remains the strongest non-owner-confirmed
/// signal. The learning graph then competes with editorial brand and MapKit priors by confidence:
/// weak bootstrap data cannot erase a better place-type signal, while repeated user-derived
/// evidence can promote the graph above a static brand prior. Graph predictions deliberately keep
/// `.brandPrior` as their source so they can never masquerade as `.observedMcc`.
///
/// Owner-confirmed categories are NOT consulted here. They outrank everything on this ladder and
/// are looked up per-caller against stored merchants — `CheckoutService.confirmedPrediction` and
/// `predictionForKnownMerchant` — because only a caller with store access can answer them.
public func resolveCategory(for merchant: NearbyPlace) -> CategoryPrediction {
    let fromSignals = predict(poiCategoryRaw: merchant.poiCategoryRaw,
                              merchantName: merchant.name,
                              merchantCategoryCode: merchant.merchantCategoryCode)

    // A real transaction MCC is already the strongest evidence available at this boundary.
    if fromSignals.confidenceSource == .observedMcc { return fromSignals }

    if let fromGraph = merchantMCCGraphPrediction(for: merchant),
       fromSignals.confidenceSource == .fallback
        || fromGraph.confidenceScore > fromSignals.confidenceScore {
        return fromGraph
    }

    guard fromSignals.confidenceSource == .fallback else { return fromSignals }
    return resolveDiscoveredMerchant(name: merchant.name,
                                     poiCategoryRaw: merchant.poiCategoryRaw).prediction
}
