import Foundation

public enum GiftCardInventoryAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable
}

public enum GiftCardInventoryEvidenceSource: String, Codable, Equatable, Sendable {
    case ownerConfirmed
    case retailerConfirmed
    case communityObserved

    fileprivate var weight: Double {
        switch self {
        case .ownerConfirmed: return 1.0
        case .retailerConfirmed: return 0.90
        case .communityObserved: return 0.60
        }
    }
}

/// One location-specific observation about whether a merchant stocked a target gift card.
///
/// Inventory is deliberately separate from MCC evidence. A store coding as grocery says nothing
/// about what is on its gift-card rack, and an observation at one location says nothing about
/// another location of the same banner.
public struct GiftCardInventoryObservation: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let merchantKey: String
    public let placeID: String?
    public let latitude: Double?
    public let longitude: Double?
    public let instrumentKey: String
    public let availability: GiftCardInventoryAvailability
    public let source: GiftCardInventoryEvidenceSource
    public let sourceConfidence: Double
    public let observedAt: Date
    public let sourceReference: String?

    public init(id: String = UUID().uuidString,
                merchantKey: String,
                placeID: String? = nil,
                latitude: Double? = nil,
                longitude: Double? = nil,
                instrumentKey: String,
                availability: GiftCardInventoryAvailability,
                source: GiftCardInventoryEvidenceSource,
                sourceConfidence: Double = 1,
                observedAt: Date = Date(),
                sourceReference: String? = nil) {
        self.id = id
        self.merchantKey = GiftCardInventoryGraph.normalizedKey(merchantKey)
        self.placeID = placeID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.latitude = latitude?.isFinite == true ? latitude : nil
        self.longitude = longitude?.isFinite == true ? longitude : nil
        self.instrumentKey = GiftCardInventoryGraph.normalizedKey(instrumentKey)
        self.availability = availability
        self.source = source
        self.sourceConfidence = min(1, max(0, sourceConfidence))
        self.observedAt = observedAt
        self.sourceReference = sourceReference?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }
}

public struct GiftCardInventoryQuery: Equatable, Sendable {
    public let merchantKey: String
    public let placeID: String?
    public let latitude: Double?
    public let longitude: Double?
    public let instrumentKey: String

    public init(merchantKey: String,
                placeID: String? = nil,
                latitude: Double? = nil,
                longitude: Double? = nil,
                instrumentKey: String) {
        self.merchantKey = GiftCardInventoryGraph.normalizedKey(merchantKey)
        self.placeID = placeID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.latitude = latitude?.isFinite == true ? latitude : nil
        self.longitude = longitude?.isFinite == true ? longitude : nil
        self.instrumentKey = GiftCardInventoryGraph.normalizedKey(instrumentKey)
    }
}

public enum GiftCardInventoryState: String, Codable, Equatable, Sendable {
    case available
    case unavailable
    case unknown
}

public struct GiftCardInventoryPrediction: Equatable, Sendable {
    public let state: GiftCardInventoryState
    public let confidence: Double
    public let availableScore: Double
    public let unavailableScore: Double
    public let latestObservedAt: Date?
    public let observationCount: Int

    public var isActionableAvailable: Bool {
        state == .available && confidence >= GiftCardInventoryGraph.actionableConfidence
    }

    public static let unknown = GiftCardInventoryPrediction(
        state: .unknown,
        confidence: 0,
        availableScore: 0,
        unavailableScore: 0,
        latestObservedAt: nil,
        observationCount: 0)
}

/// Pure inventory resolver. Unlike MCC inference, this graph refuses brand-only evidence: a gift
/// card rack is terminal/location inventory and therefore needs an exact place id or a close
/// coordinate match.
public enum GiftCardInventoryGraph {
    public static let actionableConfidence = 0.55
    private static let coordinateMatchRadiusMeters = 175.0

    public static func predict(for query: GiftCardInventoryQuery,
                               evidence: [GiftCardInventoryObservation],
                               now: Date = Date()) -> GiftCardInventoryPrediction {
        guard !query.merchantKey.isEmpty, !query.instrumentKey.isEmpty else { return .unknown }

        var available = 0.0
        var unavailable = 0.0
        var latest: Date?
        var count = 0
        var seenIDs = Set<String>()

        for item in evidence {
            guard seenIDs.insert(item.id).inserted else { continue }
            guard item.merchantKey == query.merchantKey,
                  item.instrumentKey == query.instrumentKey,
                  locationMatches(query: query, evidence: item) else { continue }

            let ageWeight = freshnessWeight(availability: item.availability,
                                            observedAt: item.observedAt,
                                            now: now)
            let score = item.source.weight * item.sourceConfidence * ageWeight
            guard score > 0 else { continue }

            switch item.availability {
            case .available: available += score
            case .unavailable: unavailable += score
            }
            latest = max(latest ?? item.observedAt, item.observedAt)
            count += 1
        }

        let total = available + unavailable
        guard total > 0 else { return .unknown }

        let winningScore = max(available, unavailable)
        let agreement = winningScore / total
        let strength = 1 - exp(-winningScore)
        let confidence = min(0.99, agreement * strength)

        let state: GiftCardInventoryState
        if confidence < actionableConfidence {
            state = .unknown
        } else if available > unavailable {
            state = .available
        } else if unavailable > available {
            state = .unavailable
        } else {
            state = .unknown
        }

        return GiftCardInventoryPrediction(state: state,
                                           confidence: confidence,
                                           availableScore: available,
                                           unavailableScore: unavailable,
                                           latestObservedAt: latest,
                                           observationCount: count)
    }

    fileprivate static func normalizedKey(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                   locale: Locale(identifier: "en_CA"))
        let pieces = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
        }
        return String(pieces).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func locationMatches(query: GiftCardInventoryQuery,
                                        evidence: GiftCardInventoryObservation) -> Bool {
        if let queryPlaceID = query.placeID, let evidencePlaceID = evidence.placeID {
            return queryPlaceID == evidencePlaceID
        }

        guard let qLat = query.latitude, let qLon = query.longitude,
              let eLat = evidence.latitude, let eLon = evidence.longitude else {
            // No brand-wide inventory inference. Location identity is mandatory.
            return false
        }
        return distanceMeters(lat1: qLat, lon1: qLon, lat2: eLat, lon2: eLon)
            <= coordinateMatchRadiusMeters
    }

    private static func freshnessWeight(availability: GiftCardInventoryAvailability,
                                        observedAt: Date,
                                        now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(observedAt) / 86_400)
        // Positive sightings describe a stocked gift-card rack and decay over weeks. A miss can be
        // a one-day stockout, so negative evidence deliberately loses authority much faster.
        let halfLifeDays = availability == .available ? 30.0 : 3.0
        let floor = availability == .available ? 0.03 : 0.01
        return max(floor, pow(0.5, days / halfLifeDays))
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

/// Small versioned local log for inventory feedback. Purchase history stays in SwiftData; volatile
/// gift-card rack observations stay independent so adding this learner does not force a migration
/// of durable financial records. The envelope is intentionally upload-friendly for a future
/// opt-in de-identified community aggregator.
public actor GiftCardInventoryObservationStore {
    public static let shared = GiftCardInventoryObservationStore()

    private struct Envelope: Codable {
        let schemaVersion: Int
        var observations: [GiftCardInventoryObservation]
    }

    private let defaults: UserDefaults
    private let storageKey: String

    public init(suiteName: String? = nil,
                storageKey: String = "pickme.giftCardInventory.v1") {
        if let suiteName, let scoped = UserDefaults(suiteName: suiteName) {
            self.defaults = scoped
        } else {
            self.defaults = .standard
        }
        self.storageKey = storageKey
    }

    public func observations() -> [GiftCardInventoryObservation] {
        guard let data = defaults.data(forKey: storageKey),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == 1 else { return [] }
        return envelope.observations
    }

    @discardableResult
    public func record(merchantKey: String,
                       placeID: String?,
                       latitude: Double?,
                       longitude: Double?,
                       instrumentKey: String,
                       availability: GiftCardInventoryAvailability,
                       observedAt: Date = Date()) -> GiftCardInventoryObservation {
        let item = GiftCardInventoryObservation(
            merchantKey: merchantKey,
            placeID: placeID,
            latitude: latitude,
            longitude: longitude,
            instrumentKey: instrumentKey,
            availability: availability,
            source: .ownerConfirmed,
            sourceConfidence: 1,
            observedAt: observedAt)
        var current = observations()
        current.append(item)
        if let data = try? JSONEncoder().encode(Envelope(schemaVersion: 1, observations: current)) {
            defaults.set(data, forKey: storageKey)
        }
        return item
    }

    public func removeAllForTesting() {
        defaults.removeObject(forKey: storageKey)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
