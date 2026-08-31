import Foundation
import SwiftData
import CardCopilotEngine

// V5 preserves category evidence and learning provenance. Every new property is nullable so an
// older row migrates as "not recorded" rather than receiving evidence it never carried.
extension CardCopilotSchemaV5 {
    @Model
    public final class StoredPrediction {
        public private(set) var id: UUID = UUID()
        public private(set) var recordedAt: Date = Date()
        public private(set) var merchantName: String = ""
        public private(set) var merchantIdentifier: String?
        public internal(set) var predictedCategory: String = ""
        public internal(set) var categoryCorrectedAt: Date?
        public private(set) var confidenceSourceRaw: String = ConfidenceSource.fallback.rawValue
        public private(set) var winnerCardId: String = ""
        public private(set) var winnerValueCad: Double = 0
        public private(set) var predictedRewardUnits: Double?
        public private(set) var predictedRewardUnitKind: String?
        public private(set) var defaultCardValueCad: Double?
        public private(set) var winnerRuleId: String?
        public private(set) var runnerUpCardId: String?
        public private(set) var runnerUpValueCad: Double?
        public private(set) var scoredAmountCad: Double?
        public private(set) var valuationCentsPerPoint: Double?
        public private(set) var contractRelease: String?
        public private(set) var contractDigest: String?
        public private(set) var frozenInputs: Data?
        public private(set) var headline: String = ""
        public private(set) var rawCategory: String?
        public private(set) var categoryTaxonomyVersion: String?
        public private(set) var categoryConfidenceScore: Double?
        public private(set) var merchantCategoryCode: Int?
        public private(set) var merchantGroupID: String?

        @Relationship(deleteRule: .cascade, inverse: \StoredPurchase.prediction)
        public var purchase: StoredPurchase?

        public var confidenceSource: ConfidenceSource {
            ConfidenceSource(rawValue: confidenceSourceRaw) ?? .fallback
        }

        public init(merchantName: String, merchantIdentifier: String? = nil,
                    predictedCategory: String, confidenceSource: ConfidenceSource,
                    winnerCardId: String, winnerValueCad: Double,
                    predictedRewardUnits: Double? = nil, predictedRewardUnitKind: String? = nil,
                    defaultCardValueCad: Double? = nil, winnerRuleId: String? = nil,
                    runnerUpCardId: String? = nil, runnerUpValueCad: Double? = nil,
                    scoredAmountCad: Double? = nil, valuationCentsPerPoint: Double? = nil,
                    contractRelease: String? = nil, contractDigest: String? = nil,
                    frozenInputs: Data? = nil,
                    rawCategory: String? = nil, categoryTaxonomyVersion: String? = nil,
                    categoryConfidenceScore: Double? = nil,
                    merchantCategoryCode: Int? = nil, merchantGroupID: String? = nil,
                    headline: String, recordedAt: Date = Date()) {
            self.id = UUID()
            self.recordedAt = recordedAt
            self.merchantName = merchantName
            self.merchantIdentifier = merchantIdentifier
            self.predictedCategory = CategoryTaxonomy.canonicalID(predictedCategory)
            self.confidenceSourceRaw = confidenceSource.rawValue
            self.winnerCardId = winnerCardId
            self.winnerValueCad = winnerValueCad
            self.predictedRewardUnits = predictedRewardUnits
            self.predictedRewardUnitKind = predictedRewardUnitKind
            self.defaultCardValueCad = defaultCardValueCad
            self.winnerRuleId = winnerRuleId
            self.runnerUpCardId = runnerUpCardId
            self.runnerUpValueCad = runnerUpValueCad
            self.scoredAmountCad = scoredAmountCad
            self.valuationCentsPerPoint = valuationCentsPerPoint
            self.contractRelease = contractRelease
            self.contractDigest = contractDigest
            self.frozenInputs = frozenInputs
            self.rawCategory = rawCategory ?? predictedCategory
            self.categoryTaxonomyVersion = categoryTaxonomyVersion ?? CategoryTaxonomy.taxonomyVersion
            self.categoryConfidenceScore = categoryConfidenceScore ?? confidenceSource.defaultScore
            self.merchantCategoryCode = merchantCategoryCode
            self.merchantGroupID = merchantGroupID ?? CategoryTaxonomy.merchantGroupID(for: predictedCategory)
            self.headline = headline
        }
    }

    /// The single persisted activity record for advised, automatic, and arrival-alert purchases.
    @Model
    public final class StoredPurchase {
        public private(set) var id: UUID = UUID()
        public private(set) var createdAt: Date = Date()
        public var cardUsedId: String?
        public var cardSourceRaw: String?
        public var amountCad: Double?
        public var amountSourceRaw: String?
        public var completedAt: Date?
        public var prediction: StoredPrediction?
        public internal(set) var walletEventId: String?
        public internal(set) var merchantLabel: String?

        /// Nullable snapshots added in V4. Nil on pre-V4 rows means unknown, never a default.
        public internal(set) var activitySourceRaw: String?
        public internal(set) var merchantKey: String?
        public internal(set) var merchantIdentifier: String?
        public internal(set) var merchantLatitude: Double?
        public internal(set) var merchantLongitude: Double?
        public internal(set) var categoryAtPurchase: String?
        public internal(set) var categoryConfidenceRaw: String?
        public internal(set) var rawCategoryAtPurchase: String?
        public internal(set) var categoryTaxonomyVersion: String?
        public internal(set) var categoryConfidenceScore: Double?
        public internal(set) var merchantCategoryCode: Int?
        public internal(set) var merchantGroupID: String?
        public internal(set) var evaluatedAt: Date?
        public internal(set) var bestCardId: String?
        public internal(set) var bestCardValueCad: Double?
        public internal(set) var usedCardValueCad: Double?
        public internal(set) var advantageCad: Double?

        @Relationship(deleteRule: .cascade, inverse: \StoredObservation.purchase)
        public var observation: StoredObservation?

        public var cardSource: CaptureSource? { cardSourceRaw.flatMap(CaptureSource.init(rawValue:)) }
        public var amountSource: CaptureSource? { amountSourceRaw.flatMap(CaptureSource.init(rawValue:)) }
        public var activitySource: PurchaseActivitySource? {
            activitySourceRaw.flatMap(PurchaseActivitySource.init(rawValue:))
        }
        public var isComplete: Bool { completedAt != nil }

        public init(createdAt: Date = Date(), merchantLabel: String? = nil,
                    walletEventId: String? = nil,
                    activitySource: PurchaseActivitySource? = nil,
                    merchantKey: String? = nil, merchantIdentifier: String? = nil,
                    merchantLatitude: Double? = nil, merchantLongitude: Double? = nil,
                    categoryAtPurchase: String? = nil,
                    categoryConfidence: ConfidenceSource? = nil,
                    rawCategoryAtPurchase: String? = nil,
                    categoryTaxonomyVersion: String? = nil,
                    categoryConfidenceScore: Double? = nil,
                    merchantCategoryCode: Int? = nil, merchantGroupID: String? = nil,
                    bestCardId: String? = nil, bestCardValueCad: Double? = nil) {
            self.id = UUID()
            self.createdAt = createdAt
            self.merchantLabel = merchantLabel
            self.walletEventId = walletEventId
            self.activitySourceRaw = activitySource?.rawValue
            self.merchantKey = merchantKey
            self.merchantIdentifier = merchantIdentifier
            self.merchantLatitude = merchantLatitude
            self.merchantLongitude = merchantLongitude
            self.categoryAtPurchase = categoryAtPurchase.map(CategoryTaxonomy.canonicalID)
            self.categoryConfidenceRaw = categoryConfidence?.rawValue
            self.rawCategoryAtPurchase = rawCategoryAtPurchase ?? categoryAtPurchase
            self.categoryTaxonomyVersion = categoryAtPurchase == nil ? categoryTaxonomyVersion
                : (categoryTaxonomyVersion ?? CategoryTaxonomy.taxonomyVersion)
            self.categoryConfidenceScore = categoryConfidenceScore ?? categoryConfidence?.defaultScore
            self.merchantCategoryCode = merchantCategoryCode
            self.merchantGroupID = merchantGroupID
                ?? categoryAtPurchase.flatMap(CategoryTaxonomy.merchantGroupID)
            self.bestCardId = bestCardId
            self.bestCardValueCad = bestCardValueCad
        }
    }

    @Model
    public final class StoredObservation {
        public private(set) var id: UUID = UUID()
        public private(set) var confirmedAt: Date = Date()
        public var observedCategory: String = ""
        public private(set) var observedRewardUnits: Double?
        public private(set) var missClassRaw: String?
        public private(set) var note: String?
        public private(set) var rawObservedCategory: String?
        public private(set) var categoryTaxonomyVersion: String?
        public private(set) var categorySourceRaw: String?
        public private(set) var categoryConfidenceScore: Double?
        public private(set) var observedMerchantCategoryCode: Int?
        public var purchase: StoredPurchase?

        public var missClass: MissClass? { missClassRaw.flatMap(MissClass.init(rawValue:)) }
        public var wasCorrect: Bool { missClassRaw == nil }

        public init(observedCategory: String, observedRewardUnits: Double? = nil,
                    missClass: MissClass? = nil, note: String? = nil,
                    rawObservedCategory: String? = nil,
                    categoryTaxonomyVersion: String? = nil,
                    categorySource: ConfidenceSource = .ownerConfirmedTerminal,
                    categoryConfidenceScore: Double? = nil,
                    observedMerchantCategoryCode: Int? = nil,
                    confirmedAt: Date = Date()) {
            self.id = UUID()
            self.confirmedAt = confirmedAt
            self.observedCategory = CategoryTaxonomy.canonicalID(observedCategory)
            self.observedRewardUnits = observedRewardUnits
            self.missClassRaw = missClass?.rawValue
            self.note = note
            self.rawObservedCategory = rawObservedCategory ?? observedCategory
            self.categoryTaxonomyVersion = categoryTaxonomyVersion ?? CategoryTaxonomy.taxonomyVersion
            self.categorySourceRaw = categorySource.rawValue
            self.categoryConfidenceScore = categoryConfidenceScore ?? categorySource.defaultScore
            self.observedMerchantCategoryCode = observedMerchantCategoryCode
        }
    }

    @Model
    public final class StoredMerchant {
        public private(set) var id: UUID = UUID()
        public private(set) var name: String = ""
        public private(set) var identifier: String?
        public var poiCategoryRaw: String?
        public private(set) var latitude: Double = 0
        public private(set) var longitude: Double = 0
        public var confirmedCategory: String?
        public var confirmationCount: Int = 0
        public var lastSeenAt: Date = Date()
        public var rawCategory: String?
        public var merchantCategoryCode: Int?
        public var merchantGroupID: String?
        public var categoryTaxonomyVersion: String?
        public var categoryConfidenceScore: Double?
        public var lastConfirmedAt: Date?

        public init(name: String, identifier: String? = nil, poiCategoryRaw: String? = nil,
                    latitude: Double, longitude: Double, confirmedCategory: String? = nil,
                    confirmationCount: Int = 0, lastSeenAt: Date = Date(),
                    rawCategory: String? = nil, merchantCategoryCode: Int? = nil,
                    merchantGroupID: String? = nil, categoryTaxonomyVersion: String? = nil,
                    categoryConfidenceScore: Double? = nil, lastConfirmedAt: Date? = nil) {
            self.id = UUID()
            self.name = name
            self.identifier = identifier
            self.poiCategoryRaw = poiCategoryRaw
            self.latitude = latitude
            self.longitude = longitude
            self.confirmedCategory = confirmedCategory.map(CategoryTaxonomy.canonicalID)
            self.confirmationCount = confirmationCount
            self.lastSeenAt = lastSeenAt
            self.rawCategory = rawCategory ?? poiCategoryRaw
            self.merchantCategoryCode = merchantCategoryCode
            self.merchantGroupID = merchantGroupID
                ?? confirmedCategory.flatMap(CategoryTaxonomy.merchantGroupID)
            self.categoryTaxonomyVersion = confirmedCategory == nil ? categoryTaxonomyVersion
                : (categoryTaxonomyVersion ?? CategoryTaxonomy.taxonomyVersion)
            self.categoryConfidenceScore = categoryConfidenceScore
                ?? (confirmedCategory == nil ? nil
                    : (confirmationCount >= 2 ? ConfidenceSource.repeatedTerminal.defaultScore
                                              : ConfidenceSource.ownerConfirmedTerminal.defaultScore))
            self.lastConfirmedAt = lastConfirmedAt
        }
    }

    @Model
    public final class ExploredCell {
        public private(set) var cellKey: String = ""
        public var exploredAt: Date = Date()
        public var areaCount: Int = 0

        public init(cellKey: String, exploredAt: Date, areaCount: Int) {
            self.cellKey = cellKey
            self.exploredAt = exploredAt
            self.areaCount = areaCount
        }
    }

    @Model
    public final class ShoppingArea {
        public private(set) var id: UUID = UUID()
        public private(set) var cellKey: String = ""
        public private(set) var centroidLatitude: Double = 0
        public private(set) var centroidLongitude: Double = 0
        public private(set) var radiusMeters: Double = 0
        public var discoveredAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \AreaMember.area)
        public var members: [AreaMember] = []

        public init(cellKey: String, centroidLatitude: Double, centroidLongitude: Double,
                    radiusMeters: Double, discoveredAt: Date) {
            self.id = UUID()
            self.cellKey = cellKey
            self.centroidLatitude = centroidLatitude
            self.centroidLongitude = centroidLongitude
            self.radiusMeters = radiusMeters
            self.discoveredAt = discoveredAt
        }
    }

    @Model
    public final class AreaMember {
        public private(set) var name: String = ""
        public private(set) var identifier: String?
        public private(set) var poiCategoryRaw: String?
        public private(set) var latitude: Double = 0
        public private(set) var longitude: Double = 0
        public var area: ShoppingArea?

        public init(name: String, identifier: String?, poiCategoryRaw: String?,
                    latitude: Double, longitude: Double) {
            self.name = name
            self.identifier = identifier
            self.poiCategoryRaw = poiCategoryRaw
            self.latitude = latitude
            self.longitude = longitude
        }
    }
}
