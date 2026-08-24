import Foundation

/// A user-accessible audit trail for every invocation of the Wallet Shortcut.
///
/// Unlike the protected capture outbox, these presence-only files live in the
/// app's Documents directory so they can be copied from Files/Finder when
/// diagnosing an Apple Wallet automation that did not arrive at the server.
/// Raw merchant, amount, and card values are deliberately never encoded here.
public struct WalletCaptureShortcutRunLog: Codable, Sendable, Equatable, Identifiable {
    public let runID: String
    public let startedAt: Date
    public var finishedAt: Date?
    public let input: WalletCaptureInputLog
    public let client: WalletCaptureClient
    public var captureEnabled: Bool
    public var outcome: String
    public var eventID: String?
    public var eventMeaningful: Bool?
    public var deliveryState: String?
    public var httpStatus: Int?
    public var serverEventID: String?
    public var safeError: String?
    public var id: String { runID }

    public init(runID: String = UUID().uuidString, startedAt: Date = Date(), input: WalletCaptureInput,
                client: WalletCaptureClient, captureEnabled: Bool) {
        self.runID = runID
        self.startedAt = startedAt
        self.finishedAt = nil
        self.input = .init(input)
        self.client = client
        self.captureEnabled = captureEnabled
        self.outcome = "started"
        self.eventID = nil
        self.eventMeaningful = nil
        self.deliveryState = nil
        self.httpStatus = nil
        self.serverEventID = nil
        self.safeError = nil
    }
}

public struct WalletCaptureInputLog: Codable, Sendable, Equatable {
    public let merchantPresent: Bool
    public let amountPresent: Bool
    public let transactionNamePresent: Bool
    public let currencyPresent: Bool
    public let cardPresent: Bool
    public let paymentMethodPresent: Bool

    public init(_ input: WalletCaptureInput) {
        merchantPresent = Self.present(input.merchant)
        amountPresent = Self.present(input.amount)
        transactionNamePresent = Self.present(input.transactionName)
        currencyPresent = Self.present(input.currency)
        cardPresent = Self.present(input.card)
        paymentMethodPresent = Self.present(input.paymentMethod)
    }

    private enum CodingKeys: String, CodingKey {
        case merchantPresent, amountPresent, transactionNamePresent, currencyPresent, cardPresent, paymentMethodPresent
        // Legacy keys are decoded only to migrate existing on-device logs to
        // presence-only metadata. They are never encoded again.
        case merchant, amount, transactionName, currency, card, paymentMethod
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func presence(_ boolean: CodingKeys, legacy: CodingKeys) -> Bool {
            if let value = try? values.decode(Bool.self, forKey: boolean) { return value }
            let legacyValue = (try? values.decodeIfPresent(String.self, forKey: legacy)) ?? nil
            return Self.present(legacyValue)
        }
        merchantPresent = presence(.merchantPresent, legacy: .merchant)
        amountPresent = presence(.amountPresent, legacy: .amount)
        transactionNamePresent = presence(.transactionNamePresent, legacy: .transactionName)
        currencyPresent = presence(.currencyPresent, legacy: .currency)
        cardPresent = presence(.cardPresent, legacy: .card)
        paymentMethodPresent = presence(.paymentMethodPresent, legacy: .paymentMethod)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(merchantPresent, forKey: .merchantPresent)
        try values.encode(amountPresent, forKey: .amountPresent)
        try values.encode(transactionNamePresent, forKey: .transactionNamePresent)
        try values.encode(currencyPresent, forKey: .currencyPresent)
        try values.encode(cardPresent, forKey: .cardPresent)
        try values.encode(paymentMethodPresent, forKey: .paymentMethodPresent)
    }

    private static func present(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

public actor WalletCaptureShortcutRunLogStore {
    /// Relative to the app's Documents directory, which is exposed by PickMe's
    /// existing file-sharing configuration.
    public static let directoryName = "WalletCapture/ShortcutLogs"

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let retention: TimeInterval
    private let limit: Int
    private let now: @Sendable () -> Date

    public init(documentsDirectory: URL, retention: TimeInterval = 30 * 24 * 60 * 60,
                limit: Int = 500, now: @escaping @Sendable () -> Date = Date.init) throws {
        directory = documentsDirectory.appendingPathComponent(Self.directoryName, isDirectory: true)
        self.retention = retention; self.limit = limit; self.now = now
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var protectedDirectory = directory; try? protectedDirectory.setResourceValues(values)
    }

    /// Creates the file before any capture work begins, including when capture
    /// is disabled or the App Intent later fails.
    public func begin(_ log: WalletCaptureShortcutRunLog) throws {
        try pruneAndRedact()
        try write(log)
    }

    public func finish(runID: String, outcome: String, event: WalletCaptureEvent? = nil,
                       diagnostic: WalletCaptureDiagnosticRecord? = nil, safeError: String? = nil,
                       at finishedAt: Date = Date()) throws {
        guard var log = try load(runID) else { return }
        log.finishedAt = finishedAt
        log.outcome = outcome
        log.eventID = event?.eventId
        log.eventMeaningful = event?.isMeaningful
        log.deliveryState = diagnostic?.deliveryState.rawValue
        log.httpStatus = diagnostic?.httpStatus
        log.serverEventID = diagnostic?.serverEventID
        log.safeError = safeError ?? diagnostic?.safeError
        try write(log)
    }

    public func records() throws -> [WalletCaptureShortcutRunLog] {
        try pruneAndRedact()
        return try readRecords()
    }

    private func readRecords() throws -> [WalletCaptureShortcutRunLog] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(WalletCaptureShortcutRunLog.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// Applies the result of a later background/app sync to the invocation that
    /// originally created the event.
    public func refreshDelivery(eventID: String, diagnostic: WalletCaptureDiagnosticRecord) throws {
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
            guard var log = try? decoder.decode(WalletCaptureShortcutRunLog.self, from: Data(contentsOf: url)),
                  log.eventID == eventID else { continue }
            log.deliveryState = diagnostic.deliveryState.rawValue
            log.httpStatus = diagnostic.httpStatus
            log.serverEventID = diagnostic.serverEventID
            log.safeError = diagnostic.safeError
            if diagnostic.deliveryState == .accepted || diagnostic.deliveryState == .duplicate {
                log.outcome = "savedAndDelivered"
            }
            try write(log)
        }
    }

    private func load(_ runID: String) throws -> WalletCaptureShortcutRunLog? {
        let url = file(runID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(WalletCaptureShortcutRunLog.self, from: Data(contentsOf: url))
    }

    private func write(_ value: WalletCaptureShortcutRunLog) throws {
        let target = file(value.runID)
        try encoder.encode(value).write(to: target, options: .atomic)
        #if os(iOS) || os(tvOS) || os(watchOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: target.path)
        #endif
    }

    private func pruneAndRedact() throws {
        let records = try readRecords()
        let cutoff = now().addingTimeInterval(-retention)
        let retained = records.filter { $0.startedAt >= cutoff }.prefix(limit)
        let retainedIDs = Set(retained.map(\.runID))
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
            let id = url.deletingPathExtension().lastPathComponent
            if !retainedIDs.contains(id) { try? FileManager.default.removeItem(at: url) }
        }
        // Re-encoding also removes raw fields from logs written by an earlier build.
        for record in retained { try write(record) }
    }

    private func file(_ runID: String) -> URL { directory.appendingPathComponent("\(runID).json") }
}
