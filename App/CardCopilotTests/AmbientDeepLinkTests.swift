import XCTest
@testable import CardCopilot

final class AmbientDeepLinkTests: XCTestCase {
    func testTheIdentifyLinkRoundTrips() throws {
        let url = AmbientDeepLink.identifyMerchant.url
        XCTAssertEqual(AmbientDeepLink(url: url), .identifyMerchant)
    }

    /// `CardCopilotLiveActivityView` is compiled into the widget extension as well as the app, and
    /// the extension cannot see this type — so it spells the URL out as a literal. Pin the exact
    /// string here: if it drifts, the presence tap silently stops routing and nothing else fails.
    func testTheLiteralTheWidgetExtensionHardcodesStillParses() throws {
        let hardcodedInLiveActivityView = "pickme://arrival/identify"
        XCTAssertEqual(AmbientDeepLink.identifyMerchant.url.absoluteString,
                       hardcodedInLiveActivityView)
        let url = try XCTUnwrap(URL(string: hardcodedInLiveActivityView))
        XCTAssertEqual(AmbientDeepLink(url: url), .identifyMerchant)
    }

    /// The scheme is registered to this app, so anything arriving on it is ours to interpret —
    /// but a URL that merely *looks* similar must not drive navigation.
    func testForeignAndMalformedLinksAreRejected() {
        let rejected = [
            "https://arrival/identify",
            "pickme://arrival",
            "pickme://arrival/identify/extra",
            "pickme://settings/identify",
            "pickme://",
        ]
        for string in rejected {
            let url = URL(string: string)
            XCTAssertNil(url.flatMap(AmbientDeepLink.init(url:)), "\(string) must not route")
        }
    }
}
