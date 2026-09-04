import Foundation

/// Exact MCC evidence and reward-category evidence are deliberately separate.
/// A category confirmation can improve recommendation confidence, but it must never be promoted
/// into a literal 4-digit MCC unless a source actually supplied that MCC.
public enum MerchantMCCEvidenceKind: String, Codable, Sendable, CaseIterable {
    /// MCC explicitly observed by the owner at a purchase/location that PickMe can anchor.
    case directOwnerMcc
    /// Literal MCC read from the owner's issuer/export data without a trustworthy store-location
    /// join. Strong owner evidence, but deliberately unable to create terminal/location trust.
    case ownerImportedMcc
    /// Location-specific public/community report with an explicit MCC.
    case externalLocationReport
    /// Editorial/researched seed used only to bootstrap coverage.
    case researchedSeed
    /// Owner-confirmed reward/category outcome with no literal MCC attached.
    case categoryOutcome
    /// A reward outcome narrows the MCC to a bounded set without revealing one literal MCC.
    /// One observation is split across every compatible candidate using `sourceConfidence`.
    case rewardOutcomeInference

    var defaultWeight: Double {
        switch self {
        case .directOwnerMcc: return 1.0
        case .ownerImportedMcc: return 0.90
        case .externalLocationReport: return 0.65
        case .researchedSeed: return 0.40
        case .rewardOutcomeInference: return 0.55
        case .categoryOutcome: return 0.0
        }
    }
}

public enum MerchantMCCChannel: String, Codable, Sendable, CaseIterable {
    case inStore
    case online
    case app
    case unknown
}

/// The merchant/location/channel PickMe is trying to score before payment.
public struct MerchantMCCQuery: Equatable, Sendable {
    public let merchantKey: String
    public let placeID: String?
    public let latitude: Double?
    public let longitude: Double?
    public let channel: MerchantMCCChannel
    public let network: String?

    public init(merchantKey: String, placeID: String? = nil,
                latitude: Double? = nil, longitude: Double? = nil,
                channel: MerchantMCCChannel = .unknown, network: String? = nil) {
        self.merchantKey = Self.normalizedKey(merchantKey)
        self.placeID = placeID?.nonEmpty
        self.latitude = latitude?.isFinite == true ? latitude : nil
        self.longitude = longitude?.isFinite == true ? longitude : nil
        self.channel = channel
        self.network = network?.lowercased().nonEmpty
    }

    fileprivate static func normalizedKey(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                   locale: Locale(identifier: "en_CA"))
        let pieces = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
        }
        return String(pieces).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

/// One candidate in an editorial seed profile. Weights are normalized by the graph at runtime, so
/// malformed or partial callers cannot accidentally multiply the total strength of the prior.
public struct MerchantMCCPriorCandidate: Equatable, Sendable {
    public let mcc: Int
    public let weight: Double

    public init(mcc: Int, weight: Double) {
        self.mcc = mcc
        self.weight = weight
    }
}

/// One piece of evidence in the graph. `mcc == nil` is valid only for category-only evidence.
public struct MerchantMCCEvidence: Equatable, Sendable, Codable {
    public let id: String
    public let merchantKey: String
    public let placeID: String?
    public let latitude: Double?
    public let longitude: Double?
    public let channel: MerchantMCCChannel
    public let network: String?
    public let mcc: Int?
    public let category: String?
    public let kind: MerchantMCCEvidenceKind
    public let sourceConfidence: Double
    public let observedAt: Date
    public let sourceReference: String?

    public init(id: String = UUID().uuidString, merchantKey: String,
                placeID: String? = nil, latitude: Double? = nil, longitude: Double? = nil,
                channel: MerchantMCCChannel = .unknown, network: String? = nil,
                mcc: Int? = nil, category: String? = nil,
                kind: MerchantMCCEvidenceKind,
                sourceConfidence: Double? = nil,
                observedAt: Date = Date(), sourceReference: String? = nil) {
        self.id = id
        self.merchantKey = MerchantMCCQuery.normalizedKey(merchantKey)
        self.placeID = placeID?.nonEmpty
        self.latitude = latitude?.isFinite == true ? latitude : nil
        self.longitude = longitude?.isFinite == true ? longitude : nil
        self.channel = channel
        self.network = network?.lowercased().nonEmpty
        self.mcc = mcc.flatMap { (0...9999).contains($0) ? $0 : nil }
        self.category = category?.nonEmpty
        self.kind = kind
        self.sourceConfidence = min(1, max(0, sourceConfidence ?? 1))
        self.observedAt = observedAt
        self.sourceReference = sourceReference?.nonEmpty
    }
}

public struct MerchantMCCCandidate: Equatable, Sendable {
    public let mcc: Int
    public let score: Double
    public let share: Double
    public let directObservationCount: Int
    public let externalObservationCount: Int
}

public struct MerchantMCCPrediction: Equatable, Sendable {
    public let bestMCC: Int?
    public let confidence: Double
    public let candidates: [MerchantMCCCandidate]
    public let directObservationCount: Int
    public let externalObservationCount: Int
    public let categoryEvidenceCount: Int

    /// True only when the winning MCC has at least one explicit owner MCC observation anchored to
    /// the purchase/location. Unlocated issuer-file imports deliberately do not satisfy this.
    public var isObserved: Bool { bestMCC != nil && directObservationCount > 0 }

    /// Two independent direct observations plus a strong aggregate score is the first point at
    /// which PickMe may treat the location MCC as durable truth rather than a working prediction.
    public var isTrusted: Bool { isObserved && directObservationCount >= 2 && confidence >= 0.80 }
}

/// Pure resolver for PickMe's Merchant MCC Graph.
///
/// It intentionally accepts evidence as input rather than owning persistence. Today that evidence
/// can come from the local store and the editorial seed pack; later the exact same resolver can
/// consume de-identified community aggregates without coupling checkout logic to a backend.
public enum MerchantMCCGraph {
    public static func predict(for query: MerchantMCCQuery,
                               seedMCC: Int? = nil,
                               seedCandidates: [MerchantMCCPriorCandidate] = [],
                               seedConfidence: Double? = nil,
                               evidence: [MerchantMCCEvidence],
                               now: Date = Date()) -> MerchantMCCPrediction {
        var scores: [Int: Double] = [:]
        var directCounts: [Int: Int] = [:]
        var externalCounts: [Int: Int] = [:]
        var categoryEvidenceCount = 0

        let usableSeedCandidates = seedCandidates.filter {
            (0...9999).contains($0.mcc) && $0.weight > 0 && $0.weight.isFinite
        }
        let seedWeightTotal = usableSeedCandidates.reduce(0) { $0 + $1.weight }
        if seedWeightTotal > 0 {
            // The profile's confidence is the TOTAL strength of the editorial prior; candidate
            // weights only distribute that strength. Adding more possible MCCs can never make the
            // seed itself stronger.
            let totalSeedStrength = min(1, max(0, seedConfidence
                ?? MerchantMCCEvidenceKind.researchedSeed.defaultWeight))
            for candidate in usableSeedCandidates {
                scores[candidate.mcc, default: 0] +=
                    (candidate.weight / seedWeightTotal) * totalSeedStrength
            }
        } else if let seedMCC, (0...9999).contains(seedMCC) {
            // Backward-compatible single-MCC prior for callers that have no weighted profile.
            scores[seedMCC, default: 0] += MerchantMCCEvidenceKind.researchedSeed.defaultWeight
        }

        var seenIDs = Set<String>()
        for item in evidence {
            guard seenIDs.insert(item.id).inserted else { continue }
            guard item.merchantKey == query.merchantKey else { continue }

            if item.kind == .categoryOutcome {
                categoryEvidenceCount += 1
                continue
            }
            guard let mcc = item.mcc else { continue }

            // Online/app/in-store can be different merchant accounts and therefore different MCCs.
            if query.channel != .unknown, item.channel != .unknown, query.channel != item.channel {
                continue
            }

            let location = locationMultiplier(query: query, evidence: item)
            let network = networkMultiplier(query: query.network, evidence: item.network)
            let age = ageMultiplier(observedAt: item.observedAt, now: now)
            let score = item.kind.defaultWeight * item.sourceConfidence * location * network * age
            guard score > 0 else { continue }
            scores[mcc, default: 0] += score

            switch item.kind {
            case .directOwnerMcc:
                directCounts[mcc, default: 0] += 1
            case .externalLocationReport:
                externalCounts[mcc, default: 0] += 1
            case .ownerImportedMcc, .researchedSeed, .categoryOutcome, .rewardOutcomeInference:
                break
            }
        }

        let total = scores.values.reduce(0, +)
        guard total > 0 else {
            return MerchantMCCPrediction(bestMCC: nil, confidence: 0, candidates: [],
                                         directObservationCount: 0,
                                         externalObservationCount: 0,
                                         categoryEvidenceCount: categoryEvidenceCount)
        }

        let candidates = scores.map { mcc, score in
            MerchantMCCCandidate(mcc: mcc, score: score, share: score / total,
                                 directObservationCount: directCounts[mcc, default: 0],
                                 externalObservationCount: externalCounts[mcc, default: 0])
        }.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.mcc < $1.mcc
        }

        guard let winner = candidates.first else {
            return MerchantMCCPrediction(bestMCC: nil, confidence: 0, candidates: [],
                                         directObservationCount: 0,
                                         externalObservationCount: 0,
                                         categoryEvidenceCount: categoryEvidenceCount)
        }

        // Confidence needs both agreement (share) and enough evidence (strength). This prevents a
        // single weak seed from becoming "100%" merely because no competing evidence exists.
        let strength = 1 - exp(-winner.score)
        let confidence = min(0.99, winner.share * (0.35 + 0.65 * strength))

        return MerchantMCCPrediction(bestMCC: winner.mcc, confidence: confidence,
                                     candidates: candidates,
                                     directObservationCount: winner.directObservationCount,
                                     externalObservationCount: winner.externalObservationCount,
                                     categoryEvidenceCount: categoryEvidenceCount)
    }

    private static func networkMultiplier(query: String?, evidence: String?) -> Double {
        switch (query, evidence) {
        case let (q?, e?) where q == e: return 1
        case (_?, _?): return 0.75
        default: return 0.90
        }
    }

    private static func locationMultiplier(query: MerchantMCCQuery,
                                           evidence: MerchantMCCEvidence) -> Double {
        if let queryPlaceID = query.placeID, let evidencePlaceID = evidence.placeID,
           queryPlaceID == evidencePlaceID {
            return 1.35
        }

        if let qLat = query.latitude, let qLon = query.longitude,
           let eLat = evidence.latitude, let eLon = evidence.longitude {
            let distance = distanceMeters(lat1: qLat, lon1: qLon, lat2: eLat, lon2: eLon)
            if distance <= 75 { return 1.20 }
            if distance <= 250 { return 0.95 }
            return 0.45
        }

        // Brand-only evidence remains useful as a prior but cannot claim terminal specificity.
        return 0.70
    }

    private static func ageMultiplier(observedAt: Date, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(observedAt) / 86_400)
        // 540-day half-life, floored so old evidence remains a weak prior rather than vanishing.
        return max(0.25, pow(0.5, days / 540))
    }

    private static func distanceMeters(lat1: Double, lon1: Double,
                                       lat2: Double, lon2: Double) -> Double {
        let radius = 6_371_000.0
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let deltaPhi = (lat2 - lat1) * .pi / 180
        let deltaLambda = (lon2 - lon1) * .pi / 180
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
