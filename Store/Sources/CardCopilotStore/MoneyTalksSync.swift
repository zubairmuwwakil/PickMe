import Foundation
import CardCopilotEngine

/// The wire format deliberately uses integer minor units. The engine continues to use its
/// existing CAD-unit cap progress internally, so conversion happens at this boundary only.
public struct SpineCap: Codable, Equatable, Sendable {
    public let usedMinor: Int
    public let periodKey: String

    public init(usedMinor: Int, periodKey: String) {
        self.usedMinor = usedMinor
        self.periodKey = periodKey
    }
}

public struct WalletFeedback: Codable, Equatable, Sendable, Identifiable {
    public let eventId: String
    public let capturedAt: Date
    public let merchantRaw: String?
    public let amountMinor: Int?
    public let currency: String?
    public let cardRaw: String?
    public let verdict: String
    public let warning: String?

    public var id: String { eventId }
}

public struct SpineSnapshot: Sendable {
    public let caps: [String: SpineCap]
    public let feedback: [WalletFeedback]
}

public struct WalletInstallation: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let createdAt: Date
    public let revokedAt: Date?
    /// Present only in the create response. It must never be persisted by the app.
    public let token: String?
}

public enum MoneyTalksAPIError: Error, LocalizedError {
    case unavailableConfiguration
    case unauthenticated
    case unexpectedResponse(Int)

    public var errorDescription: String? {
        switch self {
        case .unavailableConfiguration: "MoneyTalks sync has not been configured."
        case .unauthenticated: "Sign in to sync with MoneyTalks."
        case .unexpectedResponse(let status): "MoneyTalks returned HTTP \(status)."
        }
    }
}

/// A deliberately narrow authenticated client for the purchase spine. It owns no app state and
/// exposes only the three routes PickMe needs, keeping the checkout engine network-free.
public actor MoneyTalksAPIClient {
    public typealias TokenProvider = @Sendable () async throws -> String?

    private let baseURL: URL
    private let tokenProvider: TokenProvider
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(baseURL: URL, tokenProvider: @escaping TokenProvider,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func fetchSnapshot() async throws -> SpineSnapshot {
        async let caps: CapsResponse = get("api/spine/caps")
        async let feedback: FeedbackResponse = get("api/spine/feedback")
        return try await SpineSnapshot(caps: caps.caps, feedback: feedback.feedback)
    }

    public func createWalletInstallation(label: String) async throws -> WalletInstallation {
        var request = try await authenticatedRequest(path: "api/v1/wallet-installations")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["label": label])
        return try await send(request)
    }

    private func get<Response: Decodable>(_ path: String) async throws -> Response {
        var request = try await authenticatedRequest(path: path)
        request.httpMethod = "GET"
        return try await send(request)
    }

    private func authenticatedRequest(path: String) async throws -> URLRequest {
        guard let token = try await tokenProvider(), !token.isEmpty else {
            throw MoneyTalksAPIError.unauthenticated
        }
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw MoneyTalksAPIError.unavailableConfiguration
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MoneyTalksAPIError.unexpectedResponse(-1) }
        guard 200..<300 ~= http.statusCode else { throw MoneyTalksAPIError.unexpectedResponse(http.statusCode) }
        return try decoder.decode(Response.self, from: data)
    }

    private struct CapsResponse: Decodable { let caps: [String: SpineCap] }
    private struct FeedbackResponse: Decodable { let feedback: [WalletFeedback] }
}

public struct OwnerStateSyncResult: Sendable {
    public let ownerState: OwnerState
    public let feedback: [WalletFeedback]
    public let lastSyncedAt: Date
}

/// Sync owns the conversion from the server's minor-unit read model to the engine's existing
/// OwnerState. It never clears locally available cap progress when a remote call fails.
public actor OwnerStateSyncService {
    private let client: MoneyTalksAPIClient

    public init(client: MoneyTalksAPIClient) {
        self.client = client
    }

    public func sync(ownerState: OwnerState, catalogue: Catalogue, now: Date = Date()) async throws -> OwnerStateSyncResult {
        let snapshot = try await client.fetchSnapshot()
        return OwnerStateSyncResult(ownerState: Self.merging(snapshot.caps, into: ownerState, catalogue: catalogue),
                                    feedback: snapshot.feedback, lastSyncedAt: now)
    }

    public static func merging(_ remoteCaps: [String: SpineCap], into ownerState: OwnerState,
                               catalogue: Catalogue) -> OwnerState {
        var merged = ownerState
        for card in catalogue.cards {
            let capIDs = Set(card.caps.map(\.capId))
            let matching = remoteCaps.filter { capIDs.contains($0.key) }
            guard !matching.isEmpty else { continue }
            var state = merged.cardStates[card.cardId] ?? CardState()
            var capProgress = state.capProgress ?? [:]
            for (capID, cap) in matching {
                capProgress[capID] = Double(cap.usedMinor) / 100
            }
            state.capProgress = capProgress
            merged.cardStates[card.cardId] = state
        }
        return merged
    }
}
