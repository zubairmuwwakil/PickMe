import Foundation

public actor WalletOutboxStore {
    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL) throws {
        let captureRoot = root.appendingPathComponent("WalletCapture", isDirectory: true)
        self.root = captureRoot
        encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        for bucket in WalletOutboxBucket.allCases {
            try FileManager.default.createDirectory(
                at: captureRoot.appendingPathComponent(bucket.rawValue, isDirectory: true),
                withIntermediateDirectories: true)
        }
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var mutableRoot = captureRoot; try? mutableRoot.setResourceValues(values)
    }

    public func persist(_ capture: WalletQueuedCapture, to bucket: WalletOutboxBucket = .pending) throws {
        try write(capture, to: file(capture.event.eventId, in: bucket))
    }

    public func captures(in bucket: WalletOutboxBucket) throws -> [WalletQueuedCapture] {
        try urls(in: bucket).compactMap { try? decoder.decode(WalletQueuedCapture.self, from: Data(contentsOf: $0)) }
            .sorted { $0.event.capturedAt < $1.event.capturedAt }
    }

    public func claim(_ eventID: String) throws -> WalletQueuedCapture? {
        let source = file(eventID, in: .pending), target = file(eventID, in: .inflight)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: source, to: target)
        var capture = try decoder.decode(WalletQueuedCapture.self, from: Data(contentsOf: target))
        capture.deliveryState = .inflight
        try write(capture, to: target)
        return capture
    }

    public func recoverStaleInflight(olderThan cutoff: Date) throws {
        for capture in try captures(in: .inflight) where (capture.lastAttemptAt ?? capture.event.capturedAt) < cutoff {
            var recovered = capture; recovered.deliveryState = .pending
            try persist(recovered)
            try? FileManager.default.removeItem(at: file(capture.event.eventId, in: .inflight))
        }
    }

    public func enrich(eventID: String, location: WalletCaptureLocation) throws {
        for bucket in [WalletOutboxBucket.pending, .unassigned] {
            let url = file(eventID, in: bucket)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            var capture = try decoder.decode(WalletQueuedCapture.self, from: Data(contentsOf: url))
            capture.event.location = location
            capture.timeline.append(.init(stage: "locationCaptured"))
            try write(capture, to: url)
            return
        }
    }

    public func resolve(_ capture: WalletQueuedCapture, result: WalletUploadResult) throws {
        let inflight = file(capture.event.eventId, in: .inflight)
        switch result.disposition {
        case .accepted, .duplicate:
            try? FileManager.default.removeItem(at: inflight)
        case .authenticationRequired:
            var value = capture; value.deliveryState = .authenticationBlocked; value.safeError = result.safeError
            try write(value, to: file(value.event.eventId, in: .pending)); try? FileManager.default.removeItem(at: inflight)
        case .retry:
            var value = capture; value.deliveryState = .pending; value.nextRetryAt = result.retryAfter; value.safeError = result.safeError
            try write(value, to: file(value.event.eventId, in: .pending)); try? FileManager.default.removeItem(at: inflight)
        case .invalid:
            var value = capture; value.deliveryState = .quarantined; value.safeError = result.safeError
            try write(value, to: file(value.event.eventId, in: .quarantined)); try? FileManager.default.removeItem(at: inflight)
        }
    }

    public func deleteAll() throws {
        for bucket in WalletOutboxBucket.allCases { for url in try urls(in: bucket) { try FileManager.default.removeItem(at: url) } }
    }

    /// Called only after the owner explicitly connects/relinks the destination account.
    public func assignUnassignedToPending() throws {
        for var capture in try captures(in: .unassigned) {
            capture.deliveryState = .pending
            capture.timeline.append(.init(stage: "assignedAfterRelink"))
            try persist(capture, to: .pending)
            try? FileManager.default.removeItem(at: file(capture.event.eventId, in: .unassigned))
        }
    }

    private func directory(_ bucket: WalletOutboxBucket) -> URL { root.appendingPathComponent(bucket.rawValue, isDirectory: true) }
    private func file(_ id: String, in bucket: WalletOutboxBucket) -> URL { directory(bucket).appendingPathComponent(id + ".json") }
    private func urls(in bucket: WalletOutboxBucket) throws -> [URL] { try FileManager.default.contentsOfDirectory(at: directory(bucket), includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" } }
    private func write(_ value: WalletQueuedCapture, to url: URL) throws {
        let data = try encoder.encode(value)
        // Foundation implements `.atomic` as a sibling temp-file write followed by rename,
        // preserving the previous complete record until the replacement is durable.
        try data.write(to: url, options: [.atomic])
    }
}
