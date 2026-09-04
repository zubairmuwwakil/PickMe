import Foundation

/// The `regionId` a Radar scan records.
///
/// A scan crosses no boundary and belongs to no geofence, but the field log keys engagement and
/// correction on a region string, so scans need one. A constant rather than a nil column: it keeps
/// the export's one identity field total, and it groups scans the way a plaza groups arrivals.
public let radarFieldRegionId = "radar"

/// One foreground Radar scan, as the field log records it.
///
/// Pure, and in `Store` rather than beside the MapKit call, for the reason the whole subsystem is
/// split that way: the part worth testing is which storefronts were on the table, what each of
/// them resolved to, and how separable they were — none of which needs CoreLocation. `App` supplies
/// the fix and the raw response size and does nothing else.
///
/// Resolution runs through `resolveDiscoveredMerchant`, the same function the ambient ladder calls,
/// so a foreground record and a background one can be read side by side. Two paths answering "what
/// kind of place is this?" differently is one of the things this instrument exists to rule out.
///
/// - Parameters:
///   - fix: the owner's position when the scan ran. Nil records a scan that had no usable fix,
///     which is a fact about the scan, not a zero.
///   - rawResultCount: how many places MapKit returned **before** `rankNearbyPlaces` deduped
///     them. Taken as an argument because it is gone by the time this sees a list.
///   - merchants: the ranked, deduped results, in the order Radar published them. The first is the
///     one Home pointed the answer card at.
///   - frequentedKeys: merchants the owner has paid at on several separate days, keyed by
///     `PreIndexedMerchant.id`. Passed in so this stays pure — read once per scan, not per name.
public func radarFieldRecord(recordedAt: Date = .now,
                             id: UUID = UUID(),
                             fix: ArrivalFix?,
                             rawResultCount: Int,
                             merchants: [NearbyPlace],
                             frequentedKeys: Set<String> = []) -> ArrivalFieldRecord {
    let candidates = merchants.map { merchant -> ArrivalCandidateRecord in
        let resolution = resolveDiscoveredMerchant(name: merchant.name,
                                                   poiCategoryRaw: merchant.poiCategoryRaw,
                                                   frequentedKeys: frequentedKeys)
        let indexed = MerchantRecognizer.recognise(merchant.name)
        return ArrivalCandidateRecord(
            name: merchant.name,
            poiCategoryRaw: merchant.poiCategoryRaw,
            latitude: merchant.latitude,
            longitude: merchant.longitude,
            // Measured from the owner, not carried over from `NearbyPlace.distanceMeters`.
            // That field is MapKit's distance from whatever centre the query used, and a scan
            // reused from the movement cache was queried around a different point.
            distanceFromFixMeters: fix.map {
                greatCircleDistanceMeters(fromLatitude: $0.latitude, fromLongitude: $0.longitude,
                                          toLatitude: merchant.latitude,
                                          toLongitude: merchant.longitude)
            },
            recognisedByPack: indexed != nil,
            resolvedCategory: resolution.prediction.category,
            confidence: resolution.confidence,
            preIndexMerchantId: indexed?.id)
    }

    return ArrivalFieldRecord(
        radarScanAt: recordedAt, id: id, fix: fix, rawResultCount: rawResultCount,
        candidates: candidates,
        // The ambient path's own margin function, unchanged. Parity is the point: Radar is tapped
        // far more often than a geofence is crossed, so it is the densest source of margins in the
        // build, and a margin computed differently could not be pooled with the arrivals it is
        // meant to explain.
        discriminability: discriminability(candidates: candidates.map(\.site), fix: fix))
}
