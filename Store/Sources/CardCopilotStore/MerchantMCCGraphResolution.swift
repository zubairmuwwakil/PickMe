import Foundation
import CardCopilotEngine

/// Projects the canonical Store-side MerchantMCCGraph onto PickMe's scoreable category taxonomy.
///
/// The confidence source deliberately remains `.brandPrior`: derived reward/community evidence may
/// strengthen an editorial prior, but only a literal MCC from the owner's posted transaction earns
/// `.observedMcc`. Community rows are external evidence and therefore can never make the graph
/// `isTrusted`, which is reserved for repeated direct owner observations.
public func merchantMCCGraphPrediction(
    for merchant: NearbyPlace,
    feedbackStore: MerchantMCCRewardFeedbackStore = .shared,
    communityStore: CommunityMerchantMCCCacheStore = CommunityMerchantMCCCacheStore()
) -> CategoryPrediction? {
    guard let seed = MerchantMCCSeedCatalogue.match(merchantName: merchant.name) else { return nil }

    let query = MerchantMCCQuery(
        merchantKey: seed.merchant.name,
        placeID: merchant.placeID,
        latitude: merchant.hasMonitorableLocation ? merchant.latitude : nil,
        longitude: merchant.hasMonitorableLocation ? merchant.longitude : nil,
        channel: .inStore)
    let rewardEvidence = feedbackStore.evidence(for: merchant.name)
    let communityEvidence = communityStore.evidence()
    let seedCandidates = zip(seed.profile.candidateMccs, seed.profile.weights).map {
        MerchantMCCPriorCandidate(mcc: $0.0, weight: $0.1)
    }
    let graph = MerchantMCCGraph.predict(
        for: query,
        seedCandidates: seedCandidates,
        seedConfidence: seed.profile.confidence,
        evidence: MerchantMCCSeedCatalogue.externalEvidence(for: seed.merchant)
            + communityEvidence + rewardEvidence)

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
    let rewardObservationCount = Set(rewardEvidence.compactMap(\.sourceReference)).count
    let relevantCommunityCount = communityEvidence.filter {
        MerchantMCCQuery(merchantKey: $0.merchantKey).merchantKey == query.merchantKey
    }.count
    let categoryMargin = rankedCategories.count > 1 ? top.value - rankedCategories[1].value : top.value
    let categoryConflicted = rankedCategories.count > 1 && categoryMargin <= 0.20

    let score: Double
    if categoryConflicted {
        score = min(0.55, top.value)
    } else if rewardObservationCount >= 3, top.value >= 0.90 {
        score = min(0.97, top.value)
    } else if rewardObservationCount >= 2, top.value >= 0.80 {
        score = min(0.94, top.value)
    } else if rewardObservationCount > 0 {
        score = min(0.89, max(seed.profile.confidence, top.value * 0.90))
    } else if relevantCommunityCount > 0 {
        // Shared evidence can improve a weak bootstrap prior, but it remains deliberately below the
        // owner-learned tiers. The wire decoder already scales each row by corroboration strength.
        score = min(0.72, max(seed.profile.confidence, top.value * 0.75))
    } else {
        score = min(seed.profile.confidence, 0.60)
    }

    let state: String
    if categoryConflicted { state = "conflicted" }
    else if rewardObservationCount >= 3 { state = "strongLearned" }
    else if rewardObservationCount > 0 { state = "rewardLearned" }
    else if relevantCommunityCount > 0 { state = "communityLearned" }
    else { state = "priorOnly" }

    return CategoryPrediction(category: top.key,
                              confidenceSource: .brandPrior,
                              candidates: rankedCategories.map(\.key),
                              confidenceScore: score,
                              rawCategory: "merchantMccGraph:\(state)",
                              merchantCategoryCode: graph.bestMCC)
}
