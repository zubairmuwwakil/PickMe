import Foundation
import CardCopilotEngine

/// One nearby physical merchant that satisfies an alternate route's acquisition MCC according to
/// the learning MCC graph. `prediction` remains a prediction; callers must not label it observed
/// unless `prediction.isObserved` says actual owner evidence has won.
public struct PurchaseRouteAcquisitionCandidate: Equatable, Sendable {
    public let place: NearbyPlace
    public let seed: MerchantMCCSeedMatch
    public let prediction: MerchantMCCPrediction

    public var distanceMeters: Double? { place.distanceMeters }
    public var mcc: Int? { prediction.bestMCC }
    public var confidence: Double { prediction.confidence }
}

/// Bridges MapKit's nearby physical places to the canonical 500-merchant seed and then through the
/// evidence-weighting graph. Reconciled owner MCCs can override the seed automatically.
///
/// This is deliberately Store-side: Engine owns card/route arithmetic; Store owns merchant
/// identity, place IDs, coordinates and local evidence composition.
public enum PurchaseRouteAcquisitionResolver {
    public static func candidates(
        for route: AlternativePurchaseRoute,
        nearby places: [NearbyPlace],
        purchases: [StoredPurchase] = [],
        limit: Int = 3,
        now: Date = Date()
    ) -> [PurchaseRouteAcquisitionCandidate] {
        guard let requiredMCC = route.acquisitionMcc else { return [] }
        let ownerEvidence = MerchantMCCGraphEvidenceBuilder.evidence(from: purchases)

        return places.compactMap { place -> PurchaseRouteAcquisitionCandidate? in
            guard let seed = MerchantMCCSeedCatalogue.match(merchantName: place.name) else {
                return nil
            }

            let query = MerchantMCCQuery(
                merchantKey: seed.merchant.name,
                placeID: place.placeID,
                latitude: place.hasMonitorableLocation ? place.latitude : nil,
                longitude: place.hasMonitorableLocation ? place.longitude : nil,
                channel: .inStore)
            let prediction = MerchantMCCGraph.predict(
                for: query,
                seedMCC: seed.profile.primaryMcc,
                evidence: MerchantMCCSeedCatalogue.externalEvidence(for: seed.merchant) + ownerEvidence,
                now: now)
            guard prediction.bestMCC == requiredMCC else { return nil }

            return PurchaseRouteAcquisitionCandidate(place: place, seed: seed,
                                                      prediction: prediction)
        }
        .sorted(by: candidateOrder)
        .prefix(max(0, limit))
        .map { $0 }
    }

    /// Turns a generic route template into a physical nearby route. Card selection is still left
    /// to `PurchaseRouteAdvisor` / `RecommendationEngine`; this only resolves merchant facts.
    public static func resolvedRoute(
        from template: AlternativePurchaseRoute,
        candidate: PurchaseRouteAcquisitionCandidate
    ) -> AlternativePurchaseRoute {
        let pct = Int((candidate.confidence * 100).rounded())
        let evidenceText = candidate.prediction.isObserved
            ? "local reconciled MCC evidence"
            : "seed/community MCC evidence"
        return AlternativePurchaseRoute(
            routeId: "\(template.routeId):\(candidate.seed.merchant.id)",
            destinationMerchantAliases: template.destinationMerchantAliases,
            instrumentLabel: template.instrumentLabel,
            acquisitionMerchantLabel: candidate.place.name,
            acquisitionCategory: template.acquisitionCategory,
            acquisitionMcc: candidate.mcc,
            acquisitionMerchantBrand: candidate.seed.merchantBrand,
            acceptedNetworks: candidate.seed.acceptedNetworks,
            fixedFeeCad: template.fixedFeeCad,
            estimatedFrictionCad: template.estimatedFrictionCad,
            evidenceLevel: template.evidenceLevel,
            disclosure: "\(template.disclosure) Nearby merchant MCC uses \(evidenceText) (\(pct)% graph confidence), not a chain-wide guarantee."
        )
    }

    private static func candidateOrder(_ lhs: PurchaseRouteAcquisitionCandidate,
                                       _ rhs: PurchaseRouteAcquisitionCandidate) -> Bool {
        switch (lhs.distanceMeters, rhs.distanceMeters) {
        case let (l?, r?) where l != r:
            return l < r
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        default:
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            return lhs.place.name.localizedCaseInsensitiveCompare(rhs.place.name) == .orderedAscending
        }
    }
}
