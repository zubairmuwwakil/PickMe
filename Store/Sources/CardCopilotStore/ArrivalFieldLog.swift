import Foundation
import CardCopilotEngine

// MARK: - Discriminability

/// How separable the candidates at one arrival were, measured against the fix that had to
/// separate them.
///
/// The ceiling metric. It says whether an arrival was answerable *at all* on this hardware,
/// independently of whether the app answered it — two storefronts 12 m apart seen through a fix
/// good to ±65 m is not a resolution failure but a question no algorithm on this device can
/// answer. It accrues on every arrival, including ones with no purchase, because unlike every
/// other metric here it needs no receipt.
public struct ArrivalDiscriminability: Equatable, Sendable, Codable {
    public let nearestDistanceMeters: Double
    /// Absent when the arrival had exactly one candidate.
    public let runnerUpDistanceMeters: Double?
    /// Absent for the same reason: with one candidate there is no gap to measure.
    public let marginMeters: Double?
    public let fixAccuracyMeters: Double

    /// A single candidate is resolvable by definition — there is nothing to confuse it with, and
    /// reporting it as ambiguous would inflate the number the rework decision turns on.
    public var isResolvable: Bool {
        guard let marginMeters else { return true }
        // CoreLocation reports a negative accuracy for an invalid fix. Reading that as "accurate
        // to −1 m" would mark every ambiguous arrival resolvable, which is the exact opposite of
        // what an unusable fix means.
        guard fixAccuracyMeters >= 0 else { return false }
        return marginMeters > fixAccuracyMeters
    }
}

public func discriminability(candidates: [ArrivalSite],
                             fix: ArrivalFix?) -> ArrivalDiscriminability? {
    guard let fix, !candidates.isEmpty else { return nil }
    let distances = candidates
        .map { greatCircleDistanceMeters(fromLatitude: fix.latitude, fromLongitude: fix.longitude,
                                         toLatitude: $0.latitude, toLongitude: $0.longitude) }
        .sorted()
    let runnerUp = distances.count > 1 ? distances[1] : nil
    return ArrivalDiscriminability(
        nearestDistanceMeters: distances[0],
        runnerUpDistanceMeters: runnerUp,
        marginMeters: runnerUp.map { $0 - distances[0] },
        fixAccuracyMeters: fix.horizontalAccuracyMeters)
}

// MARK: - The record

/// Which rung of the arrival ladder produced the answer.
public enum ArrivalResolutionRung: String, Equatable, Sendable, Codable {
    /// The region was registered for one stored merchant, so there was nothing to choose between.
    case storedMerchantRegion
    /// An owner-reconciled terminal inside the area, within `verifiedMerchantRadiusMeters` of the
    /// arrival origin.
    case confirmedMerchantNearby
    /// A cached POI from the area's member set.
    case areaMember
}

/// How the owner reacted, if at all. Recorded against the arrival that produced the alert.
///
/// The only signal for whether an alert was *useful* rather than merely correct — and it accrues
/// only once alerts actually fire, which is what the adjustable policy is for.
public enum ArrivalEngagement: String, Equatable, Sendable, Codable {
    case usedRecommendedCard
    case usedOtherCard
    case mutedMerchant
    case dismissedLiveActivity
}

/// One storefront the arrival could have been, with everything an offline replay needs.
///
/// Carries the engine's answer *for this candidate*, not just its category. That is what makes
/// card-equivalence accuracy — the number that decides the rework — a pure comparison in the
/// export rather than a re-scoring job needing the catalogue that was current at the time.
public struct ArrivalCandidateRecord: Equatable, Sendable, Codable {
    public var name: String
    public var poiCategoryRaw: String?
    public var latitude: Double
    public var longitude: Double
    /// Absent when the arrival got no fix.
    public var distanceFromFixMeters: Double?
    /// Whether `MerchantRecognizer` placed the name in the merchant pack.
    public var recognisedByPack: Bool
    public var resolvedCategory: String
    public var confidence: AmbientMerchantConfidence
    /// What the engine would have recommended had this candidate been the answer.
    public var recommendedCardId: String?
    public var advantageOverDefaultCad: Double?

    public init(name: String, poiCategoryRaw: String?, latitude: Double, longitude: Double,
                distanceFromFixMeters: Double?, recognisedByPack: Bool, resolvedCategory: String,
                confidence: AmbientMerchantConfidence, recommendedCardId: String? = nil,
                advantageOverDefaultCad: Double? = nil) {
        self.name = name
        self.poiCategoryRaw = poiCategoryRaw
        self.latitude = latitude
        self.longitude = longitude
        self.distanceFromFixMeters = distanceFromFixMeters
        self.recognisedByPack = recognisedByPack
        self.resolvedCategory = resolvedCategory
        self.confidence = confidence
        self.recommendedCardId = recommendedCardId
        self.advantageOverDefaultCad = advantageOverDefaultCad
    }

    public var site: ArrivalSite { ArrivalSite(latitude: latitude, longitude: longitude) }
}

/// A Wallet capture, reduced to what a join needs.
public struct ArrivalReceipt: Equatable, Sendable, Codable {
    public var merchantDescriptor: String
    public var amountCad: Double
    public var capturedAt: Date

    public init(merchantDescriptor: String, amountCad: Double, capturedAt: Date) {
        self.merchantDescriptor = merchantDescriptor
        self.amountCad = amountCad
        self.capturedAt = capturedAt
    }
}

/// One arrival, in full.
///
/// Dev-only, and deliberately richer than the shipping counters: it records coordinates and
/// merchant names, which `SuppressionLog` and `AmbientCoverageLog` deliberately do not. Designed
/// for offline replay — the whole candidate set and the raw gate input are here so an alternative
/// policy is evaluated from an export rather than shipped to find out.
public struct ArrivalFieldRecord: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var recordedAt: Date
    public var regionId: String
    public var source: AmbientArrivalSource

    public var areaCentroidLatitude: Double?
    public var areaCentroidLongitude: Double?
    public var areaRadiusMeters: Double?

    /// The arrival fix, or nil. `fixTimedOut` distinguishes "the window closed" from "there was
    /// no fix for another reason" — an explicit marker rather than an inference from a null.
    public var fix: ArrivalFix?
    public var fixTimedOut: Bool

    public var candidates: [ArrivalCandidateRecord]
    /// Index into `candidates`. Nil for a stored-merchant region, which has no candidate set.
    public var chosenCandidateIndex: Int?
    public var rung: ArrivalResolutionRung

    public var resolvedMerchantName: String
    public var resolvedCategory: String
    /// The guessed basket the engine actually scored. Recorded because dividing the CAD floor by
    /// it is what makes the effective bar category-dependent, and a replay cannot undo that
    /// without knowing which number was used.
    public var estimatedAmountCad: Double

    public var gateInput: AmbientGateInput
    public var deliveryTier: AmbientDeliveryTier
    public var suppressionReasons: [AmbientSuppressionReason]
    /// The dials in force. Makes an export self-describing: a record that fired says which policy
    /// made it fire.
    public var policy: AmbientAlertPolicy

    public var discriminability: ArrivalDiscriminability?
    public var engagement: ArrivalEngagement?
    public var receipt: ArrivalReceipt?
    /// Index into `candidates` of the store the receipt says the owner was actually in. Nil when
    /// there is no receipt, or when no candidate matched it — and those two are different: the
    /// second means the true store was not in the candidate set at all, which is the containment
    /// ceiling.
    public var receiptCandidateIndex: Int?

    public init(id: UUID = UUID(), recordedAt: Date, regionId: String,
                source: AmbientArrivalSource,
                areaCentroidLatitude: Double? = nil, areaCentroidLongitude: Double? = nil,
                areaRadiusMeters: Double? = nil,
                fix: ArrivalFix? = nil, fixTimedOut: Bool = false,
                candidates: [ArrivalCandidateRecord] = [], chosenCandidateIndex: Int? = nil,
                rung: ArrivalResolutionRung,
                resolvedMerchantName: String, resolvedCategory: String,
                estimatedAmountCad: Double,
                gateInput: AmbientGateInput, deliveryTier: AmbientDeliveryTier,
                suppressionReasons: [AmbientSuppressionReason],
                policy: AmbientAlertPolicy,
                discriminability: ArrivalDiscriminability? = nil,
                engagement: ArrivalEngagement? = nil,
                receipt: ArrivalReceipt? = nil, receiptCandidateIndex: Int? = nil) {
        self.id = id
        self.recordedAt = recordedAt
        self.regionId = regionId
        self.source = source
        self.areaCentroidLatitude = areaCentroidLatitude
        self.areaCentroidLongitude = areaCentroidLongitude
        self.areaRadiusMeters = areaRadiusMeters
        self.fix = fix
        self.fixTimedOut = fixTimedOut
        self.candidates = candidates
        self.chosenCandidateIndex = chosenCandidateIndex
        self.rung = rung
        self.resolvedMerchantName = resolvedMerchantName
        self.resolvedCategory = resolvedCategory
        self.estimatedAmountCad = estimatedAmountCad
        self.gateInput = gateInput
        self.deliveryTier = deliveryTier
        self.suppressionReasons = suppressionReasons
        self.policy = policy
        self.discriminability = discriminability
        self.engagement = engagement
        self.receipt = receipt
        self.receiptCandidateIndex = receiptCandidateIndex
    }

    public var chosenCandidate: ArrivalCandidateRecord? {
        guard let chosenCandidateIndex, candidates.indices.contains(chosenCandidateIndex) else {
            return nil
        }
        return candidates[chosenCandidateIndex]
    }

    public var receiptCandidate: ArrivalCandidateRecord? {
        guard let receiptCandidateIndex, candidates.indices.contains(receiptCandidateIndex) else {
            return nil
        }
        return candidates[receiptCandidateIndex]
    }
}
