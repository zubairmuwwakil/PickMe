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
        guard !FileManager.default.fileExists(atPath: target.path) else { return nil }
        try FileManager.default.moveItem(at: source, to: target)
        var capture = try decoder.decode(WalletQueuedCapture.self, from: Data(contentsOf: target))
        capture.deliveryState = .inflight
        try write(capture, to: target)
        return capture
    }

    public func recoverStaleInflight(olderThan cutoff: Date) throws {
        for capture in try captures(in: .inflight) where (capture.lastAttemptAt ?? capture.event.capturedAt) < cutoff {
            var recovered = capture; recovered.deliveryState = .pending
            recovered.timeline.append(.init(stage: "staleClaimRecovered"))
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

    public func appendTimeline(eventID: String, stage: String, detail: String? = nil) throws {
        for bucket in [WalletOutboxBucket.pending, .inflight, .unassigned, .quarantined] {
            let url = file(eventID, in: bucket)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            var capture = try decoder.decode(WalletQueuedCapture.self, from: Data(contentsOf: url))
            capture.timeline.append(.init(stage: stage, detail: detail))
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
            value.timeline.append(.init(stage: "authenticationBlocked"))
            try write(value, to: file(value.event.eventId, in: .pending)); try? FileManager.default.removeItem(at: inflight)
        case .retry:
            var value = capture; value.deliveryState = .pending; value.nextRetryAt = result.retryAfter; value.safeError = result.safeError
            value.timeline.append(.init(stage: "uploadRetained", detail: result.safeError))
            try write(value, to: file(value.event.eventId, in: .pending)); try? FileManager.default.removeItem(at: inflight)
        case .invalid:
            var value = capture; value.deliveryState = .quarantined; value.safeError = result.safeError
            value.timeline.append(.init(stage: "quarantined", detail: result.safeError))
            try write(value, to: file(value.event.eventId, in: .quarantined)); try? FileManager.default.removeItem(at: inflight)
        }
    }

    public func deleteAll() throws {
        for bucket in WalletOutboxBucket.allCases { for url in try urls(in: bucket) { try FileManager.default.removeItem(at: url) } }
    }

    public func deleteAllUnsent() throws {
        for bucket in [WalletOutboxBucket.pending, .inflight, .unassigned, .quarantined] {
            for url in try urls(in: bucket) { try FileManager.default.removeItem(at: url) }
        }
    }

    public func delete(eventID: String, from bucket: WalletOutboxBucket) throws {
        let target = file(eventID, in: bucket)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
    }

    public func releaseAuthenticationBlocks() throws {
        for var capture in try captures(in: .pending) where capture.deliveryState == .authenticationBlocked {
            capture.deliveryState = .pending; capture.safeError = nil; capture.nextRetryAt = nil
            capture.timeline.append(.init(stage: "authenticationRestored"))
            try persist(capture)
        }
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

    /// A credential relink to another account must not silently carry captures that were queued
    /// for the previous account. The owner can explicitly assign or delete them after relinking.
    public func requireAccountChoiceForAssignedCaptures() throws {
        for bucket in [WalletOutboxBucket.pending, .inflight] {
            for var capture in try captures(in: bucket) {
                capture.deliveryState = .pending
                capture.nextRetryAt = nil
                capture.timeline.append(.init(stage: "accountChoiceRequiredAfterRelink"))
                try persist(capture, to: .unassigned)
                try FileManager.default.removeItem(at: file(capture.event.eventId, in: bucket))
            }
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
        #if os(iOS) || os(tvOS) || os(watchOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: url.path)
        #endif
    }
}
