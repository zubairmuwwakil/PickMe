@preconcurrency import CoreLocation
import CardCopilotEngine
import CardCopilotStore
import Foundation
import SwiftData
import SwiftUI
@preconcurrency import UserNotifications

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

    func recordArrival(_ outcome: AmbientArrivalOutcome, at date: Date = .now) {
        store.update(at: date) { $0.recordArrival(outcome) }
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
final class AmbientLocationService: NSObject, @MainActor CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    static let regionPrefix = "ambient.region."
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
    private let notificationCenter = UNUserNotificationCenter.current()
    private let diagnosticsStore = AmbientDiagnosticsStore()
    private let coverageStore = AmbientCoverageStore()
    private let muteStore = AmbientMerchantMuteStore()
    private let visitStore = AmbientVisitStore()
    private let queryLog = DiscoveryQueryLog()
    private let provider = LiveMerchantProvider()
    private let patronageStore = MerchantPatronageStore()
    private let alertPreferenceStore = ArrivalAlertPreferenceStore()

    private var modelContainer: ModelContainer?
    private var catalogue: Catalogue?
    private var ownerState: OwnerState?

    private(set) var authorizationStatus: CLAuthorizationStatus

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
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
        startIfAuthorized()
    }

    var isEnabled: Bool { authorizationStatus == .authorizedAlways }
    var diagnostics: SuppressionLog { diagnosticsStore.lastSevenDays() }
    var coverage: AmbientCoverageLog { coverageStore.lastSevenDays() }

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
        visitStore.forgetAll()
        queryLog.forgetAll()
        patronageStore.forgetAll()
        alertPreferenceStore.forgetAll()
    }

    /// Called only from the dedicated explainer screen, before either system prompt appears.
    func requestAlwaysAuthorization() {
        Task {
            _ = try? await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
        }
        manager.requestAlwaysAuthorization()
    }

    /// Re-aims regions after an owner changes a merchant-level alert preference.
    func refreshNow() {
        guard manager.authorizationStatus == .authorizedAlways else { return }
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        startIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { await refreshDiscovery(around: location) }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let target = Self.target(for: region.identifier) else { return }
        Task { await evaluateArrival(at: target, regionId: region.identifier) }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard Self.target(for: region.identifier) != nil else { return }
        evaluateExit(regionId: region.identifier)
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

        let areas = (try? cache.areasNear(latitude: coordinate.latitude,
                                          longitude: coordinate.longitude,
                                          limit: maximumMonitoredRegions)) ?? []

        let merchants = ((try? context.fetch(FetchDescriptor<StoredMerchant>())) ?? [])
            .filter { CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: $0.latitude,
                                                                          longitude: $0.longitude))
                      && ($0.latitude != 0 || $0.longitude != 0) }

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
            areas.firstIndex { area in
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
        for (areaOffset, area) in areas.enumerated() {
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

        for region in manager.monitoredRegions
        where region.identifier.hasPrefix(Self.regionPrefix)
            || region.identifier.hasPrefix(Self.legacyRegionPrefix) {
            manager.stopMonitoring(for: region)
        }

        let ceiling = manager.maximumRegionMonitoringDistance
        for candidate in allocation.granted {
            guard let spec = specs[candidate.id] else { continue }
            let radius = min(max(spec.radius, minimumAreaRadiusMeters), ceiling)
            guard radius >= minimumAreaRadiusMeters else { continue }
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: spec.latitude, longitude: spec.longitude),
                radius: radius,
                identifier: Self.regionPrefix + candidate.id)
            region.notifyOnEntry = true
            // Exit is what makes dwell measurable, and dwell is what separates a purchase from
            // walking past — and what decides which of several overlapping regions was real.
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
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
    }

    private func evaluateArrival(at target: ArrivalTarget, regionId: String) async {
        guard let modelContainer, let catalogue, let ownerState else { return }
        let context = ModelContext(modelContainer)
        // Both of the dropouts below used to `return` in silence, which made a background wake
        // that produced nothing indistinguishable from a wake that never happened.
        guard let arrival = resolve(target, context: context) else {
            coverageStore.recordArrival(.unresolved)
            return
        }

        // Dwell starts now regardless of whether anything fires. An exit still has to be able to
        // tell a twenty-minute shop from a forty-second walk-by.
        visitStore.begin(AmbientVisit(enteredAt: .now, didEngage: false, purchaseId: nil,
                                      merchantName: arrival.merchant.name),
                         forRegionId: regionId)

        let purchase = ambientPurchaseContext(merchant: arrival.merchant,
                                              category: arrival.prediction.category,
                                              mcc: arrival.mcc)
        guard case .advised(let recommendation) = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)
            .recommend(purchase, asOf: Date().formatted(.iso8601.year().month().day())) else {
            coverageStore.recordArrival(.notAdvised)
            return
        }
        coverageStore.recordArrival(.resolved)
        let advantageCad = recommendation.advantageOverDefaultCad ?? 0
        let advantagePP = purchase.amountCad > 0 ? advantageCad / purchase.amountCad * 100 : 0

        let explicit = explicitlyPrioritized(name: arrival.merchant.name,
                                             identifier: arrival.merchant.id,
                                             latitude: arrival.merchant.latitude,
                                             longitude: arrival.merchant.longitude)
        let decision = AmbientGate.evaluate(AmbientGateInput(
            merchantConfidence: explicit == true ? .frequented : arrival.confidence,
            recommendedCardId: recommendation.winner.cardId,
            defaultCardId: ownerState.defaultCardId,
            advantage: AmbientAdvantage(percentagePoints: advantagePP, cad: advantageCad),
            switchThreshold: ownerState.switchThreshold,
            isMuted: muteStore.isMuted(arrival.muteKey) || explicit == false
        ))
        diagnosticsStore.record(decision)
        guard decision.fires else { return }

        scheduleArrivalNotification(arrival: arrival, recommendation: recommendation,
                                    catalogue: catalogue, regionId: regionId)
    }

    /// Resolution ladder, cheapest and most certain first. Nothing here writes to the log — a
    /// geofence entry is not evidence that anything was bought.
    private func resolve(_ target: ArrivalTarget, context: ModelContext) -> ResolvedArrival? {
        switch target {
        case .merchant(let id):
            guard let merchant = try? context.fetch(FetchDescriptor<StoredMerchant>(
                predicate: #Predicate { $0.id == id })).first else { return nil }
            return resolved(storedMerchant: merchant, frequentedKeys: effectiveFrequentedKeys())

        case .area(let id):
            guard let area = try? context.fetch(FetchDescriptor<ShoppingArea>(
                predicate: #Predicate { $0.id == id })).first else { return nil }

            // Rung 1: an owner-reconciled terminal standing inside this area.
            let merchants = (try? context.fetch(FetchDescriptor<StoredMerchant>())) ?? []
            let nearestConfirmed = merchants
                .map { ($0, greatCircleDistanceMeters(fromLatitude: area.centroidLatitude,
                                                      fromLongitude: area.centroidLongitude,
                                                      toLatitude: $0.latitude,
                                                      toLongitude: $0.longitude)) }
                .filter { $0.1 <= Self.verifiedMerchantRadiusMeters && $0.0.confirmedCategory != nil }
                .min { $0.1 < $1.1 }?.0
            // Read once for the whole arrival rather than per candidate name: an area holds
            // several members, and this is a background wake.
            let frequentedKeys = effectiveFrequentedKeys()
            if let nearestConfirmed {
                return resolved(storedMerchant: nearestConfirmed, frequentedKeys: frequentedKeys)
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
            // A plaza holding one recognisable store and four unnamed pins is answered by the
            // store; a plaza of nothing but pins still answers, at `.unknown`, and is suppressed.
            guard let (member, resolution) = resolved.first(where: { $0.1.confidence != .unknown })
                    ?? resolved.first else { return nil }
            let nearby = NearbyMerchant(id: member.identifier ?? member.name, name: member.name,
                                        poiCategoryRaw: member.poiCategoryRaw,
                                        latitude: member.latitude, longitude: member.longitude,
                                        distanceMeters: nil)
            return ResolvedArrival(
                merchant: nearby,
                prediction: resolution.prediction,
                confidence: resolution.confidence,
                mcc: resolution.mcc,
                muteKey: nearby.id)
        }
    }

    private func resolved(storedMerchant merchant: StoredMerchant,
                          frequentedKeys: Set<String>) -> ResolvedArrival {
        let resolution = resolveStoredMerchant(name: merchant.name,
                                               poiCategoryRaw: merchant.poiCategoryRaw,
                                               confirmedCategory: merchant.confirmedCategory,
                                               confirmationCount: merchant.confirmationCount,
                                               frequentedKeys: frequentedKeys)
        let nearby = NearbyMerchant(id: merchant.identifier ?? merchant.id.uuidString,
                                    name: merchant.name, poiCategoryRaw: merchant.poiCategoryRaw,
                                    latitude: merchant.latitude, longitude: merchant.longitude,
                                    distanceMeters: nil)
        return ResolvedArrival(merchant: nearby, prediction: resolution.prediction,
                               confidence: resolution.confidence,
                               mcc: resolution.mcc,
                               muteKey: nearby.id)
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
        scheduleAmountPrompt(merchantName: visit.merchantName, purchaseId: purchaseId)
    }

    // MARK: - Notifications

    private func scheduleArrivalNotification(arrival: ResolvedArrival,
                                             recommendation: Recommendation,
                                             catalogue: Catalogue,
                                             regionId: String) {
        guard let card = catalogue.cards.first(where: { $0.cardId == recommendation.winner.cardId }) else { return }
        let headline = rewardReason(card, recommendation)
        let advantageCad = recommendation.advantageOverDefaultCad ?? 0
        let advantageText = advantageCad > 0 ? String(format: "+$%.2f", advantageCad) : ""
        let meta = CategoryVisuals.meta(for: arrival.prediction.category)

        LiveActivityManager.shared.startRecommendationActivity(
            merchantName: arrival.merchant.name,
            merchantLocation: nil,
            cardName: Self.shortCardName(card),
            cardId: card.cardId,
            multiplierHeadline: headline,
            advantageDescription: advantageText,
            categoryDisplayName: meta.displayName,
            categoryIcon: meta.icon,
            isFork: false
        )

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
        notificationCenter.add(UNNotificationRequest(
            identifier: "ambient.arrival.\(regionId).\(UUID().uuidString)",
            content: content, trigger: nil))
    }

    private func scheduleAmountPrompt(merchantName: String, purchaseId: UUID) {
        let content = UNMutableNotificationContent()
        let template = String(localized: "ambient.amount.title", defaultValue: "What did you spend at %@?")
        content.title = String(format: template, locale: .current, merchantName)
        content.body = String(localized: "ambient.amount.body",
                              defaultValue: "Stays on this iPhone. Skip it and you can add it later.")
        content.sound = nil
        content.categoryIdentifier = Self.amountCategoryIdentifier
        content.userInfo = ["purchaseId": purchaseId.uuidString]
        notificationCenter.add(UNNotificationRequest(
            identifier: "ambient.amount.\(purchaseId.uuidString)", content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let typed = (response as? UNTextInputNotificationResponse)?.userText

        if info["route"] as? String == "walletCaptureStatus" ||
           action == "OPEN_CAPTURE_STATUS" || action == "OPEN_DIAGNOSTIC" {
            WalletCaptureDeepLinkStore.markPending()
            NotificationCenter.default.post(name: .openWalletCaptureStatus, object: nil)
            return
        }

        await MainActor.run {
            self.handle(action: action, userInfo: info, typedText: typed)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge, .list]
    }

    /// Notification actions are the ONLY place an ambient record is created. A geofence entry
    /// writes nothing: without this rule a walk through a plaza would manufacture purchases the
    /// owner never made, and the metrics would measure footfall.
    private func handle(action: String, userInfo: [AnyHashable: Any], typedText: String?) {
        LiveActivityManager.shared.endActivity()
        switch action {
        case Self.muteActionIdentifier:
            if let key = userInfo["muteKey"] as? String { muteStore.mute(key) }

        case Self.usedRecommendedActionIdentifier:
            openPurchase(userInfo: userInfo, useRecommendedCard: true)

        case Self.usedOtherActionIdentifier:
            // The card is genuinely unknown until the owner says so, so the purchase opens
            // without one and surfaces in the completion queue rather than guessing.
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
        // arrival and exit wakes; this avoids continuous GPS by construction.
        manager.startMonitoringSignificantLocationChanges()
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
