import CardCopilotStore
import Foundation

/// Persists the debug alert-policy dials across the background relaunches that arrival alerts
/// consist almost entirely of.
///
/// Deliberately stores the whole `AmbientAlertPolicy` as one blob rather than five defaults keys.
/// The dials only mean anything together — a multiplier read from a build that had a different
/// threshold describes no policy at all — and the field log records the same value, so an export
/// and the live app can be compared byte for byte.
///
/// A decode failure falls back to the shipped policy rather than propagating. A build whose dials
/// have changed shape must not take the app's alert behaviour down with it.
@MainActor
final class AmbientAlertPolicyStore {
    private let defaults: UserDefaults
    private let key = "ambientAlertPolicy.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var policy: AmbientAlertPolicy {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(AmbientAlertPolicy.self, from: data) else {
            return .shipped
        }
        return stored
    }

    func save(_ policy: AmbientAlertPolicy) {
        guard let data = try? JSONEncoder().encode(policy) else { return }
        defaults.set(data, forKey: key)
    }

    func forgetAll() { defaults.removeObject(forKey: key) }
}
