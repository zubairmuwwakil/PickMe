import Foundation

/// The same versioned envelope is sent to the review inbox or shared while signed out.
/// Only build metadata and the tester's words are required. Diagnostic attachments are opt-in.
public struct TesterReport: Codable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let reportID: String
    public let createdAt: Date
    public let appVersion: String
    public let buildNumber: String
    public let osVersion: String
    public let catalogueVersion: String?
    public let area: String
    public let expected: String
    public let actual: String
    public let steps: String
    public let counters: [String: Int]?
    public let walletCapture: WalletCaptureDiagnosticReport?
    public let includedArrivalDetails: Bool
    public let arrivalLog: String?
    public var id: String { reportID }

    public init(reportID: String = UUID().uuidString, createdAt: Date = .now,
                appVersion: String, buildNumber: String, osVersion: String,
                catalogueVersion: String? = nil, area: String, expected: String,
                actual: String, steps: String, counters: [String: Int]? = nil,
                walletCapture: WalletCaptureDiagnosticReport? = nil, arrivalLog: String? = nil) {
        schemaVersion = 1
        self.reportID = reportID; self.createdAt = createdAt
        self.appVersion = appVersion; self.buildNumber = buildNumber; self.osVersion = osVersion
        self.catalogueVersion = catalogueVersion; self.area = area
        self.expected = expected; self.actual = actual; self.steps = steps
        self.counters = counters; self.walletCapture = walletCapture
        self.arrivalLog = arrivalLog; includedArrivalDetails = arrivalLog != nil
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 900_000 else { throw TesterReportError.tooLarge }
        return data
    }
}

public enum TesterReportError: LocalizedError {
    case tooLarge
    case http(Int)
    public var errorDescription: String? {
        switch self {
        case .tooLarge: "The report is larger than 900 KB. Remove the arrival log and prepare it again."
        case .http(401): "Sign in again to send this report, or share the report file."
        case .http(400): "The server could not read this report. Share the report file so it can be investigated."
        case .http(409): "This report ID is already associated with another submission. Prepare a new report."
        case .http: "The report could not be delivered. Retry or share the report file."
        }
    }
}

public struct SubmittedTesterReport: Codable, Sendable, Identifiable {
    public let id: String
    public let expiresAt: Date
    public let clientReportId: String?
    public let status: String?
    public let resolvedInBuild: String?
}

public actor TesterReportHTTPClient {
    public typealias TokenProvider = @Sendable () async throws -> String?
    private let baseURL: URL
    private let tokenProvider: TokenProvider
    private let session: URLSession

    public init(baseURL: URL, tokenProvider: @escaping TokenProvider, session: URLSession = .shared) {
        self.baseURL = baseURL; self.tokenProvider = tokenProvider; self.session = session
    }

    public func submit(_ report: TesterReport) async throws -> SubmittedTesterReport {
        let data = try await send(method: "POST", body: report.encoded())
        return try decoder().decode(SubmittedTesterReport.self, from: data)
    }

    public func list() async throws -> [SubmittedTesterReport] {
        let data = try await send(method: "GET")
        return try decoder().decode(ListResponse.self, from: data).reports
    }

    public func delete(id: String) async throws {
        _ = try await send(method: "DELETE", id: id)
    }

    private struct ListResponse: Decodable { let reports: [SubmittedTesterReport] }

    private func send(method: String, id: String? = nil, body: Data? = nil) async throws -> Data {
        guard let token = try await tokenProvider(), !token.isEmpty else { throw TesterReportError.http(401) }
        var url = baseURL.appendingPathComponent("api/v1/tester-reports")
        if let id { url.appendPathComponent(id) }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard 200..<300 ~= response.statusCode else { throw TesterReportError.http(response.statusCode) }
        return data
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
                let formatter = ISO8601DateFormatter(); formatter.formatOptions = options
                if let date = formatter.date(from: value) { return date }
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid report date"))
        }
        return decoder
    }
}
