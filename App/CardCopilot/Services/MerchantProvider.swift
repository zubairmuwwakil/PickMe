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
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let request = MKLocalPointsOfInterestRequest(center: center, radius: Self.nearbyRadiusMeters)
        let search = MKLocalSearch(request: request)
        let response = try await withTaskCancellationHandler {
            try await search.start()
        } onCancel: {
            search.cancel()
        }
        return rankNearbyMerchants(response.mapItems.map {
            Self.nearbyMerchant(from: $0, referenceCoordinate: center)
        })
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
        let matches = CanadianMerchantPreIndex.search(text, limit: 10)
        return matches.map { match in
            NearbyMerchant(
                id: "preindex:\(match.id)",
                name: match.name,
                poiCategoryRaw: match.category,
                latitude: 0,
                longitude: 0,
                distanceMeters: nil
            )
        }
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

