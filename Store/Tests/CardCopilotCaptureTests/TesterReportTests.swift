import XCTest
@testable import CardCopilotCapture

final class TesterReportTests: XCTestCase {
    private func report(arrival: String? = nil) -> TesterReport {
        TesterReport(reportID: "8c14cc23-397f-43dd-9d95-c8d3c4fdca91",
                     appVersion: "2.1", buildNumber: "42", osVersion: "iOS simulator verification",
                     area: "other", expected: "A tester report appears in the review inbox with the same reference.",
                     actual: "Synthetic handoff verification. No customer or purchase data.",
                     steps: "Prepare on iOS, share the JSON, import as reviewer, record verification and resolve.",
                     arrivalLog: arrival)
    }

    func testDefaultReportContainsNoDiagnosticAttachmentsOrAccountIdentity() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: report().encoded()) as? [String: Any])
        XCTAssertNil(object["walletCapture"])
        XCTAssertNil(object["arrivalLog"])
        XCTAssertNil(object["counters"])
        XCTAssertNil(object["userId"])
        XCTAssertEqual(object["includedArrivalDetails"] as? Bool, false)
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
    }

    func testRetryAndExportKeepTheSameReportIDAndCreationTime() throws {
        let report = report()
        XCTAssertEqual(try report.encoded(), try report.encoded())
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TesterReport.self, from: report.encoded())
        XCTAssertEqual(decoded.reportID, report.reportID)
        XCTAssertEqual(decoded.actual, report.actual)
        // Optional operator artifact uses exactly the app's serializer, not a hand-written JSON twin.
        if let path = ProcessInfo.processInfo.environment["PICKME_TESTER_REPORT_EXPORT_PATH"] {
            try report.encoded().write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    func testOversizedArrivalEvidenceFailsBeforeSendingOrSharing() throws {
        XCTAssertThrowsError(try report(arrival: String(repeating: "x", count: 900_001)).encoded()) { error in
            guard case TesterReportError.tooLarge = error else { return XCTFail("Expected size limit") }
        }
    }

    func testArrivalAttachmentCarriesExplicitInclusion() throws {
        let data = try report(arrival: "{\"metrics\":{},\"records\":[]}").encoded()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["includedArrivalDetails"] as? Bool, true)
    }

    func testSignedOutSubmissionFailsWithoutAttemptingNetworkAccess() async throws {
        let client = TesterReportHTTPClient(baseURL: URL(string: "https://invalid.example")!, tokenProvider: { nil })
        do { _ = try await client.submit(report()); XCTFail("Expected sign-in error") }
        catch TesterReportError.http(401) { }
    }
}
