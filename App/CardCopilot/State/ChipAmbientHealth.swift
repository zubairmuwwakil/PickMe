import Foundation

/// What Chip should say, if anything, about the health of arrival alerts.
///
/// Arrival detection is the one feature the owner never watches working: it manifests only as a
/// notification that arrives while the app is closed. When it degrades — notifications revoked in
/// Settings, Background App Refresh switched off, Always location downgraded — the failure looks
/// exactly like "you haven't been near a store lately." Nothing else in the app volunteers that
/// distinction, so Chip does.
///
/// Deliberately *not* a `ChipInsight`. That enum lives in the Engine and its contract is that
/// every case is derived from a `Recommendation`, a `PurchaseContext`, or a `CandidateScore` —
/// card semantics, twinned in Kotlin. iOS permission state is neither, and the Android engine has
/// no concept of it.
enum ChipAmbientAdvisory: Equatable, CaseIterable {
    /// Always-location was downgraded. Nothing else can work without it, so it outranks the rest.
    case locationBlocked
    /// Notification permission was revoked, so an arrival has no way to reach the owner.
    case notificationsBlocked
    /// Background App Refresh is off or restricted, so arrivals are never noticed in the first place.
    case backgroundRefreshBlocked
    /// Never configured. A one-off mention in Chip's ordinary rotation, never pinned — an
    /// unconfigured optional feature is a choice, not a fault, and nagging about it would make
    /// Chip an ad.
    case notSetUp

    /// The advisory worth voicing for this runtime state, or `nil` when arrival alerts are
    /// healthy (or merely still preparing their regions, which resolves itself).
    static func evaluate(isEnabled: Bool, status: AmbientRuntimeStatus) -> ChipAmbientAdvisory? {
        guard isEnabled else { return .notSetUp }
        if !status.locationAlways { return .locationBlocked }
        if !status.notificationsAllowed { return .notificationsBlocked }
        if status.backgroundRefresh != .available { return .backgroundRefreshBlocked }
        return nil
    }

    /// Urgent advisories are pinned to the front of Chip's queue; the rest take their turn in the
    /// ordinary rotation.
    var isUrgent: Bool {
        self != .notSetUp
    }

    var tag: String {
        switch self {
        case .locationBlocked, .notificationsBlocked, .backgroundRefreshBlocked:
            return "ALERTS DOWN"
        case .notSetUp:
            return "AUTOPILOT"
        }
    }

    var text: String {
        switch self {
        case .locationBlocked:
            return "Heads up — I lost background location access, so I can't tell when you walk into a store. Arrival alerts are dark until that's back on."
        case .notificationsBlocked:
            return "My notifications got switched off. I still spot the store, I just have no way to tap you on the shoulder about it. Want to fix that?"
        case .backgroundRefreshBlocked:
            return "Background App Refresh is off, so I'm asleep when you walk into a store. Arrival alerts won't fire until I'm allowed to wake up."
        case .notSetUp:
            return "Want me working while the app is closed? Turn on arrival alerts and I'll tap you on the shoulder with the right card as you walk in."
        }
    }

    var actionLabel: String {
        self == .notSetUp ? "Set up" : "Fix it"
    }

    var mood: ChipMood {
        self == .notSetUp ? .wink : .alert
    }
}
