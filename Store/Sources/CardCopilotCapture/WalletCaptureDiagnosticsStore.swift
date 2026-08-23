import Foundation

public struct WalletCaptureDiagnosticRecord: Codable, Sendable, Equatable, Identifiable {
    public let eventID: String
    public let createdAt: Date
    public var completedAt: Date?
    public var deliveryState: WalletDeliveryState
    public var amountDecodeStatus: WalletAmountDecodeStatus
    public var missingFields: [String]
    public var attemptCount: Int
    public var safeError: String?
    public var httpStatus: Int?
    public var serverEventID: String?
    public var timeline: [WalletCaptureTimelineEntry]
    public var event: WalletCaptureEvent?
    public var id: String { eventID }
}

public struct WalletCaptureDiagnosticReport: Codable, Sendable, Equatable, Identifiable {
    public let reportID: String
    public let preparedAt: Date
    public let eventID: String
    public let serverEventID: String?
    public let deliveryState: String
    public let amountDecodeStatus: String
    public let missingFields: [String]
    public let attemptCount: Int
    public let safeError: String?
    public let httpStatus: Int?
    public let appVersion: String?
    public let buildNumber: String?
    public let osVersion: String?
    public let captureVersion: Int?
    public let locationOutcome: String?
    public let locationAccuracyCategory: String?
    public let timeline: [WalletCaptureTimelineEntry]
    public let includedTransactionDetails: Bool
    public let transactionDetails: [String: String?]?
    public var id: String { reportID }
}

public struct WalletCaptureStatusSnapshot: Sendable, Equatable {
    public let lastTriggerAt: Date?
    public let lastAcceptedAt: Date?
    public let pendingCount: Int
    public let unassignedCount: Int
    public let quarantinedCount: Int
    public let oldestPendingAt: Date?
    public let lastSafeError: String?
    public let failingStage: String?
    public init(lastTriggerAt: Date?, lastAcceptedAt: Date?, pendingCount: Int, unassignedCount: Int,
                quarantinedCount: Int, oldestPendingAt: Date?, lastSafeError: String?, failingStage: String?) {
        self.lastTriggerAt = lastTriggerAt; self.lastAcceptedAt = lastAcceptedAt
        self.pendingCount = pendingCount; self.unassignedCount = unassignedCount
        self.quarantinedCount = quarantinedCount; self.oldestPendingAt = oldestPendingAt
        self.lastSafeError = lastSafeError; self.failingStage = failingStage
    }
}

public actor WalletCaptureDiagnosticsStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let now: @Sendable () -> Date
    private let completedRetention: TimeInterval
    private let completedLimit: Int

    public init(root: URL, completedRetention: TimeInterval = 30 * 24 * 60 * 60,
                completedLimit: Int = 500, now: @escaping @Sendable () -> Date = Date.init) throws {
        directory = root.appendingPathComponent("WalletCapture/diagnostics", isDirectory: true)
        self.completedRetention = completedRetention; self.completedLimit = completedLimit; self.now = now
        encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var mutable = directory; try? mutable.setResourceValues(values)
    }

    public func begin(_ capture: WalletQueuedCapture) throws {
        let record = WalletCaptureDiagnosticRecord(eventID: capture.event.eventId,
            createdAt: capture.event.capturedAt, completedAt: nil, deliveryState: capture.deliveryState,
            amountDecodeStatus: capture.event.transaction.amountDecodeStatus,
            missingFields: capture.event.missingFieldNames, attemptCount: capture.attemptCount,
            safeError: capture.safeError, httpStatus: nil, serverEventID: nil,
            timeline: capture.timeline, event: capture.event)
        try write(record)
    }

    public func append(eventID: String, stage: String, detail: String? = nil) throws {
        guard var record = try load(eventID) else { return }
        record.timeline.append(.init(at: now(), stage: stage, detail: detail))
        try write(record)
    }

    public func update(eventID: String, capture: WalletQueuedCapture, result: WalletUploadResult? = nil) throws {
        guard var record = try load(eventID) else { return }
        record.deliveryState = capture.deliveryState; record.attemptCount = capture.attemptCount
        record.safeError = result?.safeError ?? capture.safeError
        record.httpStatus = result?.httpStatus ?? record.httpStatus
        record.serverEventID = result?.serverEventID ?? record.serverEventID
        record.event = capture.event
        for entry in capture.timeline where !record.timeline.contains(entry) { record.timeline.append(entry) }
        if let result {
            record.timeline.append(.init(at: now(), stage: "upload\(result.disposition.rawValue.capitalized)", detail: result.safeError))
        }
        try write(record)
    }

    public func complete(eventID: String, disposition: WalletUploadDisposition,
                         result: WalletUploadResult? = nil) throws {
        guard var record = try load(eventID) else { return }
        record.completedAt = now()
        record.deliveryState = disposition == .duplicate ? .duplicate : .accepted
        record.httpStatus = result?.httpStatus ?? record.httpStatus
        record.serverEventID = result?.serverEventID ?? record.serverEventID
        record.safeError = nil
        record.timeline.append(.init(at: now(), stage: disposition == .duplicate ? "duplicateAccepted" : "acceptedByInunity"))
        record.timeline.append(.init(at: now(), stage: "removedFromOutbox"))
        try write(record)
        try prune()
    }

    public func records() throws -> [WalletCaptureDiagnosticRecord] {
        try prune()
        return try readRecords()
    }

    private func readRecords() throws -> [WalletCaptureDiagnosticRecord] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(WalletCaptureDiagnosticRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func prepareReport(eventID: String, includeTransactionDetails: Bool) throws -> WalletCaptureDiagnosticReport {
        guard let record = try load(eventID) else { throw CocoaError(.fileNoSuchFile) }
        let locationEntry = record.timeline.last { $0.stage.hasPrefix("location") }
        let accuracy = record.event?.location.map { locationAccuracyCategory($0.horizontalAccuracyMeters) }
        let details: [String: String?]? = includeTransactionDetails ? [
            "merchant": record.event?.transaction.merchantRaw,
            "transactionName": record.event?.transaction.transactionNameRaw,
            "amountRaw": record.event?.transaction.amountRaw,
            "currency": record.event?.transaction.currencyRaw,
            "card": record.event?.transaction.cardRaw,
        ] : nil
        return .init(reportID: UUID().uuidString, preparedAt: now(), eventID: short(record.eventID),
            serverEventID: record.serverEventID, deliveryState: record.deliveryState.rawValue,
            amountDecodeStatus: record.amountDecodeStatus.rawValue, missingFields: record.missingFields,
            attemptCount: record.attemptCount, safeError: record.safeError, httpStatus: record.httpStatus,
            appVersion: record.event?.client.appVersion, buildNumber: record.event?.client.buildNumber,
            osVersion: record.event?.client.osVersion, captureVersion: record.event?.captureVersion,
            locationOutcome: locationEntry?.detail ?? locationEntry?.stage,
            locationAccuracyCategory: accuracy, timeline: record.timeline,
            includedTransactionDetails: includeTransactionDetails, transactionDetails: details)
    }

    public func delete(eventID: String) throws { try? FileManager.default.removeItem(at: file(eventID)) }

    public func status(outbox: WalletOutboxStore) async -> WalletCaptureStatusSnapshot {
        let pending = (try? await outbox.captures(in: .pending)) ?? []
        let inflight = (try? await outbox.captures(in: .inflight)) ?? []
        let unassigned = (try? await outbox.captures(in: .unassigned)) ?? []
        let quarantined = (try? await outbox.captures(in: .quarantined)) ?? []
        let records = (try? records()) ?? []
        let queued = pending + inflight
        let latestProblem = records.first { $0.safeError != nil || $0.deliveryState == .quarantined || $0.deliveryState == .authenticationBlocked }
        return .init(lastTriggerAt: records.map(\.createdAt).max(),
            lastAcceptedAt: records.compactMap(\.completedAt).max(),
            pendingCount: queued.count, unassignedCount: unassigned.count,
            quarantinedCount: quarantined.count, oldestPendingAt: queued.map(\.event.capturedAt).min(),
            lastSafeError: latestProblem?.safeError,
            failingStage: latestProblem?.timeline.last?.stage)
    }

    private func load(_ eventID: String) throws -> WalletCaptureDiagnosticRecord? {
        let url = file(eventID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(WalletCaptureDiagnosticRecord.self, from: Data(contentsOf: url))
    }
    private func write(_ value: WalletCaptureDiagnosticRecord) throws {
        let target = file(value.eventID)
        try encoder.encode(value).write(to: target, options: .atomic)
        #if os(iOS) || os(tvOS) || os(watchOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: target.path)
        #endif
    }
    private func file(_ id: String) -> URL { directory.appendingPathComponent(id + ".json") }
    private func short(_ id: String) -> String { String(id.prefix(8)) }
    private func locationAccuracyCategory(_ meters: Double) -> String {
        if meters <= 25 { return "precise" }
        if meters <= 100 { return "nearby" }
        return "coarse"
    }
    private func prune() throws {
        let values = try readRecords()
        let expired = values.filter { $0.completedAt.map { now().timeIntervalSince($0) > completedRetention } == true }
        for value in expired { try? FileManager.default.removeItem(at: file(value.eventID)) }
        let expiredIDs = Set(expired.map(\.eventID))
        let remainingCompleted = values.filter { $0.completedAt != nil && !expiredIDs.contains($0.eventID) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        for value in remainingCompleted.dropFirst(completedLimit) { try? FileManager.default.removeItem(at: file(value.eventID)) }
    }
}
