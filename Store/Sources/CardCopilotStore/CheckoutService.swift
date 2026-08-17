import Foundation
import SwiftData
import CardCopilotEngine

/// Engine brand tokens derivable from a raw merchant name. The engine's merchant predicates
/// match exact tokens ("costco", "walmart", "canadian-tire"), so POI display names must be
/// canonicalized before scoring. Unknown names return nil — a predicate that cannot be
/// certain of the brand must not fire.
public func canonicalEngineBrand(_ merchantName: String) -> String? {
    let n = merchantName.lowercased()
    if n.contains("costco") { return "costco" }
    if n.contains("walmart") { return "walmart" }
    if n.contains("canadian tire") { return "canadian-tire" }
    if n.contains("marriott") { return "marriott" }
    if n.contains("loblaws") { return "loblaws" }
    if n.contains("netflix") { return "netflix" }
    return nil
}

/// Acceptance constraints knowable from the brand alone. Kept deliberately tiny: Costco's
/// Mastercard-only policy is Canada-wide and issuer-verified; everything else defaults to
/// all networks until owner observations say otherwise.
func knownAcceptedNetworks(for brand: String?) -> Set<Network> {
    brand == "costco" ? [.mastercard] : [.amex, .visa, .mastercard]
}

/// Default purchase amounts by category, used only when the owner skips amount capture.
/// Estimates make the recommendation renderable; they are never stored as evidence.
let categoryAmountEstimates: [String: Double] = [
    "grocery": 60, "dining": 35, "gasStation": 55, "drugStore": 25,
    "streaming": 15, "ctFamily": 80, "wholesaleClub": 150, "marriottDirect": 250,
]
let fallbackAmountEstimate: Double = 50

/// Builds the same on-device scoring context used by checkout when no amount has been entered.
/// Ambient delivery uses a clearly bounded category estimate only to decide whether to stay
/// silent; it never persists that estimate as a purchase observation.
public func ambientPurchaseContext(merchant: NearbyMerchant, category: String) -> PurchaseContext {
    let brand = canonicalEngineBrand(merchant.name)
    let amount = categoryAmountEstimates[category] ?? fallbackAmountEstimate
    return PurchaseContext(amountCad: amount,
                           category: category,
                           merchantBrand: brand,
                           acceptedNetworks: knownAcceptedNetworks(for: brand))
}

/// One branch of a fork: what the engine says IF the merchant codes as this category.
public struct CheckoutBranch: Sendable {
    public let category: String
    public let recommendation: Recommendation
}

public enum CheckoutOutcome: Sendable {
    case single(Recommendation)
    case fork([CheckoutBranch])
}

public struct CheckoutResult: Sendable {
    public let merchant: NearbyMerchant
    public let prediction: CategoryPrediction
    public let outcome: CheckoutOutcome
    public let effectiveAmountCad: Double
    public let amountWasEstimated: Bool
    /// True whenever the mapper offered multiple candidates, even if the fork collapsed
    /// because every branch agreed — reconcile still needs to know the category was a guess.
    public let categoryWasAmbiguous: Bool
    public let storedPredictionId: UUID
}

/// The Task 5 composition layer: merchant + category prediction + amount → engine →
/// outcome, with the prediction persisted immutably as a side effect of asking.
public struct CheckoutService {
    let engine: RecommendationEngine
    let explainer: RecommendationExplainer
    public let log: PredictionLog
    private let context: ModelContext
    private let mrCentsPerPoint: Double
    private let defaultCardId: String
    /// cardId -> the unit its program pays in, snapshotted onto every prediction.
    private let rewardUnitKinds: [String: String]

    public init(catalogue: Catalogue, ownerState: OwnerState, context: ModelContext) {
        self.engine = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)
        self.explainer = RecommendationExplainer(catalogue: catalogue)
        self.log = PredictionLog(context: context)
        self.context = context
        self.mrCentsPerPoint = ownerState.valuationsCad.amexMembershipRewards.centsPerPoint
        self.defaultCardId = ownerState.defaultCardId
        self.rewardUnitKinds = Dictionary(uniqueKeysWithValues:
            catalogue.cards.map { ($0.cardId, $0.program.unit) })
    }

    public func recommend(merchant: NearbyMerchant, amountCad: Double?,
                          asOf: String) throws -> CheckoutResult {
        let prediction = try confirmedPrediction(forMerchantId: merchant.id)
            ?? predict(poiCategoryRaw: merchant.poiCategoryRaw, merchantName: merchant.name)
        let brand = canonicalEngineBrand(merchant.name)
        let effectiveAmount = amountCad
            ?? categoryAmountEstimates[prediction.category]
            ?? fallbackAmountEstimate

        func recommend(for category: String) -> Recommendation {
            engine.recommend(PurchaseContext(amountCad: effectiveAmount,
                                             category: category,
                                             merchantBrand: brand,
                                             acceptedNetworks: knownAcceptedNetworks(for: brand)),
                             asOf: asOf)
        }

        let ambiguous = prediction.candidates.count > 1
        let outcome: CheckoutOutcome
        let primary: Recommendation
        if ambiguous {
            let branches = prediction.candidates.map {
                CheckoutBranch(category: $0, recommendation: recommend(for: $0))
            }
            let winners = Set(branches.map(\.recommendation.winner.cardId))
            if winners.count == 1 {
                // Every branch agrees — a fork would be noise. The ambiguity flag survives.
                primary = branches[0].recommendation
                outcome = .single(primary)
            } else {
                primary = branches[0].recommendation
                outcome = .fork(branches)
            }
        } else {
            primary = recommend(for: prediction.category)
            outcome = .single(primary)
        }

        let purchase = PurchaseContext(amountCad: effectiveAmount,
                                       category: prediction.category,
                                       merchantBrand: brand,
                                       acceptedNetworks: knownAcceptedNetworks(for: brand))
        let headline = explainer.explain(primary, purchase: purchase).headline
        let stored = try log.record(StoredPrediction(
            merchantName: merchant.name,
            merchantIdentifier: merchant.id,
            predictedCategory: prediction.category,
            confidenceSource: prediction.confidenceSource,
            winnerCardId: primary.winner.cardId,
            winnerValueCad: primary.winner.netValueCad,
            predictedRewardUnits: primary.winner.rewardUnits,
            predictedRewardUnitKind: rewardUnitKinds[primary.winner.cardId],
            defaultCardValueCad: defaultCardValueCad(for: primary),
            winnerRuleId: primary.winner.appliedRuleId,
            runnerUpCardId: primary.runnerUp?.cardId,
            runnerUpValueCad: primary.runnerUp?.netValueCad,
            scoredAmountCad: amountCad,
            valuationCentsPerPoint: mrCentsPerPoint,
            headline: headline))
        // Asking "which card here?" is an assertion of intent to buy, so the till record opens
        // now — otherwise the purchase would reach neither queue and the checkout could never be
        // reconciled. It opens EMPTY on purpose: the amount above is what the owner expected to
        // spend, and writing it here as the charge would rebuild the very conflation this model
        // exists to break. Both facts arrive after payment.
        try log.recordPurchase(for: stored)
        try upsertMerchant(merchant)

        return CheckoutResult(merchant: merchant, prediction: prediction, outcome: outcome,
                              effectiveAmountCad: effectiveAmount,
                              amountWasEstimated: amountCad == nil,
                              categoryWasAmbiguous: ambiguous,
                              storedPredictionId: stored.id)
    }

    /// Rungs 1 and 2 of the prediction ladder (design §6). An owner-reconciled result for THIS
    /// exact terminal outranks every brand prior and POI guess, and leaves a single candidate —
    /// which is what collapses the fork and makes the fork view's promise ("next time the answer
    /// is instant") literally true.
    private func confirmedPrediction(forMerchantId id: String) throws -> CategoryPrediction? {
        let matches = try context.fetch(FetchDescriptor<StoredMerchant>(
            predicate: #Predicate { $0.identifier == id }))
        guard let merchant = matches.first,
              let category = merchant.confirmedCategory else { return nil }
        return CategoryPrediction(
            category: category,
            confidenceSource: merchant.confirmationCount >= 2 ? .repeatedTerminal
                                                              : .ownerConfirmedTerminal,
            candidates: [category])
    }

    private func defaultCardValueCad(for recommendation: Recommendation) -> Double? {
        if recommendation.defaultNotAccepted {
            // Value recovered is defined against the card the owner could otherwise tap.
            // When the habitual default is not accepted, that baseline is ambiguous, so
            // decision #7 uses the engine's zero advantage-over-default semantics.
            return recommendation.winner.netValueCad
        }
        if let advantage = recommendation.advantageOverDefaultCad {
            return recommendation.winner.netValueCad - advantage
        }
        return recommendation.allCandidates.first { $0.cardId == defaultCardId }?.netValueCad
    }

    public func knownMerchants() throws -> [StoredMerchant] {
        try context.fetch(FetchDescriptor<StoredMerchant>(
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)]))
    }

    private func upsertMerchant(_ merchant: NearbyMerchant) throws {
        let id = merchant.id
        let existing = try context.fetch(FetchDescriptor<StoredMerchant>(
            predicate: #Predicate { $0.identifier == id }))
        if let found = existing.first {
            found.lastSeenAt = Date()
            found.poiCategoryRaw = merchant.poiCategoryRaw
        } else {
            context.insert(StoredMerchant(name: merchant.name, identifier: merchant.id,
                                          poiCategoryRaw: merchant.poiCategoryRaw,
                                          latitude: merchant.latitude,
                                          longitude: merchant.longitude))
        }
        try context.save()
    }
}
