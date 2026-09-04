import Foundation
import CardCopilotEngine

/// Projects the canonical Store-side MerchantMCCGraph onto PickMe's scoreable category taxonomy.
///
/// The confidence source deliberately remains `.brandPrior`: derived reward evidence may strengthen
/// an editorial prior, but only a literal MCC from a posted transaction earns `.observedMcc`.
public func merchantMCCGraphPrediction(
    for merchant: NearbyPlace,
    feedbackStore: MerchantMCCRewardFeedbackStore = .shared
) -> CategoryPrediction? {
    guard let seed = MerchantMCCSeedCatalogue.match(merchantName: merchant.name) else { return nil }

    let query = MerchantMCCQuery(
        merchantKey: seed.merchant.name,
        placeID: merchant.placeID,
        latitude: merchant.hasMonitorableLocation ? merchant.latitude : nil,
        longitude: merchant.hasMonitorableLocation ? merchant.longitude : nil,
        channel: .inStore)
    let rewardEvidence = feedbackStore.evidence(for: merchant.name)
    let graph = MerchantMCCGraph.predict(
        for: query,
        seedMCC: seed.profile.primaryMcc,
        evidence: MerchantMCCSeedCatalogue.externalEvidence(for: seed.merchant) + rewardEvidence)

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
    let categoryMargin = rankedCategories.count > 1 ? top.value - rankedCategories[1].value : top.value
    let categoryConflicted = rankedCategories.count > 1 && categoryMargin <= 0.20

    let score: Double
    if rewardObservationCount == 0 {
        score = min(seed.profile.confidence, 0.60)
    } else if categoryConflicted {
        score = min(0.55, top.value)
    } else if rewardObservationCount >= 3, top.value >= 0.90 {
        score = min(0.97, top.value)
    } else if rewardObservationCount >= 2, top.value >= 0.80 {
        score = min(0.94, top.value)
    } else {
        score = min(0.89, max(seed.profile.confidence, top.value * 0.90))
    }

    let state: String
    if categoryConflicted { state = "conflicted" }
    else if rewardObservationCount >= 3 { state = "strongLearned" }
    else if rewardObservationCount > 0 { state = "rewardLearned" }
    else { state = "priorOnly" }

    return CategoryPrediction(category: top.key,
                              confidenceSource: .brandPrior,
                              candidates: rankedCategories.map(\.key),
                              confidenceScore: score,
                              rawCategory: "merchantMccGraph:\(state)",
                              merchantCategoryCode: graph.bestMCC)
}
