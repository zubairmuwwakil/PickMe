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

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0,
                      components.day ?? 0)
    }
}

@MainActor
final class AmbientMerchantMuteStore {
    private let defaults: UserDefaults
    private let key = "ambientMutedMerchantIDs.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isMuted(_ merchantID: UUID) -> Bool {
        mutedIDs.contains(merchantID.uuidString)
    }

    func mute(_ merchantID: UUID) {
        var ids = mutedIDs
        ids.insert(merchantID.uuidString)
        defaults.set(Array(ids), forKey: key)
    }

    private var mutedIDs: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }
}

/// Battery-bounded ambient delivery: significant location changes refresh no more than 20
/// locally known terminal regions; individual region entries run the same local scorer as
/// checkout. It never starts continuous location updates or performs a network request.
@MainActor
final class AmbientLocationService: NSObject, @MainActor CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    static let regionPrefix = "ambient.merchant."
    static let muteActionIdentifier = "ambient.muteMerchant"
    static let notificationCategoryIdentifier = "ambient.recommendation"

    private let manager = CLLocationManager()
    private let notificationCenter = UNUserNotificationCenter.current()
    private let diagnosticsStore = AmbientDiagnosticsStore()
    private let muteStore = AmbientMerchantMuteStore()

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
            UNNotificationCategory(identifier: Self.notificationCategoryIdentifier,
                                   actions: [UNNotificationAction(identifier: Self.muteActionIdentifier,
                                                                 title: "Mute this merchant",
                                                                 options: [])],
                                   intentIdentifiers: [], options: [])
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
        rotateRegions(around: location.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix(Self.regionPrefix),
              let merchantID = UUID(uuidString: String(region.identifier.dropFirst(Self.regionPrefix.count))) else {
            return
        }
        evaluateArrival(at: merchantID)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == "ambient.muteMerchant",
              let rawID = response.notification.request.content.userInfo["merchantID"] as? String,
              let merchantID = UUID(uuidString: rawID) else { return }
        await MainActor.run {
            AmbientMerchantMuteStore().mute(merchantID)
        }
    }

    private func startIfAuthorized() {
        guard manager.authorizationStatus == .authorizedAlways else { return }
        // Significant-change monitoring is the only location stream. Region events supply the
        // arrival wake; this avoids continuous GPS by construction.
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        manager.startMonitoringSignificantLocationChanges()
    }

    private func rotateRegions(around coordinate: CLLocationCoordinate2D) {
        guard let modelContainer, manager.authorizationStatus == .authorizedAlways else { return }
        let context = ModelContext(modelContainer)
        let merchants = (try? context.fetch(FetchDescriptor<StoredMerchant>())) ?? []
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let candidates = merchants.compactMap { merchant -> (StoredMerchant, NearbyMerchant)? in
            let merchantCoordinate = CLLocationCoordinate2D(latitude: merchant.latitude, longitude: merchant.longitude)
            guard CLLocationCoordinate2DIsValid(merchantCoordinate),
                  merchant.latitude != 0 || merchant.longitude != 0 else { return nil }
            let distance = origin.distance(from: CLLocation(latitude: merchant.latitude,
                                                            longitude: merchant.longitude))
            return (merchant, NearbyMerchant(id: merchant.id.uuidString, name: merchant.name,
                                              poiCategoryRaw: merchant.poiCategoryRaw,
                                              latitude: merchant.latitude, longitude: merchant.longitude,
                                              distanceMeters: distance))
        }
        let merchantByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.1.id, $0.0) })
        let nearestIDs = rankNearbyMerchants(candidates.map(\.1)).prefix(20).map(\.id)

        for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.regionPrefix) {
            manager.stopMonitoring(for: region)
        }

        let radius = min(150, manager.maximumRegionMonitoringDistance)
        guard radius >= 100 else { return }
        for id in nearestIDs {
            guard let merchant = merchantByID[id] else { continue }
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: merchant.latitude,
                                                                          longitude: merchant.longitude),
                                        radius: radius,
                                        identifier: Self.regionPrefix + merchant.id.uuidString)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
    }

    private func evaluateArrival(at merchantID: UUID) {
        guard let modelContainer, let catalogue, let ownerState else { return }
        let context = ModelContext(modelContainer)
        guard let merchant = try? context.fetch(FetchDescriptor<StoredMerchant>(
            predicate: #Predicate { $0.id == merchantID }
        )).first else { return }

        let nearby = NearbyMerchant(id: merchant.id.uuidString, name: merchant.name,
                                    poiCategoryRaw: merchant.poiCategoryRaw, latitude: merchant.latitude,
                                    longitude: merchant.longitude, distanceMeters: nil)
        let prediction = predictionForKnownMerchant(merchant)
        let purchase = ambientPurchaseContext(merchant: nearby, category: prediction.category)
        let recommendation = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)
            .recommend(purchase, asOf: Date().formatted(.iso8601.year().month().day()))
        let advantageCad = recommendation.advantageOverDefaultCad ?? 0
        let advantagePP = purchase.amountCad > 0 ? advantageCad / purchase.amountCad * 100 : 0
        let decision = AmbientGate.evaluate(AmbientGateInput(
            merchantConfidence: prediction.confidenceSource.isVerified ? .high : .low,
            recommendedCardId: recommendation.winner.cardId,
            defaultCardId: ownerState.defaultCardId,
            advantage: AmbientAdvantage(percentagePoints: advantagePP, cad: advantageCad),
            switchThreshold: ownerState.switchThreshold,
            isMuted: muteStore.isMuted(merchantID)
        ))
        diagnosticsStore.record(decision)
        guard decision.fires else { return }
        scheduleNotification(merchant: merchant, recommendation: recommendation, catalogue: catalogue)
    }

    private func scheduleNotification(merchant: StoredMerchant, recommendation: Recommendation,
                                      catalogue: Catalogue) {
        guard let card = catalogue.cards.first(where: { $0.cardId == recommendation.winner.cardId }) else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(merchant.name) — use \(shortCardName(card)) (\(rewardReason(card, recommendation)))"
        content.body = "On-device advice for this saved merchant."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = Self.notificationCategoryIdentifier
        content.userInfo = ["merchantID": merchant.id.uuidString]
        let request = UNNotificationRequest(identifier: "ambient.\(merchant.id.uuidString).\(UUID().uuidString)",
                                            content: content, trigger: nil)
        notificationCenter.add(request)
    }

    private func shortCardName(_ card: CardProduct) -> String {
        switch card.cardId {
        case "amex-cobalt": return "Amex Cobalt"
        default: return card.officialName.replacingOccurrences(of: " Credit Card", with: "")
        }
    }

    private func rewardReason(_ card: CardProduct, _ recommendation: Recommendation) -> String {
        guard let ruleID = recommendation.winner.appliedRuleId,
              let rule = card.earnRules.first(where: { $0.ruleId == ruleID }) else { return "best return" }
        switch rule.earn {
        case .points(let pointsPerCad):
            let multiplier = pointsPerCad.rounded() == pointsPerCad
                ? String(Int(pointsPerCad)) : String(format: "%.1f", pointsPerCad)
            let unit = card.program.programId == "amexMembershipRewards" ? "MR" : "points"
            return "\(multiplier)× \(unit)"
        case .cashback(let rate, _):
            return String(format: "%.0f%% cash back", rate * 100)
        case .centsPerLitre:
            return "best return"
        }
    }
}
