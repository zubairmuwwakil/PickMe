import CardCopilotStore
import CoreLocation
import MapKit

/// MapKit-backed `MerchantProviding`. `nearby` stays inside a small radius, so a result
/// means "the place you're standing in," not "the whole block." `search` carries no
/// location bias — it's the Apple guideline 5.1.1 fallback and must work with zero
/// location access.
final class LiveMerchantProvider: MerchantProviding {
    private static let nearbyRadiusMeters: CLLocationDistance = 200

    func nearby(latitude: Double, longitude: Double) async throws -> [NearbyMerchant] {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let request = MKLocalPointsOfInterestRequest(center: center, radius: Self.nearbyRadiusMeters)
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        return response.mapItems.map { Self.nearbyMerchant(from: $0, referenceCoordinate: center) }
    }

    func search(text: String) async throws -> [NearbyMerchant] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .pointOfInterest
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        return response.mapItems.map { Self.nearbyMerchant(from: $0, referenceCoordinate: nil) }
    }

    private static func nearbyMerchant(from mapItem: MKMapItem,
                                        referenceCoordinate: CLLocationCoordinate2D?) -> NearbyMerchant {
        let coordinate = mapItem.placemark.coordinate
        let distance = referenceCoordinate.map { reference in
            CLLocation(latitude: reference.latitude, longitude: reference.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        let name = mapItem.name ?? "Unknown merchant"
        return NearbyMerchant(
            id: mapItem.identifier?.rawValue ?? syntheticId(name: name, coordinate: coordinate),
            name: name,
            poiCategoryRaw: mapItem.pointOfInterestCategory?.rawValue,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            distanceMeters: distance)
    }

    private static func syntheticId(name: String, coordinate: CLLocationCoordinate2D) -> String {
        "\(name)@\(coordinate.latitude),\(coordinate.longitude)"
    }
}
