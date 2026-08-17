import XCTest
import SwiftData
@testable import CardCopilotStore

/// Stubs the network at the URLProtocol seam so the delete-account request can be inspected as
/// the wire sees it. `URLProtocol` moves `httpBody` onto `httpBodyStream`, so the body is read
/// back from the stream rather than the property.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var capturedRequest: URLRequest?
    nonisolated(unsafe) static var capturedBody: Data?

    static func reset(status: Int = 200) {
        self.status = status
        capturedRequest = nil
        capturedBody = nil
    }

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedRequest = request
        Self.capturedBody = request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return data
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"ok\":true,\"scope\":\"account\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class AccountDeletionTests: XCTestCase {
    private let baseURL = URL(string: "https://example.test/")!

    private func client(token: String?) -> MoneyTalksAPIClient {
        MoneyTalksAPIClient(baseURL: baseURL, tokenProvider: { token }, session: StubURLProtocol.session)
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    func testDeleteAccountAsksTheServerForTheAccountScope() async throws {
        try await client(token: "session-jwt").deleteAccount()

        let request = try XCTUnwrap(StubURLProtocol.capturedRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/data/delete")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-jwt")

        let body = try JSONSerialization.jsonObject(
            with: try XCTUnwrap(StubURLProtocol.capturedBody)) as? [String: String]
        // Scope matters: the same route wipes data without touching the account when it is absent.
        XCTAssertEqual(body?["scope"], "account")
    }

    func testDeleteAccountRefusesWithoutASignedInSession() async {
        do {
            try await client(token: nil).deleteAccount()
            XCTFail("Deleting an account without a session must not reach the network")
        } catch MoneyTalksAPIError.unauthenticated {
            XCTAssertNil(StubURLProtocol.capturedRequest)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDeleteAccountSurfacesAServerFailureRatherThanReportingSuccess() async {
        StubURLProtocol.reset(status: 500)
        do {
            try await client(token: "session-jwt").deleteAccount()
            XCTFail("A failed deletion must not be reported as done")
        } catch MoneyTalksAPIError.unexpectedResponse(let status) {
            XCTAssertEqual(status, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

final class LocalDataEraserTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: StoredPrediction.self, StoredPurchase.self, StoredObservation.self, StoredMerchant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    private func seedConfirmedCheckout() throws {
        let merchant = StoredMerchant(name: "Loblaws", identifier: "poi-123",
                                      latitude: 45.42, longitude: -75.69)
        context.insert(merchant)
        let log = PredictionLog(context: context)
        let prediction = try log.record(StoredPrediction(
            merchantName: "Loblaws", merchantIdentifier: "poi-123",
            predictedCategory: "grocery", confidenceSource: .brandPrior,
            winnerCardId: "amex-cobalt", winnerValueCad: 7.0,
            headline: "Use American Express Cobalt Card."))
        try log.settle(prediction, cardUsed: "amex-cobalt", observedCategory: "grocery",
                        missClass: nil, note: nil)
    }

    func testErasingLocalHistoryRemovesPredictionsConfirmationsAndSavedMerchantLocations() throws {
        try seedConfirmedCheckout()

        try LocalDataEraser(context: context).eraseLocalHistory()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StoredPrediction>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StoredObservation>()), 0)
        // The merchant rows carry the coordinates of places the owner shopped; a local wipe that
        // left them behind would leave the most sensitive local data in place.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StoredMerchant>()), 0)
    }

    func testErasingLocalHistoryLeavesTheStoreUsable() throws {
        try seedConfirmedCheckout()
        let eraser = LocalDataEraser(context: context)

        try eraser.eraseLocalHistory()
        try eraser.eraseLocalHistory()
        try seedConfirmedCheckout()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StoredPrediction>()), 1)
    }
}
