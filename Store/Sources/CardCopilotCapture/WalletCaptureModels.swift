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

    public var isMeaningful: Bool {
        [transaction.merchantRaw, transaction.transactionNameRaw, transaction.amountRaw,
         transaction.currencyRaw, transaction.cardRaw, transaction.paymentMethodRaw]
            .contains { $0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
    }

    public var missingFieldNames: [String] {
        var fields: [String] = []
        if transaction.merchantRaw?.nonEmpty == nil && transaction.transactionNameRaw?.nonEmpty == nil {
            fields.append(contentsOf: ["merchantRaw", "transactionNameRaw"])
        }
        if transaction.amountDecodeStatus == .absent { fields.append("amountRaw") }
        if transaction.amountDecodeStatus == .undecodable { fields.append("amountDecimal") }
        if transaction.cardRaw?.nonEmpty == nil { fields.append("cardRaw") }
        return fields
    }
}

public enum WalletDeliveryState: String, Codable, Sendable { case pending, inflight, authenticationBlocked, quarantined, accepted, duplicate }

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
    public let httpStatus: Int?
    public let serverEventID: String?
    public let refinementVerdict: String?
    public init(_ disposition: WalletUploadDisposition, retryAfter: Date? = nil, safeError: String? = nil,
                httpStatus: Int? = nil, serverEventID: String? = nil, refinementVerdict: String? = nil) {
        self.disposition = disposition; self.retryAfter = retryAfter; self.safeError = safeError
        self.httpStatus = httpStatus; self.serverEventID = serverEventID; self.refinementVerdict = refinementVerdict
    }
}

public enum WalletOutboxBucket: String, Sendable, CaseIterable { case pending, inflight, unassigned, quarantined, diagnostics }

public struct WalletCaptureVerdictEvaluation: Sendable, Equatable {
    public let verdict: WalletCaptureVerdict?
    public let issue: String?
    public let capDataIsStale: Bool
    public init(verdict: WalletCaptureVerdict? = nil, issue: String? = nil, capDataIsStale: Bool = false) {
        self.verdict = verdict; self.issue = issue; self.capDataIsStale = capDataIsStale
    }
}

public enum WalletCaptureReceiptKind: String, Sendable { case savedSecurely, savedOffline, savedAwaitingAccount, configurationError }

public struct WalletCaptureReceipt: Sendable, Equatable {
    public let event: WalletCaptureEvent
    public let kind: WalletCaptureReceiptKind
    public let verdict: WalletCaptureVerdictEvaluation
    public init(event: WalletCaptureEvent, kind: WalletCaptureReceiptKind, verdict: WalletCaptureVerdictEvaluation) {
        self.event = event; self.kind = kind; self.verdict = verdict
    }
}

public enum WalletLocationOutcome: String, Codable, Sendable {
    case captured, permissionDenied, permissionRestricted, timedOut, unavailable, staleFix
}

public struct WalletLocationEnrichment: Sendable, Equatable {
    public let location: WalletCaptureLocation?
    public let outcome: WalletLocationOutcome
    public init(location: WalletCaptureLocation?, outcome: WalletLocationOutcome) {
        self.location = location; self.outcome = outcome
    }
    public static let unavailable = WalletLocationEnrichment(location: nil, outcome: .unavailable)
}

public struct WalletCaptureDrainSummary: Sendable, Equatable {
    public var accepted = 0
    public var duplicates = 0
    public var backlogUploaded = 0
    public var authenticationBlocked = 0
    public var quarantined = 0
    public var retainedForRetry = 0
    public init() {}
    public var uploadedCount: Int { accepted + duplicates }
}

public enum WalletCaptureError: Error, Sendable { case localPersistenceFailed, credentialUnavailable }

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
