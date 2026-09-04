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
                NearbyPlace(id: $0.identifier ?? $0.id.uuidString, name: $0.name,
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

    func preference(for merchant: NearbyPlace) -> ArrivalAlertPreference? {
        guard let key = merchantActivityKey(name: merchant.name, locationIdentifier: merchant.id) else { return nil }
        return preferences.first { $0.merchantKey == key }
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
        let candidates = savedMerchants.filter {
            merchantActivityKey(name: $0.name, locationIdentifier: $0.id) == preference.merchantKey
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
        guard let key = merchantKey ?? merchantActivityKey(name: merchant.name, locationIdentifier: merchant.id),
              scope != .exactLocation || merchant.hasMonitorableLocation else {
            error = "Search for a specific store location first."
            return false
        }
        error = nil
        do {
            if merchant.hasMonitorableLocation {
                let existing = try context.fetch(FetchDescriptor<StoredMerchant>()).contains {
                    $0.identifier == merchant.id
                        || ($0.name == merchant.name && $0.latitude == merchant.latitude && $0.longitude == merchant.longitude)
                }
                if !existing {
                    context.insert(StoredMerchant(name: merchant.name, identifier: merchant.id,
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
