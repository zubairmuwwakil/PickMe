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
    /// The `CanadianMerchantPreIndex` row this candidate's name resolved to, or nil.
    ///
    /// `recognisedByPack` says *whether*; this says *which*. The difference is what turns
    /// "Shoppers wasn't in the list" from a recollection into a counted fact, and naming the row
    /// is what lets an export tell a plaza whose anchor tenant was returned-but-outranked from one
    /// where it was never returned at all. Those are the two competing mechanisms.
    public var preIndexMerchantId: String?
    /// What the engine would have recommended had this candidate been the answer.
    public var recommendedCardId: String?
    public var advantageOverDefaultCad: Double?

    public init(name: String, poiCategoryRaw: String?, latitude: Double, longitude: Double,
                distanceFromFixMeters: Double?, recognisedByPack: Bool, resolvedCategory: String,
                confidence: AmbientMerchantConfidence, preIndexMerchantId: String? = nil,
                recommendedCardId: String? = nil,
                advantageOverDefaultCad: Double? = nil) {
        self.name = name
        self.poiCategoryRaw = poiCategoryRaw
        self.latitude = latitude
        self.longitude = longitude
        self.distanceFromFixMeters = distanceFromFixMeters
        self.recognisedByPack = recognisedByPack
        self.resolvedCategory = resolvedCategory
        self.confidence = confidence
        self.preIndexMerchantId = preIndexMerchantId
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
    /// Index into `candidates`. Nil for a stored-merchant region, which has no candidate set, and
    /// for an empty Radar scan. For a Radar scan with results it is 0 — the one Home pointed at.
    public var chosenCandidateIndex: Int?
    /// Which rung of the arrival ladder answered. Nil for a Radar scan: no ladder ran.
    public var rung: ArrivalResolutionRung?

    /// How many places MapKit returned before `rankNearbyMerchants` deduped them, and how many
    /// survived. Radar only.
    ///
    /// Recorded as a pair because a cap that truncates upstream is invisible once the list is
    /// deduped, and "the anchor tenant was crowded out of a bounded response" is one of exactly
    /// two mechanisms that explain the owner's report. Nil on an ambient arrival, which reads a
    /// cached member set rather than issuing a query.
    public var rawResultCount: Int?
    public var dedupedResultCount: Int?

    public var resolvedMerchantName: String
    public var resolvedCategory: String
    /// The guessed basket the engine actually scored. Recorded because dividing the CAD floor by
    /// it is what makes the effective bar category-dependent, and a replay cannot undo that
    /// without knowing which number was used.
    ///
    /// Nil for a Radar scan, which scores no basket.
    public var estimatedAmountCad: Double?

    // The gate block. All nil together, or all present together: a Radar scan never reaches
    // `AmbientGate`, and a zeroed input here would read to every replay in the export as a real
    // decision not to fire.
    public var gateInput: AmbientGateInput?
    public var deliveryTier: AmbientDeliveryTier?
    public var suppressionReasons: [AmbientSuppressionReason]
    /// The dials in force. Makes an export self-describing: a record that fired says which policy
    /// made it fire.
    public var policy: AmbientAlertPolicy?

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
        self.rawResultCount = nil
        self.dedupedResultCount = nil
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

    /// One foreground Radar scan.
    ///
    /// A separate initialiser rather than a pile of defaults on the arrival one, because the two
    /// carry genuinely different facts: an arrival has a region, a ladder and a gate decision; a
    /// scan has a query and its result set. Sharing one initialiser would mean every Radar record
    /// naming a region that does not exist and a rung that never ran.
    public init(radarScanAt recordedAt: Date, id: UUID = UUID(), fix: ArrivalFix?,
                rawResultCount: Int, candidates: [ArrivalCandidateRecord],
                discriminability: ArrivalDiscriminability? = nil) {
        self.id = id
        self.recordedAt = recordedAt
        self.regionId = radarFieldRegionId
        self.source = .radar
        self.fix = fix
        // A scan holds no arrival open, so there is no window to close: no fix means the owner
        // had not granted location or the fix failed outright, not that a timeout expired.
        self.fixTimedOut = false
        self.candidates = candidates
        self.chosenCandidateIndex = candidates.isEmpty ? nil : 0
        self.rung = nil
        self.rawResultCount = rawResultCount
        self.dedupedResultCount = candidates.count
        self.resolvedMerchantName = candidates.first?.name ?? ""
        self.resolvedCategory = candidates.first?.resolvedCategory ?? ""
        self.estimatedAmountCad = nil
        self.gateInput = nil
        self.deliveryTier = nil
        self.suppressionReasons = []
        self.policy = nil
        self.discriminability = discriminability
    }

    // MARK: - Chain containment
    //
    // Derived here rather than stored, so a record and its read-out cannot disagree, and so the
    // same three questions are asked of an ambient arrival and a Radar scan in the same words.

    /// The first candidate that resolved to a `CanadianMerchantPreIndex` row, if any.
    public var chainCandidateIndex: Int? {
        candidates.firstIndex { $0.preIndexMerchantId != nil }
    }

    public var containsRecognisedChain: Bool { chainCandidateIndex != nil }

    /// **The pin-geometry signature.** A recognised chain was returned and something else still
    /// took the top slot.
    ///
    /// Result-set truncation cannot produce this — the chain is demonstrably in the set. What can
    /// is a large store whose MapKit pin sits at the building centroid, leaving a small neighbour
    /// genuinely nearer to its own pin than the owner is to the anchor's. Counting this is what
    /// decides whether the fix is a second targeted query or a different ranking.
    public var topRankedMissedARecognisedChain: Bool {
        guard let chainCandidateIndex, let chosenCandidateIndex else { return false }
        return chainCandidateIndex != chosenCandidateIndex
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
