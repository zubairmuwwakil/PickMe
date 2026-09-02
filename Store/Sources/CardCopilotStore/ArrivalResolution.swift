import Foundation

/// A one-shot location fix taken because the owner just crossed into a monitored area.
///
/// Deliberately its own type rather than a `CLLocation`: this half of arrival resolution is pure
/// policy and must stay testable without CoreLocation, and the accuracy figure is not decoration —
/// the discriminability margin is meaningless without it, since a 12 m gap between two storefronts
/// says nothing when the fix itself is good to ±65 m.
public struct ArrivalFix: Equatable, Sendable, Codable {
    public let latitude: Double
    public let longitude: Double
    /// The radius of the 68% confidence circle iOS reports. Negative means invalid, which
    /// CoreLocation does emit; callers should treat such a fix as no fix at all.
    public let horizontalAccuracyMeters: Double
    public let capturedAt: Date

    public init(latitude: Double, longitude: Double, horizontalAccuracyMeters: Double,
                capturedAt: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.capturedAt = capturedAt
    }
}

/// A candidate storefront reduced to the only thing ordering needs.
///
/// Ordering takes these rather than `AreaMember` because `AreaMember` is a `@Model`: pulling
/// SwiftData into the decision would put the one part of resolution worth unit-testing behind a
/// persistent container.
public struct ArrivalSite: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// The point an arrival is measured from: the owner's own fix when one landed, the area centroid
/// otherwise.
///
/// The centroid was the only answer before, and it is wrong for rung 1 in a way that silently
/// defeated owner confirmation: areas run to `maximumAreaRadiusMeters`, so a confirmed store near
/// the edge of a plaza was never within `verifiedMerchantRadiusMeters` of the middle of it.
public func arrivalOrigin(fix: ArrivalFix?, areaCentroidLatitude: Double,
                          areaCentroidLongitude: Double) -> ArrivalSite {
    guard let fix else {
        return ArrivalSite(latitude: areaCentroidLatitude, longitude: areaCentroidLongitude)
    }
    return ArrivalSite(latitude: fix.latitude, longitude: fix.longitude)
}

/// Indices of `sites` ordered nearest-first from the owner's fix; the input order unchanged when
/// there is no fix.
///
/// Returns indices rather than reordered sites so the caller can carry parallel arrays — a member
/// and its resolution — through one ordering decision instead of two.
///
/// The tie-break on the original index is load-bearing. `clusterIntoAreas` sorts its members by
/// `(latitude, longitude, id)` to keep geofence registration stable across rotations, and that
/// sort silently became the *resolution* answer, which is the whole defect this replaces. The sort
/// there must not change; the ordering here must be equally total, or two wakes at one plaza could
/// name two different stores from the same evidence.
public func nearestFirstOrder(_ sites: [ArrivalSite], from fix: ArrivalFix?) -> [Int] {
    guard let fix else { return Array(sites.indices) }
    return sites.indices
        .map { index -> (index: Int, distance: Double) in
            (index, greatCircleDistanceMeters(fromLatitude: fix.latitude,
                                              fromLongitude: fix.longitude,
                                              toLatitude: sites[index].latitude,
                                              toLongitude: sites[index].longitude))
        }
        .sorted { ($0.distance, $0.index) < ($1.distance, $1.index) }
        .map(\.index)
}
