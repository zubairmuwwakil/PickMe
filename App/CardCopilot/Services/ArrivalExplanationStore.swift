import CardCopilotEngine
import CryptoKit
import Foundation

/// The latest diagnostic for a place, not a purchase or a visit history. No merchant name,
/// coordinate, card, amount or raw place identifier is retained here.
struct ArrivalExplanationRecord: Codable {
    enum Outcome: String, Codable {
        case checking, unresolved, noRecommendation, evaluated, notificationAccepted, notificationFailed
    }
    enum NotificationPermission: String, Codable {
        case allowed, quiet, blocked, unknown
    }

    let attemptID: UUID
    let recordedAt: Date
    let outcome: Outcome
    let reasons: [AmbientSuppressionReason]
    let activity: LiveActivityRequestOutcome
    let merchantDigest: String?
    let notificationPermission: NotificationPermission?
}

struct ArrivalExplanationSnapshot {
    let records: [String: ArrivalExplanationRecord]

    struct Match {
        let record: ArrivalExplanationRecord
        let isExactMerchant: Bool
    }

    /// An area wake must never be turned into evidence that every shop in that plaza was visited.
    func latest(merchantIdentifier: String, regionIdentifiers: [String]) -> Match? {
        let digest = ArrivalExplanationStore.digest(merchantIdentifier)
        // A later check for another store in the same plaza must not hide this branch's result.
        if let record = records["merchant:" + digest] {
            return Match(record: record, isExactMerchant: true)
        }
        let keys = regionIdentifiers.map { "region:" + ArrivalExplanationStore.digest($0) }
        guard let record = keys.compactMap({ records[$0] }).max(by: { $0.recordedAt < $1.recordedAt }) else { return nil }
        return Match(record: record, isExactMerchant: record.merchantDigest == digest)
    }
}

@MainActor
final class ArrivalExplanationStore {
    private let defaults: UserDefaults
    private let key = "arrivalExplanations.v1"
    private let retention: TimeInterval = 7 * 24 * 60 * 60
    private let maximumEntries = 200
    /// An in-flight callback cannot recreate explanations after the owner erases them.
    private(set) var generation: UInt = 0

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    nonisolated static func digest(_ identifier: String) -> String {
        SHA256.hash(data: Data(identifier.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func snapshot(now: Date = .now) -> ArrivalExplanationSnapshot {
        let records = retained(now: now)
        persist(records)
        return ArrivalExplanationSnapshot(records: records)
    }

    func record(attemptID: UUID, startedAt: Date, outcome: ArrivalExplanationRecord.Outcome,
                merchantIdentifier: String?, regionIdentifier: String,
                reasons: Set<AmbientSuppressionReason> = [], activity: LiveActivityRequestOutcome = .notRequested,
                notificationPermission: ArrivalExplanationRecord.NotificationPermission? = nil,
                generation expectedGeneration: UInt) {
        guard generation == expectedGeneration else { return }
        var records = retained(now: .now)
        let merchantDigest = merchantIdentifier.map(Self.digest)
        let record = ArrivalExplanationRecord(attemptID: attemptID, recordedAt: startedAt,
                                              outcome: outcome, reasons: reasons.sorted { $0.rawValue < $1.rawValue },
                                              activity: activity, merchantDigest: merchantDigest,
                                              notificationPermission: notificationPermission)
        var keys = ["region:" + Self.digest(regionIdentifier)]
        if let merchantDigest { keys.append("merchant:" + merchantDigest) }
        for key in keys {
            // Older asynchronous completions cannot replace a more recent arrival check.
            if let existing = records[key], existing.recordedAt > startedAt { continue }
            records[key] = record
        }
        let newest = records.sorted {
            $0.value.recordedAt == $1.value.recordedAt ? $0.key < $1.key : $0.value.recordedAt > $1.value.recordedAt
        }.prefix(maximumEntries)
        persist(Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) }))
    }

    func forgetAll() {
        generation &+= 1
        defaults.removeObject(forKey: key)
    }

    private func retained(now: Date) -> [String: ArrivalExplanationRecord] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([String: ArrivalExplanationRecord].self, from: data) else { return [:] }
        let cutoff = now.addingTimeInterval(-retention)
        return records.filter { $0.value.recordedAt >= cutoff && $0.value.recordedAt <= now }
    }

    private func persist(_ records: [String: ArrivalExplanationRecord]) {
        if records.isEmpty { defaults.removeObject(forKey: key); return }
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}
