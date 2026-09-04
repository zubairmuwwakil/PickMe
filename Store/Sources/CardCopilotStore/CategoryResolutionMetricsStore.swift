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
    /// `MerchantIdentity.MatchRung.rawValue` -> how many times that rung recognised a merchant the
    /// owner already has. A second ladder from `resolutionsByRung`, answering a different question:
    /// that one asks whether we knew what kind of spending this was, this one asks whether we
    /// recognised the shop at all. A `.fallback` category with an identity hit and a `.fallback`
    /// category with an identity miss are opposite problems — one is a merchant we have and cannot
    /// classify, the other is a merchant we have never met — and they were indistinguishable.
    public var identityMatchesByRung: [String: Int] = [:]
    /// Encounters where no stored merchant matched. Expected and healthy for a first visit; only
    /// interesting beside the rung counts, where a rising share says recognition is degrading.
    public var identityMisses = 0

    // MARK: Merchant MCC graph decision quality

    /// Checkouts where the MCC graph was the category source and therefore worth evaluating.
    /// These remain aggregate on-device counters: no merchant/MCC/card/category identity is stored.
    public var mccGraphDecisionEvaluations = 0
    /// Evaluations with at least two MCC branches holding >=10% posterior share.
    public var mccGraphMultiplePlausibleMCCs = 0
    /// Multi-MCC evaluations where every scoreable branch still chose the same card.
    public var mccGraphStableWinnerAcrossMCCs = 0
    /// Multi-MCC evaluations where different plausible MCCs chose different cards. This is the
    /// population where obtaining better MCC evidence has direct recommendation ROI.
    public var mccGraphSensitiveWinnerAcrossMCCs = 0
    /// Multi-MCC evaluations where fewer than two plausible branches mapped to scoreable categories.
    /// A rising count means taxonomy coverage, not more merchant data, is the next bottleneck.
    public var mccGraphInsufficientScoreableBranches = 0

    /// Graph evaluations where owner reward feedback or community evidence existed beyond the
    /// shipped/static baseline.
    public var mccRuntimeEvidenceEvaluations = 0
    /// Runtime-evidence evaluations where the top MCC changed from the seed/static baseline.
    public var mccRuntimeEvidenceChangedTopMCC = 0
    /// Runtime-evidence evaluations where baseline and learned top branches could both be scored.
    public var mccRuntimeEvidenceWinnerComparisons = 0
    /// Winner comparisons where learning actually changed the card recommendation.
    public var mccRuntimeEvidenceChangedWinner = 0

    public init() {}

    /// Hand-written so a missing key decodes as zero rather than throwing.
    ///
    /// Swift's synthesized decoder does NOT fall back to a property's default value — a key absent
    /// from the JSON throws `keyNotFound`. `CategoryResolutionMetricsStore.snapshot` swallows that
    /// with `try?` and returns a fresh empty struct, so adding a field to this type on the
    /// synthesized decoder would silently reset every counter an owner had accumulated, on first
    /// launch after the update, with nothing logged. `decodeIfPresent` throughout is what makes
    /// adding the next field safe.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys) throws -> Int {
            try container.decodeIfPresent(Int.self, forKey: key) ?? 0
        }
        resolutionsByRung = try container.decodeIfPresent([String: Int].self,
                                                          forKey: .resolutionsByRung) ?? [:]
        forkedResolutions = try count(.forkedResolutions)
        walletEnrichmentAttempts = try count(.walletEnrichmentAttempts)
        walletEnrichmentMatches = try count(.walletEnrichmentMatches)
        walletEnrichmentSkippedWithoutLocation = try count(.walletEnrichmentSkippedWithoutLocation)
        identityMatchesByRung = try container.decodeIfPresent(
            [String: Int].self, forKey: .identityMatchesByRung) ?? [:]
        identityMisses = try count(.identityMisses)
        mccGraphDecisionEvaluations = try count(.mccGraphDecisionEvaluations)
        mccGraphMultiplePlausibleMCCs = try count(.mccGraphMultiplePlausibleMCCs)
        mccGraphStableWinnerAcrossMCCs = try count(.mccGraphStableWinnerAcrossMCCs)
        mccGraphSensitiveWinnerAcrossMCCs = try count(.mccGraphSensitiveWinnerAcrossMCCs)
        mccGraphInsufficientScoreableBranches = try count(.mccGraphInsufficientScoreableBranches)
        mccRuntimeEvidenceEvaluations = try count(.mccRuntimeEvidenceEvaluations)
        mccRuntimeEvidenceChangedTopMCC = try count(.mccRuntimeEvidenceChangedTopMCC)
        mccRuntimeEvidenceWinnerComparisons = try count(.mccRuntimeEvidenceWinnerComparisons)
        mccRuntimeEvidenceChangedWinner = try count(.mccRuntimeEvidenceChangedWinner)
    }

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

    /// Every merchant encounter the identity ladder was asked about, recognised or not.
    public var totalIdentityLookups: Int {
        identityMatchesByRung.values.reduce(0, +) + identityMisses
    }

    /// Of graph checkouts with a scoreable MCC fork, how often better MCC evidence could change the
    /// card. Nil until there is data rather than falsely reporting 0%.
    public var mccWinnerSensitivityShare: Double? {
        let comparable = mccGraphStableWinnerAcrossMCCs + mccGraphSensitiveWinnerAcrossMCCs
        guard comparable > 0 else { return nil }
        return Double(mccGraphSensitiveWinnerAcrossMCCs) / Double(comparable)
    }

    /// Of runtime-evidence comparisons, how often learning changed the winner.
    public var mccRuntimeEvidenceWinnerChangeShare: Double? {
        guard mccRuntimeEvidenceWinnerComparisons > 0 else { return nil }
        return Double(mccRuntimeEvidenceChangedWinner) / Double(mccRuntimeEvidenceWinnerComparisons)
    }
}

public final class CategoryResolutionMetricsStore: @unchecked Sendable {
    public enum Event {
        case resolved(rung: ConfidenceSource, forked: Bool)
        case walletEnrichmentAttempted
        case walletEnrichmentMatched
        case walletEnrichmentSkippedWithoutLocation
        /// A stored merchant was recognised, and by which rung.
        case merchantIdentified(rung: MerchantIdentity.MatchRung)
        /// Nothing matched — a first visit, or a recognition the ladder could not make.
        case merchantUnrecognised
        /// One checkout where the MCC graph was actually the chosen category source.
        case mccGraphDecisionEvaluated(multiplePlausibleMCCs: Bool,
                                       winnerSensitive: Bool?)
        /// One graph checkout carrying evidence collected after the shipped/static baseline.
        case mccRuntimeEvidenceEvaluated(changedTopMCC: Bool,
                                         changedWinner: Bool?)
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
        case .merchantIdentified(let rung):
            metrics.identityMatchesByRung[rung.rawValue, default: 0] += 1
        case .merchantUnrecognised:
            metrics.identityMisses += 1
        case .mccGraphDecisionEvaluated(let multiplePlausible, let winnerSensitive):
            metrics.mccGraphDecisionEvaluations += 1
            guard multiplePlausible else { break }
            metrics.mccGraphMultiplePlausibleMCCs += 1
            switch winnerSensitive {
            case .some(true):
                metrics.mccGraphSensitiveWinnerAcrossMCCs += 1
            case .some(false):
                metrics.mccGraphStableWinnerAcrossMCCs += 1
            case .none:
                metrics.mccGraphInsufficientScoreableBranches += 1
            }
        case .mccRuntimeEvidenceEvaluated(let changedTopMCC, let changedWinner):
            metrics.mccRuntimeEvidenceEvaluations += 1
            if changedTopMCC { metrics.mccRuntimeEvidenceChangedTopMCC += 1 }
            if let changedWinner {
                metrics.mccRuntimeEvidenceWinnerComparisons += 1
                if changedWinner { metrics.mccRuntimeEvidenceChangedWinner += 1 }
            }
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
