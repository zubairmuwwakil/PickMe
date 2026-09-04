import Foundation
import CardCopilotEngine

/// Projects the MCC posterior onto PickMe's scoreable purchase-category taxonomy.
///
/// The confidence source deliberately remains `.brandPrior`: graph evidence is stronger than an
/// editorial seed as it accumulates, but it is still not the same claim as `.observedMcc`, which is
/// reserved for an MCC actually read from the owner's posted transaction/network source.
public func merchantMCCGraphPrediction(for merchant: NearbyPlace,
                                       learningStore: MerchantMCCLearningStore = .shared)
-> CategoryPrediction? {
    guard let seed = learningStore.seedMerchant(matching: merchant.name),
          let posterior = learningStore.posterior(
            merchantName: merchant.name,
            locationKey: MerchantMCCLearningStore.locationKey(for: merchant)) else { return nil }

    var categoryProbability: [String: Double] = [:]
    for candidate in posterior.candidates {
        guard let category = MerchantMCCRewardFeedback.inferredCategory(for: candidate.mcc) else { continue }
        categoryProbability[category, default: 0] += candidate.probability
    }
    guard !categoryProbability.isEmpty else { return nil }

    let rankedCategories = categoryProbability.sorted {
        if $0.value == $1.value { return $0.key < $1.key }
        return $0.value > $1.value
    }
    guard let top = rankedCategories.first else { return nil }

    let score: Double
    switch posterior.state {
    case .strongLearned, .locationLearned:
        score = posterior.confidence
    case .conflicted:
        score = min(0.55, posterior.confidence)
    case .priorOnly:
        // A prior-only single-candidate distribution normalizes to 1.0, which does NOT make the
        // underlying evidence certain. Use the seed's external/editorial confidence until real
        // feedback arrives; once it does, let that evidence improve the score without crossing the
        // strong-learned band prematurely.
        score = posterior.evidenceCount == 0
            ? min(seed.confidence, 0.60)
            : min(0.89, max(seed.confidence, posterior.confidence * 0.90))
    }

    return CategoryPrediction(category: top.key,
                              confidenceSource: .brandPrior,
                              candidates: rankedCategories.map(\.key),
                              confidenceScore: score,
                              rawCategory: "merchantMccGraph:\(posterior.state.rawValue)",
                              merchantCategoryCode: posterior.topMcc)
}
