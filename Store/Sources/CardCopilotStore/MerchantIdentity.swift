import Foundation

/// How a stored merchant is recognised again on a later encounter.
///
/// There used to be one rung: `#Predicate { $0.identifier == id }`, where `identifier` is
/// `"\(name)@\(latitude),\(longitude)"`. That is string equality over a full-precision float
/// rendering, so it does not need Apple to relocate a storefront — it needs any change at all to
/// either coordinate, or to the display name ("Metro" becoming "Metro Plus"). When it broke, the
/// owner's `confirmedCategory` stopped being found, the checkout fell back to a POI guess, and
/// nothing anywhere reported a problem. That is the failure this file exists to end.
///
/// Twenty lines away in `ArrivalAlertPreferenceStore.matchesLocation`, the same repository already
/// solved the same problem the right way — identifier first, then a proximity fallback. The ladder
/// below is that idea with Apple's persistent place id added on top, and it is deliberately the
/// only place merchant identity is decided, so no two screens can disagree about which store the
/// owner is standing in.
public enum MerchantIdentity {

    /// How much coordinate drift still counts as the same storefront.
    ///
    /// The same 100 m `ArrivalAlertPreference.matchesLocation` has trusted for exactly this
    /// question since arrival preferences shipped. Reusing the number rather than picking a new
    /// one keeps a single answer to "did the pin move, or is this a different shop" — two
    /// constants would eventually disagree, and the disagreement would show up as an arrival alert
    /// firing for a merchant the checkout screen thinks is someone else.
    public static let proximityMeters: Double = 100

    /// Which rung answered. Returned rather than logged so the caller can decide what to do with
    /// it — `.placeID` needs no backfill, the weaker two do.
    ///
    /// Measured against live MapKit, 2026-09-03: of 194 places returned for 100 m sweeps at four
    /// Canadian high streets, 172 carried an `identifier` — about 89%, and none carried an
    /// alternate. Two things follow.
    ///
    /// The weaker rungs are permanent, not transitional. Roughly one place in nine has no id at
    /// all, so "it heals to rung 1 next time the owner is there" is true for most merchants and
    /// never true for the rest; rungs 2 and 3 carry real traffic forever and must not be treated
    /// as migration scaffolding to be removed later.
    ///
    /// Coverage is not uniform. Toronto sampled 94-100%, Montreal 64%. The nil-id places skew
    /// toward user-contributed and misspelt records, which is where an independent merchant lives —
    /// exactly the population `local:` activity keys serve. One sample at four points on one day,
    /// so treat the ratio as an order of magnitude rather than a figure.
    public enum MatchRung: String, Sendable, Equatable {
        /// Apple's persistent place identifier agreed. Survives pin revisions by construction.
        case placeID
        /// The legacy `name@lat,lon` string matched exactly. Every row written before V6 lands here.
        case legacyIdentifier
        /// Same normalized name, within `proximityMeters`. The rung that rescues a nudged pin.
        case nameAndProximity
    }

    public struct Match {
        public let merchant: StoredMerchant
        public let rung: MatchRung
    }

    /// The one merchant in `merchants` that is this place, or nil.
    ///
    /// Strongest evidence first, and it short-circuits: a place-id agreement is not improved by
    /// also being nearby, and a legacy-identifier agreement must not be overruled by a closer
    /// same-named neighbour.
    public static func match(_ place: NearbyPlace, in merchants: [StoredMerchant]) -> Match? {
        let incomingPlaceIDs = place.allPlaceIDs
        if !incomingPlaceIDs.isEmpty,
           let hit = merchants.first(where: { stored in
               stored.placeID.map(incomingPlaceIDs.contains) ?? false
           }) {
            return Match(merchant: hit, rung: .placeID)
        }

        if let hit = merchants.first(where: { $0.identifier == place.id }) {
            return Match(merchant: hit, rung: .legacyIdentifier)
        }

        guard place.hasMonitorableLocation else { return nil }
        let wanted = compactMerchantIdentity(place.name)
        guard !wanted.isEmpty else { return nil }

        // Nearest wins, but only among rows this rung is allowed to speak for. A stored row that
        // already carries a place id, matched against an incoming place that also carries one,
        // was settled two rungs up: Apple has told us these are different places, and proximity
        // must not overrule that. Without this guard the two Tim Hortons at either end of one
        // mall would merge the moment both were identified.
        return merchants
            .filter { stored in
                guard stored.latitude != 0 || stored.longitude != 0 else { return false }
                guard compactMerchantIdentity(stored.name) == wanted else { return false }
                if stored.placeID != nil && !incomingPlaceIDs.isEmpty { return false }
                return true
            }
            .map { stored in
                (stored, greatCircleDistanceMeters(fromLatitude: place.latitude,
                                                   fromLongitude: place.longitude,
                                                   toLatitude: stored.latitude,
                                                   toLongitude: stored.longitude))
            }
            .filter { $0.1 <= proximityMeters }
            .min { $0.1 < $1.1 }
            .map { Match(merchant: $0.0, rung: .nameAndProximity) }
    }

    /// Records the place id on a row that was found by a weaker rung.
    ///
    /// This is the whole migration. There is no offline map from a legacy `name@lat,lon` string to
    /// an `MKMapItem.Identifier`, and a migration stage that went looking for one would be issuing
    /// a network search per stored merchant, for a place that may have closed, with no way to tell
    /// a correct answer from the shop next door. So nothing is rewritten at upgrade: a row heals
    /// the next time the owner is genuinely standing there and MapKit hands us the id for free.
    ///
    /// Deliberately never overwrites an id that is already present. A row whose place id disagrees
    /// with the incoming one should not have matched at all — and if it somehow did, silently
    /// re-pointing owner-confirmed history at a different Apple place is the last thing to do
    /// about it.
    ///
    /// The caller saves. Returns whether anything changed, so a read path does not write.
    @discardableResult
    public static func backfill(_ merchant: StoredMerchant, from place: NearbyPlace) -> Bool {
        guard merchant.placeID == nil, let placeID = place.placeID, !placeID.isEmpty else {
            return false
        }
        merchant.placeID = placeID
        return true
    }
}
