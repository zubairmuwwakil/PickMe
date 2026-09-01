import Foundation
import SwiftData
import CardCopilotEngine

/// Whether a confirmed row can be — and was — checked against the catalogue math.
public enum ArithmeticVerdict: Equatable, Sendable {
    /// Not enough evidence to judge, or judging it would measure something other than the
    /// catalogue. Counted on neither side of the ratio.
    case notEligible
    case matches
    case mismatch
}

/// How far a posted reward may sit from the predicted one before it counts as a math error.
///
/// Points post as whole units — an engine figure of 46.47 posts as 46 — so a points row gets
/// 1.0 unit of slack. Cash back and CT Money post to the cent and their "units" ARE dollars,
/// where that same slack would wave through a dollar of error on a two-dollar reward. An
/// unrecorded unit kind takes the strict tolerance on purpose: a false miss shows up on the
/// dashboard and gets reviewed, a false pass never does.
func rewardUnitTolerance(_ unitKind: String?) -> Double {
    unitKind == "point" ? 1.0 : 0.01
}

extension StoredPrediction {
    /// ELIGIBILITY RULE for the arithmetic bar (design §3, metric #2). A confirmed row enters
    /// the check ONLY when all four hold:
    ///
    /// 1. The category was right — `observedCategory == predictedCategory`. Deliberately NOT
    ///    "carries no miss class": a `capExceeded` row has the right category and the wrong
    ///    math, which is precisely the failure this metric exists to catch.
    /// 2. `purchase.amountCad != nil` — a real charge, not a category estimate and not the
    ///    preset the owner tapped before paying. Units predicted from a guessed basket cannot
    ///    meaningfully disagree with a statement.
    /// 3. The card tapped is the card recommended — now read from the purchase, where the till
    ///    fact belongs. The predicted units belong to the winner; another card's posting is a
    ///    different sum, not a catalogue error.
    /// 4. Both reward-unit figures exist. Missing means unknown, never assumed-correct — rows
    ///    predating the fields drop out instead of inflating the numerator.
    ///
    /// The comparison uses THIS prediction's snapshotted units. Re-running today's engine
    /// against an old row would measure today's catalogue and today's valuation, not the advice
    /// that was actually given — which is the entire reason the snapshot exists.
    public var arithmeticVerdict: ArithmeticVerdict {
        guard let purchase, let observation = purchase.observation,
              observation.observedCategory == predictedCategory,
              purchase.cardUsedId == winnerCardId,
              // The *actual* charge, not the pre-purchase estimate: reward units predicted from
              // a preset button cannot meaningfully disagree with a statement.
              purchase.amountCad != nil,
              let predicted = predictedRewardUnits,
              let observed = observation.observedRewardUnits else { return .notEligible }
        let tolerance = rewardUnitTolerance(predictedRewardUnitKind)
        // 1e-9 absorbs binary-floating-point noise (2.00 - 1.99 is not exactly 0.01), not
        // reward error.
        return abs(predicted - observed) <= tolerance + 1e-9 ? .matches : .mismatch
    }
}

/// The two numbers the personal MVP exists to measure, plus the reconcile queue that feeds them.
public struct ExperimentMetrics: Equatable, Sendable {
    public let confirmedCount: Int
    public let categoryCorrectCount: Int
    public let missBreakdown: [MissClass: Int]
    public let targetCheckouts: Int
    /// Confirmed rows that cleared the eligibility rule above — the arithmetic denominator.
    public let arithmeticEligibleCount: Int
    public let arithmeticCorrectCount: Int

    /// No evidence at all — what the app shows before it has read the store. Deliberately the
    /// only ExperimentMetrics value constructible from outside this module: metrics are
    /// something the log computes, never something a caller can assert.
    public static let empty = ExperimentMetrics(confirmedCount: 0, categoryCorrectCount: 0,
                                                missBreakdown: [:],
                                                targetCheckouts: PredictionLog.targetCheckouts,
                                                arithmeticEligibleCount: 0,
                                                arithmeticCorrectCount: 0)

    /// Nil rather than zero when there is no evidence — an unmeasured experiment is not a
    /// failing one, and a dashboard showing "0%" on day one would be a lie.
    public var categoryAccuracy: Double? {
        confirmedCount > 0 ? Double(categoryCorrectCount) / Double(confirmedCount) : nil
    }

    /// Nil when no confirmed row could be checked. A dashboard that printed "0%" here would be
    /// reporting a failure the evidence does not support.
    public var arithmeticCorrectRate: Double? {
        arithmeticEligibleCount > 0
            ? Double(arithmeticCorrectCount) / Double(arithmeticEligibleCount) : nil
    }

    public var progressToTarget: Int { confirmedCount }
    public var meetsCategoryBar: Bool? { categoryAccuracy.map { $0 >= 0.85 } }
    /// The bar is 100%: one row of wrong catalogue math fails the metric (design §3).
    public var meetsArithmeticBar: Bool? { arithmeticCorrectRate.map { $0 == 1.0 } }
}

/// Append-only store for predictions and their later confirmations.
///
/// The API deliberately offers no way to edit a prediction. `confirm` attaches an
/// observation instead, so the record of what the app said survives being wrong.
public struct PredictionLog {
    public static let targetCheckouts = 30

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func record(_ prediction: StoredPrediction) throws -> StoredPrediction {
        context.insert(prediction)
        try context.save()
        return prediction
    }

    /// Creates the till record for a prediction, or returns the one already there.
    ///
    /// Get-or-create rather than insert: the same purchase can be reached from a notification
    /// action, from the app, and from reconcile. A second call must never orphan the first
    /// record — that would silently discard a card the owner already told us about.
    ///
    /// `walletEventId`, when the caller is saving a `CaptureProposal`'s facts, stamps which
    /// Wallet-captured event supplied them. This is NOT what makes the purchase "auto-logged" —
    /// `StoredPurchase.isAutoLogged` is `prediction == nil`, and this purchase plainly has one — it
    /// is what keeps `AutoCaptureLog` from later mistaking the SAME tap for an orphaned one once
    /// this checkout completes and its prediction drops out of the open set. Set once: a purchase
    /// answered by two different captures across two syncs keeps the first, since the dedup key
    /// only needs to name ONE representative event, not enumerate every one that ever touched it.
    @discardableResult
    public func recordPurchase(for prediction: StoredPrediction,
                               cardUsedId: String? = nil, cardSource: CaptureSource? = nil,
                               walletEventId: String? = nil,
                               activitySource: PurchaseActivitySource = .pickMeCheckout,
                               merchantKey: String? = nil,
                               merchantIdentifier: String? = nil,
                               merchantLatitude: Double? = nil,
                               merchantLongitude: Double? = nil,
                               at date: Date = Date()) throws -> StoredPurchase {
        let purchase: StoredPurchase
        if let existing = prediction.purchase {
            purchase = existing
        } else {
            purchase = StoredPurchase(
                createdAt: date,
                merchantLabel: prediction.merchantName,
                activitySource: activitySource,
                merchantKey: merchantKey
                    ?? merchantActivityKey(name: prediction.merchantName,
                                           locationIdentifier: merchantIdentifier
                                            ?? prediction.merchantIdentifier),
                merchantIdentifier: merchantIdentifier ?? prediction.merchantIdentifier,
                merchantLatitude: merchantLatitude,
                merchantLongitude: merchantLongitude,
                categoryAtPurchase: prediction.predictedCategory,
                categoryConfidence: prediction.confidenceSource,
                rawCategoryAtPurchase: prediction.rawCategory,
                categoryTaxonomyVersion: prediction.categoryTaxonomyVersion,
                categoryConfidenceScore: prediction.categoryConfidenceScore,
                merchantCategoryCode: prediction.merchantCategoryCode,
                merchantGroupID: prediction.merchantGroupID,
                bestCardId: prediction.winnerCardId,
                bestCardValueCad: prediction.winnerValueCad)
            context.insert(purchase)
            purchase.prediction = prediction
        }
        if let cardUsedId {
            purchase.cardUsedId = cardUsedId
            purchase.cardSourceRaw = cardSource?.rawValue
        }
        if purchase.walletEventId == nil, let walletEventId {
            purchase.walletEventId = walletEventId
        }
        refreshCompletion(purchase, at: date)
        try context.save()
        return purchase
    }

    /// Saves the comparison as it was evaluated for this purchase. Activity reads this snapshot
    /// first, so a later wallet/catalogue edit does not rewrite history on screen.
    public func recordAssessment(on purchase: StoredPurchase, bestCardId: String,
                                 bestCardValueCad: Double?, usedCardValueCad: Double?,
                                 evaluatedAt: Date = Date()) throws {
        purchase.bestCardId = bestCardId
        purchase.bestCardValueCad = bestCardValueCad
        purchase.usedCardValueCad = usedCardValueCad
        purchase.advantageCad = {
            guard let bestCardValueCad, let usedCardValueCad else { return nil }
            return max(0, bestCardValueCad - usedCardValueCad)
        }()
        purchase.evaluatedAt = evaluatedAt
        try context.save()
    }

    public func recordAmount(_ amountCad: Double, source: CaptureSource,
                             on purchase: StoredPurchase, at date: Date = Date()) throws {
        purchase.amountCad = amountCad
        purchase.amountSourceRaw = source.rawValue
        refreshCompletion(purchase, at: date)
        try context.save()
    }

    /// Refines the pre-payment estimate on an already-answered checkout — the owner adjusting
    /// the amount on the recommendation screen, before tapping Pay. Deliberately NOT
    /// `recordAmount`: that records the actual charge on the *purchase*, and conflating the two
    /// is exactly what `scoredAmountCad`'s split from `StoredPurchase.amountCad` exists to
    /// prevent. Takes an id rather than the object because the caller (`CopilotSession`, which
    /// holds no `ModelContext`) only ever has the id a `CheckoutResult` carries. Silent no-op if
    /// the row is gone, matching `recordAssessment`'s tolerance for a stale reference.
    public func recordScoredAmount(_ amountCad: Double, forPredictionId id: UUID) throws {
        guard let prediction = try context.fetch(FetchDescriptor<StoredPrediction>(
            predicate: #Predicate { $0.id == id })).first else { return }
        prediction.scoredAmountCad = amountCad
        try context.save()
    }

    public func recordCard(_ cardUsedId: String?, source: CaptureSource? = .recalledLater,
                           on purchase: StoredPurchase, at date: Date = Date()) throws {
        purchase.cardUsedId = cardUsedId
        purchase.cardSourceRaw = source?.rawValue
        refreshCompletion(purchase, at: date)
        try context.save()
    }

    public func deletePurchase(_ purchase: StoredPurchase) throws {
        context.delete(purchase)
        try context.save()
    }

    /// Completion is derived, never asserted by a caller — a purchase is complete exactly when
    /// both facts are present, and no code path gets to claim otherwise.
    private func refreshCompletion(_ purchase: StoredPurchase, at date: Date) {
        let hasBoth = purchase.cardUsedId != nil && purchase.amountCad != nil
        if hasBoth, purchase.completedAt == nil { purchase.completedAt = date }
        if !hasBoth { purchase.completedAt = nil }
    }

    public func confirm(_ purchase: StoredPurchase,
                        observedCategory: String, observedRewardUnits: Double? = nil,
                        missClass: MissClass?,
                        note: String?, confirmedAt: Date = Date(),
                        observedMerchantCategoryCode: Int? = nil) throws {
        let rawObservedCategory = observedCategory
        let observedCategory = CategoryTaxonomy.canonicalID(observedCategory)
        let observation = StoredObservation(observedCategory: observedCategory,
                                            observedRewardUnits: observedRewardUnits,
                                            missClass: missClass, note: note,
                                            rawObservedCategory: rawObservedCategory,
                                            observedMerchantCategoryCode: observedMerchantCategoryCode,
                                            confirmedAt: confirmedAt)
        context.insert(observation)
        observation.purchase = purchase
        if let prediction = purchase.prediction {
            try promoteMerchant(for: prediction, observedCategory: observedCategory, at: confirmedAt)
        }
        try context.save()
    }

    /// Terminal-level promotion, never brand-wide. The dossier (§6) is explicit: the owner's
    /// reconciled outcome is the only source that can promote a merchant to "verified", and it
    /// promotes THAT location — a confirmation at one Walmart says nothing about another.
    private func promoteMerchant(for prediction: StoredPrediction,
                                 observedCategory: String, at date: Date) throws {
        guard let identifier = prediction.merchantIdentifier else { return }
        let matches = try context.fetch(FetchDescriptor<StoredMerchant>(
            predicate: #Predicate { $0.identifier == identifier }))
        guard let merchant = matches.first else { return }

        // The count is a streak, not a total: it answers "how many times has this same result
        // repeated here", which is the claim `.repeatedTerminal` makes. A terminal that re-codes
        // starts over rather than accruing confidence its own evidence contradicts.
        merchant.confirmationCount = merchant.confirmedCategory == observedCategory
            ? merchant.confirmationCount + 1
            : 1
        merchant.confirmedCategory = observedCategory
        merchant.rawCategory = observedCategory
        merchant.categoryTaxonomyVersion = CategoryTaxonomy.taxonomyVersion
        merchant.categoryConfidenceScore = merchant.confirmationCount >= 2
            ? ConfidenceSource.repeatedTerminal.defaultScore
            : ConfidenceSource.ownerConfirmedTerminal.defaultScore
        merchant.merchantGroupID = CategoryTaxonomy.merchantGroupID(for: observedCategory)
        merchant.lastConfirmedAt = date
    }

    /// Reclassifies a transaction's category and updates the Merchant Truth Graph.
    ///
    /// Stamps `categoryCorrectedAt`. Rewriting the category makes the prediction agree with the
    /// observation, which would otherwise turn a recorded miss into an indistinguishable hit; the
    /// stamp is what lets the accuracy math exclude the row instead of silently counting it.
    public func updateCategory(for prediction: StoredPrediction, to newCategory: String,
                               correctedAt: Date = Date()) throws {
        let rawCategory = newCategory
        let newCategory = CategoryTaxonomy.canonicalID(newCategory)
        prediction.predictedCategory = newCategory
        prediction.categoryCorrectedAt = correctedAt
        if let purchase = prediction.purchase {
            if let observation = purchase.observation {
                observation.observedCategory = newCategory
            } else {
                let observation = StoredObservation(observedCategory: newCategory,
                                                    rawObservedCategory: rawCategory,
                                                    confirmedAt: correctedAt)
                context.insert(observation)
                observation.purchase = purchase
            }
        }
        try promoteMerchant(for: prediction, observedCategory: newCategory, at: correctedAt)
        try context.save()
    }

    /// Records an owner-supplied category on a purchase that may not have checkout advice.
    ///
    /// Automatic Wallet captures deliberately have no `StoredPrediction`, so rewriting a
    /// prediction cannot be the only category-edit path. Keep the capture-time category snapshot
    /// intact and store the owner's later answer as an observation; `displayCategory` already
    /// prefers that observation, while the original machine evidence remains auditable.
    public func updateCategory(for purchase: StoredPurchase, to newCategory: String,
                               correctedAt: Date = Date()) throws {
        let rawCategory = newCategory
        let newCategory = CategoryTaxonomy.canonicalID(newCategory)
        if let prediction = purchase.prediction {
            try updateCategory(for: prediction, to: newCategory, correctedAt: correctedAt)
            return
        }

        let isFirstOwnerCategory = purchase.observation == nil
        if let observation = purchase.observation {
            observation.observedCategory = newCategory
        } else {
            let observation = StoredObservation(observedCategory: newCategory,
                                                rawObservedCategory: rawCategory,
                                                confirmedAt: correctedAt)
            context.insert(observation)
            observation.purchase = purchase
        }
        try learnMerchant(from: purchase, category: newCategory,
                          incrementsConfirmation: isFirstOwnerCategory,
                          correctedAt: correctedAt)
        try context.save()
    }

    private func learnMerchant(from purchase: StoredPurchase, category: String,
                               incrementsConfirmation: Bool, correctedAt: Date) throws {
        let identifier = purchase.merchantIdentifier
            ?? purchase.merchantKey
            ?? merchantActivityKey(name: purchase.displayMerchant, locationIdentifier: nil)
        let activityKey = merchantActivityKey(name: purchase.displayMerchant,
                                              locationIdentifier: nil)
        let merchants = try context.fetch(FetchDescriptor<StoredMerchant>())
        let existing = merchants.first { merchant in
            if let identifier, merchant.identifier == identifier { return true }
            return activityKey != nil
                && merchantActivityKey(name: merchant.name, locationIdentifier: nil) == activityKey
        }

        if let existing {
            if existing.confirmedCategory == category {
                if incrementsConfirmation { existing.confirmationCount += 1 }
            } else {
                existing.confirmedCategory = category
                existing.confirmationCount = 1
            }
            existing.lastSeenAt = purchase.createdAt
            existing.rawCategory = category
            existing.categoryTaxonomyVersion = CategoryTaxonomy.taxonomyVersion
            existing.categoryConfidenceScore = existing.confirmationCount >= 2
                ? ConfidenceSource.repeatedTerminal.defaultScore
                : ConfidenceSource.ownerConfirmedTerminal.defaultScore
            existing.merchantCategoryCode = purchase.merchantCategoryCode
            existing.merchantGroupID = CategoryTaxonomy.merchantGroupID(for: category)
            existing.lastConfirmedAt = correctedAt
            return
        }

        context.insert(StoredMerchant(
            name: purchase.displayMerchant,
            identifier: identifier,
            latitude: purchase.merchantLatitude ?? 0,
            longitude: purchase.merchantLongitude ?? 0,
            confirmedCategory: category,
            confirmationCount: 1,
            lastSeenAt: purchase.createdAt,
            rawCategory: category,
            merchantCategoryCode: purchase.merchantCategoryCode,
            merchantGroupID: CategoryTaxonomy.merchantGroupID(for: category),
            categoryTaxonomyVersion: CategoryTaxonomy.taxonomyVersion,
            categoryConfidenceScore: ConfidenceSource.ownerConfirmedTerminal.defaultScore,
            lastConfirmedAt: correctedAt))
    }

    public func allPredictions() throws -> [StoredPrediction] {
        try context.fetch(FetchDescriptor<StoredPrediction>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]))
    }

    /// The one purchase history, independent of whether advice preceded the purchase.
    public func allPurchases(limit: Int = 100) throws -> [StoredPurchase] {
        var descriptor = FetchDescriptor<StoredPurchase>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// Purchases missing a card or an amount — the "finish these" queue. One field each, and no
    /// statement required, so this is deliberately a different ritual from reconciling.
    public func awaitingCompletion() throws -> [StoredPrediction] {
        Self.awaitingCompletion(from: try allPredictions())
    }

    private static func awaitingCompletion(from predictions: [StoredPrediction]) -> [StoredPrediction] {
        predictions.filter { prediction in
            guard let purchase = prediction.purchase else { return false }
            return !purchase.isComplete
        }
    }

    /// Complete purchases still waiting on a statement — the weekly reconcile queue.
    ///
    /// A prediction with no purchase appears in neither queue. That is the point: advice the
    /// owner never acted on is a real outcome, not an unfinished chore, and dropping it into a
    /// to-do list would make the queue a measure of walking past shops.
    public func awaitingConfirmation() throws -> [StoredPrediction] {
        Self.awaitingConfirmation(from: try allPredictions())
    }

    private static func awaitingConfirmation(from predictions: [StoredPrediction]) -> [StoredPrediction] {
        predictions.filter { prediction in
            guard let purchase = prediction.purchase else { return false }
            return purchase.isComplete && purchase.observation == nil
        }
    }

    /// Complete or incomplete purchases recorded in the log, newest first.
    public func recentPurchases(limit: Int = 20) throws -> [StoredPrediction] {
        Self.recentPurchases(from: try allPredictions(), limit: limit)
    }

    private static func recentPurchases(from predictions: [StoredPrediction], limit: Int = 20) -> [StoredPrediction] {
        let purchases = predictions.filter { $0.purchase != nil }
        return Array(purchases.prefix(limit))
    }

    /// Everything the home screen needs, from one fetch.
    ///
    /// The four accessors below stay — they are the readable unit and every test asserts against
    /// them — but calling all four in sequence runs three unfiltered fetches and filters each in
    /// memory. That was fine against a 30-row target; ambient capture exists to raise the row
    /// count, and a third record type with relationships to walk makes every pass heavier.
    public struct LogSnapshot {
        public let valueRecovered: ValueRecovered
        public let awaitingCompletion: [StoredPrediction]
        public let awaitingConfirmation: [StoredPrediction]
        public let metrics: ExperimentMetrics
        public let recentPurchases: [StoredPrediction]
        public let purchaseHistory: [StoredPurchase]
    }

    public func snapshot(recentLimit: Int = 20) throws -> LogSnapshot {
        let predictions = try allPredictions()
        return LogSnapshot(valueRecovered: Self.valueRecovered(from: predictions),
                           awaitingCompletion: Self.awaitingCompletion(from: predictions),
                           awaitingConfirmation: Self.awaitingConfirmation(from: predictions),
                           metrics: Self.metrics(from: predictions),
                           recentPurchases: Self.recentPurchases(from: predictions, limit: recentLimit),
                           purchaseHistory: try allPurchases(limit: recentLimit))
    }

    public func metrics() throws -> ExperimentMetrics {
        Self.metrics(from: try allPredictions())
    }

    private static func metrics(from predictions: [StoredPrediction]) -> ExperimentMetrics {
        let confirmed = predictions.compactMap { $0.purchase?.observation }
        var breakdown: [MissClass: Int] = [:]
        for miss in confirmed.compactMap(\.missClass) {
            breakdown[miss, default: 0] += 1
        }
        let verdicts = predictions.map(\.arithmeticVerdict)
        return ExperimentMetrics(confirmedCount: confirmed.count,
                                 categoryCorrectCount: confirmed.filter(\.wasCorrect).count,
                                 missBreakdown: breakdown,
                                 targetCheckouts: Self.targetCheckouts,
                                 arithmeticEligibleCount: verdicts.filter { $0 != .notEligible }.count,
                                 arithmeticCorrectCount: verdicts.filter { $0 == .matches }.count)
    }

    /// Value recovered, split by whether a statement has backed it up yet.
    ///
    /// Reporting one number would force a choice between honest and motivating. Requiring
    /// reconciliation is the honest reading — until the statement lands, "it coded as grocery"
    /// is an assumption — but it would hold the scoreboard at $0 for weeks on a feature whose
    /// whole job is getting purchases logged. Two labelled numbers keep the strong claim strong.
    public struct ValueRecovered: Equatable, Sendable {
        public let confirmedCad: Double
        public let pendingCad: Double

        public static let zero = ValueRecovered(confirmedCad: 0, pendingCad: 0)
    }

    public func valueRecovered() throws -> ValueRecovered {
        Self.valueRecovered(from: try allPredictions())
    }

    private static func valueRecovered(from predictions: [StoredPrediction]) -> ValueRecovered {
        var confirmed: Double = 0
        var pending: Double = 0
        for prediction in predictions {
            guard let purchase = prediction.purchase,
                  let advantage = advantageRealised(prediction, purchase) else { continue }
            if purchase.observation != nil { confirmed += advantage } else { pending += advantage }
        }
        return ValueRecovered(confirmedCad: confirmed, pendingCad: pending)
    }

    /// What taking the advice was actually worth on this purchase, or nil when the question does
    /// not apply.
    ///
    /// The card check is the one this shipped without, and its absence was not cosmetic: value
    /// recovered means "I earned more BECAUSE I took the advice", so a purchase paid on the
    /// habitual default card recovered nothing, however large the advantage on offer was.
    ///
    /// The advantage is scaled from the scored amount to the real one. `winnerValueCad` and
    /// `defaultCardValueCad` are absolute figures the engine computed against whatever amount it
    /// was given, so a $50 preset standing in for a $47.83 charge overstates by 4.5%. Scaling
    /// assumes reward rates are linear in amount, which is true away from cap boundaries and
    /// approximate at them — better than multiplying through a button the owner tapped, and the
    /// residual error is bounded by how close the purchase sat to a cap.
    private static func advantageRealised(_ prediction: StoredPrediction,
                                          _ purchase: StoredPurchase) -> Double? {
        guard purchase.cardUsedId == prediction.winnerCardId,
              let actualAmount = purchase.amountCad,
              let defaultCardValueCad = prediction.defaultCardValueCad,
              // No scored amount means the engine priced a category estimate. There is no
              // per-dollar advantage to rescale, so the row is excluded rather than guessed at.
              let scoredAmount = prediction.scoredAmountCad, scoredAmount > 0 else { return nil }
        let advantagePerDollar = (prediction.winnerValueCad - defaultCardValueCad) / scoredAmount
        return advantagePerDollar * actualAmount
    }
}
