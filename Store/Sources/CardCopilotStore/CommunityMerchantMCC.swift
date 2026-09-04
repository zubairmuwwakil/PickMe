import Foundation

/// Explicit privacy gate for shared merchant-MCC evidence. Local learning always remains enabled;
/// this setting controls only network upload/download of anonymous aggregates.
public struct CommunityMerchantMCCSettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(suiteName: String? = nil,
                key: String = "pickme.communityMerchantMCC.enabled.v1") {
        if let suiteName, let scoped = UserDefaults(suiteName: suiteName) {
            defaults = scoped
        } else {
            defaults = .standard
        }
        self.key = key
    }

    public var isEnabled: Bool { defaults.bool(forKey: key) }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
        if !enabled { CommunityMerchantMCCCacheStore().replace([]) }
    }
}

/// Community MCCs are volatile external evidence, never merged into the owner's append-only local
/// observations. The cache expires quickly and disappears immediately when sharing is disabled.
public struct CommunityMerchantMCCCacheStore: @unchecked Sendable {
    private struct Envelope: Codable {
        let schemaVersion: Int
        let evidence: [MerchantMCCEvidence]
        let refreshedAt: Date
    }

    private let defaults: UserDefaults
    private let key: String

    public init(suiteName: String? = nil,
                key: String = "pickme.communityMerchantMCC.cache.v1") {
        if let suiteName, let scoped = UserDefaults(suiteName: suiteName) {
            defaults = scoped
        } else {
            defaults = .standard
        }
        self.key = key
    }

    public func evidence(now: Date = Date()) -> [MerchantMCCEvidence] {
        guard CommunityMerchantMCCSettingsStore().isEnabled,
              let data = defaults.data(forKey: key),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == 1,
              now.timeIntervalSince(envelope.refreshedAt) <= 6 * 60 * 60 else { return [] }
        return envelope.evidence.filter {
            $0.kind == .externalLocationReport
                && $0.sourceReference?.hasPrefix("community-mcc-v1:") == true
        }
    }

    public func replace(_ evidence: [MerchantMCCEvidence], now: Date = Date()) {
        if evidence.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        let communityOnly = evidence.filter {
            $0.kind == .externalLocationReport
                && $0.sourceReference?.hasPrefix("community-mcc-v1:") == true
        }
        guard let data = try? JSONEncoder().encode(
            Envelope(schemaVersion: 1, evidence: communityOnly, refreshedAt: now)) else { return }
        defaults.set(data, forKey: key)
    }
}

public enum CommunityMerchantMCCClientError: Error, Equatable {
    case invalidResponse
    case serverStatus(Int)
}

/// A privacy-minimal upload created only from an explicit owner-observed literal MCC.
/// Card id, amount, Wallet descriptor, account, user id and device id are intentionally absent.
public struct CommunityMerchantMCCReport: Equatable, Sendable {
    public let observationID: UUID
    public let merchantID: String
    public let latitude: Double
    public let longitude: Double
    public let network: String?
    public let mcc: Int
    public let observedAt: Date
}

public actor CommunityMerchantMCCClient {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func submit(_ report: CommunityMerchantMCCReport) async throws {
        let endpoint = baseURL.appendingPathComponent("api/community/merchant-mcc")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try CommunityMerchantMCCWire.submissionData(report)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CommunityMerchantMCCClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CommunityMerchantMCCClientError.serverStatus(http.statusCode)
        }
    }

    public func evidence(nearby places: [NearbyPlace]) async throws -> [MerchantMCCEvidence] {
        let candidates = CommunityMerchantMCCWire.candidates(from: places)
        guard !candidates.isEmpty else { return [] }
        let endpoint = baseURL.appendingPathComponent("api/community/merchant-mcc/query")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try CommunityMerchantMCCWire.queryData(candidates: candidates)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CommunityMerchantMCCClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CommunityMerchantMCCClientError.serverStatus(http.statusCode)
        }
        return try CommunityMerchantMCCWire.decodeEvidence(data)
    }
}

enum CommunityMerchantMCCWire {
    struct Submission: Encodable {
        let schemaVersion = 1
        let observationId: String
        let merchantId: String
        let latitude: Double
        let longitude: Double
        let channel = "inStore"
        let network: String?
        let mcc: Int
        let observedAt: Date
    }

    struct Candidate: Codable, Equatable, Hashable {
        let merchantId: String
        let placeId: String?
        let latitude: Double?
        let longitude: Double?
        let channel: String

        var identity: String {
            if let placeId { return "p:\(placeId)|\(channel)" }
            return String(format: "c:%@:%0.4f:%0.4f|%@",
                          merchantId, latitude ?? 0, longitude ?? 0, channel)
        }
    }

    struct Query: Encodable {
        let schemaVersion = 1
        let candidates: [Candidate]
    }

    struct QueryResponse: Decodable {
        let schemaVersion: Int
        let signals: [Signal]
    }

    struct Signal: Decodable {
        let candidateKey: String
        let merchantId: String
        let placeId: String?
        let latitude: Double?
        let longitude: Double?
        let channel: String
        let network: String?
        let mcc: Int
        let supportDays: Int
        let supportUnits: Int
        let totalUnits: Int
        let confidence: Double
        let latestDay: String
    }

    static func report(from purchase: StoredPurchase, network: String?) -> CommunityMerchantMCCReport? {
        guard let observation = purchase.observation,
              let mcc = observation.observedMerchantCategoryCode,
              purchase.hasPreciseLocation,
              let latitude = purchase.merchantLatitude,
              let longitude = purchase.merchantLongitude,
              let seed = MerchantMCCSeedCatalogue.match(merchantName: purchase.displayMerchant)
        else { return nil }
        return CommunityMerchantMCCReport(
            observationID: observation.id,
            merchantID: seed.merchant.id,
            latitude: latitude,
            longitude: longitude,
            network: network?.lowercased(),
            mcc: mcc,
            observedAt: observation.confirmedAt)
    }

    static func submissionData(_ report: CommunityMerchantMCCReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Submission(
            observationId: report.observationID.uuidString,
            merchantId: report.merchantID,
            latitude: roundCoordinate(report.latitude),
            longitude: roundCoordinate(report.longitude),
            network: report.network,
            mcc: report.mcc,
            observedAt: report.observedAt))
    }

    static func candidates(from places: [NearbyPlace]) -> [Candidate] {
        var seen = Set<String>()
        var result: [Candidate] = []
        for place in places {
            guard result.count < 25,
                  let seed = MerchantMCCSeedCatalogue.match(merchantName: place.name) else { continue }
            let hasPlaceID = place.placeID != nil
            guard hasPlaceID || place.hasMonitorableLocation else { continue }
            let candidate = Candidate(
                merchantId: seed.merchant.id,
                placeId: place.placeID,
                latitude: hasPlaceID ? nil : roundCoordinate(place.latitude),
                longitude: hasPlaceID ? nil : roundCoordinate(place.longitude),
                channel: "inStore")
            guard seen.insert(candidate.identity).inserted else { continue }
            result.append(candidate)
        }
        return result
    }

    static func queryData(candidates: [Candidate]) throws -> Data {
        try JSONEncoder().encode(Query(candidates: Array(candidates.prefix(25))))
    }

    static func decodeEvidence(_ data: Data) throws -> [MerchantMCCEvidence] {
        let response = try JSONDecoder().decode(QueryResponse.self, from: data)
        guard response.schemaVersion == 1 else {
            throw CommunityMerchantMCCClientError.invalidResponse
        }
        return response.signals.compactMap { signal in
            guard let seed = MerchantMCCSeedCatalogue.match(merchantID: signal.merchantId),
                  (0...9999).contains(signal.mcc),
                  signal.supportDays >= 3,
                  signal.supportUnits > 0,
                  signal.totalUnits >= signal.supportUnits,
                  let observedAt = ISO8601DateFormatter().date(from: "\(signal.latestDay)T12:00:00Z")
            else { return nil }
            let channel: MerchantMCCChannel
            switch signal.channel {
            case "inStore": channel = .inStore
            case "online": channel = .online
            case "app": channel = .app
            default: channel = .unknown
            }
            // Shared evidence must remain weaker than owner evidence. Three-day corroboration starts
            // at roughly half strength and rises slowly; even a unanimous community signal stays an
            // external prior and can never make MerchantMCCPrediction.isTrusted true.
            let supportStrength = min(0.80, 0.50 + 0.08 * Double(max(0, signal.supportDays - 3)))
            let sourceConfidence = min(0.80, max(0, signal.confidence) * supportStrength)
            return MerchantMCCEvidence(
                id: "community-mcc:\(signal.candidateKey):\(signal.network ?? "unknown"):\(signal.mcc):\(signal.latestDay)",
                merchantKey: seed.merchant.name,
                placeID: signal.placeId,
                latitude: signal.latitude,
                longitude: signal.longitude,
                channel: channel,
                network: signal.network,
                mcc: signal.mcc,
                kind: .externalLocationReport,
                sourceConfidence: sourceConfidence,
                observedAt: observedAt,
                sourceReference: "community-mcc-v1:\(signal.supportDays)d:\(signal.supportUnits)/\(signal.totalUnits)")
        }
    }

    private static func roundCoordinate(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }
}
