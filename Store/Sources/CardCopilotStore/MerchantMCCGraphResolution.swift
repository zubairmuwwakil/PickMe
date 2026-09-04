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
/// The confidence source deliberately remains `.brandPrior`: imported literal MCC rows are strong
/// owner evidence but, until a safe local purchase/location join exists, they are brand-level and
/// cannot claim `.observedMcc` terminal truth. Community rows are external evidence and therefore
/// can never make the graph `isTrusted`, which is reserved for repeated location-anchored direct
/// owner observations.
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

    let score: Double
    if categoryConflicted {
        score = min(0.55, top.value)
    } else if snapshot.rewardObservationCount >= 3, top.value >= 0.90 {
        score = min(0.97, top.value)
    } else if snapshot.rewardObservationCount >= 2, top.value >= 0.80 {
        score = min(0.94, top.value)
    } else if snapshot.importedObservationCount >= 2, top.value >= 0.85 {
        // Exact owner MCC evidence is stronger than reward/category inference, but an issuer export
        // with no trusted store-location join must remain below terminal/location verification.
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
    else if snapshot.rewardObservationCount >= 3 { state = "strongLearned" }
    else if snapshot.importedObservationCount > 0 { state = "ownerImportedExact" }
    else if snapshot.rewardObservationCount > 0 { state = "rewardLearned" }
    else if snapshot.relevantCommunityCount > 0 { state = "communityLearned" }
    else { state = "priorOnly" }

    return CategoryPrediction(category: top.key,
                              confidenceSource: .brandPrior,
                              candidates: rankedCategories.map(\.key),
                              confidenceScore: score,
                              rawCategory: "merchantMccGraph:\(state)",
                              merchantCategoryCode: graph.bestMCC)
}
