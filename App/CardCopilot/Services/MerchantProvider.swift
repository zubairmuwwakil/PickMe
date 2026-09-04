import CardCopilotEngine
import CardCopilotStore
import CoreLocation
import Foundation
@preconcurrency import MapKit

#if FIELD_DIAGNOSTICS
/// The only owner-adjustable Radar input, compiled out with the rest of the field instrument.
/// Fixed choices keep exported scans comparable instead of producing a continuum of one-offs.
enum RadarDiagnosticSettings {
    static let radiusDefaultsKey = "fieldDiagnostics.radarRadiusMeters"
    static let defaultRadiusMeters: CLLocationDistance = 100
    static let allowedRadiusMeters: [CLLocationDistance] = [100, 150, 200]

    static var radiusMeters: CLLocationDistance {
        guard let stored = UserDefaults.standard.object(forKey: radiusDefaultsKey) as? NSNumber,
              allowedRadiusMeters.contains(stored.doubleValue) else {
            return defaultRadiusMeters
        }
        return stored.doubleValue
    }
}
#endif

/// MapKit-backed `MerchantProviding`. `nearby` stays inside a small radius, so a result
/// means "the place you're standing in," not "the whole block." `search` carries no
/// location bias — it's the Apple guideline 5.1.1 fallback and must work with zero
/// location access.
final class LiveMerchantProvider: MerchantProviding {
    /// Production stays at its current 100 m. Field builds can vary one input without changing
    /// ranking, eligibility, or the manual-search fallback.
    private static var nearbyRadiusMeters: CLLocationDistance {
        #if FIELD_DIAGNOSTICS
        RadarDiagnosticSettings.radiusMeters
        #else
        100
        #endif
    }

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
        let places = try await nearbyScan(latitude: latitude, longitude: longitude).places
        await refreshCommunityGiftCardInventory(nearby: places)
        return places
    }

    /// Community inventory is a separately consented network feature. The normal MapKit result is
    /// still the source of candidate places; when sharing is off this function performs no request
    /// to In Unity and removes any cached community evidence immediately.
    private func refreshCommunityGiftCardInventory(nearby places: [NearbyPlace]) async {
        let settings = CommunityGiftCardInventorySettingsStore()
        let cache = CommunityGiftCardInventoryCacheStore()
        guard settings.isEnabled else {
            cache.replace([])
            return
        }
        guard let baseURL = MoneyTalksConfiguration.apiBaseURL else { return }

        let client = CommunityGiftCardInventoryClient(baseURL: baseURL)
        let instruments = Array(Set(PurchaseRouteCatalogue.canadaV1.map(\.instrumentLabel))).sorted()
        var communityEvidence: [GiftCardInventoryObservation] = []
        var didRefresh = false

        for instrument in instruments {
            do {
                communityEvidence += try await client.evidence(instrumentKey: instrument,
                                                                nearby: places)
                didRefresh = true
            } catch {
                // Community evidence is opportunistic. A server/network failure must never make
                // local checkout fail or erase a still-fresh cache.
            }
        }
        if didRefresh {
            cache.replace(communityEvidence)
        }

        // Upload recent owner-confirmed inventory in the background. Observation UUIDs make retry
        // idempotent, so there is no "sent" identifier tied back to an account or device.
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        let local = await GiftCardInventoryObservationStore.shared.observations()
        let pending = local.filter {
            $0.source == .ownerConfirmed
                && $0.observedAt >= cutoff
                && instruments.contains($0.instrumentKey)
                && ($0.placeID != nil || ($0.latitude != nil && $0.longitude != nil))
        }.suffix(20)
        guard !pending.isEmpty else { return }

        Task.detached(priority: .utility) {
            for observation in pending {
                try? await client.submit(observation)
            }
        }
    }

    /// The only place that can see how large MapKit's response was before `rankNearbyPlaces`
    /// dedupes it, so it is the only place that can report it. A small sweep over checkout-eligible
    /// categories returns a bounded set, and whether a plaza's anchor tenant was crowded out of
    /// that set or merely outranked inside it is the question the field log exists to settle.
    func nearbyScan(latitude: Double, longitude: Double) async throws -> NearbyScan {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let queryRadiusMeters = Self.nearbyRadiusMeters
        let request = MKLocalPointsOfInterestRequest(center: center, radius: queryRadiusMeters)
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
                          queryRadiusMeters: queryRadiusMeters,
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
