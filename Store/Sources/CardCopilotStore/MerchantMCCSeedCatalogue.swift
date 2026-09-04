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
    private static let merchantById: [String: MerchantMCCSeedMerchant] =
        Dictionary(uniqueKeysWithValues: merchants.map { ($0.id, $0) })

    /// Resolves a MapKit/Wallet merchant name through the curated merchant recognizer first, then
    /// performs exact normalized seed-name matching. The exact fallback expands coverage to the
    /// 500-row graph without reintroducing substring failures such as Metro -> Metropolitan Hotel.
    public static func match(merchantName: String) -> MerchantMCCSeedMatch? {
        let recognized = MerchantRecognizer.recognise(merchantName)
        let canonicalName = recognized?.name ?? merchantName
        guard let merchant = merchantByNormalizedName[normalized(canonicalName)],
              let profile = profiles[merchant.profile] else { return nil }
        return MerchantMCCSeedMatch(merchant: merchant, profile: profile,
                                    recognizedMerchant: recognized)
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

    private static var generatedDate: Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: manifest.generatedAt) ?? Date(timeIntervalSince1970: 0)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive],
                      locale: Locale(identifier: "en_CA"))
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
            .split(whereSeparator: { $0 == " " })
            .map(String.init)
            .joined(separator: " ")
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
