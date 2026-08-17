@preconcurrency import CoreLocation
import CardCopilotEngine
import CardCopilotStore
import Foundation
import SwiftData
@preconcurrency import UserNotifications

/// Persists the field-test counters locally. The engine owns the counter model; this tiny store
/// merely partitions it by day so the UI can report the last seven days without any network.
@MainActor
final class AmbientDiagnosticsStore {
    private let defaults: UserDefaults
    private let key = "ambientDiagnostics.v1"
    private let calendar = Calendar(identifier: .gregorian)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func record(_ decision: AmbientGateDecision, at date: Date = .now) {
        var daily = loadDaily()
        let key = dayKey(for: date)
        var log = daily[key] ?? SuppressionLog()
        log.record(decision)
        daily[key] = log
        save(daily)
    }

    func lastSevenDays(ending date: Date = .now) -> SuppressionLog {
        let daily = loadDaily()
        var total = SuppressionLog()
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
            if let log = daily[dayKey(for: day)] { total.merge(log) }
        }
        return total
    }

    private func loadDaily() -> [String: SuppressionLog] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: SuppressionLog].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func save(_ daily: [String: SuppressionLog]) {
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

    private static let maximumMonitoredRegions = 20
    /// How close a stored, owner-reconciled merchant must be to the arrival fix to claim the
    /// visit. Tight on purpose: `.verified` is the tier that fires at the owner's own threshold.
    private static let verifiedMerchantRadiusMeters: Double = 60

    private let manager = CLLocationManager()
    private let notificationCenter = UNUserNotificationCenter.current()
    private let diagnosticsStore = AmbientDiagnosticsStore()
    private let muteStore = AmbientMerchantMuteStore()
    private let visitStore = AmbientVisitStore()
    private let queryLog = DiscoveryQueryLog()
    private let provider = LiveMerchantProvider()

    private var modelContainer: ModelContainer?
    private var catalogue: Catalogue?
    private var ownerState: OwnerState?

    private(set) var authorizationStatus: CLAuthorizationStatus

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        notificationCenter.delegate = self
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
        visitStore.forgetAll()
        queryLog.forgetAll()
    }

    /// Called only from the dedicated explainer screen, before either system prompt appears.
    func requestAlwaysAuthorization() {
        Task {
            _ = try? await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
        }
        manager.requestAlwaysAuthorization()
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
                                          limit: Self.maximumMonitoredRegions)) ?? []

        let merchants = ((try? context.fetch(FetchDescriptor<StoredMerchant>())) ?? [])
            .filter { CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: $0.latitude,
                                                                          longitude: $0.longitude))
                      && ($0.latitude != 0 || $0.longitude != 0) }

        // A confirmed merchant already inside a discovered area needs no region of its own — the
        // area wake resolves to it anyway, and a duplicate would burn a slot for nothing.
        let uncovered = merchants.filter { merchant in
            !areas.contains { area in
                greatCircleDistanceMeters(fromLatitude: area.centroidLatitude,
                                          fromLongitude: area.centroidLongitude,
                                          toLatitude: merchant.latitude,
                                          toLongitude: merchant.longitude) <= area.radiusMeters
            }
        }

        var specs: [(id: String, latitude: Double, longitude: Double, radius: Double, distance: Double)] = []
        for merchant in uncovered {
            specs.append((id: "merchant:\(merchant.id.uuidString)",
                          latitude: merchant.latitude, longitude: merchant.longitude,
                          radius: minimumAreaRadiusMeters,
                          distance: greatCircleDistanceMeters(fromLatitude: coordinate.latitude,
                                                              fromLongitude: coordinate.longitude,
                                                              toLatitude: merchant.latitude,
                                                              toLongitude: merchant.longitude)))
        }
        for area in areas {
            specs.append((id: "area:\(area.id.uuidString)",
                          latitude: area.centroidLatitude, longitude: area.centroidLongitude,
                          radius: area.radiusMeters,
                          distance: greatCircleDistanceMeters(fromLatitude: coordinate.latitude,
                                                              fromLongitude: coordinate.longitude,
                                                              toLatitude: area.centroidLatitude,
                                                              toLongitude: area.centroidLongitude)))
        }
        // Stable sort: distance decides, and confirmed merchants were appended first so they take
        // the slot at equal distance.
        let chosen = specs.sorted { $0.distance < $1.distance }.prefix(Self.maximumMonitoredRegions)

        for region in manager.monitoredRegions
        where region.identifier.hasPrefix(Self.regionPrefix)
            || region.identifier.hasPrefix(Self.legacyRegionPrefix) {
            manager.stopMonitoring(for: region)
        }

        let ceiling = manager.maximumRegionMonitoringDistance
        for spec in chosen {
            let radius = min(max(spec.radius, minimumAreaRadiusMeters), ceiling)
            guard radius >= minimumAreaRadiusMeters else { continue }
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: spec.latitude, longitude: spec.longitude),
                radius: radius,
                identifier: Self.regionPrefix + spec.id)
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
        /// Mute identity. A string because discovered POIs have no local UUID.
        let muteKey: String
    }

    private func evaluateArrival(at target: ArrivalTarget, regionId: String) async {
        guard let modelContainer, let catalogue, let ownerState else { return }
        let context = ModelContext(modelContainer)
        guard let arrival = resolve(target, context: context) else { return }

        // Dwell starts now regardless of whether anything fires. An exit still has to be able to
        // tell a twenty-minute shop from a forty-second walk-by.
        visitStore.begin(AmbientVisit(enteredAt: .now, didEngage: false, purchaseId: nil,
                                      merchantName: arrival.merchant.name),
                         forRegionId: regionId)

        let purchase = ambientPurchaseContext(merchant: arrival.merchant,
                                              category: arrival.prediction.category)
        let recommendation = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)
            .recommend(purchase, asOf: Date().formatted(.iso8601.year().month().day()))
        let advantageCad = recommendation.advantageOverDefaultCad ?? 0
        let advantagePP = purchase.amountCad > 0 ? advantageCad / purchase.amountCad * 100 : 0

        let decision = AmbientGate.evaluate(AmbientGateInput(
            merchantConfidence: arrival.confidence,
            recommendedCardId: recommendation.winner.cardId,
            defaultCardId: ownerState.defaultCardId,
            advantage: AmbientAdvantage(percentagePoints: advantagePP, cad: advantageCad),
            switchThreshold: ownerState.switchThreshold,
            isMuted: muteStore.isMuted(arrival.muteKey)
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
            return resolved(storedMerchant: merchant)

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
            if let nearestConfirmed { return resolved(storedMerchant: nearestConfirmed) }

            // Rung 2: a cached POI whose name the catalogue's own brand vocabulary recognises.
            // Checkable, unlike a bare pin — which is the whole basis for the middle tier.
            let branded = area.members.first { canonicalEngineBrand($0.name) != nil }
            let member = branded ?? area.members.first
            guard let member else { return nil }
            let nearby = NearbyMerchant(id: member.identifier ?? member.name, name: member.name,
                                        poiCategoryRaw: member.poiCategoryRaw,
                                        latitude: member.latitude, longitude: member.longitude,
                                        distanceMeters: nil)
            return ResolvedArrival(
                merchant: nearby,
                prediction: predict(poiCategoryRaw: member.poiCategoryRaw, merchantName: member.name),
                confidence: branded != nil ? .brandMatched : .unknown,
                muteKey: nearby.id)
        }
    }

    private func resolved(storedMerchant merchant: StoredMerchant) -> ResolvedArrival {
        let prediction = predictionForKnownMerchant(merchant)
        let nearby = NearbyMerchant(id: merchant.identifier ?? merchant.id.uuidString,
                                    name: merchant.name, poiCategoryRaw: merchant.poiCategoryRaw,
                                    latitude: merchant.latitude, longitude: merchant.longitude,
                                    distanceMeters: nil)
        return ResolvedArrival(merchant: nearby, prediction: prediction,
                               confidence: prediction.confidenceSource.isVerified ? .verified : .unknown,
                               muteKey: nearby.id)
    }

    // MARK: - Exit

    /// The other half of dwell. Everything the exit decides is in `dwellDecision`; this only
    /// carries the outcome out to a notification.
    private func evaluateExit(regionId: String) {
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
        let content = UNMutableNotificationContent()
        let titleTemplate = String(localized: "ambient.notification.title",
                                   defaultValue: "%@ — use %@ (%@)")
        content.title = String(format: titleTemplate, locale: .current,
                               notificationMerchantName(arrival.merchant.name), Self.shortCardName(card),
                               rewardReason(card, recommendation))
        content.body = String(localized: "ambient.notification.body",
                              defaultValue: "On-device advice for this saved merchant.")
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

        await MainActor.run {
            self.handle(action: action, userInfo: info, typedText: typed)
        }
    }

    /// Notification actions are the ONLY place an ambient record is created. A geofence entry
    /// writes nothing: without this rule a walk through a plaza would manufacture purchases the
    /// owner never made, and the metrics would measure footfall.
    private func handle(action: String, userInfo: [AnyHashable: Any], typedText: String?) {
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
                                                  asOf: Date().formatted(.iso8601.year().month().day()))
        else { return }
        // Bound to a local first: #Predicate lifts captured values, not property accesses on them.
        let predictionId = result.storedPredictionId
        guard let prediction = try? context.fetch(FetchDescriptor<StoredPrediction>(
            predicate: #Predicate { $0.id == predictionId })).first else { return }

        let cardId = useRecommendedCard ? userInfo["recommendedCardId"] as? String : nil
        guard let purchase = try? service.log.recordPurchase(for: prediction, cardUsedId: cardId,
                                                             cardSource: cardId == nil ? nil : .atTill)
        else { return }

        visitStore.update(regionId: regionId) { visit in
            visit.didEngage = true
            visit.purchaseId = purchase.id
        }
    }

    private func recordTypedAmount(userInfo: [AnyHashable: Any], typedText: String?) {
        guard let modelContainer,
              let raw = userInfo["purchaseId"] as? String, let purchaseId = UUID(uuidString: raw),
              let amount = Self.parseAmount(typedText) else { return }
        let context = ModelContext(modelContainer)
        guard let purchase = try? context.fetch(FetchDescriptor<StoredPurchase>(
            predicate: #Predicate { $0.id == purchaseId })).first else { return }
        // `.atTill`: typed on the way out with the receipt in hand, which is the strongest a
        // manual amount gets and materially better than the same figure recalled next week.
        try? PredictionLog(context: context).recordAmount(amount, source: .atTill, on: purchase)
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
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
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
        case "scotia-passport-visa-infinite-plus": return "Scotia Passport"
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
        case .points(let pointsPerCad):
            let multiplier = pointsPerCad.rounded() == pointsPerCad
                ? String(Int(pointsPerCad)) : String(format: "%.1f", pointsPerCad)
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
