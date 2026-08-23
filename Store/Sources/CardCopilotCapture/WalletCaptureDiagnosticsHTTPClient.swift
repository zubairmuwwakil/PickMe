import Foundation

public struct WalletSubmittedDiagnostic: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let expiresAt: Date
}

public actor WalletCaptureDiagnosticsHTTPClient {
    public typealias TokenProvider = @Sendable () async throws -> String?
    private let baseURL: URL
    private let tokenProvider: TokenProvider
    private let session: URLSession

    public init(baseURL: URL, tokenProvider: @escaping TokenProvider, session: URLSession = .shared) {
        self.baseURL = baseURL; self.tokenProvider = tokenProvider; self.session = session
    }

    public func submit(_ report: WalletCaptureDiagnosticReport) async throws -> WalletSubmittedDiagnostic {
        var request = try await request(path: "api/v1/wallet-capture-diagnostics")
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(report)
        let data = try await send(request)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
                let formatter = ISO8601DateFormatter(); formatter.formatOptions = options
                if let date = formatter.date(from: value) { return date }
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO date"))
        }
        return try decoder.decode(WalletSubmittedDiagnostic.self, from: data)
    }

    public func delete(id: String) async throws {
        var request = try await request(path: "api/v1/wallet-capture-diagnostics/\(id)")
        request.httpMethod = "DELETE"; _ = try await send(request)
    }

    public func list() async throws -> [WalletSubmittedDiagnostic] {
        var request = try await request(path: "api/v1/wallet-capture-diagnostics")
        request.httpMethod = "GET"
        let data = try await send(request)
        return try decoder().decode(ListResponse.self, from: data).reports
    }

    private func request(path: String) async throws -> URLRequest {
        guard let token = try await tokenProvider(), !token.isEmpty else { throw WalletCaptureError.credentialUnavailable }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return data
    }
    private struct ListResponse: Decodable { let reports: [WalletSubmittedDiagnostic] }
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
                let formatter = ISO8601DateFormatter(); formatter.formatOptions = options
                if let date = formatter.date(from: value) { return date }
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO date"))
        }
        return decoder
    }
}
