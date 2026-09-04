import Foundation
import CardCopilotEngine

/// One nearby physical merchant that satisfies an alternate route's acquisition MCC according to
/// the learning MCC graph. Gift-card inventory remains a separate prediction because an MCC says
/// nothing about what is currently stocked at this location.
public struct PurchaseRouteAcquisitionCandidate: Equatable, Sendable {
    public let place: NearbyPlace
    public let seed: MerchantMCCSeedMatch
    public let prediction: MerchantMCCPrediction
    public let inventoryPrediction: GiftCardInventoryPrediction

    public var distanceMeters: Double? { place.distanceMeters }
    public var mcc: Int? { prediction.bestMCC }
    public var confidence: Double { prediction.confidence }
    public var hasActionableInventory: Bool { inventoryPrediction.isActionableAvailable }
}

/// Bridges MapKit's nearby physical places to the canonical 500-merchant seed and then through the
/// evidence-weighting graph. Reconciled owner MCCs can override the seed automatically. Inventory
/// evidence is evaluated independently and can only strengthen/suppress the exact physical place.
///
/// This is deliberately Store-side: Engine owns card/route arithmetic; Store owns merchant
/// identity, place IDs, coordinates and local evidence composition.
public enum PurchaseRouteAcquisitionResolver {
    public static func candidates(
        for route: AlternativePurchaseRoute,
        nearby places: [NearbyPlace],
        purchases: [StoredPurchase] = [],
        inventoryEvidence: [GiftCardInventoryObservation] = [],
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

            let inventoryQuery = GiftCardInventoryQuery(
                merchantKey: seed.merchant.name,
                placeID: place.placeID,
                latitude: place.hasMonitorableLocation ? place.latitude : nil,
                longitude: place.hasMonitorableLocation ? place.longitude : nil,
                instrumentKey: route.instrumentLabel)
            let inventory = GiftCardInventoryGraph.predict(for: inventoryQuery,
                                                           evidence: inventoryEvidence,
                                                           now: now)
            // A fresh, confident miss is stronger evidence than a generic MCC-compatible route.
            // Because negative inventory evidence decays in days, a temporary stockout does not
            // blacklist the location indefinitely.
            guard inventory.state != .unavailable else { return nil }

            return PurchaseRouteAcquisitionCandidate(place: place,
                                                      seed: seed,
                                                      prediction: prediction,
                                                      inventoryPrediction: inventory)
        }
        .sorted(by: candidateOrder)
        .prefix(max(0, limit))
        .map { $0 }
    }

    /// Turns a generic route template into a physical nearby route. Card selection is still left
    /// to `PurchaseRouteAdvisor` / `RecommendationEngine`; this only resolves merchant facts.
    public static func resolvedRoute(
        from template: AlternativePurchaseRoute,
        candidate: PurchaseRouteAcquisitionCandidate,
        now: Date = Date()
    ) -> AlternativePurchaseRoute {
        let pct = Int((candidate.confidence * 100).rounded())
        let evidenceText = candidate.prediction.isObserved
            ? "local reconciled MCC evidence"
            : "seed/community MCC evidence"
        let merchantLabel = acquisitionLabel(for: candidate)
        let inventoryText = inventoryDisclosure(for: candidate.inventoryPrediction, now: now)
        return AlternativePurchaseRoute(
            routeId: "\(template.routeId):\(candidate.seed.merchant.id)",
            destinationMerchantAliases: template.destinationMerchantAliases,
            instrumentLabel: template.instrumentLabel,
            acquisitionMerchantLabel: merchantLabel,
            acquisitionCategory: template.acquisitionCategory,
            acquisitionMcc: candidate.mcc,
            acquisitionMerchantBrand: candidate.seed.merchantBrand,
            acceptedNetworks: candidate.seed.acceptedNetworks,
            fixedFeeCad: template.fixedFeeCad,
            estimatedFrictionCad: template.estimatedFrictionCad,
            evidenceLevel: template.evidenceLevel,
            disclosure: "Nearby merchant MCC uses \(evidenceText) (\(pct)% graph confidence), not a chain-wide guarantee. \(inventoryText) Issuer reward treatment can still vary by transaction."
        )
    }

    private static func inventoryDisclosure(for prediction: GiftCardInventoryPrediction,
                                            now: Date) -> String {
        guard prediction.isActionableAvailable else {
            return "Gift-card inventory has not yet been confirmed at this location."
        }
        let pct = Int((prediction.confidence * 100).rounded())
        guard let observedAt = prediction.latestObservedAt else {
            return "Gift-card inventory was recently observed here (\(pct)% confidence)."
        }
        let days = max(0, Int(now.timeIntervalSince(observedAt) / 86_400))
        let age = days == 0 ? "today" : (days == 1 ? "1 day ago" : "\(days) days ago")
        return "Gift-card inventory was observed here \(age) (\(pct)% inventory confidence)."
    }

    private static func acquisitionLabel(for candidate: PurchaseRouteAcquisitionCandidate) -> String {
        guard let metres = candidate.distanceMeters, metres >= 0 else { return candidate.place.name }
        if metres < 1_000 {
            return "\(candidate.place.name) (\(Int(metres.rounded())) m away)"
        }
        return String(format: "%@ (%.1f km away)", candidate.place.name, metres / 1_000)
    }

    private static func candidateOrder(_ lhs: PurchaseRouteAcquisitionCandidate,
                                       _ rhs: PurchaseRouteAcquisitionCandidate) -> Bool {
        // Inventory-confirmed routes are more actionable than a closer store whose rack is unknown.
        if lhs.hasActionableInventory != rhs.hasActionableInventory {
            return lhs.hasActionableInventory
        }

        switch (lhs.distanceMeters, rhs.distanceMeters) {
        case let (l?, r?) where l != r:
            return l < r
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        default:
            if lhs.inventoryPrediction.confidence != rhs.inventoryPrediction.confidence {
                return lhs.inventoryPrediction.confidence > rhs.inventoryPrediction.confidence
            }
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            return lhs.place.name.localizedCaseInsensitiveCompare(rhs.place.name) == .orderedAscending
        }
    }
}
