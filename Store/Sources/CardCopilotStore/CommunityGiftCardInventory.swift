import Foundation

/// Explicit privacy gate for community gift-card inventory. Off is the only implicit/default state.
/// Enabling this does not require a PickMe account and never changes local-only inventory learning.
public struct CommunityGiftCardInventorySettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(suiteName: String? = nil,
                key: String = "pickme.communityGiftCardInventory.enabled.v1") {
        if let suiteName, let scoped = UserDefaults(suiteName: suiteName) {
            self.defaults = scoped
        } else {
            self.defaults = .standard
        }
        self.key = key
    }

    public var isEnabled: Bool { defaults.bool(forKey: key) }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
        if !enabled {
            CommunityGiftCardInventoryCacheStore().replace([])
        }
    }
}

/// Volatile community evidence is kept separate from the owner's append-only local confirmations.
/// It is safe to replace wholesale after each nearby query and is cleared immediately on opt-out.
public struct CommunityGiftCardInventoryCacheStore: @unchecked Sendable {
    private struct Envelope: Codable {
        let schemaVersion: Int
        let evidence: [GiftCardInventoryObservation]
        let refreshedAt: Date
    }

    private let defaults: UserDefaults
    private let key: String

    public init(suiteName: String? = nil,
                key: String = "pickme.communityGiftCardInventory.cache.v1") {
        if let suiteName, let scoped = UserDefaults(suiteName: suiteName) {
            self.defaults = scoped
        } else {
            self.defaults = .standard
        }
        self.key = key
    }

    public func evidence(now: Date = Date()) -> [GiftCardInventoryObservation] {
        guard CommunityGiftCardInventorySettingsStore().isEnabled,
              let data = defaults.data(forKey: key),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == 1,
              now.timeIntervalSince(envelope.refreshedAt) <= 6 * 60 * 60 else {
            return []
        }
        return envelope.evidence
    }

    public func replace(_ evidence: [GiftCardInventoryObservation], now: Date = Date()) {
        if evidence.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        let communityOnly = evidence.filter { $0.source == .communityObserved }
        guard let data = try? JSONEncoder().encode(
            Envelope(schemaVersion: 1, evidence: communityOnly, refreshedAt: now)) else { return }
        defaults.set(data, forKey: key)
    }
}

public enum CommunityGiftCardInventoryClientError: Error, Equatable {
    case missingPhysicalLocation
    case invalidResponse
    case serverStatus(Int)
}

/// Anonymous transport for the evidence model owned by `GiftCardInventoryGraph`.
///
/// Privacy boundary: requests contain only merchant/store identity, the target gift-card label,
/// found/not-found, time, and an idempotency UUID. If an Apple place id exists, coordinates are
/// omitted entirely. No card, amount, purchase, account, login, or device identifier is accepted.
public actor CommunityGiftCardInventoryClient {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func submit(_ observation: GiftCardInventoryObservation) async throws {
        guard observation.source == .ownerConfirmed else { return }
        let data = try CommunityGiftCardInventoryWire.submissionData(for: observation)
        let endpoint = baseURL.appendingPathComponent("api/community/gift-card-inventory")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CommunityGiftCardInventoryClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CommunityGiftCardInventoryClientError.serverStatus(http.statusCode)
        }
    }

    /// Fetches only evidence for nearby physical merchants already returned by MapKit. Candidate
    /// lists are capped to 25 by the server contract and deduplicated by physical location here.
    public func evidence(instrumentKey: String,
                         nearby places: [NearbyPlace]) async throws -> [GiftCardInventoryObservation] {
        let candidates = CommunityGiftCardInventoryWire.candidates(from: places)
        guard !candidates.isEmpty else { return [] }
        let body = try CommunityGiftCardInventoryWire.queryData(instrumentKey: instrumentKey,
                                                                 candidates: candidates)
        let endpoint = baseURL.appendingPathComponent("api/community/gift-card-inventory/query")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CommunityGiftCardInventoryClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CommunityGiftCardInventoryClientError.serverStatus(http.statusCode)
        }
        return try CommunityGiftCardInventoryWire.decodeEvidence(data,
                                                                  instrumentKey: instrumentKey)
    }
}

enum CommunityGiftCardInventoryWire {
    struct Submission: Encodable {
        let schemaVersion = 1
        let observationId: String
        let merchantKey: String
        let placeId: String?
        let latitude: Double?
        let longitude: Double?
        let instrumentKey: String
        let availability: String
        let observedAt: Date
    }

    struct Candidate: Codable, Equatable, Hashable {
        let merchantKey: String
        let placeId: String?
        let latitude: Double?
        let longitude: Double?

        var identity: String {
            if let placeId { return "p:\(placeId)" }
            return String(format: "c:%@:%0.4f:%0.4f",
                          merchantKey, latitude ?? 0, longitude ?? 0)
        }
    }

    struct Query: Encodable {
        let schemaVersion = 1
        let instrumentKey: String
        let candidates: [Candidate]
    }

    struct QueryResponse: Decodable {
        let schemaVersion: Int
        let signals: [Signal]
    }

    struct Signal: Decodable {
        let candidateKey: String
        let merchantKey: String
        let placeId: String?
        let latitude: Double?
        let longitude: Double?
        let day: String
        let availableUnits: Int
        let unavailableUnits: Int
    }

    static func submissionData(for observation: GiftCardInventoryObservation) throws -> Data {
        let hasPlaceID = observation.placeID != nil
        guard hasPlaceID || (observation.latitude != nil && observation.longitude != nil) else {
            throw CommunityGiftCardInventoryClientError.missingPhysicalLocation
        }
        let submission = Submission(
            observationId: observation.id,
            merchantKey: observation.merchantKey,
            placeId: observation.placeID,
            latitude: hasPlaceID ? nil : observation.latitude.map(roundCoordinate),
            longitude: hasPlaceID ? nil : observation.longitude.map(roundCoordinate),
            instrumentKey: observation.instrumentKey,
            availability: observation.availability.rawValue,
            observedAt: observation.observedAt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(submission)
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
                merchantKey: seed.merchant.name,
                placeId: place.placeID,
                latitude: hasPlaceID ? nil : roundCoordinate(place.latitude),
                longitude: hasPlaceID ? nil : roundCoordinate(place.longitude))
            guard seen.insert(candidate.identity).inserted else { continue }
            result.append(candidate)
        }
        return result
    }

    static func queryData(instrumentKey: String, candidates: [Candidate]) throws -> Data {
        try JSONEncoder().encode(Query(instrumentKey: instrumentKey,
                                       candidates: Array(candidates.prefix(25))))
    }

    static func decodeEvidence(_ data: Data,
                               instrumentKey: String) throws -> [GiftCardInventoryObservation] {
        let response = try JSONDecoder().decode(QueryResponse.self, from: data)
        guard response.schemaVersion == 1 else {
            throw CommunityGiftCardInventoryClientError.invalidResponse
        }
        var evidence: [GiftCardInventoryObservation] = []
        for signal in response.signals {
            guard let observedAt = ISO8601DateFormatter().date(from: "\(signal.day)T12:00:00Z") else {
                continue
            }
            let available = max(0, min(3, signal.availableUnits))
            let unavailable = max(0, min(3, signal.unavailableUnits))
            for index in 0..<available {
                evidence.append(observation(signal: signal,
                                            instrumentKey: instrumentKey,
                                            availability: .available,
                                            unit: index,
                                            observedAt: observedAt))
            }
            for index in 0..<unavailable {
                evidence.append(observation(signal: signal,
                                            instrumentKey: instrumentKey,
                                            availability: .unavailable,
                                            unit: index,
                                            observedAt: observedAt))
            }
        }
        return evidence
    }

    private static func observation(signal: Signal,
                                    instrumentKey: String,
                                    availability: GiftCardInventoryAvailability,
                                    unit: Int,
                                    observedAt: Date) -> GiftCardInventoryObservation {
        GiftCardInventoryObservation(
            id: "community:\(signal.candidateKey):\(signal.day):\(availability.rawValue):\(unit)",
            merchantKey: signal.merchantKey,
            placeID: signal.placeId,
            latitude: signal.latitude,
            longitude: signal.longitude,
            instrumentKey: instrumentKey,
            availability: availability,
            source: .communityObserved,
            sourceConfidence: 1,
            observedAt: observedAt,
            sourceReference: "community-daily-aggregate-v1")
    }

    private static func roundCoordinate(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }
}
