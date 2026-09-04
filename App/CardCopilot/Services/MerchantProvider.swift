import CardCopilotStore
import CoreLocation
@preconcurrency import MapKit

/// MapKit-backed `MerchantProviding`. `nearby` stays inside a small radius, so a result
/// means "the place you're standing in," not "the whole block." `search` carries no
/// location bias — it's the Apple guideline 5.1.1 fallback and must work with zero
/// location access.
final class LiveMerchantProvider: MerchantProviding {
    /// Large enough for storefront pins placed at a building centroid, but small enough that
    /// "nearby" still means the place the owner could plausibly be checking out at.
    private static let nearbyRadiusMeters: CLLocationDistance = 100

    /// Must mirror `isRadarEligiblePOICategory`. The MapKit filter prevents irrelevant places
    /// from consuming its bounded response; the shared Store policy below is the defensive gate.
    private static let radarPOICategories: [MKPointOfInterestCategory] = [
        .bakery,
        .cafe,
        .carRental,
        .evCharger,
        .fitnessCenter,
        .foodMarket,
        .gasStation,
        .hotel,
        .movieTheater,
        .pharmacy,
        .restaurant,
        .store,
    ]

    func nearby(latitude: Double, longitude: Double) async throws -> [NearbyPlace] {
        try await nearbyScan(latitude: latitude, longitude: longitude).places
    }

    /// The only place that can see how large MapKit's response was before `rankNearbyPlaces`
    /// dedupes it, so it is the only place that can report it. A 100 m sweep over checkout-eligible
    /// categories returns a bounded set, and whether a plaza's anchor tenant was crowded out of
    /// that set or merely outranked inside it is the question the field log exists to settle.
    func nearbyScan(latitude: Double, longitude: Double) async throws -> NearbyScan {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let request = MKLocalPointsOfInterestRequest(center: center, radius: Self.nearbyRadiusMeters)
        request.pointOfInterestFilter = MKPointOfInterestFilter(
            including: Self.radarPOICategories)
        let search = MKLocalSearch(request: request)
        let response = try await withTaskCancellationHandler {
            try await search.start()
        } onCancel: {
            search.cancel()
        }
        var eligibleResultCount = 0
        var excludedPublicTransportResultCount = 0
        var excludedMissingCategoryResultCount = 0
        var excludedUnsupportedCategoryResultCount = 0
        let mapped = response.mapItems.compactMap { item -> NearbyPlace? in
            switch radarPOIExclusionReason(item.pointOfInterestCategory?.rawValue) {
            case nil:
                eligibleResultCount += 1
            case .some(.publicTransport):
                excludedPublicTransportResultCount += 1
                return nil
            case .some(.missingCategory):
                excludedMissingCategoryResultCount += 1
                return nil
            case .some(.unsupportedCategory):
                excludedUnsupportedCategoryResultCount += 1
                return nil
            }
            return Self.nearbyPlace(from: item, referenceCoordinate: center)
        }
        return NearbyScan(places: rankNearbyPlaces(mapped),
                          rawResultCount: response.mapItems.count,
                          eligibleResultCount: eligibleResultCount,
                          excludedPublicTransportResultCount: excludedPublicTransportResultCount,
                          excludedMissingCategoryResultCount: excludedMissingCategoryResultCount,
                          excludedUnsupportedCategoryResultCount: excludedUnsupportedCategoryResultCount)
    }

    func search(text: String) async throws -> [NearbyPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .pointOfInterest
        let search = MKLocalSearch(request: request)
        do {
            let response = try await withTaskCancellationHandler {
                try await search.start()
            } onCancel: {
                search.cancel()
            }
            let results = response.mapItems.map { Self.nearbyPlace(from: $0, referenceCoordinate: nil) }
            if !results.isEmpty { return results }
            let fallback = Self.fallbackSearch(text)
            return fallback.isEmpty ? results : fallback
        } catch {
            let fallback = Self.fallbackSearch(text)
            if !fallback.isEmpty { return fallback }
            throw error
        }
    }

    private static func fallbackSearch(_ text: String) -> [NearbyPlace] {
        CanadianMerchantPreIndex.search(text, limit: 10).map(NearbyPlace.init(preIndexed:))
    }

    private static func nearbyPlace(from mapItem: MKMapItem,
                                    referenceCoordinate: CLLocationCoordinate2D?) -> NearbyPlace {
        let coordinate = mapItem.placemark.coordinate
        let distance = referenceCoordinate.map { reference in
            CLLocation(latitude: reference.latitude, longitude: reference.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        let name = mapItem.name ?? "Unknown place"
        let street = [mapItem.placemark.subThoroughfare, mapItem.placemark.thoroughfare]
            .compactMap { $0 }.joined(separator: " ")
        let address = [street, mapItem.placemark.locality, mapItem.placemark.administrativeArea]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return NearbyPlace(
            id: syntheticId(name: name, coordinate: coordinate),
            placeID: mapItem.identifier?.rawValue,
            alternatePlaceIDs: mapItem.alternateIdentifiers.map(\.rawValue),
            name: name,
            poiCategoryRaw: mapItem.pointOfInterestCategory?.rawValue,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            distanceMeters: distance,
            locationDescription: address.isEmpty ? nil : address)
    }

    /// The identity string every existing keyspace is already built on, and therefore frozen.
    ///
    /// It is a poor identity: two `Double`s rendered at full precision and compared as text, so a
    /// coordinate that shifts in its twelfth decimal is a different merchant, and so is "Metro"
    /// becoming "Metro Plus". `MKMapItem.identifier` — carried alongside it since iOS 18, which is
    /// this app's deployment floor — is what actually answers "same store?"; see `MerchantIdentity`
    /// for how the two are weighed. This stays because the mute list, saved arrival preferences and
    /// every `merchantIdentifier` already written to the store are keyed on it, and moving four
    /// keyspaces at once to fix an orphan is how you cause one.
    private static func syntheticId(name: String, coordinate: CLLocationCoordinate2D) -> String {
        "\(name)@\(coordinate.latitude),\(coordinate.longitude)"
    }
}
