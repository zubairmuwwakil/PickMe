import XCTest
import Security
import CardCopilotStore
import ClerkKit
@testable import CardCopilot

final class WelcomeGatewayStateTests: XCTestCase {
    @MainActor
    func testPendingAccountRequirementsKeepAuthenticationOpenUntilSessionIsActive() {
        let now = Date()
        let user = User(
            backupCodeEnabled: false, createdAt: now, createOrganizationEnabled: false,
            deleteSelfEnabled: false, emailAddresses: [], externalAccounts: [],
            hasImage: false, id: "user-auth-test", imageUrl: "", organizationMemberships: [],
            passkeys: [], passwordEnabled: false, phoneNumbers: [], totpEnabled: false,
            twoFactorEnabled: false, updatedAt: now
        )
        var session = ClerkKit.Session(
            id: "session-auth-test", status: .pending, expireAt: now.addingTimeInterval(3600),
            abandonAt: now.addingTimeInterval(3600), lastActiveAt: now, user: user,
            createdAt: now, updatedAt: now
        )

        XCTAssertNil(ClerkSession.authenticatedUser(in: session))
        let content = WelcomeGatewayContent.resolve(
            isConfigured: true,
            isSignedIn: ClerkSession.authenticatedUser(in: session) != nil,
            isPreparingAccount: false,
            syncIssueMessage: nil
        )
        XCTAssertTrue(content.shouldPresentAuthentication(requested: true))

        session.status = .active
        XCTAssertEqual(ClerkSession.authenticatedUser(in: session)?.id, user.id)
        session.status = .revoked
        XCTAssertNil(ClerkSession.authenticatedUser(in: session))
        XCTAssertNil(ClerkSession.authenticatedUser(in: nil))
    }

    func testClerkStartsOnlyWhenKeychainIsUsable() {
        XCTAssertTrue(ClerkStartupPolicy.permitsConfiguration(for: errSecSuccess))
        XCTAssertTrue(ClerkStartupPolicy.permitsConfiguration(for: errSecItemNotFound))
        XCTAssertFalse(ClerkStartupPolicy.permitsConfiguration(for: errSecMissingEntitlement))
        XCTAssertFalse(ClerkStartupPolicy.permitsConfiguration(for: errSecNotAvailable))
    }

    /// `Clerk.shared` calls `fatalError` when `Clerk.configure` was never run, and it is never
    /// run when `MoneyTalksConfiguration.isConfigured` is false — the state of every
    /// `CODE_SIGNING_ALLOWED=NO` build, this test process included. Reading it directly killed
    /// the whole test host at launch, before one test ran.
    ///
    /// That this test *executes at all* is most of the regression guard: reintroducing an
    /// unguarded `Clerk.shared` read on any launch path takes the suite down with it. The
    /// assertions cover the rest — that the safe accessor reports "signed out" rather than
    /// trapping when Clerk is absent.
    @MainActor
    func testSignedInUserIsReadableWithoutClerkConfigured() {
        XCTAssertFalse(MoneyTalksConfiguration.isConfigured,
                       "A signing-disabled test build must not report itself as configured")
        XCTAssertNil(ClerkSession.currentUserID)
        XCTAssertNil(ClerkSession.currentUser)
        XCTAssertFalse(ClerkSession.isSignedIn)
    }

    /// The token provider throws rather than trapping, so an unconfigured build fails the
    /// request instead of the process.
    @MainActor
    func testTokenProviderThrowsInsteadOfTrappingWhenClerkIsAbsent() async {
        do {
            _ = try await ClerkSession.token()
            XCTFail("An unconfigured build must not vend a token")
        } catch {
            XCTAssertTrue(error is MoneyTalksAPIError, "Got \(error)")
        }
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
