import CardCopilotStore
import Foundation
import Observation
import SwiftData

/// A snapshot of a region actually registered with iOS, reconstructed from the local place cache.
struct MonitoredArrivalPlace: Identifiable {
    let id: String
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double
    let merchants: [NearbyPlace]

    func contains(_ merchant: NearbyPlace) -> Bool {
        merchant.hasMonitorableLocation && merchants.contains(where: { $0.id == merchant.id })
            && greatCircleDistanceMeters(
            fromLatitude: latitude, fromLongitude: longitude,
            toLatitude: merchant.latitude, toLongitude: merchant.longitude) <= radiusMeters
    }
}

@Observable
@MainActor
final class ArrivalPlacesModel {
    private(set) var preferences: [ArrivalAlertPreference] = []
    private(set) var savedMerchants: [NearbyPlace] = []
    private(set) var monitoredPlaces: [MonitoredArrivalPlace] = []
    private(set) var runtimeStatus = AmbientRuntimeStatus()
    private(set) var searchResults: [NearbyPlace] = []
    private(set) var isSearching = false
    private(set) var hasSearched = false
    private(set) var mutedMerchantCount = 0
    private(set) var arrivalExplanations = ArrivalExplanationSnapshot(records: [:])
    var error: String?

    private let context: ModelContext
    private let provider: any MerchantProviding
    private let ambient: AmbientLocationService
    private let preferenceStore = ArrivalAlertPreferenceStore()

    init(context: ModelContext, provider: any MerchantProviding, ambient: AmbientLocationService) {
        self.context = context
        self.provider = provider
        self.ambient = ambient
    }

    func refresh() async {
        runtimeStatus = await ambient.runtimeStatus()
        mutedMerchantCount = ambient.mutedMerchantCount
        arrivalExplanations = ambient.arrivalExplanations
        do {
            preferences = preferenceStore.all()
            savedMerchants = try context.fetch(FetchDescriptor<StoredMerchant>()).map {
                NearbyPlace(id: $0.identifier ?? $0.id.uuidString, placeID: $0.placeID,
                               name: $0.name,
                               poiCategoryRaw: $0.poiCategoryRaw, latitude: $0.latitude,
                               longitude: $0.longitude, distanceMeters: nil)
            }.filter(\.hasMonitorableLocation).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            monitoredPlaces = try ambient.monitoredPlaces()
        } catch {
            self.error = "Could not load monitored places. Please try again."
        }
    }

    func search(_ query: String) async {
        error = nil
        searchResults = []
        hasSearched = false
        guard !query.isEmpty else { isSearching = false; return }
        isSearching = true
        do {
            let results = try await provider.search(text: query)
            guard !Task.isCancelled else { return }
            searchResults = rankNearbyPlaces(results.filter(\.hasMonitorableLocation))
            isSearching = false
            hasSearched = true
        } catch {
            guard !Task.isCancelled else { return }
            isSearching = false
            self.error = "Could not search for places. Check your connection and try again."
        }
    }

    /// The owner's choice for this branch.
    ///
    /// Reads through the store rather than scanning the cached `preferences` array, because the
    /// store is what knows that a qualified local key falls back to its provisional ancestor — a
    /// choice made before local keys carried a place token is still the owner's choice.
    func preference(for merchant: NearbyPlace) -> ArrivalAlertPreference? {
        guard let key = merchantActivityKey(name: merchant.name, locationIdentifier: merchant.id,
                                            latitude: merchant.latitude,
                                            longitude: merchant.longitude) else { return nil }
        return preferenceStore.preference(for: key)
    }

    func isMuted(_ merchant: NearbyPlace) -> Bool { ambient.isMerchantMuted(merchant.id) }

    func isMonitoring(_ merchant: NearbyPlace) -> Bool {
        runtimeStatus.locationAlways && monitoredPlaces.contains { $0.contains(merchant) }
    }

    func latestArrivalExplanation(for merchant: NearbyPlace) -> ArrivalExplanationSnapshot.Match? {
        guard merchant.hasMonitorableLocation else { return nil }
        return arrivalExplanations.latest(merchantIdentifier: merchant.id,
                                          regionIdentifiers: monitoredPlaces.filter { $0.contains(merchant) }.map(\.id))
    }

    func clearArrivalExplanations() {
        ambient.clearArrivalExplanations()
        arrivalExplanations = ambient.arrivalExplanations
    }

    /// A chain choice made by an older build may have no selected branch. The detail screen can
    /// still edit it, but cannot manufacture coordinates for "Only this location".
    func merchant(for preference: ArrivalAlertPreference) -> NearbyPlace {
        let candidates = savedMerchants.filter { saved in
            let key = merchantActivityKey(name: saved.name, locationIdentifier: saved.id,
                                          latitude: saved.latitude, longitude: saved.longitude)
            return key == preference.merchantKey
                || key.flatMap(provisionalMerchantKey(for:)) == preference.merchantKey
        }
        let saved = candidates.first { $0.id == preference.locationIdentifier }
            ?? candidates.first {
                preference.matchesLocation(identifier: $0.id, latitude: $0.latitude, longitude: $0.longitude)
            }
        return NearbyPlace(id: saved?.id ?? preference.locationIdentifier ?? preference.merchantKey,
                              name: preference.merchantName, poiCategoryRaw: saved?.poiCategoryRaw,
                              latitude: preference.latitude ?? saved?.latitude ?? 0,
                              longitude: preference.longitude ?? saved?.longitude ?? 0,
                              distanceMeters: nil, locationDescription: preference.locationDescription)
    }

    var otherSavedMerchants: [NearbyPlace] {
        let representedIDs = Set(preferences.map { merchant(for: $0).id })
        return savedMerchants.filter { !representedIDs.contains($0.id) }
    }

    /// Saving an alert choice is not a purchase or category confirmation.
    @discardableResult
    func save(_ scope: ArrivalAlertScope, merchant: NearbyPlace,
              merchantKey: String? = nil) async -> Bool {
        guard let key = merchantKey ?? merchantActivityKey(name: merchant.name,
                                                           locationIdentifier: merchant.id,
                                                           latitude: merchant.latitude,
                                                           longitude: merchant.longitude),
              scope != .exactLocation || merchant.hasMonitorableLocation else {
            error = "Search for a specific store location first."
            return false
        }
        error = nil
        do {
            if merchant.hasMonitorableLocation {
                // The exact-coordinate arm of the old check was doing the work of a proximity
                // rung with no tolerance at all: two `Double`s compared for equality, so the same
                // shop saved twice after a pin revision inserted a second row. `MerchantIdentity`
                // is the one place that decides this now, and a row found by a weaker rung gets
                // Apple's place id recorded on it here.
                let stored = try context.fetch(FetchDescriptor<StoredMerchant>())
                if let match = MerchantIdentity.match(merchant, in: stored) {
                    if MerchantIdentity.backfill(match.merchant, from: merchant) {
                        try context.save()
                    }
                } else {
                    context.insert(StoredMerchant(name: merchant.name, identifier: merchant.id,
                                                  placeID: merchant.placeID,
                                                  poiCategoryRaw: merchant.poiCategoryRaw,
                                                  latitude: merchant.latitude, longitude: merchant.longitude,
                                                  merchantCategoryCode: merchant.merchantCategoryCode))
                    try context.save()
                }
            }
            // Retain the branch even for chain/automatic/off, so changing one's mind is reversible.
            let previous = preferenceStore.preference(for: key)
            let address = merchant.locationDescription
                ?? (previous?.locationIdentifier == merchant.id ? previous?.locationDescription : nil)
            preferenceStore.save(ArrivalAlertPreference(
                merchantKey: key, merchantName: merchant.name, scope: scope,
                locationIdentifier: merchant.hasMonitorableLocation ? merchant.id : nil,
                latitude: merchant.hasMonitorableLocation ? merchant.latitude : nil,
                longitude: merchant.hasMonitorableLocation ? merchant.longitude : nil,
                locationDescription: address))
            if scope != .disabled { ambient.unmuteMerchant(merchant.id, merchantKey: key, allBranches: scope == .chain) }
            ambient.refreshNow()
            await refresh()
            return true
        } catch {
            context.rollback()
            self.error = "Could not save this place. Please try again."
            return false
        }
    }

    func refreshNearby() {
        ambient.refreshNow()
    }

    func unmuteAll() async {
        ambient.unmuteAllMerchants()
        await refresh()
    }
}
