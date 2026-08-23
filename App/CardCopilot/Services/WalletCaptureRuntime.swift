import CardCopilotCapture
@preconcurrency import CoreLocation
import Foundation
import Network
import Observation
import UIKit
import UserNotifications

extension Notification.Name {
    static let walletCaptureConnectivityRestored = Notification.Name("walletCaptureConnectivityRestored")
}

struct WalletCaptureBanner: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let isProblem: Bool
}

@Observable
@MainActor
final class WalletCaptureBannerCenter {
    static let shared = WalletCaptureBannerCenter()
    var banner: WalletCaptureBanner?
    private var dismissal: Task<Void, Never>?

    func show(_ value: WalletCaptureBanner) {
        dismissal?.cancel(); banner = value
        dismissal = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled, banner?.id == value.id { banner = nil }
        }
    }

    func dismiss() { dismissal?.cancel(); banner = nil }
}

enum WalletCaptureNotificationCoordinator {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) == true
    }

    @MainActor
    static func publish(_ receipt: WalletCaptureReceipt, catalogueCardName: String?) async {
        let active = UIApplication.shared.applicationState == .active
        let decision = WalletCaptureNotificationDecision.currentEvent(
            receipt: receipt, appIsActive: active, recommendedCardName: catalogueCardName)
        switch decision.route {
        case .inApp:
            WalletCaptureBannerCenter.shared.show(.init(id: decision.identifier, title: decision.title,
                                                        body: decision.body,
                                                        isProblem: receipt.kind == .configurationError))
        case .localNotification:
            await schedule(identifier: decision.identifier, title: decision.title, body: decision.body,
                           category: receipt.kind == .configurationError ? "WALLET_CAPTURE_REVIEW" : nil)
        }
    }

    static func persistenceFailure() async {
        await schedule(identifier: "wallet-capture-persistence-failure", title: "Purchase could not be saved",
                       body: "Open PickMe to review Wallet Capture.", category: "WALLET_CAPTURE_REVIEW")
    }

    static func publishDrain(_ summary: WalletCaptureDrainSummary) async {
        if summary.backlogUploaded > 0 {
            await schedule(identifier: "wallet-capture-backlog-synced", title: "Wallet Capture is up to date",
                           body: summary.backlogUploaded == 1 ? "1 saved purchase synced." : "\(summary.backlogUploaded) saved purchases synced.")
        }
        if summary.authenticationBlocked > 0 {
            await schedule(identifier: "wallet-capture-authentication", title: "Reconnect Wallet Capture",
                           body: "Purchases are saved on this iPhone and need a new secure connection.",
                           category: "WALLET_CAPTURE_RECONNECT")
        }
        if summary.quarantined > 0 {
            await schedule(identifier: "wallet-capture-review", title: "Review a Wallet capture",
                           body: "A saved capture needs attention. Review it or prepare a diagnostic report in PickMe.",
                           category: "WALLET_CAPTURE_REVIEW")
        }
    }

    private static func schedule(identifier: String, title: String, body: String,
                                 category: String? = nil) async {
        let content = UNMutableNotificationContent(); content.title = title; content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category; content.userInfo["route"] = "walletCaptureStatus" }
        try? await UNUserNotificationCenter.current().add(.init(identifier: identifier, content: content, trigger: nil))
    }
}

enum WalletCaptureDeepLinkStore {
    private static let key = "walletCapture.openStatus"
    static func markPending() { UserDefaults.standard.set(true, forKey: key) }
    static func consume() -> Bool {
        let pending = UserDefaults.standard.bool(forKey: key)
        if pending { UserDefaults.standard.removeObject(forKey: key) }
        return pending
    }
}

final class WalletCaptureNetworkMonitor: @unchecked Sendable {
    static let shared = WalletCaptureNetworkMonitor()
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var offline = false
    var isOffline: Bool { lock.withLock { offline } }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let wasOffline = lock.withLock { let old = offline; offline = path.status != .satisfied; return old }
            if wasOffline && path.status == .satisfied {
                NotificationCenter.default.post(name: .walletCaptureConnectivityRestored, object: nil)
            }
        }
        monitor.start(queue: DispatchQueue(label: "ca.inunity.pickme.wallet-connectivity"))
    }
}

@MainActor
private final class WalletIntentLocationRequest: NSObject, @MainActor CLLocationManagerDelegate {
    private static var active: [UUID: WalletIntentLocationRequest] = [:]
    private let id = UUID()
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<WalletLocationEnrichment, Never>?
    private var timeout: Task<Void, Never>?

    static func sample() async -> WalletLocationEnrichment {
        let request = WalletIntentLocationRequest()
        active[request.id] = request
        return await request.run()
    }

    private func run() async -> WalletLocationEnrichment {
        switch manager.authorizationStatus {
        case .denied: return finishImmediately(.init(location: nil, outcome: .permissionDenied))
        case .restricted: return finishImmediately(.init(location: nil, outcome: .permissionRestricted))
        case .notDetermined: return finishImmediately(.init(location: nil, outcome: .unavailable))
        default: break
        }
        if let warm = manager.location, warm.horizontalAccuracy >= 0,
           abs(Date().timeIntervalSince(warm.timestamp)) <= 60 {
            return finishImmediately(enrichment(warm))
        }
        manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.finish(.init(location: nil, outcome: .timedOut))
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.filter({ $0.horizontalAccuracy >= 0 }).max(by: { $0.timestamp < $1.timestamp }) else {
            finish(.init(location: nil, outcome: .unavailable)); return
        }
        guard abs(Date().timeIntervalSince(latest.timestamp)) <= 60 else {
            finish(.init(location: nil, outcome: .staleFix)); return
        }
        finish(enrichment(latest))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.init(location: nil, outcome: .unavailable))
    }

    private func enrichment(_ value: CLLocation) -> WalletLocationEnrichment {
        .init(location: .init(latitude: value.coordinate.latitude, longitude: value.coordinate.longitude,
                              horizontalAccuracyMeters: value.horizontalAccuracy, capturedAt: value.timestamp),
              outcome: .captured)
    }
    private func finishImmediately(_ value: WalletLocationEnrichment) -> WalletLocationEnrichment {
        Self.active[id] = nil; return value
    }
    private func finish(_ value: WalletLocationEnrichment) {
        guard let continuation else { return }
        self.continuation = nil; timeout?.cancel(); manager.stopUpdatingLocation()
        Self.active[id] = nil; continuation.resume(returning: value)
    }
}

enum WalletIntentLocationSampler {
    static func sample() async -> WalletLocationEnrichment { await WalletIntentLocationRequest.sample() }
}
