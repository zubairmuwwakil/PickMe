@preconcurrency import CoreLocation
import CardCopilotEngine
import CardCopilotStore
import Foundation
import SwiftData
import UIKit
@preconcurrency import UserNotifications

enum AmbientNotificationAuthorization: String, Codable, Equatable, Sendable {
    case unknown, allowed, denied
}

enum AmbientBackgroundRefreshState: String, Codable, Equatable, Sendable {
    case available, denied, restricted
}

struct AmbientRuntimeIssue: Codable, Equatable, Sendable {
    let message: String
    let recordedAt: Date
}

/// The owner-visible health of the Apple-controlled half of arrival alerts. Keeping this separate
/// from `SuppressionLog` is important: the latter starts only after a region fires and the engine
/// evaluates it, while this describes why that region or notification may never happen at all.
struct AmbientRuntimeStatus: Equatable, Sendable {
    var locationAlways = false
    var notificationAuthorization: AmbientNotificationAuthorization = .unknown
    var backgroundRefresh: AmbientBackgroundRefreshState = .available
    var monitoredRegionCount = 0
    var lastNotificationScheduledAt: Date?
    var latestIssue: AmbientRuntimeIssue?

    var notificationsAllowed: Bool { notificationAuthorization == .allowed }
    var hasSystemBlocker: Bool {
        !locationAlways || !notificationsAllowed || backgroundRefresh != .available
    }
    var isReady: Bool { !hasSystemBlocker && monitoredRegionCount > 0 }
}

@MainActor
final class AmbientRuntimeStore {
    private struct State: Codable {
        var lastNotificationScheduledAt: Date? = nil
        var latestIssue: AmbientRuntimeIssue? = nil
    }

    private let defaults: UserDefaults
    private let key = "ambientRuntimeHealth.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastNotificationScheduledAt: Date? { load().lastNotificationScheduledAt }
    var latestIssue: AmbientRuntimeIssue? { load().latestIssue }

    func recordScheduledNotification(at date: Date = .now) {
        var state = load()
        state.lastNotificationScheduledAt = date
        save(state)
    }

    func recordIssue(_ message: String, at date: Date = .now) {
        var state = load()
        state.latestIssue = AmbientRuntimeIssue(message: message, recordedAt: date)
        save(state)
    }

    func forgetAll() { defaults.removeObject(forKey: key) }

    private func load() -> State {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(State.self, from: data) else {
            return State()
        }
        return state
    }

    private func save(_ state: State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}

/// A counter model that can start empty and be summed across days. Both ambient logs already had
/// exactly these two members before this protocol existed — it names the shape rather than
/// imposing one.
protocol DailyMergeable: Codable, Sendable {
    static var empty: Self { get }
    mutating func merge(_ other: Self)
}

extension SuppressionLog: DailyMergeable {
    static var empty: SuppressionLog { SuppressionLog() }
}

extension AmbientCoverageLog: DailyMergeable {
    static var empty: AmbientCoverageLog { AmbientCoverageLog() }
}

/// Persists the field-test counters locally, partitioned by day so the UI can report the last
/// seven days without any network.
///
/// Generic over the counter model because there are now two of them — `SuppressionLog` (what the
/// gate decided) and `AmbientCoverageLog` (what never reached the gate). They answer different
/// questions and are deliberately separate models, but the storage mechanics — a day key, a JSON
/// dictionary, a rolling seven-day sum, a wipe — are identical, and a second hand-rolled copy of
/// them is a second place for the day-key format to drift.
@MainActor
final class DailyLogStore<Log: DailyMergeable> {
    private let defaults: UserDefaults
    private let key: String
    private let calendar = Calendar(identifier: .gregorian)

    init(defaults: UserDefaults = .standard, key: String) {
        self.defaults = defaults
        self.key = key
    }

    /// Read-modify-write against today's bucket. Takes a mutation rather than a value so callers
    /// never have to load, merge, and store correctly themselves.
    func update(at date: Date = .now, _ mutate: (inout Log) -> Void) {
        var daily = loadDaily()
        let dayKey = dayKey(for: date)
        var log = daily[dayKey] ?? .empty
        mutate(&log)
        daily[dayKey] = log
        save(daily)
    }

    func lastSevenDays(ending date: Date = .now) -> Log {
        let daily = loadDaily()
        var total = Log.empty
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
            if let log = daily[dayKey(for: day)] { total.merge(log) }
        }
        return total
    }

    private func loadDaily() -> [String: Log] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Log].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func save(_ daily: [String: Log]) {
        guard let data = try? JSONEncoder().encode(daily) else { return }
        defaults.set(data, forKey: key)
    }

    func forgetAll() {
        defaults.removeObject(forKey: key)
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0,
                      components.day ?? 0)
    }
}

/// The gate's own counters: of the arrivals that reached `AmbientGate`, what it decided.
@MainActor
final class AmbientDiagnosticsStore {
    private let store: DailyLogStore<SuppressionLog>

    init(defaults: UserDefaults = .standard) {
        store = DailyLogStore(defaults: defaults, key: "ambientDiagnostics.v1")
    }

    func record(_ decision: AmbientGateDecision, at date: Date = .now) {
        store.update(at: date) { $0.record(decision) }
    }

    func lastSevenDays(ending date: Date = .now) -> SuppressionLog {
        store.lastSevenDays(ending: date)
    }

    func forgetAll() { store.forgetAll() }
}

/// The counters `AmbientDiagnosticsStore` structurally cannot hold: what never got a geofence
/// slot, and what got one but never reached the gate. See `AmbientCoverageLog` for why these
/// cannot be derived from the suppression counters.
@MainActor
final class AmbientCoverageStore {
    private let store: DailyLogStore<AmbientCoverageLog>

    init(defaults: UserDefaults = .standard) {
        store = DailyLogStore(defaults: defaults, key: "ambientCoverage.v1")
    }

    func record(_ allocation: RegionAllocation, at date: Date = .now) {
        store.update(at: date) { $0.record(allocation) }
    }

    func recordArrival(_ outcome: AmbientArrivalOutcome,
                       source: AmbientArrivalSource = .regionEntry, at date: Date = .now) {
        store.update(at: date) { $0.recordArrival(outcome, source: source) }
    }

    func recordNotificationDelivery(_ outcome: ArrivalNotificationDelivery, at date: Date = .now) {
        store.update(at: date) { $0.recordNotificationDelivery(outcome) }
    }

    func lastSevenDays(ending date: Date = .now) -> AmbientCoverageLog {
        store.lastSevenDays(ending: date)
    }

    func forgetAll() { store.forgetAll() }
}

/// Muted merchants, keyed by the same string identity the rest of the ambient path uses.
///
/// Was keyed on `StoredMerchant.id` (a UUID). Discovery surfaces merchants that have never been
/// stored locally and so have no UUID to mute — only an Apple Maps place id or a synthesised one.
/// The key is bumped to v2 rather than migrated: a mute is cheap to redo and the old keyspace
/// cannot be mapped onto the new one without inventing identities.
@MainActor
final class AmbientMerchantMuteStore {
    private let defaults: UserDefaults
    private let key = "ambientMutedMerchantIDs.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isMuted(_ merchantKey: String) -> Bool {
        mutedIDs.contains(merchantKey)
    }

    func mute(_ merchantKey: String) {
        var ids = mutedIDs
        ids.insert(merchantKey)
        defaults.set(Array(ids), forKey: key)
    }

    var count: Int { mutedIDs.count }

    func unmute(_ merchantKey: String) {
        var ids = mutedIDs
        ids.remove(merchantKey)
        defaults.set(Array(ids), forKey: key)
    }

    func forgetAll() {
        defaults.removeObject(forKey: key)
    }

    private var mutedIDs: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }
}

/// Ambient delivery, bounded by battery rather than by ambition.
///
/// The unit of monitoring is the shopping AREA, not the storefront. CoreLocation allows 20
/// monitored regions app-wide and twenty shops fit inside one 150 m circle, so storefront-level
/// geofencing spends the entire budget on a single plaza and then fires a dozen simultaneous
/// entries with nothing to arbitrate them. Areas make the budget cover ~20 plazas, and which shop
/// the owner is actually in gets resolved on arrival, from a fresh fix.
///
/// Nothing here decides policy. Whether to spend a MapKit query, how POIs cluster, what a dwell
/// means, and whether a notification fires all live in `CardCopilotStore`/`CardCopilotEngine` as
/// pure functions, because none of it is testable once it is entangled with CoreLocation.
@MainActor
final class AmbientLocationService: NSObject, @MainActor CLLocationManagerDelegate {
    private enum DeliveryError: LocalizedError {
        case missingRecommendedCard(String)

        var errorDescription: String? {
            switch self {
            case .missingRecommendedCard(let cardId):
                return "The recommended card \(cardId) is missing from the catalogue."
            }
        }
    }

    static let shared = AmbientLocationService()
    static let regionPrefix = "ambient.region."
    static let monitoringDidChange = Notification.Name("ambientMonitoringDidChange")
    /// Regions registered by the storefront-era build. Still stopped on rotation so an upgrade
    /// does not leave orphaned geofences monitoring forever.
    static let legacyRegionPrefix = "ambient.merchant."

    static let muteActionIdentifier = "ambient.muteMerchant"
    static let usedRecommendedActionIdentifier = "ambient.usedRecommended"
    static let usedOtherActionIdentifier = "ambient.usedOtherCard"
    static let enterAmountActionIdentifier = "ambient.enterAmount"
    static let notificationCategoryIdentifier = "ambient.recommendation"
    static let amountCategoryIdentifier = "ambient.amountPrompt"

    /// How close a stored, owner-reconciled merchant must be to the arrival fix to claim the
    /// visit. Tight on purpose: `.verified` is the tier that fires at the owner's own threshold.
    private static let verifiedMerchantRadiusMeters: Double = 60

    private let manager = CLLocationManager()
    /// A second manager exists purely so an arrival fix and a significant-change update cannot
    /// arrive on the same callback. `didUpdateLocations` has always meant "the owner moved far
    /// enough to re-aim the geofences"; a one-shot arrival fix means nothing of the kind, and
    /// routing both through one delegate would make every arrival trigger a discovery refresh
    /// and every refresh look like an arrival's answer.
    private let arrivalFixManager = CLLocationManager()
    private let notificationCenter = UNUserNotificationCenter.current()
    private let diagnosticsStore = AmbientDiagnosticsStore()
    private let coverageStore = AmbientCoverageStore()
    private let explanationStore = ArrivalExplanationStore()
    private let runtimeStore = AmbientRuntimeStore()
    private let muteStore = AmbientMerchantMuteStore()
    private let visitStore = AmbientVisitStore()
    private let queryLog = DiscoveryQueryLog()
    private let provider = LiveMerchantProvider()
    private let patronageStore = MerchantPatronageStore()
    private let alertPreferenceStore = ArrivalAlertPreferenceStore()
    private let alertPolicyStore = AmbientAlertPolicyStore()
    private let fieldLogStore = ArrivalFieldLogStore()

    /// Ten metres rather than `kCLLocationAccuracyBest`: storefronts in a plaza are tens of
    /// metres apart, so ten metres is the accuracy that actually decides anything, and it settles
    /// well inside a background wake where Best may not.
    private lazy var arrivalFixRequester = ArrivalFixRequester { [weak self] in
        self?.arrivalFixManager.requestLocation()
    }

    private var modelContainer: ModelContainer?
    private var catalogue: Catalogue?
    private var ownerState: OwnerState?
    private var pendingArrivals: [(target: ArrivalTarget, regionId: String)] = []
    /// Regions whose arrival is being evaluated right now.
    ///
    /// A synthesised arrival holds for up to five seconds waiting on a location fix, and the
    /// visit that would otherwise guard against a duplicate is not opened until after resolution.
    /// Two rotations inside that window — a real possibility, since each significant location
    /// change rotates — would otherwise both synthesise the same arrival.
    private var arrivalsInFlight: Set<String> = []

    private(set) var authorizationStatus: CLAuthorizationStatus

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        arrivalFixManager.delegate = self
        arrivalFixManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Registers every notification category in one operation. `setNotificationCategories`
    /// replaces the previous set, so separate ambient and Wallet registration sites race and one
    /// silently deletes the other's actions.
    func registerNotificationCategories() {
        let openCapture = UNNotificationAction(identifier: "OPEN_CAPTURE_STATUS", title: "Open Capture Status", options: [.foreground])
        let diagnosticCapture = UNNotificationAction(identifier: "OPEN_DIAGNOSTIC", title: "Prepare Diagnostic", options: [.foreground])
        notificationCenter.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.notificationCategoryIdentifier,
                actions: [
                    UNNotificationAction(identifier: Self.usedRecommendedActionIdentifier,
                                         title: String(localized: "ambient.used-this-card",
                                                       defaultValue: "Used this card"),
                                         options: []),
                    UNNotificationAction(identifier: Self.usedOtherActionIdentifier,
                                         title: String(localized: "ambient.used-other-card",
                                                       defaultValue: "Used a different card"),
                                         options: []),
                    UNNotificationAction(identifier: Self.muteActionIdentifier,
                                         title: String(localized: "ambient.mute-merchant",
                                                       defaultValue: "Mute this merchant"),
                                         options: []),
                ],
                intentIdentifiers: [], options: []),
            // The amount prompt is its own category: it fires on EXIT, when the receipt is in
            // hand. Asking on arrival would be asking before the amount exists.
            UNNotificationCategory(
                identifier: Self.amountCategoryIdentifier,
                actions: [
                    UNTextInputNotificationAction(identifier: Self.enterAmountActionIdentifier,
                                                  title: String(localized: "ambient.enter-amount",
                                                                defaultValue: "Enter amount"),
                                                  options: [],
                                                  textInputButtonTitle: String(localized: "ambient.save-amount",
                                                                               defaultValue: "Save"),
                                                  textInputPlaceholder: "0.00"),
                ],
                intentIdentifiers: [], options: []),
            UNNotificationCategory(
                identifier: "WALLET_CAPTURE_RECONNECT",
                actions: [openCapture],
                intentIdentifiers: [],
                options: []),
            UNNotificationCategory(
                identifier: "WALLET_CAPTURE_REVIEW",
                actions: [openCapture, diagnosticCapture],
                intentIdentifiers: [],
                options: []),
        ])
    }

    func configure(modelContainer: ModelContainer, catalogue: Catalogue, ownerState: OwnerState) {
        self.modelContainer = modelContainer
        self.catalogue = catalogue
        self.ownerState = ownerState
        _ = explanationStore.snapshot() // Expire diagnostics when the app next runs.
        LiveActivityManager.shared.onDismissal = { [weak self] regionId in
            self?.visitStore.markLiveActivityDismissed(regionId: regionId)
            // A swipe is an answer too — the quietest kind, and the one an alert that fired but
            // was not wanted produces. Pooling it with "no reaction" would lose it entirely.
            self?.recordEngagement(.dismissedLiveActivity, userInfo: ["regionId": regionId])
        }
        startIfAuthorized()
        let pending = pendingArrivals
        pendingArrivals.removeAll()
        for arrival in pending {
            Task { await evaluateArrival(at: arrival.target, regionId: arrival.regionId) }
        }
    }

    var isEnabled: Bool { authorizationStatus == .authorizedAlways }
    var diagnostics: SuppressionLog { diagnosticsStore.lastSevenDays() }
    var coverage: AmbientCoverageLog { coverageStore.lastSevenDays() }

    func runtimeStatus() async -> AmbientRuntimeStatus {
        let settings = await notificationCenter.notificationSettings()
        let notifications: AmbientNotificationAuthorization
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notifications = .allowed
        case .denied:
            notifications = .denied
        case .notDetermined:
            notifications = .unknown
        @unknown default:
            notifications = .unknown
        }

        let backgroundRefresh: AmbientBackgroundRefreshState
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: backgroundRefresh = .available
        case .denied: backgroundRefresh = .denied
        case .restricted: backgroundRefresh = .restricted
        @unknown default: backgroundRefresh = .restricted
        }

        return AmbientRuntimeStatus(
            locationAlways: manager.authorizationStatus == .authorizedAlways,
            notificationAuthorization: notifications,
            backgroundRefresh: backgroundRefresh,
            monitoredRegionCount: monitoredAmbientRegions.count,
            lastNotificationScheduledAt: runtimeStore.lastNotificationScheduledAt,
            latestIssue: runtimeStore.latestIssue)
    }

    private var monitoredAmbientRegions: [CLRegion] {
        manager.monitoredRegions.filter {
            $0.identifier.hasPrefix(Self.regionPrefix)
                || $0.identifier.hasPrefix(Self.legacyRegionPrefix)
        }
    }

    var mutedMerchantCount: Int { muteStore.count }
    var arrivalExplanations: ArrivalExplanationSnapshot { explanationStore.snapshot() }

    func clearArrivalExplanations() {
        explanationStore.forgetAll()
        NotificationCenter.default.post(name: Self.monitoringDidChange, object: nil)
    }
    func isMerchantMuted(_ identifier: String) -> Bool { muteStore.isMuted(identifier) }

    func unmuteAllMerchants() {
        muteStore.forgetAll()
        refreshNow()
    }

    func unmuteMerchant(_ identifier: String, merchantKey: String, allBranches: Bool) {
        muteStore.unmute(identifier)
        guard allBranches, let modelContainer else { return }
        let context = ModelContext(modelContainer)
        let stored = (try? context.fetch(FetchDescriptor<StoredMerchant>())) ?? []
        for merchant in stored where merchantActivityKey(name: merchant.name, locationIdentifier: merchant.identifier) == merchantKey {
            muteStore.unmute(merchant.identifier ?? merchant.id.uuidString)
        }
        let members = (try? DiscoveryCache(context: context).allMembers()) ?? []
        for member in members where merchantActivityKey(name: member.name, locationIdentifier: member.identifier) == merchantKey {
            muteStore.unmute(member.identifier ?? member.name)
        }
    }

    /// Read iOS's registered set, never the last proposed allocation. An area expands into the
    /// stores it covers so one plaza is not misleadingly presented as one merchant.
    func monitoredPlaces() throws -> [MonitoredArrivalPlace] {
        guard let modelContainer else { return [] }
        let context = ModelContext(modelContainer)
        let stored = try context.fetch(FetchDescriptor<StoredMerchant>())
        let areas = try DiscoveryCache(context: context).allAreas()
        return monitoredAmbientRegions.compactMap { region -> MonitoredArrivalPlace? in
            guard let circle = region as? CLCircularRegion else { return nil }
            var merchants: [NearbyMerchant] = []
            let target = Self.target(for: region.identifier)
            if case .area(let id) = target,
               let area = areas.first(where: { $0.id == id }) {
                merchants = area.members.map {
                    NearbyMerchant(id: $0.identifier ?? $0.name, name: $0.name,
                                   poiCategoryRaw: $0.poiCategoryRaw, latitude: $0.latitude,
                                   longitude: $0.longitude, distanceMeters: nil)
                }
            }
            for merchant in stored {
                switch target {
                case .merchant(let id): guard merchant.id == id else { continue }
                case .area:
                    guard circle.contains(CLLocationCoordinate2D(latitude: merchant.latitude,
                                                                  longitude: merchant.longitude)) else { continue }
                case nil: continue
                }
                merchants.append(NearbyMerchant(id: merchant.identifier ?? merchant.id.uuidString,
                                                name: merchant.name, poiCategoryRaw: merchant.poiCategoryRaw,
                                                latitude: merchant.latitude, longitude: merchant.longitude,
                                                distanceMeters: nil))
            }
            return MonitoredArrivalPlace(id: region.identifier, latitude: circle.center.latitude,
                                         longitude: circle.center.longitude, radiusMeters: circle.radius,
                                         merchants: rankNearbyMerchants(merchants))
        }.sorted { $0.id < $1.id }
    }

    /// Called when the owner erases this iPhone's history.
    ///
    /// Regions are otherwise only refreshed on the next significant location change, which could
    /// be hours away — without this the app keeps monitoring arrivals derived from data that no
    /// longer exists. Every local side-store goes too: the mute list, the counters, the in-flight
    /// visits, and the discovery query log are all keyed to erased rows or to the owner's
    /// movements.
    func forgetLocalHistory() {
        for region in manager.monitoredRegions
        where region.identifier.hasPrefix(Self.regionPrefix)
            || region.identifier.hasPrefix(Self.legacyRegionPrefix) {
            manager.stopMonitoring(for: region)
        }
        muteStore.forgetAll()
        diagnosticsStore.forgetAll()
        coverageStore.forgetAll()
        explanationStore.forgetAll()
        runtimeStore.forgetAll()
        visitStore.forgetAll()
        queryLog.forgetAll()
        patronageStore.forgetAll()
        alertPreferenceStore.forgetAll()
        alertPolicyStore.forgetAll()
        fieldLogStore.forgetAll()
        NotificationCenter.default.post(name: Self.monitoringDidChange, object: nil)
    }

    /// Called only from the dedicated explainer screen, before either system prompt appears.
    func requestAlwaysAuthorization() async {
        do {
            let settings = await notificationCenter.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
                if !granted {
                    runtimeStore.recordIssue("Notifications were not allowed. Arrival advice cannot appear until notifications are enabled in Settings.")
                }
            } else if settings.authorizationStatus == .denied {
                runtimeStore.recordIssue("Notifications are off for PickMe. Enable them in Settings to receive arrival advice.")
            }
        } catch {
            runtimeStore.recordIssue("PickMe could not request notification permission: \(error.localizedDescription)")
        }
        manager.requestAlwaysAuthorization()
    }

    /// Called during `didFinishLaunching`, including a Core Location background relaunch. Region
    /// and significant-change services persist at the system level, but their manager/delegate do
    /// not; recreating this shared service and restarting delivery is required to receive the
    /// queued event.
    func resumeMonitoringIfAuthorized() {
        startIfAuthorized()
    }

    /// Re-aims regions after an owner changes a merchant-level alert preference.
    func refreshNow() {
        guard manager.authorizationStatus == .authorizedAlways else { return }
        // Apply edits to the cached set immediately, even if the next location fix fails.
        if let modelContainer, let location = manager.location {
            rotateRegions(around: location.coordinate, cache: DiscoveryCache(context: ModelContext(modelContainer)))
        }
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            runtimeStore.recordIssue("Always Location access is required for arrival alerts.")
        }
        startIfAuthorized()
        NotificationCenter.default.post(name: Self.monitoringDidChange, object: nil)
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        NotificationCenter.default.post(name: Self.monitoringDidChange, object: nil)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        guard manager !== arrivalFixManager else {
            if let fix = Self.arrivalFix(from: location) {
                arrivalFixRequester.deliver(fix)
            } else {
                // CoreLocation does emit a negative `horizontalAccuracy`, which means the fix is
                // invalid rather than merely coarse. Ranking storefronts against it would be
                // worse than not ranking them at all.
                arrivalFixRequester.fail()
            }
            return
        }
        Task { await refreshDiscovery(around: location) }
    }

    /// The one place a `CLLocation` becomes the pure `ArrivalFix` the resolution policy takes.
    private static func arrivalFix(from location: CLLocation) -> ArrivalFix? {
        guard location.horizontalAccuracy >= 0 else { return nil }
        return ArrivalFix(latitude: location.coordinate.latitude,
                          longitude: location.coordinate.longitude,
                          horizontalAccuracyMeters: location.horizontalAccuracy,
                          capturedAt: location.timestamp)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let target = Self.target(for: region.identifier) else { return }
        guard modelContainer != nil, catalogue != nil, ownerState != nil else {
            if !pendingArrivals.contains(where: { $0.regionId == region.identifier }) {
                pendingArrivals.append((target, region.identifier))
            }
            return
        }
        Task { await evaluateArrival(at: target, regionId: region.identifier) }
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState,
                         for region: CLRegion) {
        guard state == .inside, let target = Self.target(for: region.identifier) else { return }
        // A region the owner is still inside keeps reporting `.inside` on every rotation. The
        // in-flight visit is what separates "they just got here" from "they have been here for
        // twenty minutes and we have rotated four times since".
        guard visitStore.visit(forRegionId: region.identifier) == nil,
              !arrivalsInFlight.contains(region.identifier) else { return }
        guard modelContainer != nil, catalogue != nil, ownerState != nil else {
            if !pendingArrivals.contains(where: { $0.regionId == region.identifier }) {
                pendingArrivals.append((target, region.identifier))
            }
            return
        }
        arrivalsInFlight.insert(region.identifier)
        Task {
            await evaluateArrival(at: target, regionId: region.identifier, source: .alreadyInside)
            arrivalsInFlight.remove(region.identifier)
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard Self.target(for: region.identifier) != nil else { return }
        evaluateExit(regionId: region.identifier)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager !== arrivalFixManager else {
            // No fix is a complete answer. Releasing the arrival now, rather than making it wait
            // out a window nothing will arrive in, is the difference between resolving the way
            // this always did and not resolving at all.
            arrivalFixRequester.fail()
            return
        }
        runtimeStore.recordIssue("Location monitoring failed: \(error.localizedDescription)")
        NotificationCenter.default.post(name: Self.monitoringDidChange, object: nil)
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?,
                         withError error: Error) {
        let subject = region.map { " for \($0.identifier)" } ?? ""
        runtimeStore.recordIssue("Arrival-region monitoring failed\(subject): \(error.localizedDescription)")
        NotificationCenter.default.post(name: Self.monitoringDidChange, object: nil)
    }

    // MARK: - Discovery

    /// One significant location change: decide whether to look around, then re-aim the geofences.
    ///
    /// The gate runs before the query, never after. A cached cell — including one cached as
    /// *empty* — costs no network at all, which is what takes the steady state to one to three
    /// queries a day once the owner's usual ground is known.
    private func refreshDiscovery(around location: CLLocation) async {
        guard let modelContainer, manager.authorizationStatus == .authorizedAlways else { return }
        let cache = DiscoveryCache(context: ModelContext(modelContainer))
        let key = cellKey(latitude: location.coordinate.latitude,
                          longitude: location.coordinate.longitude)

        let decision = shouldQueryDiscovery(cellKey: key,
                                            cachedEntry: try? cache.entry(forCellKey: key),
                                            speedMetersPerSecond: location.speed,
                                            recentQueryTimes: queryLog.recent(),
                                            now: .now)
        if case .query = decision {
            do {
                let pois = try await provider.nearby(latitude: location.coordinate.latitude,
                                                     longitude: location.coordinate.longitude)
                try cache.record(cellKey: key, areas: clusterIntoAreas(pois), at: .now)
                queryLog.record()
            } catch {
                // Includes MKError.loadingThrottled. Back off silently and let the next
                // significant change retry — never retry inside one background wake.
            }
        }

        // Retention pruning rides the same wake rather than a timer: it is the only moment the
        // app is reliably alive, and a cache the owner has stopped visiting must still expire.
        try? cache.prune(now: .now)
        rotateRegions(around: location.coordinate, cache: cache)
    }

    /// Re-aims the 20-region budget at wherever the owner now is.
    ///
    /// Discovered areas and owner-confirmed merchants compete for the same budget, and confirmed
    /// merchants win ties: they are the only ones that fire at the owner's own threshold, so a
    /// slot spent on one is worth more than a slot spent on a guess.
    private func rotateRegions(around coordinate: CLLocationCoordinate2D, cache: DiscoveryCache) {
        guard let modelContainer, manager.authorizationStatus == .authorizedAlways else { return }
        let context = ModelContext(modelContainer)

        let areas = ((try? cache.allAreas()) ?? [])
            .filter { area in
                area.members.contains { permitsMonitoring(name: $0.name, identifier: $0.identifier ?? $0.name,
                                                          latitude: $0.latitude, longitude: $0.longitude) }
            }
            .sorted {
                let left = greatCircleDistanceMeters(fromLatitude: coordinate.latitude, fromLongitude: coordinate.longitude,
                                                     toLatitude: $0.centroidLatitude, toLongitude: $0.centroidLongitude)
                let right = greatCircleDistanceMeters(fromLatitude: coordinate.latitude, fromLongitude: coordinate.longitude,
                                                      toLatitude: $1.centroidLatitude, toLongitude: $1.centroidLongitude)
                return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
            }.prefix(maximumMonitoredRegions)
        let nearbyAreas = Array(areas)

        let merchants = ((try? context.fetch(FetchDescriptor<StoredMerchant>())) ?? [])
            .filter { CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: $0.latitude,
                                                                          longitude: $0.longitude))
                      && ($0.latitude != 0 || $0.longitude != 0)
                      && permitsMonitoring(name: $0.name, identifier: $0.identifier ?? $0.id.uuidString,
                                           latitude: $0.latitude, longitude: $0.longitude) }

        // Read once for the whole rotation, exactly as the arrival path does: this is a background
        // wake and `merchants` can hold every merchant the owner has ever saved.
        let frequentedKeys = effectiveFrequentedKeys()
        let standings = merchants.map {
            storedMerchantRegionTier(
                confirmedCategory: $0.confirmedCategory,
                isFrequented: explicitlyPrioritized(name: $0.name,
                                                    identifier: $0.identifier,
                                                    latitude: $0.latitude,
                                                    longitude: $0.longitude)
                    ?? (MerchantRecognizer.recognise($0.name)
                        .map { frequentedKeys.contains($0.id) } ?? false))
        }

        // Which area, if any, already covers each merchant. Computed once and used twice: a
        // covered merchant needs no region of its own (the area wake resolves to it anyway, and a
        // duplicate would burn a slot for nothing), and the area inherits its standing so the
        // coverage counters do not report a weekly grocery run as anonymous ground.
        let coveringAreaIndex = merchants.map { merchant in
            nearbyAreas.firstIndex { area in
                greatCircleDistanceMeters(fromLatitude: area.centroidLatitude,
                                          fromLongitude: area.centroidLongitude,
                                          toLatitude: merchant.latitude,
                                          toLongitude: merchant.longitude) <= area.radiusMeters
            }
        }

        var specs: [String: (latitude: Double, longitude: Double, radius: Double)] = [:]
        var candidates: [RegionCandidate] = []
        for (offset, merchant) in merchants.enumerated() where coveringAreaIndex[offset] == nil {
            let id = "merchant:\(merchant.id.uuidString)"
            specs[id] = (merchant.latitude, merchant.longitude, minimumAreaRadiusMeters)
            candidates.append(RegionCandidate(
                id: id,
                tier: standings[offset],
                distanceMeters: greatCircleDistanceMeters(fromLatitude: coordinate.latitude,
                                                          fromLongitude: coordinate.longitude,
                                                          toLatitude: merchant.latitude,
                                                          toLongitude: merchant.longitude)))
        }
        for (areaOffset, area) in nearbyAreas.enumerated() {
            let id = "area:\(area.id.uuidString)"
            specs[id] = (area.centroidLatitude, area.centroidLongitude, area.radiusMeters)
            let covered = coveringAreaIndex.enumerated()
                .filter { $0.element == areaOffset }
                .map { standings[$0.offset] }
            candidates.append(RegionCandidate(
                id: id,
                tier: areaRegionTier(coveringStandings: covered),
                distanceMeters: greatCircleDistanceMeters(fromLatitude: coordinate.latitude,
                                                          fromLongitude: coordinate.longitude,
                                                          toLatitude: area.centroidLatitude,
                                                          toLongitude: area.centroidLongitude)))
        }

        // Distance still decides — this is the shipping policy, not a new one. What is new is
        // that the ordering is total (so an unchanged world produces an unchanged region set) and
        // that what fell off the end is now counted instead of silently discarded.
        let allocation = allocateRegionBudget(candidates, limit: maximumMonitoredRegions)
        coverageStore.record(allocation)

        let desiredIDs = Set(allocation.granted.map { Self.regionPrefix + $0.id })
        for region in monitoredAmbientRegions where !desiredIDs.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }

        let ceiling = manager.maximumRegionMonitoringDistance
        for candidate in allocation.granted {
            guard let spec = specs[candidate.id] else { continue }
            let radius = min(max(spec.radius, minimumAreaRadiusMeters), ceiling)
            guard radius >= minimumAreaRadiusMeters else { continue }
            let identifier = Self.regionPrefix + candidate.id
            if let existing = manager.monitoredRegions.first(where: { $0.identifier == identifier }) as? CLCircularRegion,
               existing.center.latitude == spec.latitude, existing.center.longitude == spec.longitude,
               existing.radius == radius, existing.notifyOnEntry, existing.notifyOnExit {
                continue
            }
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: spec.latitude, longitude: spec.longitude),
                radius: radius,
                identifier: identifier)
            region.notifyOnEntry = true
            // Exit is what makes dwell measurable, and dwell is what separates a purchase from
            // walking past — and what decides which of several overlapping regions was real.
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
            // iOS delivers `didEnterRegion` only on a boundary *crossing*, so a region registered
            // around the owner cannot fire for the visit that created it — and rotation runs off
            // a significant location change, which is roughly the event that happens when someone
            // arrives somewhere new. Without this question, the first visit to any newly
            // discovered place is silent by construction, and invisible to every counter, since
            // `arrivals` counts wakes that happened.
            manager.requestState(for: region)
        }
        NotificationCenter.default.post(name: Self.monitoringDidChange, object: nil)
    }

    private func permitsMonitoring(name: String, identifier: String, latitude: Double, longitude: Double) -> Bool {
        !muteStore.isMuted(identifier)
            && explicitlyPrioritized(name: name, identifier: identifier, latitude: latitude, longitude: longitude) != false
    }

    // MARK: - Arrival

    private enum ArrivalTarget {
        case area(UUID)
        case merchant(UUID)
    }

    private static func target(for identifier: String) -> ArrivalTarget? {
        guard identifier.hasPrefix(regionPrefix) else { return nil }
        let body = String(identifier.dropFirst(regionPrefix.count))
        let parts = body.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "area": return .area(id)
        case "merchant": return .merchant(id)
        default: return nil
        }
    }

    /// A merchant resolved at the moment of arrival, with the confidence that resolution earns.
    private struct ResolvedArrival {
        let merchant: NearbyMerchant
        let prediction: CategoryPrediction
        let confidence: AmbientMerchantConfidence
        /// The merchant category code, when the name resolved to a known merchant. Reaches the
        /// scoring context so the catalogue's `mccInclude` rules can see it — without this the
        /// index's best evidence is read and then dropped.
        let mcc: Int?
        /// Mute identity. A string because discovered POIs have no local UUID.
        let muteKey: String

        // Everything below is for the field log alone. Carried on the resolution rather than
        // recomputed later because it describes the decision *as it was made* — which candidates
        // were on the table, in what order, and which rung answered. Recomputing it after the
        // fact would be describing a different decision.
        let candidates: [ArrivalCandidateRecord]
        let chosenIndex: Int?
        let rung: ArrivalResolutionRung
        let areaCentroidLatitude: Double?
        let areaCentroidLongitude: Double?
        let areaRadiusMeters: Double?
    }

    /// One candidate as the log records it. Distance is measured from the owner when there is a
    /// fix, and absent otherwise — an absent distance is a fact about the arrival, not a zero.
    private static func candidateRecord(name: String, poiCategoryRaw: String?,
                                        latitude: Double, longitude: Double,
                                        resolution: DiscoveredMerchantResolution,
                                        fix: ArrivalFix?) -> ArrivalCandidateRecord {
        let indexed = MerchantRecognizer.recognise(name)
        return ArrivalCandidateRecord(
            name: name, poiCategoryRaw: poiCategoryRaw, latitude: latitude, longitude: longitude,
            distanceFromFixMeters: fix.map {
                greatCircleDistanceMeters(fromLatitude: $0.latitude, fromLongitude: $0.longitude,
                                          toLatitude: latitude, toLongitude: longitude)
            },
            recognisedByPack: indexed != nil,
            resolvedCategory: resolution.prediction.category,
            confidence: resolution.confidence,
            // Named, not merely counted, and named on both paths — chain containment is only
            // comparable between a geofence arrival and a Radar scan if both say which row.
            preIndexMerchantId: indexed?.id)
    }

    /// `source` is provenance, not a quality grade: a synthesised arrival is exactly as real a
    /// visit as a delivered one, and takes exactly the same path — including opening a visit, so
    /// dwell and the exit amount prompt still work.
    private func evaluateArrival(at target: ArrivalTarget, regionId: String,
                                 source: AmbientArrivalSource = .regionEntry) async {
        guard let modelContainer, let catalogue, let ownerState else { return }
        let attemptID = UUID()
        let startedAt = Date.now
        let explanationGeneration = explanationStore.generation
        func explain(_ outcome: ArrivalExplanationRecord.Outcome, merchant: NearbyMerchant? = nil,
                     reasons: Set<AmbientSuppressionReason> = [], activity: LiveActivityRequestOutcome = .notRequested,
                     notificationPermission: ArrivalExplanationRecord.NotificationPermission? = nil) {
            explanationStore.record(attemptID: attemptID, startedAt: startedAt, outcome: outcome,
                                    merchantIdentifier: merchant?.id, regionIdentifier: regionId,
                                    reasons: reasons, activity: activity, notificationPermission: notificationPermission,
                                    generation: explanationGeneration)
            NotificationCenter.default.post(name: Self.monitoringDidChange, object: nil)
        }
        explain(.checking)
        // Hold the arrival open until iOS says where the owner is, or until the window closes.
        // `nil` is a complete answer: every use of it below falls back to exactly the behaviour
        // this had before a fix was ever requested.
        let fix = await arrivalFixRequester.fix()
        let context = ModelContext(modelContainer)
        // Both of the dropouts below used to `return` in silence, which made a background wake
        // that produced nothing indistinguishable from a wake that never happened.
        guard let arrival = resolve(target, fix: fix, context: context) else {
            coverageStore.recordArrival(.unresolved, source: source)
            explain(.unresolved)
            return
        }

        // Dwell starts now regardless of whether anything fires. An exit still has to be able to
        // tell a twenty-minute shop from a forty-second walk-by.
        visitStore.begin(AmbientVisit(enteredAt: .now, didEngage: false, purchaseId: nil,
                                      merchantName: arrival.merchant.name),
                         forRegionId: regionId)

        // The dials are read once per arrival and then carried, so the estimate the engine
        // scored and the multiplier the gate applied are guaranteed to come from one policy —
        // which is what makes a field-log record replayable at all.
        let policy = activeAlertPolicy
        let purchase = ambientPurchaseContext(merchant: arrival.merchant,
                                              category: arrival.prediction.category,
                                              mcc: arrival.mcc,
                                              estimate: policy.amountEstimate)
        guard case .advised(let recommendation) = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)
            .recommend(purchase, asOf: Date().formatted(.iso8601.year().month().day())) else {
            coverageStore.recordArrival(.notAdvised, source: source)
            explain(.noRecommendation, merchant: arrival.merchant)
            return
        }
        coverageStore.recordArrival(.resolved, source: source)
        let advantageCad = recommendation.advantageOverDefaultCad ?? 0
        let advantagePP = purchase.amountCad > 0 ? advantageCad / purchase.amountCad * 100 : 0

        let explicit = explicitlyPrioritized(name: arrival.merchant.name,
                                             identifier: arrival.merchant.id,
                                             latitude: arrival.merchant.latitude,
                                             longitude: arrival.merchant.longitude)
        // Choosing a place expresses interest; it does not verify its category. Preserve unknown,
        // category-only and owner-verified evidence, and do not lift an ambiguous brand like Walmart.
        let canPrioritize = explicit == true && arrival.confidence == .brandMatched
            && arrival.prediction.category != "other" && arrival.prediction.candidates.count == 1
        let gateInput = AmbientGateInput(
            merchantConfidence: canPrioritize ? .frequented : arrival.confidence,
            recommendedCardId: recommendation.winner.cardId,
            defaultCardId: ownerState.defaultCardId,
            advantage: AmbientAdvantage(percentagePoints: advantagePP, cad: advantageCad),
            switchThreshold: policy.threshold(ownerThreshold: ownerState.switchThreshold),
            isMuted: muteStore.isMuted(arrival.muteKey) || explicit == false,
            unverifiedAdvantageMultiplier: policy.unverifiedAdvantageMultiplier,
            frequentedAdvantageMultiplier: policy.frequentedAdvantageMultiplier,
            categoryAdvantageMultiplier: policy.categoryAdvantageMultiplier
        )
        let decision = AmbientGate.evaluate(gateInput)
        // Delivery truth. `.neverRequested` is the honest default for every tier below
        // `.interrupt`: those arrivals asked nothing of iOS, and the field log has to say so
        // rather than leave a gap a reader would fill with "delivery failed".
        var notificationRequestIdentifier: String?
        var notificationDelivery: ArrivalNotificationDelivery = .neverRequested
        // The gate no longer decides whether PickMe is visible — only how loud it is. Silence is
        // now reserved for the one reason that is the owner's own instruction.
        switch decision.tier {
        case .silent:
            diagnosticsStore.record(decision)
            explain(.evaluated, merchant: arrival.merchant, reasons: decision.suppressionReasons)

        case .presence:
            // Deliberately no recommendation: the merchant could not be identified, and naming a
            // card here would be a confident wrong answer.
            let activity = presentArrivalActivity(tier: .presence, arrival: arrival, recommendation: nil,
                                                  catalogue: catalogue, regionId: regionId)
            diagnosticsStore.record(decision)
            explain(.evaluated, merchant: arrival.merchant, reasons: decision.suppressionReasons, activity: activity)

        case .confirm:
            let activity = presentArrivalActivity(tier: .confirm, arrival: arrival, recommendation: recommendation,
                                                  catalogue: catalogue, regionId: regionId)
            diagnosticsStore.record(decision)
            explain(.evaluated, merchant: arrival.merchant, reasons: decision.suppressionReasons, activity: activity)

        case .interrupt:
            let settings = await notificationCenter.notificationSettings()
            let notificationPermission: ArrivalExplanationRecord.NotificationPermission
            switch settings.authorizationStatus {
            case .authorized, .ephemeral: notificationPermission = .allowed
            case .provisional: notificationPermission = .quiet
            case .denied, .notDetermined: notificationPermission = .blocked
            @unknown default: notificationPermission = .unknown
            }
            do {
                let identifier = try await scheduleArrivalNotification(
                    arrival: arrival, recommendation: recommendation,
                    catalogue: catalogue, regionId: regionId)
                notificationRequestIdentifier = identifier
                notificationDelivery = await sampleDelivery(of: identifier, requestFailed: false)
                let activity = presentArrivalActivity(tier: .interrupt, arrival: arrival,
                                                      recommendation: recommendation, catalogue: catalogue,
                                                      regionId: regionId)
                // A "fired" count means iOS accepted the notification request, not merely that the
                // pure gate approved one that may have failed before reaching Notification Center.
                diagnosticsStore.record(decision)
                explain(.notificationAccepted, merchant: arrival.merchant, activity: activity,
                        notificationPermission: notificationPermission)
            } catch {
                notificationDelivery = .requestFailed
                explain(.notificationFailed, merchant: arrival.merchant, notificationPermission: notificationPermission)
                runtimeStore.recordIssue("Arrival advice was approved but could not be delivered: \(error.localizedDescription)")
            }
        }

        #if FIELD_DIAGNOSTICS
        // Gated with the rest of the instrument. The counter holds no identity and no timing, but
        // the privacy policy does not disclose it either, and everything in this expansion except
        // the correction loop is removed before submission.
        coverageStore.recordNotificationDelivery(notificationDelivery)
        #endif

        recordFieldLog(arrival: arrival, regionId: regionId, source: source, fix: fix,
                       policy: policy, estimatedAmountCad: purchase.amountCad,
                       gateInput: gateInput, decision: decision,
                       notificationRequestIdentifier: notificationRequestIdentifier,
                       notificationDelivery: notificationDelivery)
    }

    /// One record per arrival, dev-only.
    ///
    /// Written after the delivery switch, so the tier recorded is the one that was acted on. It
    /// records coordinates and merchant names, which the shipping counters deliberately do not —
    /// which is exactly why it is compiled out of anything an owner could install.
    private func recordFieldLog(arrival: ResolvedArrival, regionId: String,
                                source: AmbientArrivalSource, fix: ArrivalFix?,
                                policy: AmbientAlertPolicy, estimatedAmountCad: Double,
                                gateInput: AmbientGateInput, decision: AmbientGateDecision,
                                notificationRequestIdentifier: String?,
                                notificationDelivery: ArrivalNotificationDelivery) {
        #if FIELD_DIAGNOSTICS
        guard let catalogue, let ownerState else { return }
        // Each candidate carries the card the engine would have chosen for it. Scored here, at
        // capture, because card-equivalence accuracy — the number that decides the rework — has
        // to be a pure comparison in the export rather than a re-scoring job against whichever
        // catalogue happened to be current that week.
        let engine = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)
        let today = Date().formatted(.iso8601.year().month().day())
        let candidates = arrival.candidates.map { candidate -> ArrivalCandidateRecord in
            var scored = candidate
            let merchant = NearbyMerchant(id: candidate.name, name: candidate.name,
                                          poiCategoryRaw: candidate.poiCategoryRaw,
                                          latitude: candidate.latitude,
                                          longitude: candidate.longitude, distanceMeters: nil)
            let context = ambientPurchaseContext(merchant: merchant,
                                                 category: candidate.resolvedCategory,
                                                 estimate: policy.amountEstimate)
            if case .advised(let recommendation) = engine.recommend(context, asOf: today) {
                scored.recommendedCardId = recommendation.winner.cardId
                scored.advantageOverDefaultCad = recommendation.advantageOverDefaultCad
            }
            return scored
        }

        fieldLogStore.record(ArrivalFieldRecord(
            recordedAt: .now, regionId: regionId, source: source,
            areaCentroidLatitude: arrival.areaCentroidLatitude,
            areaCentroidLongitude: arrival.areaCentroidLongitude,
            areaRadiusMeters: arrival.areaRadiusMeters,
            fix: fix,
            // An explicit marker, not an inference from a null: "the window closed" and "there
            // was no fix for some other reason" are different facts about the arrival.
            fixTimedOut: fix == nil,
            candidates: candidates, chosenCandidateIndex: arrival.chosenIndex,
            rung: arrival.rung,
            resolvedMerchantName: arrival.merchant.name,
            resolvedCategory: arrival.prediction.category,
            estimatedAmountCad: estimatedAmountCad,
            gateInput: gateInput, deliveryTier: decision.tier,
            suppressionReasons: Array(decision.suppressionReasons),
            policy: policy,
            notificationRequestIdentifier: notificationRequestIdentifier,
            notificationDeliveryAtSchedule: notificationDelivery,
            discriminability: discriminability(candidates: candidates.map(\.site), fix: fix)))
        #endif
    }

    /// The log, with Wallet captures joined and the metrics derived.
    ///
    /// Receipts are read here rather than kept alongside the records, because a charge posts
    /// minutes to hours after the arrival and the join is a pure function worth re-running.
    func fieldLogExport() -> Data? {
        fieldLogStore.exportJSON(receipts: walletReceipts())
    }

    var fieldLogRecordCount: Int { fieldLogStore.all().count }

    private func walletReceipts() -> [ArrivalReceipt] {
        guard let modelContainer else { return [] }
        let context = ModelContext(modelContainer)
        let purchases = (try? context.fetch(FetchDescriptor<StoredPurchase>())) ?? []
        return purchases.compactMap { purchase in
            // Wallet-sourced only. A purchase the owner typed in is not independent evidence of
            // which store they were in — it came from the same arrival this is trying to check.
            guard purchase.walletEventId != nil, let amount = purchase.amountCad,
                  let descriptor = purchase.merchantLabel ?? purchase.prediction?.merchantName
            else { return nil }
            return ArrivalReceipt(merchantDescriptor: descriptor, amountCad: amount,
                                  capturedAt: purchase.createdAt)
        }
    }

    private func recordEngagement(_ action: ArrivalEngagement, userInfo: [AnyHashable: Any]) {
        #if FIELD_DIAGNOSTICS
        guard let regionId = userInfo["regionId"] as? String else { return }
        fieldLogStore.recordEngagement(action, regionId: regionId)
        #endif
    }

    /// Resolution ladder, cheapest and most certain first. Nothing here writes to the log — a
    /// geofence entry is not evidence that anything was bought.
    private func resolve(_ target: ArrivalTarget, fix: ArrivalFix?,
                         context: ModelContext) -> ResolvedArrival? {
        switch target {
        case .merchant(let id):
            guard let merchant = try? context.fetch(FetchDescriptor<StoredMerchant>(
                predicate: #Predicate { $0.id == id })).first else { return nil }
            return resolved(storedMerchant: merchant, frequentedKeys: effectiveFrequentedKeys(),
                            fix: fix)

        case .area(let id):
            guard let area = try? context.fetch(FetchDescriptor<ShoppingArea>(
                predicate: #Predicate { $0.id == id })).first else { return nil }

            // Rung 1: an owner-reconciled or explicitly chosen store inside this area, measured from the
            // owner rather than from the middle of the plaza. Areas run to
            // `maximumAreaRadiusMeters`, so measuring the 60 m radius from the centroid meant a
            // confirmed store near the edge could never claim its own visit — confirming a
            // terminal by hand did not reliably promote it.
            let origin = arrivalOrigin(fix: fix,
                                       areaCentroidLatitude: area.centroidLatitude,
                                       areaCentroidLongitude: area.centroidLongitude)
            let merchants = (try? context.fetch(FetchDescriptor<StoredMerchant>())) ?? []
            let nearestChosenOrConfirmed = merchants
                .map { ($0, greatCircleDistanceMeters(fromLatitude: origin.latitude,
                                                      fromLongitude: origin.longitude,
                                                      toLatitude: $0.latitude,
                                                      toLongitude: $0.longitude)) }
                .filter {
                    $0.1 <= Self.verifiedMerchantRadiusMeters
                        && ($0.0.confirmedCategory != nil
                            || explicitlyPrioritized(name: $0.0.name, identifier: $0.0.identifier,
                                                     latitude: $0.0.latitude, longitude: $0.0.longitude) == true)
                }
                .min { $0.1 < $1.1 }?.0
            // Read once for the whole arrival rather than per candidate name: an area holds
            // several members, and this is a background wake.
            let frequentedKeys = effectiveFrequentedKeys()
            if let nearestChosenOrConfirmed {
                return resolved(storedMerchant: nearestChosenOrConfirmed, frequentedKeys: frequentedKeys,
                                fix: fix, rung: .confirmedMerchantNearby, area: area)
            }

            // Rung 2: a cached POI whose name resolves to a merchant the app can name.
            // Checkable, unlike a bare pin — which is the whole basis for the middle tier.
            //
            // The tier and the category come from one call, deliberately. Deciding them
            // separately is how a notification ends up confident about a store whose coding was
            // guessed from a POI pin — the failure the three tiers exist to prevent.
            let resolved = area.members.map {
                ($0, resolveDiscoveredMerchant(name: $0.name, poiCategoryRaw: $0.poiCategoryRaw,
                                               frequentedKeys: frequentedKeys))
            }
            // Nearest-first against the owner's own fix. Before this, the answer was
            // `resolved.first`, whose order came from `clusterIntoAreas` sorting members by
            // `(latitude, longitude, id)` — a sort that exists to keep region registration stable
            // across rotations and silently became the resolution answer, naming the
            // southernmost recognised store in the plaza. That sort is untouched; the ordering
            // happens here, at the point of resolution. With no fix, the input order stands.
            let ranked = nearestFirstOrder(area.members.map {
                ArrivalSite(latitude: $0.latitude, longitude: $0.longitude)
            }, from: fix).map { resolved[$0] }
            // A plaza holding one recognisable store and four unnamed pins is answered by the
            // store; a plaza of nothing but pins still answers, at `.unknown`, and is suppressed.
            // The index, not just the element: the log records the whole ranked set and which
            // position won, and re-finding the winner by name afterwards would silently pick the
            // first of two identically named units in one plaza.
            guard let chosenIndex = ranked.firstIndex(where: { $0.1.confidence != .unknown })
                    ?? (ranked.isEmpty ? nil : 0) else { return nil }
            let (member, resolution) = ranked[chosenIndex]
            let nearby = NearbyMerchant(id: member.identifier ?? member.name, name: member.name,
                                        poiCategoryRaw: member.poiCategoryRaw,
                                        latitude: member.latitude, longitude: member.longitude,
                                        distanceMeters: nil)
            return ResolvedArrival(
                merchant: nearby,
                prediction: resolution.prediction,
                confidence: resolution.confidence,
                mcc: resolution.mcc,
                muteKey: nearby.id,
                candidates: ranked.map { member, resolution in
                    Self.candidateRecord(name: member.name, poiCategoryRaw: member.poiCategoryRaw,
                                         latitude: member.latitude, longitude: member.longitude,
                                         resolution: resolution, fix: fix)
                },
                chosenIndex: chosenIndex,
                rung: .areaMember,
                areaCentroidLatitude: area.centroidLatitude,
                areaCentroidLongitude: area.centroidLongitude,
                areaRadiusMeters: area.radiusMeters)
        }
    }

    private func resolved(storedMerchant merchant: StoredMerchant,
                          frequentedKeys: Set<String>,
                          fix: ArrivalFix? = nil,
                          rung: ArrivalResolutionRung = .storedMerchantRegion,
                          area: ShoppingArea? = nil) -> ResolvedArrival {
        let resolution = resolveStoredMerchant(name: merchant.name,
                                               poiCategoryRaw: merchant.poiCategoryRaw,
                                               confirmedCategory: merchant.confirmedCategory,
                                               confirmationCount: merchant.confirmationCount,
                                               frequentedKeys: frequentedKeys)
        let nearby = NearbyMerchant(id: merchant.identifier ?? merchant.id.uuidString,
                                    name: merchant.name, poiCategoryRaw: merchant.poiCategoryRaw,
                                    latitude: merchant.latitude, longitude: merchant.longitude,
                                    distanceMeters: nil)
        // The candidate set for a stored-merchant answer is the area's members plus the
        // stored merchant itself, which is deliberately not one of them: a confirmed terminal
        // is a different kind of row from a cached POI. Appending it keeps `chosenCandidate`
        // meaningful on every rung, which is what card equivalence reads.
        var candidates = (area?.members ?? []).map { member in
            Self.candidateRecord(
                name: member.name, poiCategoryRaw: member.poiCategoryRaw,
                latitude: member.latitude, longitude: member.longitude,
                resolution: resolveDiscoveredMerchant(name: member.name,
                                                      poiCategoryRaw: member.poiCategoryRaw,
                                                      frequentedKeys: frequentedKeys),
                fix: fix)
        }
        candidates.append(Self.candidateRecord(
            name: merchant.name, poiCategoryRaw: merchant.poiCategoryRaw,
            latitude: merchant.latitude, longitude: merchant.longitude,
            resolution: resolution, fix: fix))
        return ResolvedArrival(merchant: nearby, prediction: resolution.prediction,
                               confidence: resolution.confidence,
                               mcc: resolution.mcc,
                               muteKey: nearby.id,
                               candidates: candidates,
                               chosenIndex: candidates.count - 1,
                               rung: rung,
                               areaCentroidLatitude: area?.centroidLatitude,
                               areaCentroidLongitude: area?.centroidLongitude,
                               areaRadiusMeters: area?.radiusMeters)
    }

    /// Chain choices lift every recognised branch. Exact choices are checked against the POI id
    /// and a 100 m coordinate fallback. Nil deliberately preserves automatic learning.
    private func explicitlyPrioritized(name: String, identifier: String?,
                                       latitude: Double, longitude: Double) -> Bool? {
        guard let merchantKey = merchantActivityKey(name: name,
                                                    locationIdentifier: identifier) else { return nil }
        return alertPreferenceStore.permits(merchantKey: merchantKey,
                                            locationIdentifier: identifier,
                                            latitude: latitude,
                                            longitude: longitude)
    }

    /// The policy an arrival is actually evaluated against.
    ///
    /// A release build evaluates the shipped policy, full stop. The dials exist so a field build
    /// can be moved while the suppression counters accrue — the whole argument for making them
    /// adjustable is that the right threshold is what the engagement data says — and they are
    /// deliberately not a hidden owner setting.
    var activeAlertPolicy: AmbientAlertPolicy {
        #if FIELD_DIAGNOSTICS
        return alertPolicyStore.policy
        #else
        return .shipped
        #endif
    }

    func saveAlertPolicy(_ policy: AmbientAlertPolicy) {
        alertPolicyStore.save(policy)
    }

    private func effectiveFrequentedKeys() -> Set<String> {
        patronageStore.frequentedKeys().union(alertPreferenceStore.chainKeys())
    }

    // MARK: - Exit

    /// The other half of dwell. Everything the exit decides is in `dwellDecision`; this only
    /// carries the outcome out to a notification.
    private func evaluateExit(regionId: String) {
        LiveActivityManager.shared.endActivity()
        guard let visit = visitStore.visit(forRegionId: regionId) else { return }
        let outcome = dwellDecision(enteredAt: visit.enteredAt, exitedAt: .now,
                                    didEngage: visit.didEngage)
        visitStore.end(regionId: regionId)

        guard outcome == .promptForAmount, let purchaseId = visit.purchaseId else { return }
        Task {
            do {
                try await scheduleAmountPrompt(merchantName: visit.merchantName, purchaseId: purchaseId)
            } catch {
                runtimeStore.recordIssue("The arrival follow-up could not be delivered: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Notifications

    /// Returns the request identifier iOS accepted, so delivery can be checked for later.
    ///
    /// The identifier used to be built and discarded inside the `enqueue` call. Keeping it is what
    /// makes "did this specific notification reach Notification Center" answerable at all — the
    /// alternative is matching by timestamp, which cannot tell two arrivals in one plaza apart.
    @discardableResult
    private func scheduleArrivalNotification(arrival: ResolvedArrival,
                                             recommendation: Recommendation,
                                             catalogue: Catalogue,
                                             regionId: String) async throws -> String {
        guard let card = catalogue.cards.first(where: { $0.cardId == recommendation.winner.cardId }) else {
            throw DeliveryError.missingRecommendedCard(recommendation.winner.cardId)
        }
        let headline = rewardReason(card, recommendation)
        let advantageCad = recommendation.advantageOverDefaultCad ?? 0
        let advantageText = advantageCad > 0 ? String(format: "+$%.2f", advantageCad) : ""
        let meta = CategoryVisuals.meta(for: arrival.prediction.category)

        let content = UNMutableNotificationContent()
        let titleTemplate = String(localized: "ambient.notification.title",
                                   defaultValue: "%@ — use %@ (%@)")
        content.title = String(format: titleTemplate, locale: .current,
                               notificationMerchantName(arrival.merchant.name), Self.shortCardName(card),
                               headline)
        if advantageCad > 0.005 {
            content.body = String(format: "Earns %@ more than your default card at %@.", advantageText, notificationMerchantName(arrival.merchant.name))
        } else {
            content.body = String(format: "Your best card for %@ purchases.", meta.displayName)
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = Self.notificationCategoryIdentifier
        // Everything an action needs to write a record without a second location fix. The record
        // itself is written on tap, never here.
        // Built key by key because userInfo must be property-list serialisable: a nil Optional
        // boxed as `Any` is not, and UNMutableNotificationContent rejects it at runtime rather
        // than at compile time.
        var info: [String: Any] = [
            "regionId": regionId,
            "muteKey": arrival.muteKey,
            "merchantId": arrival.merchant.id,
            "merchantName": arrival.merchant.name,
            "latitude": arrival.merchant.latitude,
            "longitude": arrival.merchant.longitude,
            "recommendedCardId": recommendation.winner.cardId,
        ]
        if let poi = arrival.merchant.poiCategoryRaw { info["poiCategoryRaw"] = poi }
        content.userInfo = info
        let identifier = "ambient.arrival.\(regionId).\(UUID().uuidString)"
        try await enqueue(UNNotificationRequest(identifier: identifier, content: content,
                                                trigger: nil))
        return identifier
    }

    /// How long to wait before asking Notification Center whether the alert landed.
    ///
    /// `add` returning is not delivery — it is iOS accepting the request — so a sample taken the
    /// instant it returns reports an absence that means nothing. Half a second is enough for an
    /// immediate trigger to land and small enough to spend inside a background region wake, which
    /// gets on the order of ten seconds in total.
    private static let deliverySampleDelay: Duration = .milliseconds(500)

    /// Whether Notification Center is holding this notification, shortly after it was scheduled.
    private func sampleDelivery(of identifier: String?, requestFailed: Bool) async
    -> ArrivalNotificationDelivery {
        guard let identifier, !requestFailed else {
            return arrivalNotificationDelivery(requestIdentifier: identifier,
                                               requestFailed: requestFailed,
                                               deliveredIdentifiers: [])
        }
        try? await Task.sleep(for: Self.deliverySampleDelay)
        let delivered = await notificationCenter.deliveredNotifications()
        return arrivalNotificationDelivery(
            requestIdentifier: identifier, requestFailed: false,
            deliveredIdentifiers: Set(delivered.map(\.request.identifier)))
    }

    /// The second sample, on the next foreground. Called from `refreshAmbientDiagnostics`, which
    /// is the app's existing scene-active tick.
    func resampleNotificationDelivery() async {
        #if FIELD_DIAGNOSTICS
        let delivered = await notificationCenter.deliveredNotifications()
        fieldLogStore.recordForegroundDelivery(
            deliveredIdentifiers: Set(delivered.map(\.request.identifier)))
        #endif
    }

    /// Starts the Live Activity for an arrival at the tier the gate chose.
    ///
    /// Separate from `scheduleArrivalNotification` on purpose. Those two calls used to be one, so
    /// a single boolean decided both whether PickMe spoke and whether PickMe was visible — which
    /// is why the owner saw nothing on most arrivals.
    @discardableResult
    private func presentArrivalActivity(tier: AmbientDeliveryTier,
                                        arrival: ResolvedArrival,
                                        recommendation: Recommendation?,
                                        catalogue: Catalogue,
                                        regionId: String) -> LiveActivityRequestOutcome {
        // A swipe is the only "not now" that costs the owner nothing, and it is worth exactly as
        // much as our willingness to honour it. Plaza geofences flap entry/exit/entry during one
        // shop, so without this the card the owner just cleared is back within the minute — which
        // teaches them the swipe does not work, and the next thing they reach for is the Settings
        // toggle we cannot undo. The notification path is deliberately untouched: this suppresses
        // presence, not the alert that earns money.
        guard !visitStore.liveActivityWasDismissed(regionId: regionId) else { return .dismissed }

        let meta = CategoryVisuals.meta(for: arrival.prediction.category)
        let merchant = notificationMerchantName(arrival.merchant.name)

        guard tier != .presence else {
            return LiveActivityManager.shared.startRecommendationActivity(
                merchantName: merchant, merchantLocation: nil,
                cardName: "", cardId: "", multiplierHeadline: "",
                advantageDescription: "", categoryDisplayName: meta.displayName,
                categoryIcon: meta.icon, tier: .presence, visitKey: regionId)
        }

        guard let recommendation,
              let card = catalogue.cards.first(where: { $0.cardId == recommendation.winner.cardId })
        else { return .failed }

        let advantageCad = recommendation.advantageOverDefaultCad ?? 0
        let advantage: String
        switch tier {
        case .interrupt where advantageCad > 0.005:
            advantage = String(format: "+$%.2f vs default", advantageCad)
        case .confirm:
            // The answer is "stay on the card you were already going to use". Saying so plainly
            // is the whole point of this tier: it is reassurance, not a suppressed alert.
            advantage = String(localized: "ambient.activity.confirm.advantage",
                               defaultValue: "Already your best card here")
        default:
            advantage = String(localized: "ambient.activity.best.advantage",
                               defaultValue: "Best card here")
        }

        return LiveActivityManager.shared.startRecommendationActivity(
            merchantName: merchant, merchantLocation: nil,
            cardName: Self.shortCardName(card), cardId: card.cardId,
            multiplierHeadline: rewardReason(card, recommendation),
            advantageDescription: advantage,
            categoryDisplayName: meta.displayName, categoryIcon: meta.icon,
            tier: tier, visitKey: regionId)
    }

    private func scheduleAmountPrompt(merchantName: String, purchaseId: UUID) async throws {
        let content = UNMutableNotificationContent()
        let template = String(localized: "ambient.amount.title", defaultValue: "What did you spend at %@?")
        content.title = String(format: template, locale: .current, merchantName)
        content.body = String(localized: "ambient.amount.body",
                              defaultValue: "Stays on this iPhone. Skip it and you can add it later.")
        content.sound = nil
        content.categoryIdentifier = Self.amountCategoryIdentifier
        content.userInfo = ["purchaseId": purchaseId.uuidString]
        try await enqueue(UNNotificationRequest(
            identifier: "ambient.amount.\(purchaseId.uuidString)", content: content, trigger: nil))
    }

    func sendTestNotification() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else {
            runtimeStore.recordIssue("Test alert not sent because notifications are not enabled for PickMe.")
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "PickMe arrival alerts are ready"
        content.body = "Notification delivery works. A real arrival alert still fires only when switching cards is worthwhile."
        content.sound = .default
        do {
            try await enqueue(UNNotificationRequest(identifier: "ambient.delivery-test.\(UUID().uuidString)",
                                                    content: content, trigger: nil))
            return true
        } catch {
            runtimeStore.recordIssue("The test alert could not be delivered: \(error.localizedDescription)")
            return false
        }
    }

    private func enqueue(_ request: UNNotificationRequest) async throws {
        try await notificationCenter.add(request)
        runtimeStore.recordScheduledNotification()
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let typed = (response as? UNTextInputNotificationResponse)?.userText
        handle(action: action, userInfo: info, typedText: typed)
    }

    /// Notification actions are the ONLY place an ambient record is created. A geofence entry
    /// writes nothing: without this rule a walk through a plaza would manufacture purchases the
    /// owner never made, and the metrics would measure footfall.
    private func handle(action: String, userInfo: [AnyHashable: Any], typedText: String?) {
        LiveActivityManager.shared.endActivity()
        switch action {
        case Self.muteActionIdentifier:
            recordEngagement(.mutedMerchant, userInfo: userInfo)
                        if let key = userInfo["muteKey"] as? String {
                muteStore.mute(key)
                refreshNow()
            }

        case Self.usedRecommendedActionIdentifier:
            recordEngagement(.usedRecommendedCard, userInfo: userInfo)
            openPurchase(userInfo: userInfo, useRecommendedCard: true)

        case Self.usedOtherActionIdentifier:
            // The card is genuinely unknown until the owner says so, so the purchase opens
            // without one and surfaces in the completion queue rather than guessing.
            recordEngagement(.usedOtherCard, userInfo: userInfo)
            openPurchase(userInfo: userInfo, useRecommendedCard: false)

        case Self.enterAmountActionIdentifier:
            recordTypedAmount(userInfo: userInfo, typedText: typedText)

        default:
            break
        }
    }

    /// Writes the prediction/purchase pair by replaying the same `CheckoutService.recommend` path
    /// the in-app flow uses, rather than reconstructing a prediction from notification payload.
    /// The advice has to be recomputed anyway to be honest about what was recommended, and
    /// duplicating the write here would mean two ways to create a row that must stay identical.
    private func openPurchase(userInfo: [AnyHashable: Any], useRecommendedCard: Bool) {
        guard let modelContainer, let catalogue, let ownerState,
              let regionId = userInfo["regionId"] as? String,
              let merchantId = userInfo["merchantId"] as? String,
              let merchantName = userInfo["merchantName"] as? String,
              let latitude = userInfo["latitude"] as? Double,
              let longitude = userInfo["longitude"] as? Double else { return }

        let context = ModelContext(modelContainer)
        let service = CheckoutService(catalogue: catalogue, ownerState: ownerState, context: context)
        let merchant = NearbyMerchant(id: merchantId, name: merchantName,
                                      poiCategoryRaw: userInfo["poiCategoryRaw"] as? String,
                                      latitude: latitude, longitude: longitude,
                                      distanceMeters: nil)
        // No amount: the owner has not paid yet, or has not said. `recommend` scores a category
        // estimate for the advice and stores nil, which is exactly right — the charge lands later.
        guard let result = try? service.recommend(merchant: merchant, amountCad: nil,
                                                  asOf: Date().formatted(.iso8601.year().month().day()),
                                                  purchaseSource: .arrivalAlert)
        else { return }
        // Bound to a local first: #Predicate lifts captured values, not property accesses on them.
        let predictionId = result.storedPredictionId
        guard let prediction = try? context.fetch(FetchDescriptor<StoredPrediction>(
            predicate: #Predicate { $0.id == predictionId })).first else { return }

        let cardId = useRecommendedCard ? userInfo["recommendedCardId"] as? String : nil
        guard let purchase = try? service.log.recordPurchase(for: prediction, cardUsedId: cardId,
                                                             cardSource: cardId == nil ? nil : .atTill)
        else { return }

        // Engaging with the arrival alert is explicit evidence that this was a real shopping
        // visit. The day-key store is idempotent, so a later Wallet tap cannot double-count it.
        if let key = purchase.merchantKey
            ?? merchantActivityKey(name: merchantName,
                                   locationIdentifier: purchase.merchantIdentifier) {
            patronageStore.recordVisit(merchantKey: key, displayName: merchantName,
                                       at: purchase.createdAt)
        }

        visitStore.update(regionId: regionId) { visit in
            visit.didEngage = true
            visit.purchaseId = purchase.id
        }
    }

    private func recordTypedAmount(userInfo: [AnyHashable: Any], typedText: String?) {
        guard let modelContainer, let catalogue, let ownerState,
              let raw = userInfo["purchaseId"] as? String, let purchaseId = UUID(uuidString: raw),
              let amount = Self.parseAmount(typedText) else { return }
        let context = ModelContext(modelContainer)
        guard let purchase = try? context.fetch(FetchDescriptor<StoredPurchase>(
            predicate: #Predicate { $0.id == purchaseId })).first else { return }
        // `.atTill`: typed on the way out with the receipt in hand, which is the strongest a
        // manual amount gets and materially better than the same figure recalled next week.
        let service = CheckoutService(catalogue: catalogue, ownerState: ownerState, context: context)
        try? service.log.recordAmount(amount, source: .atTill, on: purchase)
        try? service.assessPurchase(purchase)
    }

    /// Lenient on purpose. A lock-screen keyboard produces "$47.83", "47,83" and stray spaces, and
    /// refusing those loses the one figure this whole flow exists to capture.
    static func parseAmount(_ text: String?) -> Double? {
        guard let text else { return nil }
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    private func startIfAuthorized() {
        guard manager.authorizationStatus == .authorizedAlways else { return }
        // Significant-change monitoring is the only location stream. Region events supply the
        // arrival and exit wakes; this avoids continuous GPS by construction. The one-shot fix
        // is what seeds regions immediately after setup or launch instead of waiting for the
        // owner to travel far enough to generate a significant-change event.
        manager.startMonitoringSignificantLocationChanges()
        manager.requestLocation()
    }

    nonisolated static func shortCardName(_ card: CardProduct) -> String {
        switch card.cardId {
        case "amex-cobalt": return "Amex Cobalt"
        case "amex-platinum": return "Amex Platinum"
        case "amex-bonvoy": return "Marriott Bonvoy"
        case "mbna-rewards-we": return "MBNA Rewards"
        case "scotia-momentum-vi-plus": return "Scotia Momentum"
        case "tangerine-moneyback-world": return "Tangerine Money-Back"
        case "triangle-we": return "Triangle"
        case "wealthsimple-vip": return "Wealthsimple VIP"
        case "rogers-red-we": return "Rogers Red"
        case "cryptocom-royal-indigo": return "Crypto.com Indigo"
        case "scotia-gold-amex": return "Scotia Gold Amex"
        case "td-aeroplan-visa-infinite": return "TD Aeroplan"
        case "rbc-avion-visa-infinite": return "RBC Avion"
        case "cibc-dividend-visa-infinite": return "CIBC Dividend"
        case "cibc-dividend-visa": return "CIBC Dividend"
        case "td-business-travel-visa": return "TD Biz Travel"
        case "walmart-rewards-mastercard": return "Walmart Rewards"
        case "walmart-rewards-world-mastercard": return "Walmart World"
        case "scotia-passport-visa-infinite-plus": return "Scotia Passport"
        case "cibc-costco-mastercard": return "CIBC Costco"
        case "royal-bank-of-canada-rbc-british-airways-visa": return "RBC British Airways"
        case "neo-financial-neo-world-mastercard": return "Neo World"
        case "mbna-true-line-mastercard": return "MBNA True Line"
        case "capital-one-canada-capital-one-guaranteed": return "Capital One Guaranteed"
        default: return card.officialName.replacingOccurrences(of: " Credit Card", with: "")
        }
    }

    /// Keeps the time-sensitive alert readable on a lock screen while retaining the full merchant
    /// name in the action payload and purchase record.
    private func notificationMerchantName(_ name: String) -> String {
        let maximumLength = 28
        guard name.count > maximumLength else { return name }
        return String(name.prefix(maximumLength - 1)) + "…"
    }

    private func rewardReason(_ card: CardProduct, _ recommendation: Recommendation) -> String {
        guard let ruleID = recommendation.winner.appliedRuleId,
              let rule = card.earnRules.first(where: { $0.ruleId == ruleID }) else {
            return String(localized: "ambient.reward.best-return", defaultValue: "best return")
        }
        switch rule.earn {
        case .points(let pointsPerUnit):
            let multiplier = pointsPerUnit.rounded() == pointsPerUnit
                ? String(Int(pointsPerUnit)) : String(format: "%.1f", pointsPerUnit)
            let unit = card.program.programId == "amexMembershipRewards"
                ? "MR"
                : String(localized: "ambient.reward.points", defaultValue: "points")
            let template = String(localized: "ambient.reward.multiplier", defaultValue: "%@\u{00D7} %@")
            return String(format: template, locale: .current, multiplier, unit)
        case .cashback(let rate, _):
            let template = String(localized: "ambient.reward.cash-back", defaultValue: "%.0f%% cash back")
            return String(format: template, locale: .current, rate * 100)
        case .centsPerLitre:
            return String(localized: "ambient.reward.best-return", defaultValue: "best return")
        }
    }
}
