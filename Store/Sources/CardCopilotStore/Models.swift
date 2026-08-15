import Foundation
import SwiftData

/// Where a category prediction came from, in descending confidence.
/// Mirrors the prediction ladder in the MVP design doc (§6).
public enum ConfidenceSource: String, Codable, Sendable, CaseIterable {
    case ownerConfirmedTerminal   // this exact location/terminal, previously confirmed
    case repeatedTerminal         // repeated reconciled result at the same terminal
    case issuerOverride           // issuer-specific known-merchant rule
    case observedMcc              // MCC read off the owner's own posted transaction
    case brandPrior               // brand/location seed plus MapKit category
    case mapKitCategory           // MapKit POI category alone
    case fallback                 // unknown

    /// Whether this source is strong enough to call a merchant "verified" in the UI.
    public var isVerified: Bool {
        self == .ownerConfirmedTerminal || self == .repeatedTerminal
    }
}

/// How a prediction went wrong. Chosen during the weekly reconcile ritual so that a failed
/// experiment says *which* thing failed — the taxonomy in the MVP design doc (§6).
public enum MissClass: String, Codable, Sendable, CaseIterable {
    case wrongCategory
    case capExceeded
    case staleRule
    case processorWeirdness
    case networkNotAccepted
}

/// What the app said at the moment of payment. Never edited after it is written:
/// corrections arrive as a separate `StoredObservation`. Accuracy measured against a
/// log that could be rewritten would measure nothing.
@Model
public final class StoredPrediction {
    public private(set) var id: UUID = UUID()
    public private(set) var recordedAt: Date = Date()
    public private(set) var merchantName: String = ""
    public private(set) var merchantIdentifier: String?
    public private(set) var predictedCategory: String = ""
    public private(set) var confidenceSourceRaw: String = ConfidenceSource.fallback.rawValue
    public private(set) var winnerCardId: String = ""
    public private(set) var winnerValueCad: Double = 0
    /// Reward units the engine predicted the winning card would earn — points, cash-back
    /// dollars, CT Money, whatever the program pays in. Snapshotted so the arithmetic bar can
    /// be checked against the advice as given; optional so rows written before this field
    /// existed are excluded from the arithmetic metric rather than guessed at.
    public private(set) var predictedRewardUnits: Double?
    /// The winning program's unit ("point", "cad", "ctDollar", "cro") at prediction time.
    /// Decides the comparison tolerance: points post as integers, cash back posts to the cent.
    public private(set) var predictedRewardUnitKind: String?
    /// The value the designated default card would have earned on the same purchase.
    /// Optional so predictions written before Task 6 are excluded from value-recovered math.
    public private(set) var defaultCardValueCad: Double?
    public private(set) var winnerRuleId: String?
    public private(set) var runnerUpCardId: String?
    public private(set) var runnerUpValueCad: Double?
    public private(set) var amountCad: Double?
    /// The point valuation in force when this advice was given — without it, a later
    /// valuation change would silently invalidate the arithmetic check.
    public private(set) var valuationCentsPerPoint: Double?
    public private(set) var headline: String = ""

    @Relationship(deleteRule: .cascade, inverse: \StoredObservation.prediction)
    public var observation: StoredObservation?

    public var confidenceSource: ConfidenceSource {
        ConfidenceSource(rawValue: confidenceSourceRaw) ?? .fallback
    }

    public init(merchantName: String, merchantIdentifier: String? = nil,
                predictedCategory: String, confidenceSource: ConfidenceSource,
                winnerCardId: String, winnerValueCad: Double,
                predictedRewardUnits: Double? = nil, predictedRewardUnitKind: String? = nil,
                defaultCardValueCad: Double? = nil, winnerRuleId: String? = nil,
                runnerUpCardId: String? = nil, runnerUpValueCad: Double? = nil,
                amountCad: Double? = nil, valuationCentsPerPoint: Double? = nil,
                headline: String, recordedAt: Date = Date()) {
        self.id = UUID()
        self.recordedAt = recordedAt
        self.merchantName = merchantName
        self.merchantIdentifier = merchantIdentifier
        self.predictedCategory = predictedCategory
        self.confidenceSourceRaw = confidenceSource.rawValue
        self.winnerCardId = winnerCardId
        self.winnerValueCad = winnerValueCad
        self.predictedRewardUnits = predictedRewardUnits
        self.predictedRewardUnitKind = predictedRewardUnitKind
        self.defaultCardValueCad = defaultCardValueCad
        self.winnerRuleId = winnerRuleId
        self.runnerUpCardId = runnerUpCardId
        self.runnerUpValueCad = runnerUpValueCad
        self.amountCad = amountCad
        self.valuationCentsPerPoint = valuationCentsPerPoint
        self.headline = headline
    }
}

/// What actually happened, recorded after the transaction posts.
@Model
public final class StoredObservation {
    public private(set) var id: UUID = UUID()
    public private(set) var confirmedAt: Date = Date()
    public private(set) var cardUsed: String = ""
    public private(set) var observedCategory: String = ""
    /// Reward units the statement actually posted for this transaction — points for a points
    /// card, dollars for cash back. Optional and never inferred: a statement that shows no
    /// per-transaction reward line leaves this unknown, which excludes the row from the
    /// arithmetic bar rather than fabricating evidence for it.
    public private(set) var observedRewardUnits: Double?
    public private(set) var missClassRaw: String?
    public private(set) var note: String?
    public var prediction: StoredPrediction?

    public var missClass: MissClass? { missClassRaw.flatMap(MissClass.init(rawValue:)) }
    /// A confirmation with no miss class is a correct prediction.
    public var wasCorrect: Bool { missClassRaw == nil }

    public init(cardUsed: String, observedCategory: String, observedRewardUnits: Double? = nil,
                missClass: MissClass? = nil,
                note: String? = nil, confirmedAt: Date = Date()) {
        self.id = UUID()
        self.confirmedAt = confirmedAt
        self.cardUsed = cardUsed
        self.observedCategory = observedCategory
        self.observedRewardUnits = observedRewardUnits
        self.missClassRaw = missClass?.rawValue
        self.note = note
    }
}

/// A merchant the owner has confirmed at least once — the basis for instant repeats and
/// the embryo of the Merchant Truth Graph. Deliberately terminal-specific: a confirmation
/// at one Walmart says nothing about another.
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

    public init(name: String, identifier: String? = nil, poiCategoryRaw: String? = nil,
                latitude: Double, longitude: Double,
                confirmedCategory: String? = nil, confirmationCount: Int = 0,
                lastSeenAt: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.identifier = identifier
        self.poiCategoryRaw = poiCategoryRaw
        self.latitude = latitude
        self.longitude = longitude
        self.confirmedCategory = confirmedCategory
        self.confirmationCount = confirmationCount
        self.lastSeenAt = lastSeenAt
    }
}
