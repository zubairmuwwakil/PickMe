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
    public let locationDescription: String?

    public init(id: String, name: String, poiCategoryRaw: String?, merchantCategoryCode: Int? = nil,
                latitude: Double, longitude: Double, distanceMeters: Double?,
                locationDescription: String? = nil) {
        self.id = id
        self.name = name
        self.poiCategoryRaw = poiCategoryRaw
        self.merchantCategoryCode = merchantCategoryCode
        self.latitude = latitude
        self.longitude = longitude
        self.distanceMeters = distanceMeters
        self.locationDescription = locationDescription
    }

    /// Brand-only offline results have no physical place to monitor.
    public var hasMonitorableLocation: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
            && (latitude != 0 || longitude != 0)
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

public extension NearbyMerchant {
    /// A pre-index row the owner tapped, projected onto the shape the rest of the app scores.
    ///
    /// Lives here, once, because it used to live twice — in `HomeView`'s offline dropdown and in
    /// `LiveMerchantProvider.fallbackSearch` — and both copies made the same mistake: they passed
    /// the row's canonical taxonomy category (`grocery`, `dining`) as `poiCategoryRaw`, which
    /// means Apple's place-type vocabulary, and dropped `mcc`. Two vocabularies sharing one
    /// `String?` compiles cleanly and fails silently, so the two fields are set here and nowhere
    /// else.
    ///
    /// `poiCategoryRaw` is deliberately nil: a pre-index tap carries no MapKit signal at all, and
    /// saying otherwise is what discarded the category. The row's own facts travel as `mcc`, and
    /// the brand itself stays recoverable from `name` through `MerchantRecognizer`.
    ///
    /// Coordinates are zero because the owner named a brand, not a place. Nothing is written to
    /// the store until they ask for the breakdown, which keeps a merchant with no real location
    /// out of the merchant table.
    init(preIndexed merchant: PreIndexedMerchant) {
        self.init(id: "preindex:\(merchant.id)",
                  name: merchant.name,
                  poiCategoryRaw: nil,
                  merchantCategoryCode: merchant.mcc,
                  latitude: 0,
                  longitude: 0,
                  distanceMeters: nil)
    }
}
