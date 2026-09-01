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

/// Acceptance constraints knowable from the brand or merchant name.
public func knownAcceptedNetworks(for brand: String?, merchantName: String? = nil) -> Set<Network> {
    if let merchantName {
        let clean = merchantName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let match = CanadianMerchantPreIndex.all.first(where: {
            let pre = $0.name.lowercased()
            return clean == pre || clean.contains(pre) || pre.contains(clean)
        }) {
            return match.acceptedNetworks
        }
    }
    return brand == "costco" ? [.mastercard] : [.amex, .visa, .mastercard]
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
public func ambientPurchaseContext(merchant: NearbyMerchant, category: String,
                                   mcc: Int? = nil) -> PurchaseContext {
    let brand = canonicalEngineBrand(merchant.name)
    let amount = categoryAmountEstimates[category] ?? fallbackAmountEstimate
    return PurchaseContext(amountCad: amount,
                           category: category,
                           mcc: mcc,
                           merchantBrand: brand,
                           acceptedNetworks: knownAcceptedNetworks(for: brand, merchantName: merchant.name))
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

public enum CheckoutError: Error, Equatable, Sendable {
    case cannotAdvise(reasons: [String])
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

/// Re-scores an already-answered checkout at a refined amount, without asking again.
///
/// The day-to-day flow no longer collects an amount before showing an answer (2026-08-31): the
/// owner sees a category-estimate answer first and may refine it in place. A second call to
/// `CheckoutService.recommend` is the wrong tool for that refinement — it logs a second
/// `StoredPrediction` and opens a second purchase, which is exactly the duplicate-till problem
/// that design exists to avoid. This walks the same candidate categories `recommend` would and
/// calls the engine directly, mirroring its single/fork collapse rule, but touches no store.
///
/// Returns nil only if the engine cannot advise at the new amount (e.g. a cap makes every card
/// ineligible) — the caller keeps showing the prior result rather than an empty one.
public func rescoreCheckout(_ result: CheckoutResult, amountCad: Double,
                            engine: RecommendationEngine, asOf: String) -> CheckoutResult? {
    let brand = canonicalEngineBrand(result.merchant.name)
    let acceptedNetworks = knownAcceptedNetworks(for: brand, merchantName: result.merchant.name)

    func recommend(for category: String) -> Recommendation? {
        let outcome = engine.recommend(PurchaseContext(amountCad: amountCad,
                                                       category: category,
                                                       mcc: result.prediction.merchantCategoryCode,
                                                       merchantBrand: brand,
                                                       acceptedNetworks: acceptedNetworks),
                                       asOf: asOf)
        guard case .advised(let rec) = outcome else { return nil }
        return rec
    }

    let candidates = result.prediction.candidates
    let outcome: CheckoutOutcome
    if candidates.count > 1 {
        let branches = candidates.compactMap { category in
            recommend(for: category).map { CheckoutBranch(category: category, recommendation: $0) }
        }
        guard !branches.isEmpty else { return nil }
        let winners = Set(branches.map(\.recommendation.winner.cardId))
        // Same collapse rule as `recommend`: every branch agreeing makes a fork noise, not signal.
        outcome = winners.count == 1 ? .single(branches[0].recommendation) : .fork(branches)
    } else {
        guard let rec = recommend(for: result.prediction.category) else { return nil }
        outcome = .single(rec)
    }

    return CheckoutResult(merchant: result.merchant, prediction: result.prediction, outcome: outcome,
                          effectiveAmountCad: amountCad, amountWasEstimated: false,
                          categoryWasAmbiguous: result.categoryWasAmbiguous,
                          storedPredictionId: result.storedPredictionId)
}

/// The Task 5 composition layer: merchant + category prediction + amount → engine →
/// outcome, with the prediction persisted immutably as a side effect of asking.
public struct CheckoutService {
    let engine: RecommendationEngine
    let explainer: RecommendationExplainer
    public let log: PredictionLog
    private let context: ModelContext
    /// The Membership Rewards valuation in force when a prediction is logged, so an audit can
    /// tell which assumption produced it. Optional since valuations became a keyed dictionary:
    /// nil records "the owner declared none", which is the truth, rather than a zero that would
    /// read as a deliberate valuation of nothing.
    private let mrCentsPerPoint: Double?
    private let defaultCardId: String
    /// cardId -> the unit its program pays in, snapshotted onto every prediction.
    private let rewardUnitKinds: [String: String]
    /// The contract release this build ships. Loaded once: it cannot change while the process
    /// runs, and re-reading it per checkout would be a bundle read on the critical path.
    private let contractRelease: ContractRelease?
    /// The winning card has to be resolvable to freeze the rule it won on. Indexed here for the
    /// same reason `rewardUnitKinds` is: the catalogue is an init parameter, not a stored one.
    private let cardsById: [String: CardProduct]
    /// programId -> the owner's valuation for that program. Keyed by program rather than reusing
    /// `mrCentsPerPoint`, which is Membership Rewards only: freezing an MR rate against a
    /// cashback winner would record a valuation that never applied to it.
    private let programCentsPerPoint: [String: Double]

    public init(catalogue: Catalogue, ownerState: OwnerState, context: ModelContext) {
        self.engine = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)
        self.explainer = RecommendationExplainer(catalogue: catalogue)
        self.log = PredictionLog(context: context)
        self.context = context
        self.mrCentsPerPoint = ownerState.valuationsCad[points: "amexMembershipRewards"]?.centsPerPoint
        self.defaultCardId = ownerState.defaultCardId
        self.rewardUnitKinds = Dictionary(uniqueKeysWithValues:
            catalogue.cards.map { ($0.cardId, $0.program.unit) })
        // A missing stamp must not block a checkout. Provenance is a property of the record,
        // not a precondition for giving advice — an unstamped row is honest about being unstamped.
        self.contractRelease = try? SeedLoader.loadContractRelease()
        self.cardsById = Dictionary(uniqueKeysWithValues: catalogue.cards.map { ($0.cardId, $0) })
        self.programCentsPerPoint = Dictionary(
            catalogue.cards.compactMap { card -> (String, Double)? in
                guard let cpp = ownerState.valuationsCad[points: card.program.programId]?.centsPerPoint
                else { return nil }
                return (card.program.programId, cpp)
            }, uniquingKeysWith: { first, _ in first })
    }

    public func recommend(merchant: NearbyMerchant, amountCad: Double?,
                          asOf: String,
                          purchaseSource: PurchaseActivitySource = .pickMeCheckout) throws -> CheckoutResult {
        let prediction = try confirmedPrediction(forMerchantId: merchant.id)
            ?? predict(poiCategoryRaw: merchant.poiCategoryRaw, merchantName: merchant.name,
                       merchantCategoryCode: merchant.merchantCategoryCode)
        let brand = canonicalEngineBrand(merchant.name)
        let effectiveAmount = amountCad
            ?? categoryAmountEstimates[prediction.category]
            ?? fallbackAmountEstimate

        let acceptedNetworks = knownAcceptedNetworks(for: brand, merchantName: merchant.name)
        func recommend(for category: String) throws -> Recommendation {
            let outcome = engine.recommend(PurchaseContext(amountCad: effectiveAmount,
                                                           category: category,
                                                           mcc: prediction.merchantCategoryCode,
                                                           merchantBrand: brand,
                                                           acceptedNetworks: acceptedNetworks),
                                           asOf: asOf)
            switch outcome {
            case .advised(let rec):
                return rec
            case .cannotAdvise(let reasons):
                throw CheckoutError.cannotAdvise(reasons: reasons)
            }
        }

        let ambiguous = prediction.candidates.count > 1
        let outcome: CheckoutOutcome
        let primary: Recommendation
        if ambiguous {
            let branches = try prediction.candidates.map {
                CheckoutBranch(category: $0, recommendation: try recommend(for: $0))
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
            primary = try recommend(for: prediction.category)
            outcome = .single(primary)
        }

        let purchase = PurchaseContext(amountCad: effectiveAmount,
                                       category: prediction.category,
                                       mcc: prediction.merchantCategoryCode,
                                       merchantBrand: brand,
                                       acceptedNetworks: acceptedNetworks)
        let headline = explainer.explain(primary, purchase: purchase).headline
        let frozen = cardsById[primary.winner.cardId].map { card in
            ScoredRuleSnapshot.capture(score: primary.winner, card: card, asOf: asOf,
                                       programId: card.program.programId,
                                       unit: card.program.unit,
                                       centsPerPoint: programCentsPerPoint[card.program.programId])
        }
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
            contractRelease: contractRelease?.release,
            contractDigest: contractRelease?.digest,
            frozenInputs: frozen.flatMap { try? JSONEncoder().encode($0) },
            rawCategory: prediction.rawCategory,
            categoryTaxonomyVersion: prediction.taxonomyVersion,
            categoryConfidenceScore: prediction.confidenceScore,
            merchantCategoryCode: prediction.merchantCategoryCode,
            merchantGroupID: prediction.merchantGroupID,
            headline: headline))
        // Asking "which card here?" is an assertion of intent to buy, so the till record opens
        // now — otherwise the purchase would reach neither queue and the checkout could never be
        // reconciled. It opens EMPTY on purpose: the amount above is what the owner expected to
        // spend, and writing it here as the charge would rebuild the very conflation this model
        // exists to break. Both facts arrive after payment.
        try log.recordPurchase(for: stored,
                               activitySource: purchaseSource,
                               merchantKey: merchantActivityKey(name: merchant.name,
                                                                locationIdentifier: merchant.id),
                               merchantIdentifier: merchant.id,
                               merchantLatitude: merchant.latitude,
                               merchantLongitude: merchant.longitude)
        try upsertMerchant(merchant)

        return CheckoutResult(merchant: merchant, prediction: prediction, outcome: outcome,
                              effectiveAmountCad: effectiveAmount,
                              amountWasEstimated: amountCad == nil,
                              categoryWasAmbiguous: ambiguous,
                              storedPredictionId: stored.id)
    }

    /// Freezes the best-vs-used comparison once enough purchase facts exist.
    public func assessPurchase(_ purchase: StoredPurchase, evaluatedAt: Date = Date()) throws {
        guard purchase.evaluatedAt == nil,
              let usedCardId = purchase.cardUsedId,
              let amountCad = purchase.amountCad,
              let category = purchase.observation?.observedCategory
                ?? purchase.categoryAtPurchase
                ?? purchase.prediction?.predictedCategory else { return }

        let merchantName = purchase.displayMerchant
        let indexed = MerchantRecognizer.recognise(merchantName)
        let brand = indexed?.merchantBrand ?? canonicalEngineBrand(merchantName)
        let context = PurchaseContext(
            amountCad: amountCad,
            category: category,
            mcc: indexed?.mcc,
            merchantBrand: brand,
            acceptedNetworks: indexed?.acceptedNetworks
                ?? knownAcceptedNetworks(for: brand, merchantName: merchantName))
        guard case .advised(let current) = engine.recommend(
            context, asOf: evaluatedAt.formatted(.iso8601.year().month().day())) else { return }

        // Advice-bearing purchases preserve the winner the owner was actually shown. Automatic
        // captures freeze the winner from their first successful post-purchase evaluation.
        let bestCardId = purchase.prediction?.winnerCardId
            ?? purchase.bestCardId
            ?? current.winner.cardId
        let bestValue = current.allCandidates.first { $0.cardId == bestCardId }?.netValueCad
            ?? purchase.bestCardValueCad
        let usedValue = current.allCandidates.first { $0.cardId == usedCardId }?.netValueCad
        try log.recordAssessment(on: purchase, bestCardId: bestCardId,
                                 bestCardValueCad: bestValue,
                                 usedCardValueCad: usedValue,
                                 evaluatedAt: evaluatedAt)
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
            candidates: [category], confidenceScore: merchant.categoryConfidenceScore,
            rawCategory: merchant.rawCategory,
            merchantCategoryCode: merchant.merchantCategoryCode,
            merchantGroupID: merchant.merchantGroupID,
            taxonomyVersion: merchant.categoryTaxonomyVersion ?? CategoryTaxonomy.taxonomyVersion)
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

    /// Logs every synced wallet-tap that was never asked about at a live checkout, with no
    /// confirmation gate — see `AutoCaptureLog`'s doc comment for why that is safe here and is
    /// deliberately NOT how `CaptureProposal` behaves. Call after every sync that refreshes
    /// `WalletFeedback`, before re-reading `log.snapshot()`, so the newly logged purchases are
    /// reflected in the same UI update as the sync that produced them.
    @discardableResult
    public func ingestAutomaticCaptures(from feedback: [WalletFeedback]) throws -> [StoredPurchase] {
        let purchases = try AutoCaptureLog(context: context)
            .ingest(feedback: feedback, openPredictions: log.allPredictions())
        for purchase in purchases {
            try assessPurchase(purchase, evaluatedAt: purchase.createdAt)
            if let merchantKey = purchase.merchantKey {
                MerchantPatronageStore().recordVisit(merchantKey: merchantKey,
                                                     displayName: purchase.displayMerchant,
                                                     at: purchase.createdAt)
            }
        }
        return purchases
    }

    /// Applies a high-confidence MapKit resolution to an automatic Wallet capture.
    ///
    /// The capture remains prediction-free: resolving what the merchant is after payment must not
    /// fabricate advice the app never gave. Instead this fills the purchase's capture snapshot,
    /// attaches the exact POI identity, and saves the POI for future name-only captures.
    public func enrichAutomaticPurchase(_ purchase: StoredPurchase,
                                        with resolution: WalletMerchantResolution) throws {
        guard purchase.isAutoLogged, purchase.displayCategory == nil else { return }
        let prediction = resolution.prediction
        guard prediction.confidenceSource != .fallback,
              prediction.category != "other",
              prediction.candidates.count == 1 else { return }

        let merchant = resolution.merchant
        purchase.merchantIdentifier = merchant.id
        purchase.merchantLatitude = merchant.latitude
        purchase.merchantLongitude = merchant.longitude
        purchase.merchantKey = merchantActivityKey(name: purchase.displayMerchant,
                                                   locationIdentifier: merchant.id)
        purchase.categoryAtPurchase = prediction.category
        purchase.categoryConfidenceRaw = prediction.confidenceSource.rawValue
        purchase.rawCategoryAtPurchase = prediction.rawCategory
        purchase.categoryTaxonomyVersion = prediction.taxonomyVersion
        purchase.categoryConfidenceScore = prediction.confidenceScore
        purchase.merchantCategoryCode = prediction.merchantCategoryCode
        purchase.merchantGroupID = prediction.merchantGroupID

        // Retain the Wallet descriptor as the display name so a later name-only capture can join
        // the learned POI even when the descriptor carries a city or processor suffix.
        try upsertMerchant(NearbyMerchant(
            id: merchant.id,
            name: purchase.displayMerchant,
            poiCategoryRaw: merchant.poiCategoryRaw,
            merchantCategoryCode: merchant.merchantCategoryCode,
            latitude: merchant.latitude,
            longitude: merchant.longitude,
            distanceMeters: merchant.distanceMeters))
        try assessPurchase(purchase, evaluatedAt: purchase.createdAt)
    }

    /// Purchases logged automatically from a Wallet capture with no live checkout behind them —
    /// the "Logged Automatically" section of Activity, distinct from `PredictionLog.recentPurchases`
    /// because these carry no predicted category to grade.
    public func autoLoggedPurchases(limit: Int = 20) throws -> [StoredPurchase] {
        try AutoCaptureLog(context: context).recent(limit: limit)
    }

    private func upsertMerchant(_ merchant: NearbyMerchant) throws {
        let id = merchant.id
        let existing = try context.fetch(FetchDescriptor<StoredMerchant>(
            predicate: #Predicate { $0.identifier == id }))
        if let found = existing.first {
            found.lastSeenAt = Date()
            found.poiCategoryRaw = merchant.poiCategoryRaw
            found.rawCategory = merchant.poiCategoryRaw
            found.merchantCategoryCode = merchant.merchantCategoryCode
        } else {
            context.insert(StoredMerchant(name: merchant.name, identifier: merchant.id,
                                          poiCategoryRaw: merchant.poiCategoryRaw,
                                          latitude: merchant.latitude,
                                          longitude: merchant.longitude,
                                          merchantCategoryCode: merchant.merchantCategoryCode))
        }
        try context.save()
    }
}
