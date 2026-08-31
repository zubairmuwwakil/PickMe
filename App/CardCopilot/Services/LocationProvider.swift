import CoreLocation

/// Why a one-time location fix couldn't be obtained. Denied/restricted are distinguished
/// from a transient fix failure so the caller can route straight to manual search instead
/// of showing a dead-end error.
enum LocationUnavailable: Error, Sendable, Equatable {
    case permissionDenied
    case permissionRestricted
    case timedOut
    case fixFailed(String)
}

extension LocationUnavailable: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Location access is disabled."
        case .permissionRestricted: return "Location access is restricted on this device."
        case .timedOut: return "Location took too long to respond."
        case .fixFailed(let detail): return "Location is unavailable: \(detail)."
        }
    }
}

/// A validated fix rather than a bare coordinate. Accuracy and age are required to decide
/// whether a 200 m merchant result is safe to reuse after the app becomes active again.
struct CheckoutLocationFix: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracyMeters: Double
    let capturedAt: Date

    init(latitude: Double, longitude: Double, horizontalAccuracyMeters: Double,
         capturedAt: Date = .now) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.capturedAt = capturedAt
    }

    init(_ location: CLLocation) {
        self.init(latitude: location.coordinate.latitude,
                  longitude: location.coordinate.longitude,
                  horizontalAccuracyMeters: location.horizontalAccuracy,
                  capturedAt: location.timestamp)
    }

    func isUsable(now: Date = .now) -> Bool {
        CLLocationCoordinate2DIsValid(coordinate)
            && horizontalAccuracyMeters >= 0
            && horizontalAccuracyMeters <= 250
            && abs(now.timeIntervalSince(capturedAt)) <= 60
    }

    func distance(from other: CheckoutLocationFix) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// The narrow location surface used by checkout. The preflight variant never presents a
/// permission prompt, which lets a returning, already-authorized owner warm checkout at launch
/// without turning app launch itself into a request for new consent.
@MainActor
protocol CheckoutLocationProviding: AnyObject {
    func requestLocation() async throws -> CheckoutLocationFix
    func requestLocationIfAuthorized() async throws -> CheckoutLocationFix?
}

/// A one-shot location fix. Always `requestLocation()`, never `startUpdatingLocation` — even the
/// launch preflight samples once and stops, preserving the app's no-continuous-tracking posture.
@MainActor
final class LocationProvider: NSObject, @MainActor CLLocationManagerDelegate, CheckoutLocationProviding {
    private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        return manager
    }()

    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CheckoutLocationFix, Error>?
    private var locationTimeoutTask: Task<Void, Never>?

    func requestLocation() async throws -> CheckoutLocationFix {
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

    /// Returns `nil` when the owner has not made a permission choice yet. Denied and restricted
    /// remain explicit failures so the home screen can keep its manual-search fallback visible.
    func requestLocationIfAuthorized() async throws -> CheckoutLocationFix? {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return try await fetchOneShotLocation()
        case .notDetermined:
            return nil
        case .restricted:
            throw LocationUnavailable.permissionRestricted
        case .denied:
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

    private func fetchOneShotLocation() async throws -> CheckoutLocationFix {
        if let warm = manager.location.map(CheckoutLocationFix.init), warm.isUsable() {
            return warm
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            locationTimeoutTask?.cancel()
            locationTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.finishLocation(.failure(LocationUnavailable.timedOut))
            }
            manager.requestLocation()
        }
    }

    private func finishLocation(_ result: Result<CheckoutLocationFix, Error>) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil
        manager.stopUpdatingLocation()
        continuation.resume(with: result)
    }

    // MARK: - CLLocationManagerDelegate
    //
    // `requestLocation()` can call `didUpdateLocations` and `didFailWithError` for the same
    // request, and `locationManagerDidChangeAuthorization` can re-enter (e.g. once when the
    // delegate is assigned, again once the owner responds to the prompt). Every handler below
    // takes its continuation and nils the stored one out before resuming, so a second callback
    // finds nothing to resume — resume-exactly-once is enforced by construction, not by care.
    //
    // Confirmed live: `locationManagerDidChangeAuthorization` fires once immediately after
    // `requestWhenInUseAuthorization()`, while the status is still `.notDetermined` — before
    // the owner has answered the system prompt. Resuming on that call would report "denied"
    // before the prompt is even on screen, so it's treated as a pending re-entrant call and
    // ignored: the continuation is only consumed once the status has actually resolved.

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = authorizationContinuation else { return }
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        authorizationContinuation = nil
        continuation.resume(returning: status)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard locationContinuation != nil else { return }
        guard let fix = locations.map(CheckoutLocationFix.init)
            .filter({ $0.isUsable() })
            .max(by: { $0.capturedAt < $1.capturedAt }) else {
            finishLocation(.failure(LocationUnavailable.fixFailed("no recent accurate fix")))
            return
        }
        finishLocation(.success(fix))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishLocation(.failure(error))
    }
}
