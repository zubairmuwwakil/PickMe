import Foundation
import CardCopilotEngine

/// The two posteriors needed to answer whether runtime learning is actually helping checkout.
///
/// `baseline` is the shipped weighted seed plus static researched/location evidence. `graph` adds
/// volatile runtime evidence (owner reward outcomes + imported owner MCCs + community aggregates).
/// Keeping both here prevents analytics callers from rebuilding the graph with subtly different
/// evidence semantics. Nothing in this value is persisted by the metrics layer.
struct MerchantMCCGraphRuntimeSnapshot {
    let baseline: MerchantMCCPrediction
    let graph: MerchantMCCPrediction
    let seedConfidence: Double
    let rewardObservationCount: Int
    let importedObservationCount: Int
    let relevantCommunityCount: Int

    /// Kept explicit instead of relying on the synthesized memberwise initializer so adding an
    /// evidence source does not break decision-quality fixtures that construct snapshots directly.
    /// Callers predating issuer-file imports naturally mean zero imported observations.
    init(baseline: MerchantMCCPrediction,
         graph: MerchantMCCPrediction,
         seedConfidence: Double,
         rewardObservationCount: Int,
         importedObservationCount: Int = 0,
         relevantCommunityCount: Int) {
        self.baseline = baseline
        self.graph = graph
        self.seedConfidence = seedConfidence
        self.rewardObservationCount = rewardObservationCount
        self.importedObservationCount = importedObservationCount
        self.relevantCommunityCount = relevantCommunityCount
    }

    var hasRuntimeEvidence: Bool {
        rewardObservationCount > 0 || importedObservationCount > 0 || relevantCommunityCount > 0
    }
}

/// Builds the canonical Store-side MCC posterior once, with a seed/static baseline beside it.
/// Checkout, Purchase Routes and decision-quality measurement must share these evidence semantics.
func merchantMCCGraphRuntimeSnapshot(
    for merchant: NearbyPlace,
    feedbackStore: MerchantMCCRewardFeedbackStore = .shared,
    importedStore: MerchantMCCImportedEvidenceStore = .shared,
    communityStore: CommunityMerchantMCCCacheStore = CommunityMerchantMCCCacheStore()
) -> MerchantMCCGraphRuntimeSnapshot? {
    guard let seed = MerchantMCCSeedCatalogue.match(merchantName: merchant.name) else { return nil }

    let query = MerchantMCCQuery(
        merchantKey: seed.merchant.name,
        placeID: merchant.placeID,
        latitude: merchant.hasMonitorableLocation ? merchant.latitude : nil,
        longitude: merchant.hasMonitorableLocation ? merchant.longitude : nil,
        channel: .inStore)
    let rewardEvidence = feedbackStore.evidence(for: merchant.name)
    let importedEvidence = importedStore.evidence(for: merchant.name)
    let communityEvidence = communityStore.evidence()
    let staticEvidence = MerchantMCCSeedCatalogue.externalEvidence(for: seed.merchant)
    let seedCandidates = zip(seed.profile.candidateMccs, seed.profile.weights).map {
        MerchantMCCPriorCandidate(mcc: $0.0, weight: $0.1)
    }

    let baseline = MerchantMCCGraph.predict(
        for: query,
        seedCandidates: seedCandidates,
        seedConfidence: seed.profile.confidence,
        evidence: staticEvidence)
    let graph = MerchantMCCGraph.predict(
        for: query,
        seedCandidates: seedCandidates,
        seedConfidence: seed.profile.confidence,
        evidence: staticEvidence + communityEvidence + rewardEvidence + importedEvidence)

    let rewardObservationCount = Set(rewardEvidence.compactMap(\.sourceReference)).count
    let importedObservationCount = Set(importedEvidence.compactMap(\.sourceReference)).count
    let relevantCommunityCount = communityEvidence.filter {
        MerchantMCCQuery(merchantKey: $0.merchantKey).merchantKey == query.merchantKey
    }.count

    return MerchantMCCGraphRuntimeSnapshot(
        baseline: baseline,
        graph: graph,
        seedConfidence: seed.profile.confidence,
        rewardObservationCount: rewardObservationCount,
        importedObservationCount: importedObservationCount,
        relevantCommunityCount: relevantCommunityCount)
}

/// Projects the canonical Store-side MerchantMCCGraph onto PickMe's scoreable category taxonomy.
///
/// Unlocated issuer-file MCC rows remain `.brandPrior`: a literal MCC without a trustworthy store
/// join is strong brand evidence, not terminal truth. A safely joined issuer row is persisted as
/// location-anchored `directOwnerMcc`; when that direct evidence wins at the queried location, the
/// projection may therefore use `.observedMcc`. Community evidence can never create that state.
///
/// `metrics` remains aggregate-only and on device. It records whether runtime evidence moved the
/// top MCC, never which merchant/MCC/category caused the move.
public func merchantMCCGraphPrediction(
    for merchant: NearbyPlace,
    feedbackStore: MerchantMCCRewardFeedbackStore = .shared,
    importedStore: MerchantMCCImportedEvidenceStore = .shared,
    communityStore: CommunityMerchantMCCCacheStore = CommunityMerchantMCCCacheStore(),
    metrics: CategoryResolutionMetricsStore = CategoryResolutionMetricsStore()
) -> CategoryPrediction? {
    guard let snapshot = merchantMCCGraphRuntimeSnapshot(
        for: merchant, feedbackStore: feedbackStore, importedStore: importedStore,
        communityStore: communityStore)
    else { return nil }

    if snapshot.hasRuntimeEvidence {
        metrics.record(.mccRuntimeEvidenceEvaluated(
            changedTopMCC: snapshot.baseline.bestMCC != snapshot.graph.bestMCC,
            changedWinner: nil))
    }

    let graph = snapshot.graph
    var categoryProbability: [String: Double] = [:]
    for candidate in graph.candidates {
        guard let category = MerchantMCCRewardFeedback.inferredCategory(for: candidate.mcc) else { continue }
        categoryProbability[category, default: 0] += candidate.share
    }
    guard !categoryProbability.isEmpty else { return nil }

    let rankedCategories = categoryProbability.sorted {
        if $0.value == $1.value { return $0.key < $1.key }
        return $0.value > $1.value
    }
    guard let top = rankedCategories.first else { return nil }

    // One grocery answer is deliberately represented as several fractional MCC candidates. Count
    // independent purchase fingerprints, not evidence rows, so one answer cannot look like six.
    let categoryMargin = rankedCategories.count > 1 ? top.value - rankedCategories[1].value : top.value
    let categoryConflicted = rankedCategories.count > 1 && categoryMargin <= 0.20
    let hasObservedLocationMCC = graph.isObserved && !categoryConflicted

    let score: Double
    if categoryConflicted {
        score = min(0.55, top.value)
    } else if hasObservedLocationMCC {
        // The literal MCC came from owner-controlled evidence and was safely anchored to this
        // location. Match CategoryMapper's observed-MCC floor while retaining stronger graph
        // confidence when repeated corroboration earns it.
        score = min(0.97, max(ConfidenceSource.observedMcc.defaultScore, graph.confidence))
    } else if snapshot.rewardObservationCount >= 3, top.value >= 0.90 {
        score = min(0.97, top.value)
    } else if snapshot.rewardObservationCount >= 2, top.value >= 0.80 {
        score = min(0.94, top.value)
    } else if snapshot.importedObservationCount >= 2, top.value >= 0.85 {
        // Exact but unlocated owner MCC evidence is stronger than reward/category inference while
        // remaining below terminal/location verification.
        score = min(0.92, max(snapshot.seedConfidence, top.value * 0.95))
    } else if snapshot.importedObservationCount > 0 {
        score = min(0.88, max(snapshot.seedConfidence, top.value * 0.92))
    } else if snapshot.rewardObservationCount > 0 {
        score = min(0.89, max(snapshot.seedConfidence, top.value * 0.90))
    } else if snapshot.relevantCommunityCount > 0 {
        // Shared evidence can improve a weak bootstrap prior, but it remains deliberately below the
        // owner-learned tiers. The wire decoder already scales each row by corroboration strength.
        score = min(0.72, max(snapshot.seedConfidence, top.value * 0.75))
    } else {
        score = min(snapshot.seedConfidence, 0.60)
    }

    let state: String
    if categoryConflicted { state = "conflicted" }
    else if hasObservedLocationMCC { state = "ownerLocatedExact" }
    else if snapshot.rewardObservationCount >= 3 { state = "strongLearned" }
    else if snapshot.importedObservationCount > 0 { state = "ownerImportedExact" }
    else if snapshot.rewardObservationCount > 0 { state = "rewardLearned" }
    else if snapshot.relevantCommunityCount > 0 { state = "communityLearned" }
    else { state = "priorOnly" }

    return CategoryPrediction(category: top.key,
                              confidenceSource: hasObservedLocationMCC ? .observedMcc : .brandPrior,
                              candidates: rankedCategories.map(\.key),
                              confidenceScore: score,
                              rawCategory: "merchantMccGraph:\(state)",
                              merchantCategoryCode: graph.bestMCC)
}
