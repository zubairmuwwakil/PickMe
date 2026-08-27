import XCTest
@testable import CardCopilot

/// The guard that keeps an empty search field from ending the checkout.
///
/// `MerchantConfirmView` forwarded its raw `searchText`, so submitting an empty field pushed
/// `.nothingFound(query: "")` through the router and replaced the nearby merchant list with a
/// full-screen `Nothing found for “”.` dead end whose only exit was "Start over" — the owner lost
/// their GPS results while standing at the till. Both search fields now share this rule.
final class SearchSubmissionTests: XCTestCase {

    func testAnEmptyFieldIsNotAQuery() {
        XCTAssertNil(SearchSubmission.query(from: ""))
    }

    /// Whitespace looks like input and is not. Untrimmed, it reaches MapKit as a real lookup and
    /// comes back empty, which is the same dead end by a slower route.
    func testWhitespaceOnlyIsNotAQuery() {
        XCTAssertNil(SearchSubmission.query(from: "   "))
        XCTAssertNil(SearchSubmission.query(from: "\n \t"))
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(SearchSubmission.query(from: "  Loblaws "), "Loblaws")
    }

    /// Interior spacing belongs to the merchant name — "Real Canadian Superstore" must survive.
    func testInteriorSpacingSurvives() {
        XCTAssertEqual(SearchSubmission.query(from: "Real Canadian Superstore"),
                       "Real Canadian Superstore")
    }
}
