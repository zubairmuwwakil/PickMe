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

    // Exact-MCC ambiguity is not necessarily category ambiguity. A grocery outcome deliberately
    // spreads one vote across 5411/5422/5441/etc.; those candidates should reinforce grocery
    // together rather than make the category look conflicted merely because no exact MCC wins.
    let categoryMargin = rankedCategories.count > 1 ? top.value - rankedCategories[1].value : top.value
    let categoryConflicted = rankedCategories.count > 1 && categoryMargin <= 0.20

    let score: Double
    if posterior.evidenceCount == 0 {
        score = min(seed.confidence, 0.60)
    } else if categoryConflicted {
        score = min(0.55, top.value)
    } else if posterior.evidenceCount >= 3, top.value >= 0.90 {
        score = min(0.97, top.value)
    } else if posterior.evidenceCount >= 2, top.value >= 0.80 {
        score = min(0.94, top.value)
    } else {
        // One low-friction reward outcome may improve a seed, but it cannot jump directly into the
        // repeated/strong band. Additional independent purchases are what earn that promotion.
        score = min(0.89, max(seed.confidence, top.value * 0.90))
    }

    return CategoryPrediction(category: top.key,
                              confidenceSource: .brandPrior,
                              candidates: rankedCategories.map(\.key),
                              confidenceScore: score,
                              rawCategory: "merchantMccGraph:\(posterior.state.rawValue)",
                              merchantCategoryCode: posterior.topMcc)
}
