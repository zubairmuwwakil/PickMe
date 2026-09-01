import XCTest
import Security
@testable import CardCopilot

final class WelcomeGatewayStateTests: XCTestCase {
    func testClerkStartsOnlyWhenKeychainIsUsable() {
        XCTAssertTrue(ClerkStartupPolicy.permitsConfiguration(for: errSecSuccess))
        XCTAssertTrue(ClerkStartupPolicy.permitsConfiguration(for: errSecItemNotFound))
        XCTAssertFalse(ClerkStartupPolicy.permitsConfiguration(for: errSecMissingEntitlement))
        XCTAssertFalse(ClerkStartupPolicy.permitsConfiguration(for: errSecNotAvailable))
    }

    func testConfiguredSignedOutInstallOffersAuthentication() {
        XCTAssertEqual(
            WelcomeGatewayContent.resolve(
                isConfigured: true,
                isSignedIn: false,
                isPreparingAccount: false,
                syncIssueMessage: nil
            ),
            .authenticationChoice
        )
    }

    func testActiveSessionNeverReturnsToAuthenticationWhileWalletRestores() {
        XCTAssertEqual(
            WelcomeGatewayContent.resolve(
                isConfigured: true,
                isSignedIn: true,
                isPreparingAccount: true,
                syncIssueMessage: nil
            ),
            .restoringAccount
        )
    }

    func testActiveSessionShowsRetryInsteadOfAuthenticationAfterRestoreFailure() {
        XCTAssertEqual(
            WelcomeGatewayContent.resolve(
                isConfigured: true,
                isSignedIn: true,
                isPreparingAccount: false,
                syncIssueMessage: "Could not reach Inunity. Check your connection and retry."
            ),
            .accountUnavailable("Could not reach Inunity. Check your connection and retry.")
        )
    }

    func testActiveSessionWaitingToStartRestoreStillNeverOffersAuthentication() {
        let content = WelcomeGatewayContent.resolve(
            isConfigured: true,
            isSignedIn: true,
            isPreparingAccount: false,
            syncIssueMessage: nil
        )

        XCTAssertEqual(content, .accountUnavailable(nil))
        XCTAssertFalse(content.shouldPresentAuthentication(requested: true))
    }

    func testSignedOutAuthenticationChoiceMayPresentARequestedSheet() {
        let content = WelcomeGatewayContent.resolve(
            isConfigured: true,
            isSignedIn: false,
            isPreparingAccount: false,
            syncIssueMessage: nil
        )

        XCTAssertTrue(content.shouldPresentAuthentication(requested: true))
        XCTAssertFalse(content.shouldPresentAuthentication(requested: false))
    }

    func testUnconfiguredInstallRemainsOfflineOnly() {
        for isSignedIn in [false, true] {
            let content = WelcomeGatewayContent.resolve(
                isConfigured: false,
                isSignedIn: isSignedIn,
                isPreparingAccount: false,
                syncIssueMessage: nil
            )

            XCTAssertEqual(content, .offlineOnly)
            XCTAssertFalse(content.shouldPresentAuthentication(requested: true))
        }
    }
}
