import CoreLocation

/// Why a one-time location fix couldn't be obtained. Denied/restricted are distinguished
/// from a transient fix failure so the caller can route straight to manual search instead
/// of showing a dead-end error.
enum LocationUnavailable: Error, Sendable, Equatable {
    case permissionDenied
    case permissionRestricted
    case fixFailed(String)
}

/// A single, on-demand location fix. Always `requestLocation()`, never
/// `startUpdatingLocation` — location is off by default and only sampled for the moment the
/// owner asks "where am I", per the Quebec Law 25 posture (design doc, decision table).
@MainActor
final class LocationProvider: NSObject, @MainActor CLLocationManagerDelegate {
    private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        return manager
    }()

    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    func requestLocation() async throws -> CLLocationCoordinate2D {
        let status = manager.authorizationStatus
        let resolvedStatus = status == .notDetermined ? await requestAuthorization() : status

        switch resolvedStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return try await fetchOneShotLocation()
        case .restricted:
            throw LocationUnavailable.permissionRestricted
        case .denied, .notDetermined:
            throw LocationUnavailable.permissionDenied
        @unknown default:
            throw LocationUnavailable.permissionDenied
        }
    }

    private func requestAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    private func fetchOneShotLocation() async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate
    //
    // `requestLocation()` can call `didUpdateLocations` and `didFailWithError` for the same
    // request, and `locationManagerDidChangeAuthorization` can re-enter (e.g. once when the
    // delegate is assigned, again once the owner responds to the prompt). Every handler below
    // takes its continuation and nils the stored one out before resuming, so a second callback
    // finds nothing to resume — resume-exactly-once is enforced by construction, not by care.

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = authorizationContinuation else { return }
        authorizationContinuation = nil
        continuation.resume(returning: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        guard let location = locations.last else {
            continuation.resume(throwing: LocationUnavailable.fixFailed("no location in update"))
            return
        }
        continuation.resume(returning: location.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(throwing: error)
    }
}
