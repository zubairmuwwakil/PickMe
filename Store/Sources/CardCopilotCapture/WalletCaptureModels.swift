import Foundation

public enum WalletAmountDecodeStatus: String, Codable, Sendable { case decoded, undecodable, absent }

public struct WalletCaptureInput: Sendable, Equatable {
    public let merchant: String?
    public let amount: String?
    public let transactionName: String?
    public let currency: String?
    public let card: String?
    public let paymentMethod: String?

    public init(merchant: String?, amount: String?, transactionName: String?, currency: String?,
                card: String?, paymentMethod: String?) {
        self.merchant = merchant; self.amount = amount; self.transactionName = transactionName
        self.currency = currency; self.card = card; self.paymentMethod = paymentMethod
    }
}

public struct WalletCaptureTransaction: Codable, Sendable, Equatable {
    public var merchantRaw: String?
    public var transactionNameRaw: String?
    public var amountRaw: String?
    public var amountDecimal: String?
    public var amountDecodeStatus: WalletAmountDecodeStatus
    public var currencyRaw: String?
    public var cardRaw: String?
    public var paymentMethodRaw: String?
}

public struct WalletCaptureLocation: Codable, Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracyMeters: Double
    public let capturedAt: Date
    public init(latitude: Double, longitude: Double, horizontalAccuracyMeters: Double, capturedAt: Date) {
        self.latitude = latitude; self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters; self.capturedAt = capturedAt
    }
}

public struct WalletCaptureClient: Codable, Sendable, Equatable {
    public let appVersion: String
    public let buildNumber: String
    public let osVersion: String
    public let locale: String
    public init(appVersion: String, buildNumber: String, osVersion: String, locale: String) {
        self.appVersion = appVersion; self.buildNumber = buildNumber
        self.osVersion = osVersion; self.locale = locale
    }
}

public struct WalletCaptureEvent: Codable, Sendable, Equatable, Identifiable {
    public let schemaVersion: Int
    public let captureVersion: Int
    public let source: String
    public let transport: String
    public let eventId: String
    public let capturedAt: Date
    public let timezone: String
    public var transaction: WalletCaptureTransaction
    public var location: WalletCaptureLocation?
    public let client: WalletCaptureClient
    public var id: String { eventId }
}

public enum WalletDeliveryState: String, Codable, Sendable { case pending, inflight, authenticationBlocked, quarantined }

public struct WalletCaptureTimelineEntry: Codable, Sendable, Equatable {
    public let at: Date
    public let stage: String
    public let detail: String?
    public init(at: Date = Date(), stage: String, detail: String? = nil) {
        self.at = at; self.stage = stage; self.detail = detail
    }
}

public struct WalletQueuedCapture: Codable, Sendable, Equatable {
    public var event: WalletCaptureEvent
    public var deliveryState: WalletDeliveryState
    public var attemptCount: Int
    public var lastAttemptAt: Date?
    public var nextRetryAt: Date?
    public var safeError: String?
    public var timeline: [WalletCaptureTimelineEntry]
}

public enum WalletUploadDisposition: String, Codable, Sendable { case accepted, duplicate, authenticationRequired, retry, invalid }

public struct WalletUploadResult: Sendable, Equatable {
    public let disposition: WalletUploadDisposition
    public let retryAfter: Date?
    public let safeError: String?
    public init(_ disposition: WalletUploadDisposition, retryAfter: Date? = nil, safeError: String? = nil) {
        self.disposition = disposition; self.retryAfter = retryAfter; self.safeError = safeError
    }
}

public enum WalletOutboxBucket: String, Sendable, CaseIterable { case pending, inflight, unassigned, quarantined, diagnostics }

public enum WalletCaptureError: Error, Sendable { case localPersistenceFailed, emptyInput, credentialUnavailable }
