import Foundation

/// A place found near the owner, or matched by manual text search. MapKit-free by design —
/// this is the shape `LiveMerchantProvider` (App target) maps `MKMapItem` into.
public struct NearbyMerchant: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let poiCategoryRaw: String?
    public let merchantCategoryCode: Int?
    public let latitude: Double
    public let longitude: Double
    public let distanceMeters: Double?

    public init(id: String, name: String, poiCategoryRaw: String?, merchantCategoryCode: Int? = nil,
                latitude: Double, longitude: Double, distanceMeters: Double?) {
        self.id = id
        self.name = name
        self.poiCategoryRaw = poiCategoryRaw
        self.merchantCategoryCode = merchantCategoryCode
        self.latitude = latitude
        self.longitude = longitude
        self.distanceMeters = distanceMeters
    }
}

/// Merchant lookup, kept behind a protocol so engine-facing code never depends on MapKit
/// directly. `search` takes no location — it is the mandatory manual fallback (Apple
/// guideline 5.1.1) and must work whether or not location was ever granted.
public protocol MerchantProviding: Sendable {
    func nearby(latitude: Double, longitude: Double) async throws -> [NearbyMerchant]
    func search(text: String) async throws -> [NearbyMerchant]
}

/// Orders merchants by distance (closest first, unknown distance last), breaks ties by
/// name, and keeps only the closest copy of each id — a POI search and a brand search can
/// both surface the same place.
public func rankNearbyMerchants(_ merchants: [NearbyMerchant]) -> [NearbyMerchant] {
    let sorted = merchants.sorted(by: isOrderedBefore)

    var seenIds = Set<String>()
    var deduped: [NearbyMerchant] = []
    for merchant in sorted {
        guard seenIds.insert(merchant.id).inserted else { continue }
        deduped.append(merchant)
    }
    return deduped
}

private func isOrderedBefore(_ lhs: NearbyMerchant, _ rhs: NearbyMerchant) -> Bool {
    switch (lhs.distanceMeters, rhs.distanceMeters) {
    case let (l?, r?) where l != r:
        return l < r
    case (nil, .some):
        return false
    case (.some, nil):
        return true
    default:
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
