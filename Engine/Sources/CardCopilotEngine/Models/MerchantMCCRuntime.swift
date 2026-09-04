import Foundation
import Compression

/// The compact 500-merchant bootstrap bundled with the app. Values here are priors, never
/// payment-network observations. Runtime evidence lives separately and is folded into a posterior.
public struct MerchantMCCRuntimeSeed: Codable, Sendable, Equatable {
    public let graphVersion: String
    public let generatedAt: String
    public let merchants: [MerchantMCCSeedMerchant]

    public init(graphVersion: String, generatedAt: String, merchants: [MerchantMCCSeedMerchant]) {
        self.graphVersion = graphVersion
        self.generatedAt = generatedAt
        self.merchants = merchants
    }
}

public struct MerchantMCCSeedMerchant: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let seedMcc: Int?
    public let candidateMccs: [Int]
    public let weights: [Double]
    public let confidence: Double

    public init(id: String, name: String, seedMcc: Int?, candidateMccs: [Int],
                weights: [Double], confidence: Double) {
        self.id = id
        self.name = name
        self.seedMcc = seedMcc
        self.candidateMccs = candidateMccs
        self.weights = weights
        self.confidence = confidence
    }
}

/// Evidence PickMe itself can collect without linking a financial account.
///
/// `networkObserved` is reserved for a future source that really supplies the processor/network MCC;
/// the current Wallet shortcut does not, and callers must not manufacture this case from a seed.
public enum MerchantMCCEvidenceType: String, Codable, Sendable, Equatable {
    case userEnteredExactMcc
    case rewardOutcomeInference
    case networkObserved

    public var defaultWeight: Double {
        switch self {
        case .networkObserved: return 1.00
        case .userEnteredExactMcc: return 0.80
        case .rewardOutcomeInference: return 0.55
        }
    }
}

public struct MerchantMCCRuntimeEvidence: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let merchantId: String
    public let mcc: Int
    public let type: MerchantMCCEvidenceType
    public let weight: Double
    public let locationKey: String?
    public let network: String?
    public let channel: String?
    public let sourceFingerprint: String?
    public let observedAt: Date

    public init(id: String = UUID().uuidString,
                merchantId: String,
                mcc: Int,
                type: MerchantMCCEvidenceType,
                weight: Double? = nil,
                locationKey: String? = nil,
                network: String? = nil,
                channel: String? = nil,
                sourceFingerprint: String? = nil,
                observedAt: Date = Date()) {
        self.id = id
        self.merchantId = merchantId
        self.mcc = mcc
        self.type = type
        self.weight = max(0, weight ?? type.defaultWeight)
        self.locationKey = locationKey
        self.network = network
        self.channel = channel
        self.sourceFingerprint = sourceFingerprint
        self.observedAt = observedAt
    }
}

public struct MerchantMCCPosteriorCandidate: Codable, Sendable, Equatable {
    public let mcc: Int
    public let probability: Double

    public init(mcc: Int, probability: Double) {
        self.mcc = mcc
        self.probability = probability
    }
}

public enum MerchantMCCPosteriorState: String, Codable, Sendable, Equatable {
    case priorOnly
    case locationLearned
    case strongLearned
    case conflicted
}

public struct MerchantMCCPosterior: Codable, Sendable, Equatable {
    public let merchantId: String
    public let candidates: [MerchantMCCPosteriorCandidate]
    public let confidence: Double
    public let evidenceCount: Int
    public let state: MerchantMCCPosteriorState

    public init(merchantId: String, candidates: [MerchantMCCPosteriorCandidate], confidence: Double,
                evidenceCount: Int, state: MerchantMCCPosteriorState) {
        self.merchantId = merchantId
        self.candidates = candidates
        self.confidence = confidence
        self.evidenceCount = evidenceCount
        self.state = state
    }

    public var topMcc: Int? { candidates.first?.mcc }
}

/// Pure posterior math. The audit trail stays immutable: contradictory evidence is retained and
/// lowers confidence instead of being overwritten by the newest answer.
public enum MerchantMCCPosteriorResolver {
    private static let priorFloor = 0.01

    public static func posterior(seed: MerchantMCCSeedMerchant,
                                 evidence: [MerchantMCCRuntimeEvidence],
                                 locationKey: String? = nil,
                                 network: String? = nil,
                                 channel: String? = nil) -> MerchantMCCPosterior {
        var scores: [Int: Double] = [:]
        let priorConfidence = max(seed.confidence, 0.20)

        for (index, mcc) in seed.candidateMccs.enumerated() {
            let declaredWeight = index < seed.weights.count ? seed.weights[index] : 0
            scores[mcc, default: 0] += max(declaredWeight, priorFloor) * priorConfidence
        }
        if let seedMcc = seed.seedMcc, scores[seedMcc] == nil {
            scores[seedMcc] = priorFloor * priorConfidence
        }

        let applicable = evidence.filter {
            $0.merchantId == seed.id
                && scopeMatches($0, locationKey: locationKey, network: network, channel: channel)
        }
        for item in applicable {
            scores[item.mcc, default: 0] += item.weight
        }

        guard !scores.isEmpty else {
            return MerchantMCCPosterior(merchantId: seed.id, candidates: [], confidence: 0,
                                        evidenceCount: applicable.count, state: .priorOnly)
        }

        let total = scores.values.reduce(0, +)
        let ranked = scores
            .map { MerchantMCCPosteriorCandidate(mcc: $0.key, probability: total > 0 ? $0.value / total : 0) }
            .sorted {
                if $0.probability == $1.probability { return $0.mcc < $1.mcc }
                return $0.probability > $1.probability
            }
        let confidence = ranked.first?.probability ?? 0
        let distinctSources = Set(applicable.compactMap(\.sourceFingerprint)).count
        let isConflicted = ranked.count > 1 && (ranked[0].probability - ranked[1].probability) <= 0.20

        let state: MerchantMCCPosteriorState
        if isConflicted {
            state = .conflicted
        } else if applicable.count >= 3, distinctSources >= 2, confidence >= 0.90 {
            state = .strongLearned
        } else if applicable.count >= 2, confidence >= 0.80 {
            state = .locationLearned
        } else {
            state = .priorOnly
        }

        return MerchantMCCPosterior(merchantId: seed.id, candidates: ranked,
                                    confidence: confidence, evidenceCount: applicable.count,
                                    state: state)
    }

    private static func scopeMatches(_ evidence: MerchantMCCRuntimeEvidence,
                                     locationKey: String?, network: String?, channel: String?) -> Bool {
        if let scoped = evidence.locationKey, scoped != locationKey { return false }
        if let scoped = evidence.network,
           scoped.caseInsensitiveCompare(network ?? "") != .orderedSame { return false }
        if let scoped = evidence.channel,
           scoped.caseInsensitiveCompare(channel ?? "") != .orderedSame { return false }
        return true
    }
}

public enum MerchantMCCRuntimeSeedCodec {
    public enum CodecError: Error { case invalidBase64, decompressionFailed }

    /// Decodes the checked-in zlib+base64 snapshot. A generous fixed output ceiling keeps the
    /// implementation deterministic; the current 500-row JSON is far below 2 MB and validation
    /// rejects malformed release artifacts before they reach the app.
    public static func decode(_ encoded: Data) throws -> MerchantMCCRuntimeSeed {
        guard let string = String(data: encoded, encoding: .utf8) else { throw CodecError.invalidBase64 }
        let compact = string.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let compressed = Data(base64Encoded: compact) else { throw CodecError.invalidBase64 }

        let capacity = 2_000_000
        var output = [UInt8](repeating: 0, count: capacity)
        let decodedCount = output.withUnsafeMutableBytes { destination -> Int in
            compressed.withUnsafeBytes { source -> Int in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(destinationBase, capacity, sourceBase,
                                                 compressed.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard decodedCount > 0 else { throw CodecError.decompressionFailed }
        let json = Data(output.prefix(decodedCount))
        return try JSONDecoder().decode(MerchantMCCRuntimeSeed.self, from: json)
    }
}
