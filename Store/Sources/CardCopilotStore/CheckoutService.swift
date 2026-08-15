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

    public init(catalogue: Catalogue, ownerState: OwnerState, context: ModelContext) {
        self.engine = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)
        self.explainer = RecommendationExplainer(catalogue: catalogue)
        self.log = PredictionLog(context: context)
        self.context = context
        self.mrCentsPerPoint = ownerState.valuationsCad.amexMembershipRewards.centsPerPoint
    }

    public func recommend(merchant: NearbyMerchant, amountCad: Double?,
                          asOf: String) throws -> CheckoutResult {
        let prediction = predict(poiCategoryRaw: merchant.poiCategoryRaw,
                                 merchantName: merchant.name)
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
            winnerRuleId: primary.winner.appliedRuleId,
            runnerUpCardId: primary.runnerUp?.cardId,
            runnerUpValueCad: primary.runnerUp?.netValueCad,
            amountCad: amountCad,
            valuationCentsPerPoint: mrCentsPerPoint,
            headline: headline))
        try upsertMerchant(merchant)

        return CheckoutResult(merchant: merchant, prediction: prediction, outcome: outcome,
                              effectiveAmountCad: effectiveAmount,
                              amountWasEstimated: amountCad == nil,
                              categoryWasAmbiguous: ambiguous,
                              storedPredictionId: stored.id)
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
        } else {
            context.insert(StoredMerchant(name: merchant.name, identifier: merchant.id,
                                          latitude: merchant.latitude,
                                          longitude: merchant.longitude))
        }
        try context.save()
    }
}
