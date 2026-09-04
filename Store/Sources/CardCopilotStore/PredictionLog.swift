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
              purchase.amountCad != nil,
              let predicted = predictedRewardUnits,
              let observed = observation.observedRewardUnits else { return .notEligible }
        let tolerance = rewardUnitTolerance(predictedRewardUnitKind)
        return abs(predicted - observed) <= tolerance + 1e-9 ? .matches : .mismatch
    }
}

/// The two numbers the personal MVP exists to measure, plus the reconcile queue that feeds them.
public struct ExperimentMetrics: Equatable, Sendable {
    public let confirmedCount: Int
    public let categoryCorrectCount: Int
    public let missBreakdown: [MissClass: Int]
    public let targetCheckouts: Int
    public let arithmeticEligibleCount: Int
    public let arithmeticCorrectCount: Int

    public static let empty = ExperimentMetrics(confirmedCount: 0, categoryCorrectCount: 0,
                                                missBreakdown: [:],
                                                targetCheckouts: PredictionLog.targetCheckouts,
                                                arithmeticEligibleCount: 0,
                                                arithmeticCorrectCount: 0)

    public var categoryAccuracy: Double? {
        confirmedCount > 0 ? Double(categoryCorrectCount) / Double(confirmedCount) : nil
    }

    public var arithmeticCorrectRate: Double? {
        arithmeticEligibleCount > 0
            ? Double(arithmeticCorrectCount) / Double(arithmeticEligibleCount) : nil
    }

    public var progressToTarget: Int { confirmedCount }
    public var meetsCategoryBar: Bool? { categoryAccuracy.map { $0 >= 0.85 } }
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

    @discardableResult
    public func applyAutomaticCapture(_ proposal: CaptureProposal,
                                      to prediction: StoredPrediction) throws -> StoredPurchase? {
        guard proposal.predictionId == prediction.id,
              let purchase = prediction.purchase else { return nil }

        let eventID = proposal.eventId
        let represented = try context.fetch(FetchDescriptor<StoredPurchase>(
            predicate: #Predicate { $0.walletEventId == eventID }))
        guard represented.allSatisfy({ $0.id == purchase.id }) else { return nil }

        let settledAmount = purchase.amountCad ?? proposal.amountCad
        let settledCard = purchase.cardUsedId ?? proposal.cardUsedId
        guard let settledAmount, settledAmount.isFinite, settledAmount > 0,
              let settledCard, !settledCard.isEmpty else { return nil }

        if purchase.amountCad == nil {
            purchase.amountCad = settledAmount
            purchase.amountSourceRaw = CaptureSource.walletCapture.rawValue
        }
        if purchase.cardUsedId == nil {
            purchase.cardUsedId = settledCard
            purchase.cardSourceRaw = CaptureSource.walletCapture.rawValue
        }
        if purchase.walletEventId == nil {
            purchase.walletEventId = eventID
        }
        refreshCompletion(purchase, at: proposal.capturedAt)
        try context.save()
        return purchase
    }

    public func deletePurchase(_ purchase: StoredPurchase) throws {
        context.delete(purchase)
        try context.save()
    }

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
        // Queue only a literal MCC the owner actually reconciled. The queue itself checks the
        // explicit opt-in, canonical merchant identity and precise-location privacy requirements.
        CommunityMerchantMCCPendingStore.shared.enqueue(purchase: purchase)
    }

    private func promoteMerchant(for prediction: StoredPrediction,
                                 observedCategory: String, at date: Date) throws {
        guard let identifier = prediction.merchantIdentifier else { return }
        let matches = try context.fetch(FetchDescriptor<StoredMerchant>(
            predicate: #Predicate { $0.identifier == identifier }))
        guard let merchant = matches.first else { return }

        applyOwnerConfirmation(to: merchant, category: observedCategory,
                               incrementsConfirmation: true, at: date)
    }

    private func applyOwnerConfirmation(to merchant: StoredMerchant, category: String,
                                        incrementsConfirmation: Bool, at date: Date) {
        if merchant.confirmedCategory == category {
            if incrementsConfirmation { merchant.confirmationCount += 1 }
        } else {
            merchant.confirmedCategory = category
            merchant.confirmationCount = 1
        }
        merchant.rawCategory = category
        merchant.categoryTaxonomyVersion = CategoryTaxonomy.taxonomyVersion
        merchant.categoryConfidenceScore = merchant.confirmationCount >= 2
            ? ConfidenceSource.repeatedTerminal.defaultScore
            : ConfidenceSource.ownerConfirmedTerminal.defaultScore
        merchant.merchantGroupID = CategoryTaxonomy.merchantGroupID(for: category)
        merchant.lastConfirmedAt = date
    }

    public func confirmMerchant(_ merchant: NearbyPlace, category rawCategory: String,
                                confirmedAt: Date = Date()) throws {
        let category = CategoryTaxonomy.canonicalID(rawCategory)
        guard category != "other" else { return }

        let all = try context.fetch(FetchDescriptor<StoredMerchant>())
        let stored: StoredMerchant
        if let match = MerchantIdentity.match(merchant, in: all) {
            stored = match.merchant
            MerchantIdentity.backfill(stored, from: merchant)
        } else {
            stored = StoredMerchant(name: merchant.name, identifier: merchant.id,
                                    placeID: merchant.placeID,
                                    poiCategoryRaw: merchant.poiCategoryRaw,
                                    latitude: merchant.latitude, longitude: merchant.longitude,
                                    merchantCategoryCode: merchant.merchantCategoryCode)
            context.insert(stored)
        }
        stored.lastSeenAt = confirmedAt
        applyOwnerConfirmation(to: stored, category: category,
                               incrementsConfirmation: true, at: confirmedAt)
        try context.save()
    }

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

        let located = purchase.merchantLatitude.flatMap { latitude in
            purchase.merchantLongitude.map { longitude in
                NearbyPlace(id: identifier ?? purchase.displayMerchant,
                            name: purchase.displayMerchant, poiCategoryRaw: nil,
                            latitude: latitude, longitude: longitude, distanceMeters: nil)
            }
        }
        let existing: StoredMerchant?
        if let located, located.hasMonitorableLocation {
            existing = MerchantIdentity.match(located, in: merchants)?.merchant
        } else {
            existing = merchants.first { merchant in
                if let identifier, merchant.identifier == identifier { return true }
                return activityKey != nil
                    && merchantActivityKey(name: merchant.name, locationIdentifier: nil) == activityKey
            }
        }

        if let existing {
            existing.lastSeenAt = purchase.createdAt
            existing.merchantCategoryCode = purchase.merchantCategoryCode
            applyOwnerConfirmation(to: existing, category: category,
                                   incrementsConfirmation: incrementsConfirmation,
                                   at: correctedAt)
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

    public func allPurchases(limit: Int = 100) throws -> [StoredPurchase] {
        var descriptor = FetchDescriptor<StoredPurchase>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    public func awaitingCompletion() throws -> [StoredPrediction] {
        Self.awaitingCompletion(from: try allPredictions())
    }

    private static func awaitingCompletion(from predictions: [StoredPrediction]) -> [StoredPrediction] {
        predictions.filter { prediction in
            guard let purchase = prediction.purchase else { return false }
            return !purchase.isComplete
        }
    }

    public func awaitingConfirmation() throws -> [StoredPrediction] {
        Self.awaitingConfirmation(from: try allPredictions())
    }

    private static func awaitingConfirmation(from predictions: [StoredPrediction]) -> [StoredPrediction] {
        predictions.filter { prediction in
            guard let purchase = prediction.purchase else { return false }
            return purchase.isComplete && purchase.observation == nil
        }
    }

    public func recentPurchases(limit: Int = 20) throws -> [StoredPrediction] {
        Self.recentPurchases(from: try allPredictions(), limit: limit)
    }

    private static func recentPurchases(from predictions: [StoredPrediction], limit: Int = 20) -> [StoredPrediction] {
        let purchases = predictions.filter { $0.purchase != nil }
        return Array(purchases.prefix(limit))
    }

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

    private static func advantageRealised(_ prediction: StoredPrediction,
                                          _ purchase: StoredPurchase) -> Double? {
        guard purchase.cardUsedId == prediction.winnerCardId,
              let actualAmount = purchase.amountCad,
              let defaultCardValueCad = prediction.defaultCardValueCad,
              let scoredAmount = prediction.scoredAmountCad, scoredAmount > 0 else { return nil }
        let advantagePerDollar = (prediction.winnerValueCad - defaultCardValueCad) / scoredAmount
        return advantagePerDollar * actualAmount
    }
}
