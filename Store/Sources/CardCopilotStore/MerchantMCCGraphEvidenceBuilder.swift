import Foundation

/// Bridges PickMe's existing append-only reconciliation history into the MCC graph.
///
/// No second persistence model is needed: every reconciled `StoredObservation` already retains an
/// explicit `observedMerchantCategoryCode` when one was genuinely supplied. Rebuilding evidence
/// from that history preserves conflicting observations instead of overwriting the merchant with
/// whichever MCC happened to be seen last.
public enum MerchantMCCGraphEvidenceBuilder {
    public static func evidence(from purchases: [StoredPurchase]) -> [MerchantMCCEvidence] {
        purchases.compactMap { purchase in
            guard let observation = purchase.observation else { return nil }
            let canonicalName = MerchantRecognizer.recognise(purchase.displayMerchant)?.name
                ?? purchase.displayMerchant

            if let mcc = observation.observedMerchantCategoryCode {
                return MerchantMCCEvidence(
                    id: "observation:\(observation.id.uuidString)",
                    merchantKey: canonicalName,
                    latitude: purchase.merchantLatitude,
                    longitude: purchase.merchantLongitude,
                    mcc: mcc,
                    category: observation.observedCategory,
                    kind: .directOwnerMcc,
                    sourceConfidence: 1,
                    observedAt: observation.confirmedAt,
                    sourceReference: "storedObservation:\(observation.id.uuidString)")
            }

            // Category feedback still matters to the broader learner, but this evidence has no
            // literal MCC. `MerchantMCCGraph` deliberately refuses to turn it into one.
            return MerchantMCCEvidence(
                id: "category:\(observation.id.uuidString)",
                merchantKey: canonicalName,
                latitude: purchase.merchantLatitude,
                longitude: purchase.merchantLongitude,
                category: observation.observedCategory,
                kind: .categoryOutcome,
                sourceConfidence: observation.categoryConfidenceScore ?? 1,
                observedAt: observation.confirmedAt,
                sourceReference: "storedObservation:\(observation.id.uuidString)")
        }
    }

    /// Convenience entry point for checkout callers: seed with editorial data, then let actual
    /// reconciled observations compete with it. A current MapKit place contributes identity only;
    /// it never creates MCC evidence on its own.
    public static func predict(for merchant: NearbyPlace, seedMCC: Int?,
                               purchases: [StoredPurchase], now: Date = Date())
        -> MerchantMCCPrediction {
        let canonicalName = MerchantRecognizer.recognise(merchant.name)?.name ?? merchant.name
        let query = MerchantMCCQuery(
            merchantKey: canonicalName,
            placeID: merchant.placeID,
            latitude: merchant.hasMonitorableLocation ? merchant.latitude : nil,
            longitude: merchant.hasMonitorableLocation ? merchant.longitude : nil)
        return MerchantMCCGraph.predict(for: query, seedMCC: seedMCC,
                                        evidence: evidence(from: purchases), now: now)
    }
}
