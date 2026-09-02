import Foundation
import CardCopilotEngine

/// Which rung of the resolution ladder actually answers, counted on device.
///
/// Deliberately holds no merchant, no category, no coordinate and no timestamp — only how often
/// each `ConfidenceSource` was the one that answered. That is enough to decide whether the pack
/// is the bottleneck and not enough to reconstruct a single purchase, which is the line the
/// ambient design draws: nothing about what the owner bought leaves the device, and nothing here
/// would be worth exfiltrating if it did.
///
/// It exists because nobody knew this number. Not knowing it is how importing an open places
/// dataset came to look like the obvious fix — the pack was assumed to be the bottleneck without
/// any evidence that it was, when the actual failures were a discarded field and a gate that
/// refused a deliberate fork.
public struct CategoryResolutionMetrics: Codable, Equatable, Sendable {
    /// `ConfidenceSource.rawValue` -> how many times it was the rung that answered.
    public var resolutionsByRung: [String: Int] = [:]
    /// Answers carrying more than one candidate. Not a failure — the engine collapses a fork when
    /// the branches agree — but the population that better evidence would most improve.
    public var forkedResolutions = 0
    public var walletEnrichmentAttempts = 0
    public var walletEnrichmentMatches = 0
    /// Captures that could never be enriched because the server sent no coordinates. Distinguishes
    /// "we looked and found nothing" from "we were never able to look", which are different
    /// problems with different owners.
    public var walletEnrichmentSkippedWithoutLocation = 0

    public init() {}

    public var totalResolutions: Int { resolutionsByRung.values.reduce(0, +) }

    /// How often nothing on the ladder could answer.
    public var unresolved: Int { resolutionsByRung[ConfidenceSource.fallback.rawValue] ?? 0 }

    /// The number worth acting on. Nil rather than zero before anything is recorded: no data is
    /// not the same claim as "nothing fails", and the difference decides whether to ship more data.
    public var unresolvedShare: Double? {
        let total = totalResolutions
        guard total > 0 else { return nil }
        return Double(unresolved) / Double(total)
    }
}

public final class CategoryResolutionMetricsStore: @unchecked Sendable {
    public enum Event {
        case resolved(rung: ConfidenceSource, forked: Bool)
        case walletEnrichmentAttempted
        case walletEnrichmentMatched
        case walletEnrichmentSkippedWithoutLocation
    }

    private let defaults: UserDefaults
    private let key: String

    /// Shares the App Group suite for the same reason `MerchantPatronageStore` does: resolution
    /// happens in the app, in the Wallet Capture App Intent, and on a geofence wake, and a counter
    /// split across three process-local stores would answer nothing.
    public init(defaults: UserDefaults = OwnerStateLocalStore.sharedDefaults,
                key: String = "ca.pickme.category-resolution-metrics.v1") {
        self.defaults = defaults
        self.key = key
    }

    public var snapshot: CategoryResolutionMetrics {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(CategoryResolutionMetrics.self, from: data)
        else { return CategoryResolutionMetrics() }
        return decoded
    }

    public func record(_ event: Event) {
        var metrics = snapshot
        switch event {
        case .resolved(let rung, let forked):
            metrics.resolutionsByRung[rung.rawValue, default: 0] += 1
            if forked { metrics.forkedResolutions += 1 }
        case .walletEnrichmentAttempted:
            metrics.walletEnrichmentAttempts += 1
        case .walletEnrichmentMatched:
            metrics.walletEnrichmentMatches += 1
        case .walletEnrichmentSkippedWithoutLocation:
            metrics.walletEnrichmentSkippedWithoutLocation += 1
        }
        guard let data = try? JSONEncoder().encode(metrics) else { return }
        defaults.set(data, forKey: key)
    }

    /// Owner-facing erase. Counters are derived from purchases; a history wipe that left them
    /// standing would keep describing activity the owner asked to be forgotten.
    public func forgetAll() {
        defaults.removeObject(forKey: key)
    }
}
