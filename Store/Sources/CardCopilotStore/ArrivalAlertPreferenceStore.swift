import Foundation

/// The owner's chosen reach for arrival advice at a merchant.
public enum ArrivalAlertScope: String, Codable, Sendable, CaseIterable {
    /// Alert at every discovered branch of a recognisable retailer.
    case chain
    /// Alert only at the saved POI (identifier first, coordinates as a resilient fallback).
    case exactLocation
    /// Keep the existing three-separate-days learning rule.
    case automatic
    /// Never alert for this merchant.
    case disabled
}

public struct ArrivalAlertPreference: Codable, Equatable, Sendable, Identifiable {
    public var id: String { merchantKey }
    public let merchantKey: String
    public let merchantName: String
    public let scope: ArrivalAlertScope
    public let locationIdentifier: String?
    public let latitude: Double?
    public let longitude: Double?
    public let locationDescription: String?
    public let decidedAt: Date

    public init(merchantKey: String, merchantName: String, scope: ArrivalAlertScope,
                locationIdentifier: String? = nil, latitude: Double? = nil,
                longitude: Double? = nil, locationDescription: String? = nil,
                decidedAt: Date = Date()) {
        self.merchantKey = merchantKey
        self.merchantName = merchantName
        self.scope = scope
        self.locationIdentifier = locationIdentifier
        self.latitude = latitude
        self.longitude = longitude
        self.locationDescription = locationDescription
        self.decidedAt = decidedAt
    }

    /// Exact-location matching survives unstable MapKit identifiers by falling back to 100 m.
    public func matchesLocation(identifier: String?, latitude: Double, longitude: Double) -> Bool {
        if let locationIdentifier, let identifier, locationIdentifier == identifier { return true }
        guard let savedLatitude = self.latitude, let savedLongitude = self.longitude else { return false }
        return greatCircleDistanceMeters(fromLatitude: savedLatitude,
                                         fromLongitude: savedLongitude,
                                         toLatitude: latitude,
                                         toLongitude: longitude) <= 100
    }
}

/// Shared between the app UI and background arrival wakes.
public final class ArrivalAlertPreferenceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = OwnerStateLocalStore.sharedDefaults,
                key: String = "ca.pickme.arrival-alert-preferences.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func preference(for merchantKey: String) -> ArrivalAlertPreference? {
        load()[merchantKey]
    }

    public func save(_ preference: ArrivalAlertPreference) {
        var values = load()
        values[preference.merchantKey] = preference
        persist(values)
    }

    public func remove(merchantKey: String) {
        var values = load()
        values.removeValue(forKey: merchantKey)
        persist(values)
    }

    public func all() -> [ArrivalAlertPreference] {
        load().values.sorted { $0.decidedAt > $1.decidedAt }
    }

    public func chainKeys() -> Set<String> {
        Set(load().values.filter { $0.scope == .chain }.map(\.merchantKey))
    }

    /// Whether an arrival at this branch is permitted by an explicit choice. Nil means the owner
    /// has not chosen yet, so the caller may apply the automatic learning policy.
    public func permits(merchantKey: String, locationIdentifier: String?,
                        latitude: Double, longitude: Double) -> Bool? {
        guard let preference = preference(for: merchantKey) else { return nil }
        switch preference.scope {
        case .chain: return true
        case .exactLocation:
            return preference.matchesLocation(identifier: locationIdentifier,
                                              latitude: latitude, longitude: longitude)
        case .automatic: return nil
        case .disabled: return false
        }
    }

    public func forgetAll() { defaults.removeObject(forKey: key) }

    private func load() -> [String: ArrivalAlertPreference] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: ArrivalAlertPreference].self,
                                                       from: data) else { return [:] }
        return decoded
    }

    private func persist(_ values: [String: ArrivalAlertPreference]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: key)
    }
}
