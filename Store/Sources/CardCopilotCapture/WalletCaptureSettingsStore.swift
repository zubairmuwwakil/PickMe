import Foundation

public struct WalletCaptureConnectionState: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var connectionVerifiedAt: Date?
    public var boundUserID: String?
    public init(isEnabled: Bool = true, connectionVerifiedAt: Date? = nil, boundUserID: String? = nil) {
        self.isEnabled = isEnabled; self.connectionVerifiedAt = connectionVerifiedAt; self.boundUserID = boundUserID
    }
}

public struct WalletCaptureSettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "walletCapture.connectionState.v1"
    public init(suiteName: String = "group.ca.inunity.pickme") {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }
    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func load() -> WalletCaptureConnectionState {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(WalletCaptureConnectionState.self, from: data) else {
            return .init()
        }
        return value
    }
    public func save(_ value: WalletCaptureConnectionState) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
    public func setEnabled(_ enabled: Bool) {
        var value = load(); value.isEnabled = enabled; save(value)
    }
    public func markConnectionPending(boundUserID: String) {
        var value = load(); value.isEnabled = true; value.boundUserID = boundUserID
        value.connectionVerifiedAt = nil; save(value)
    }
    public func markConnectionVerified(boundUserID: String, at: Date = Date()) {
        var value = load(); value.isEnabled = true; value.boundUserID = boundUserID
        value.connectionVerifiedAt = at; save(value)
    }
    public func clearConnection() {
        var value = load(); value.connectionVerifiedAt = nil; value.boundUserID = nil; save(value)
    }
}

public struct WalletCardAliasStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "walletCapture.cardAliases.v1"
    public init(suiteName: String = "group.ca.inunity.pickme") {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }
    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func cardID(for raw: String?) -> String? {
        guard let raw else { return nil }
        return aliases()[Self.key(raw)]
    }
    public func merge(raw: String?, cardID: String?) {
        guard let raw, let cardID else { return }
        var values = aliases(); values[Self.key(raw)] = cardID
        defaults.set(try? JSONEncoder().encode(values), forKey: key)
    }
    public func replace(_ values: [String: String]) {
        if let data = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: values.map { (Self.key($0.key), $0.value) })) {
            defaults.set(data, forKey: key)
        }
    }
    private func aliases() -> [String: String] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
    private static func key(_ raw: String) -> String {
        raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct WalletCaptureNotificationDecision: Sendable, Equatable {
    public enum Route: Sendable { case inApp, localNotification }
    public let identifier: String
    public let title: String
    public let body: String
    public let route: Route

    public static func currentEvent(receipt: WalletCaptureReceipt, appIsActive: Bool,
                                    recommendedCardName: String?) -> Self {
        let title: String
        let body: String
        switch receipt.kind {
        case .configurationError:
            title = "Wallet Capture needs attention"
            body = "No Wallet fields arrived. Review the automation mappings in PickMe."
        case .savedOffline:
            title = "Purchase received"
            if let recommendedCardName {
                body = "Saved offline. \(recommendedCardName) would have earned more. It will sync automatically."
            } else {
                body = "Saved offline. It will sync automatically."
            }
        case .savedSecurely:
            title = "Purchase received"
            body = recommendedCardName.map { "Saved securely. \($0) would have earned more." } ?? "Saved securely."
        case .savedAwaitingAccount:
            title = "Purchase saved on this iPhone"
            body = "Open PickMe and choose the Inunity account that should receive it."
        }
        return .init(identifier: receipt.event.eventId, title: title, body: body,
                     route: appIsActive ? .inApp : .localNotification)
    }
}

public enum WalletCaptureAccountRouting: Sendable, Equatable {
    case boundAccount
    case unassigned

    public static func decide(credentialBoundUserID: String?, signedInUserID: String?) -> Self {
        guard let credentialBoundUserID else { return .unassigned }
        guard let signedInUserID else { return .boundAccount }
        return signedInUserID == credentialBoundUserID ? .boundAccount : .unassigned
    }
}

public struct WalletCaptureDeliveryDecision: Sendable, Equatable {
    public let accountRouting: WalletCaptureAccountRouting
    public let canUpload: Bool

    public static func decide(credentialBoundUserID: String?,
                              connection: WalletCaptureConnectionState,
                              signedInUserID: String?) -> Self {
        let routing = WalletCaptureAccountRouting.decide(
            credentialBoundUserID: credentialBoundUserID,
            signedInUserID: signedInUserID)
        let isVerified = credentialBoundUserID.map {
            connection.connectionVerifiedAt != nil && connection.boundUserID == $0
        } ?? false
        return .init(accountRouting: routing,
                     canUpload: routing == .boundAccount && isVerified)
    }
}
