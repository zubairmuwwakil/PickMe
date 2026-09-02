import XCTest
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot

/// Persistence for the debug dials. The dials are only useful if a field build keeps them across
/// the background relaunches that arrival alerts consist almost entirely of.
@MainActor
final class AmbientAlertPolicyStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ambient-alert-policy-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testAnUntouchedStoreReportsTheShippedPolicy() {
        XCTAssertEqual(AmbientAlertPolicyStore(defaults: defaults).policy, .shipped)
    }

    func testAStoredPolicySurvivesARelaunch() {
        var policy = AmbientAlertPolicy.shipped
        policy.categoryAdvantageMultiplier = 1.25
        policy.amountEstimate = .fixed(amountCad: 40)
        policy.switchThresholdOverride = SwitchThreshold(minAdvantagePercentagePoints: 0.5,
                                                        minAdvantageCad: 0, semantics: "both")
        AmbientAlertPolicyStore(defaults: defaults).save(policy)

        XCTAssertEqual(AmbientAlertPolicyStore(defaults: defaults).policy, policy)
    }

    /// A policy written by a build with different dials must not take the app's alert behaviour
    /// with it. Falling back to the shipped policy is the only safe answer.
    func testAnUndecodablePolicyFallsBackToTheShippedOne() {
        defaults.set(Data("not a policy".utf8), forKey: "ambientAlertPolicy.v1")
        XCTAssertEqual(AmbientAlertPolicyStore(defaults: defaults).policy, .shipped)
    }

    func testForgettingRestoresTheShippedPolicy() {
        let store = AmbientAlertPolicyStore(defaults: defaults)
        var policy = AmbientAlertPolicy.shipped
        policy.unverifiedAdvantageMultiplier = 5
        store.save(policy)
        store.forgetAll()
        XCTAssertEqual(store.policy, .shipped)
    }
}
