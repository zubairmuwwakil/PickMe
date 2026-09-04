import Foundation
import CardCopilotEngine

/// Runtime view of the canonical, sharded Canada merchant-MCC seed under `contracts/`.
///
/// The files bundled into Store are byte-identical copies maintained by
/// `scripts/sync-merchant-mcc-graph-into-store.sh`. Seed values are editorial priors only: they
/// bootstrap the graph but never become an observed MCC merely by being present here.
public struct MerchantMCCSeedProfile: Codable, Equatable, Sendable {
    public let primaryMcc: Int
    public let candidateMccs: [Int]
    public let weights: [Double]
    public let confidence: Double
    public let basis: String
}

public struct MerchantMCCSeedMerchant: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let tier: String
    public let category: String
    public let profile: String
}

public struct MerchantMCCSeedMatch: Equatable, Sendable {
    public let merchant: MerchantMCCSeedMerchant
    public let profile: MerchantMCCSeedProfile
    public let recognizedMerchant: PreIndexedMerchant?

    public var acceptedNetworks: Set<Network> {
        recognizedMerchant?.acceptedNetworks ?? [.amex, .visa, .mastercard]
    }

    public var merchantBrand: String? { recognizedMerchant?.merchantBrand }
}

public enum MerchantMCCSeedCatalogue {
    private struct Manifest: Decodable {
        struct Files: Decodable { let merchantShards: [String] }
        let graphVersion: String
        let generatedAt: String
        let files: Files
    }

    private struct SeedObservation: Decodable {
        struct Scope: Decodable { let channel: String? }
        let id: String
        let merchantId: String
        let mcc: Int
        let sourceType: String
        let sourceUrl: String?
        let confidence: Double
        let scope: Scope
    }

    private static let manifest: Manifest = decodeResource("merchant-mcc-manifest")
    public static let profiles: [String: MerchantMCCSeedProfile] =
        decodeResource("merchant-mcc-profiles")
    private static let observations: [SeedObservation] = decodeResource("merchant-mcc-observations")

    /// All 500 canonical Canada seed merchants, decoded once at process startup.
    public static let merchants: [MerchantMCCSeedMerchant] = {
        manifest.files.merchantShards.flatMap { filename -> [MerchantMCCSeedMerchant] in
            let stem = filename.hasSuffix(".json") ? String(filename.dropLast(5)) : filename
            return decodeResource("merchant-mcc-\(stem)")
        }
    }()

    public static var graphVersion: String { manifest.graphVersion }

    private static let merchantByNormalizedName: [String: MerchantMCCSeedMerchant] = {
        var result: [String: MerchantMCCSeedMerchant] = [:]
        for merchant in merchants { result[normalized(merchant.name)] = merchant }
        return result
    }()

    private static let merchantByID: [String: MerchantMCCSeedMerchant] =
        Dictionary(uniqueKeysWithValues: merchants.map { ($0.id, $0) })

    /// Multi-word seed names used for a conservative descriptor fallback. One-word brands are not
    /// allowed to expand this way: `Metro Pizza` must never become `Metro`. Curated one-word alias
    /// handling remains MerchantRecognizer's job.
    private static let descriptorTokenIndex: [(merchant: MerchantMCCSeedMerchant, tokens: [String])] =
        merchants.compactMap { merchant in
            let merchantTokens = tokens(merchant.name)
            guard merchantTokens.count >= 2 else { return nil }
            return (merchant, merchantTokens)
        }

    /// Resolves a MapKit/Wallet merchant name through deterministic catalogue evidence first. If
    /// that fails, an exact alias learned from repeated real Wallet-to-checkout joins may resolve
    /// it. Learned aliases never participate in fuzzy matching and never override curated data.
    public static func match(merchantName: String) -> MerchantMCCSeedMatch? {
        canonicalMatch(merchantName: merchantName)
            ?? MerchantMCCIdentityLearningStore.shared.match(merchantName: merchantName)
    }

    /// Deterministic resolver with no learned state. The identity learner uses this to anchor new
    /// aliases without recursively consulting itself.
    public static func canonicalMatch(merchantName: String) -> MerchantMCCSeedMatch? {
        let recognized = MerchantRecognizer.recognise(merchantName)
        let canonicalName = recognized?.name ?? merchantName

        if let merchant = merchantByNormalizedName[normalized(canonicalName)],
           let profile = profiles[merchant.profile] {
            return MerchantMCCSeedMatch(merchant: merchant, profile: profile,
                                        recognizedMerchant: recognized)
        }

        guard recognized == nil,
              let merchant = descriptorMatch(merchantName),
              let profile = profiles[merchant.profile] else { return nil }
        return MerchantMCCSeedMatch(merchant: merchant, profile: profile,
                                    recognizedMerchant: nil)
    }

    /// Stable seed-id lookup used after a learned alias has already settled identity.
    public static func match(merchantID: String) -> MerchantMCCSeedMatch? {
        guard let merchant = merchantByID[merchantID],
              let profile = profiles[merchant.profile] else { return nil }
        return MerchantMCCSeedMatch(merchant: merchant, profile: profile,
                                    recognizedMerchant: MerchantRecognizer.recognise(merchant.name))
    }

    public static func seedMCC(for merchantName: String) -> Int? {
        match(merchantName: merchantName)?.profile.primaryMcc
    }

    /// Low-confidence public location reports bundled with the seed become external graph evidence,
    /// not direct observations. Address text is intentionally not fabricated into coordinates.
    public static func externalEvidence(for merchant: MerchantMCCSeedMerchant) -> [MerchantMCCEvidence] {
        let date = generatedDate
        return observations.compactMap { observation in
            guard observation.merchantId == merchant.id,
                  observation.sourceType == "community_directory_location" else { return nil }
            let channel: MerchantMCCChannel
            switch observation.scope.channel?.lowercased() {
            case "instore": channel = .inStore
            case "online": channel = .online
            case "app": channel = .app
            default: channel = .unknown
            }
            return MerchantMCCEvidence(
                id: "seed:\(observation.id)", merchantKey: merchant.name,
                channel: channel, mcc: observation.mcc,
                kind: .externalLocationReport,
                sourceConfidence: observation.confidence,
                observedAt: date,
                sourceReference: observation.sourceUrl)
        }
    }

    private static func descriptorMatch(_ value: String) -> MerchantMCCSeedMerchant? {
        let haystack = tokens(value)
        guard !haystack.isEmpty else { return nil }

        var best: (merchant: MerchantMCCSeedMerchant, length: Int)?
        var tiedAtBestLength = false
        for entry in descriptorTokenIndex where contains(haystack, entry.tokens) {
            if best == nil || entry.tokens.count > best!.length {
                best = (entry.merchant, entry.tokens.count)
                tiedAtBestLength = false
            } else if entry.tokens.count == best!.length,
                      entry.merchant.id != best!.merchant.id {
                tiedAtBestLength = true
            }
        }
        guard !tiedAtBestLength else { return nil }
        return best?.merchant
    }

    private static var generatedDate: Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: manifest.generatedAt) ?? Date(timeIntervalSince1970: 0)
    }

    private static func normalized(_ value: String) -> String {
        tokens(value).joined(separator: " ")
    }

    private static func tokens(_ value: String) -> [String] {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive],
                      locale: Locale(identifier: "en_CA"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func contains(_ haystack: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count)
        where Array(haystack[start..<(start + needle.count)]) == needle {
            return true
        }
        return false
    }

    private static func decodeResource<T: Decodable>(_ name: String) -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            preconditionFailure("Bundled MCC graph resource missing: \(name).json")
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            preconditionFailure("Bundled MCC graph resource unreadable: \(name).json: \(error)")
        }
    }
}
