import CardCopilotStore
import CoreLocation
@preconcurrency import MapKit

/// MapKit-backed `MerchantProviding`. `nearby` stays inside a small radius, so a result
/// means "the place you're standing in," not "the whole block." `search` carries no
/// location bias — it's the Apple guideline 5.1.1 fallback and must work with zero
/// location access.
final class LiveMerchantProvider: MerchantProviding {
    private static let nearbyRadiusMeters: CLLocationDistance = 200

    func nearby(latitude: Double, longitude: Double) async throws -> [NearbyMerchant] {
        try await nearbyScan(latitude: latitude, longitude: longitude).merchants
    }

    /// The only place that can see how large MapKit's response was before `rankNearbyMerchants`
    /// dedupes it, so it is the only place that can report it. A 200 m sweep with no category
    /// filter returns a bounded set, and whether a plaza's anchor tenant was crowded out of that
    /// set or merely outranked inside it is the question the field log exists to settle.
    func nearbyScan(latitude: Double, longitude: Double) async throws -> NearbyScan {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let request = MKLocalPointsOfInterestRequest(center: center, radius: Self.nearbyRadiusMeters)
        let search = MKLocalSearch(request: request)
        let response = try await withTaskCancellationHandler {
            try await search.start()
        } onCancel: {
            search.cancel()
        }
        let mapped = response.mapItems.map {
            Self.nearbyMerchant(from: $0, referenceCoordinate: center)
        }
        return NearbyScan(merchants: rankNearbyMerchants(mapped),
                          rawResultCount: response.mapItems.count)
    }

    func search(text: String) async throws -> [NearbyMerchant] {
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
            let results = response.mapItems.map { Self.nearbyMerchant(from: $0, referenceCoordinate: nil) }
            if !results.isEmpty { return results }
            let fallback = Self.fallbackSearch(text)
            return fallback.isEmpty ? results : fallback
        } catch {
            let fallback = Self.fallbackSearch(text)
            if !fallback.isEmpty { return fallback }
            throw error
        }
    }

    private static func fallbackSearch(_ text: String) -> [NearbyMerchant] {
        CanadianMerchantPreIndex.search(text, limit: 10).map(NearbyMerchant.init(preIndexed:))
    }

    private static func nearbyMerchant(from mapItem: MKMapItem,
                                        referenceCoordinate: CLLocationCoordinate2D?) -> NearbyMerchant {
        let coordinate = mapItem.placemark.coordinate
        let distance = referenceCoordinate.map { reference in
            CLLocation(latitude: reference.latitude, longitude: reference.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        let name = mapItem.name ?? "Unknown merchant"
        let street = [mapItem.placemark.subThoroughfare, mapItem.placemark.thoroughfare]
            .compactMap { $0 }.joined(separator: " ")
        let address = [street, mapItem.placemark.locality, mapItem.placemark.administrativeArea]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return NearbyMerchant(
            id: syntheticId(name: name, coordinate: coordinate),
            name: name,
            poiCategoryRaw: mapItem.pointOfInterestCategory?.rawValue,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            distanceMeters: distance,
            locationDescription: address.isEmpty ? nil : address)
    }

    private static func syntheticId(name: String, coordinate: CLLocationCoordinate2D) -> String {
        "\(name)@\(coordinate.latitude),\(coordinate.longitude)"
    }
}
