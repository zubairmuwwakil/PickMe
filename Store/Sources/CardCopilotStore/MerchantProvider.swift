import Foundation

/// A place found near the owner, or matched by manual text search. MapKit-free by design —
/// this is the shape `LiveMerchantProvider` (App target) maps `MKMapItem` into.
public struct NearbyPlace: Equatable, Sendable, Identifiable {
    public let id: String
    /// Apple's persistent place identifier (`MKMapItem.Identifier.rawValue`), when this place came
    /// from a MapKit service that supplied one. Nil for pre-index taps, for stub providers, and
    /// for anything reconstructed from a stored row that predates V6.
    ///
    /// Deliberately NOT folded into `id`. `id` is the string the mute list, saved arrival
    /// preferences, `StoredPrediction.merchantIdentifier` and `StoredPurchase.merchantIdentifier`
    /// are all already keyed on; changing what it holds would move four keyspaces at once, which
    /// is the very orphan this field exists to prevent — just paid once, at upgrade, by everyone.
    /// The place id is better *evidence about* identity, and `MerchantIdentity` is what weighs it.
    public let placeID: String?
    /// Identifiers this place is also known by — ids it superseded when Apple merged or revised
    /// the record (`MKMapItem.alternateIdentifiers`). This is what makes place-id adoption actually
    /// survive a revision instead of producing a second, rarer generation of the same orphan.
    public let alternatePlaceIDs: [String]
    public let name: String
    public let poiCategoryRaw: String?
    public let merchantCategoryCode: Int?
    public let latitude: Double
    public let longitude: Double
    public let distanceMeters: Double?
    public let locationDescription: String?

    public init(id: String, placeID: String? = nil, alternatePlaceIDs: [String] = [],
                name: String, poiCategoryRaw: String?, merchantCategoryCode: Int? = nil,
                latitude: Double, longitude: Double, distanceMeters: Double?,
                locationDescription: String? = nil) {
        self.id = id
        self.placeID = placeID
        self.alternatePlaceIDs = alternatePlaceIDs
        self.name = name
        self.poiCategoryRaw = poiCategoryRaw
        self.merchantCategoryCode = merchantCategoryCode
        self.latitude = latitude
        self.longitude = longitude
        self.distanceMeters = distanceMeters
        self.locationDescription = locationDescription
    }

    /// Every identifier Apple currently considers this place to be, primary first. Empty when
    /// MapKit gave us none, which is the signal `MerchantIdentity` reads to decide whether
    /// proximity is still allowed to speak.
    public var allPlaceIDs: Set<String> {
        var ids = Set(alternatePlaceIDs.filter { !$0.isEmpty })
        if let placeID, !placeID.isEmpty { ids.insert(placeID) }
        return ids
    }

    /// Brand-only offline results have no physical place to monitor.
    public var hasMonitorableLocation: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
            && (latitude != 0 || longitude != 0)
    }
}

/// A nearby lookup's results together with the size of the response they were distilled from.
///
/// The raw count exists because `rankNearbyPlaces` dedupes, and a cap that truncates upstream
/// is invisible afterwards: eight results that are really eight and eight results that are the
/// survivors of a bounded response are different facts about a plaza, and only one of them
/// explains an anchor tenant going missing.
public struct NearbyScan: Equatable, Sendable {
    /// Ranked and deduped — what the app actually shows.
    public let places: [NearbyPlace]
    /// How many places the source returned before ranking and deduping.
    public let rawResultCount: Int
    /// Aggregate-only filter outcomes. These carry no place identity or coordinates.
    public let eligibleResultCount: Int
    public let excludedPublicTransportResultCount: Int
    public let excludedMissingCategoryResultCount: Int
    public let excludedUnsupportedCategoryResultCount: Int

    public init(places: [NearbyPlace], rawResultCount: Int,
                eligibleResultCount: Int? = nil,
                excludedPublicTransportResultCount: Int = 0,
                excludedMissingCategoryResultCount: Int = 0,
                excludedUnsupportedCategoryResultCount: Int = 0) {
        self.places = places
        self.rawResultCount = max(0, rawResultCount)
        self.eligibleResultCount = max(0, eligibleResultCount ?? places.count)
        self.excludedPublicTransportResultCount = max(0, excludedPublicTransportResultCount)
        self.excludedMissingCategoryResultCount = max(0, excludedMissingCategoryResultCount)
        self.excludedUnsupportedCategoryResultCount = max(0, excludedUnsupportedCategoryResultCount)
    }
}

/// Merchant lookup, kept behind a protocol so engine-facing code never depends on MapKit
/// directly. `search` takes no location — it is the mandatory manual fallback (Apple
/// guideline 5.1.1) and must work whether or not location was ever granted.
public protocol MerchantProviding: Sendable {
    func nearby(latitude: Double, longitude: Double) async throws -> [NearbyPlace]
    /// The same lookup, plus what the raw response held. Defaulted, because only a provider that
    /// can see the response before it is deduped has anything extra to say.
    func nearbyScan(latitude: Double, longitude: Double) async throws -> NearbyScan
    func search(text: String) async throws -> [NearbyPlace]
}

public extension MerchantProviding {
    /// Reports the ranked count as the raw one. Honest for a provider with no view of the
    /// underlying response: nothing was dropped that this provider could have seen.
    func nearbyScan(latitude: Double, longitude: Double) async throws -> NearbyScan {
        let places = try await nearby(latitude: latitude, longitude: longitude)
        return NearbyScan(places: places, rawResultCount: places.count)
    }
}

/// Orders places by distance (closest first, unknown distance last), breaks ties by
/// name, and keeps only the closest copy of each id — a POI search and a brand search can
/// both surface the same place.
public func rankNearbyPlaces(_ places: [NearbyPlace]) -> [NearbyPlace] {
    let sorted = places.sorted(by: isOrderedBefore)

    var seenIds = Set<String>()
    var deduped: [NearbyPlace] = []
    for place in sorted {
        guard seenIds.insert(place.id).inserted else { continue }
        deduped.append(place)
    }
    return deduped
}

private func isOrderedBefore(_ lhs: NearbyPlace, _ rhs: NearbyPlace) -> Bool {
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

public extension NearbyPlace {
    /// A pre-index row the owner tapped, projected onto the shape the rest of the app scores.
    ///
    /// Lives here, once, because it used to live twice — in `HomeView`'s offline dropdown and in
    /// `LiveMerchantProvider.fallbackSearch` — and both copies made the same mistake: they passed
    /// the row's canonical taxonomy category (`grocery`, `dining`) as `poiCategoryRaw`, which
    /// means Apple's place-type vocabulary. Two vocabularies sharing one `String?` compiles
    /// cleanly and fails silently, so the POI signal is set here and nowhere else.
    ///
    /// `poiCategoryRaw` is deliberately nil: a pre-index tap carries no MapKit signal at all, and
    /// saying otherwise is what discarded the category. `merchantCategoryCode` is also nil: that
    /// slot is evidence observed from the owner's transaction, while the pack's MCC is editorial.
    /// The exact tapped brand stays recoverable from `name` through `MerchantRecognizer`, which
    /// carries the editorial MCC on a `.brandPrior` prediction without upgrading its provenance.
    ///
    /// Coordinates are zero because the owner named a brand, not a place. Nothing is written to
    /// the store until they ask for the breakdown, which keeps a merchant with no real location
    /// out of the merchant table.
    init(preIndexed merchant: PreIndexedMerchant) {
        self.init(id: "preindex:\(merchant.id)",
                  name: merchant.name,
                  poiCategoryRaw: nil,
                  merchantCategoryCode: nil,
                  latitude: 0,
                  longitude: 0,
                  distanceMeters: nil)
    }
}
