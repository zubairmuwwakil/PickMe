import Foundation
import CardCopilotStore

/// One in-progress visit to a monitored area.
///
/// This has to survive app termination: the entry wake and the exit wake are separate process
/// launches, often twenty minutes apart, and the dwell that decides whether anything happened is
/// the interval between them. `UserDefaults` matches the existing ambient stores and avoids
/// opening a SwiftData context on a background wake just to note a timestamp.
struct AmbientVisit: Codable, Equatable {
    var enteredAt: Date
    /// Whether the owner acted on the arrival notification. The exit prompt is a follow-up to an
    /// engagement, never a cold ask — see `dwellDecision`.
    var didEngage: Bool
    /// The purchase opened by a notification action, so the exit prompt knows what to attach an
    /// amount to.
    var purchaseId: UUID?
    /// Enough of the merchant to write the prompt without re-resolving location.
    var merchantName: String
    /// Whether the owner swiped this visit's Live Activity away.
    ///
    /// A swipe is the only "not now" the owner has that costs them nothing. Honouring it means
    /// not re-showing the card when a plaza geofence flaps, and — in the payment loop — not
    /// pushing a confirmation they already dismissed.
    var liveActivityDismissed: Bool = false

    init(enteredAt: Date, didEngage: Bool, purchaseId: UUID?, merchantName: String,
         liveActivityDismissed: Bool = false) {
        self.enteredAt = enteredAt
        self.didEngage = didEngage
        self.purchaseId = purchaseId
        self.merchantName = merchantName
        self.liveActivityDismissed = liveActivityDismissed
    }

    /// Written by hand rather than synthesised: synthesised `Codable` throws on a missing key
    /// even where the property has a default, so a visit stored before this field existed would
    /// fail to decode and `all()`'s `try?` would silently discard every in-flight visit.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enteredAt = try container.decode(Date.self, forKey: .enteredAt)
        didEngage = try container.decode(Bool.self, forKey: .didEngage)
        purchaseId = try container.decodeIfPresent(UUID.self, forKey: .purchaseId)
        merchantName = try container.decode(String.self, forKey: .merchantName)
        liveActivityDismissed = try container.decodeIfPresent(
            Bool.self, forKey: .liveActivityDismissed) ?? false
    }
}

/// How long a swipe keeps PickMe off the Lock Screen at that region.
///
/// Refreshed by every arrival it suppresses, so the window measures time since the owner was last
/// *seen* there rather than time since the swipe: a long shop with a flapping plaza geofence stays
/// quiet throughout, and the suppression lifts twenty minutes after they have actually left. A
/// return trip that afternoon is a new visit and gets service again.
let dismissalRespectWindow: TimeInterval = 20 * 60

/// Per-area visit state. Entries are pruned on write rather than on a timer: a region exit that
/// never arrives would otherwise strand a timestamp forever, and the next entry to that area
/// would compute a dwell measured in days.
@MainActor
final class AmbientVisitStore {
    private let defaults: UserDefaults
    private let key = "ambientVisits.v1"
    private let dismissalKey = "ambientLiveActivityDismissals.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func visit(forRegionId id: String) -> AmbientVisit? {
        all()[id]
    }

    func begin(_ visit: AmbientVisit, forRegionId id: String, now: Date = .now) {
        var visits = pruned(all(), now: now)
        visits[id] = visit
        save(visits)
    }

    func update(regionId id: String, _ mutate: (inout AmbientVisit) -> Void) {
        var visits = all()
        guard var visit = visits[id] else { return }
        mutate(&visit)
        visits[id] = visit
        save(visits)
    }

    func end(regionId id: String) {
        var visits = all()
        visits.removeValue(forKey: id)
        save(visits)
    }

    func forgetAll() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: dismissalKey)
    }

    // MARK: - Dismissals

    /// Records that the owner swiped this region's Live Activity away.
    ///
    /// Kept separately from `AmbientVisit.liveActivityDismissed` because the two answer different
    /// questions over different lifetimes. The visit flag answers "was it dismissed during *this*
    /// visit", which the payment loop needs — and it dies with the visit, since an exit calls
    /// `end(regionId:)` and the next entry calls `begin(_:forRegionId:)`. A plaza geofence flaps
    /// entry/exit/entry during one shop, so relying on the flag alone would put the card straight
    /// back on the screen the owner just cleared. Both are written here.
    func markLiveActivityDismissed(regionId: String, at date: Date = .now) {
        update(regionId: regionId) { $0.liveActivityDismissed = true }
        var dismissals = prunedDismissals(now: date)
        dismissals[regionId] = date.timeIntervalSince1970
        saveDismissals(dismissals)
    }

    /// Whether a swipe at this region should still be honoured.
    ///
    /// Reading refreshes the window for that region, so suppression persists for as long as the
    /// owner keeps re-entering. See `dismissalRespectWindow`.
    func liveActivityWasDismissed(regionId: String, now: Date = .now) -> Bool {
        var dismissals = prunedDismissals(now: now)
        guard dismissals[regionId] != nil else {
            saveDismissals(dismissals)
            return false
        }
        dismissals[regionId] = now.timeIntervalSince1970
        saveDismissals(dismissals)
        return true
    }

    private func prunedDismissals(now: Date) -> [String: Double] {
        let stored = defaults.dictionary(forKey: dismissalKey) as? [String: Double] ?? [:]
        let cutoff = now.addingTimeInterval(-dismissalRespectWindow).timeIntervalSince1970
        return stored.filter { $0.value > cutoff }
    }

    private func saveDismissals(_ dismissals: [String: Double]) {
        defaults.set(dismissals, forKey: dismissalKey)
    }

    /// Drops entries older than a plausible visit. `maximumPlausibleDwell` is the same bound
    /// `dwellDecision` uses to call an interval stranded, so the two cannot disagree about what
    /// counts as a visit that never ended.
    private func pruned(_ visits: [String: AmbientVisit], now: Date) -> [String: AmbientVisit] {
        visits.filter { now.timeIntervalSince($0.value.enteredAt) <= maximumPlausibleDwell }
    }

    private func all() -> [String: AmbientVisit] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: AmbientVisit].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func save(_ visits: [String: AmbientVisit]) {
        guard let data = try? JSONEncoder().encode(visits) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Timestamps of recent MapKit discovery queries, backing the local rate ceiling.
///
/// The ceiling is a backstop against a bug in the caller becoming `MKError.loadingThrottled`, not
/// the operating point — realistic use sits one to three queries a day, three orders of magnitude
/// under Apple's limit.
@MainActor
final class DiscoveryQueryLog {
    private let defaults: UserDefaults
    private let key = "ambientDiscoveryQueries.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recent(now: Date = .now) -> [Date] {
        let stamps = defaults.array(forKey: key) as? [Double] ?? []
        let cutoff = now.addingTimeInterval(-3_600).timeIntervalSince1970
        return stamps.filter { $0 > cutoff }.map(Date.init(timeIntervalSince1970:))
    }

    func record(at date: Date = .now) {
        let kept = recent(now: date).map(\.timeIntervalSince1970) + [date.timeIntervalSince1970]
        defaults.set(kept, forKey: key)
    }

    func forgetAll() {
        defaults.removeObject(forKey: key)
    }
}
