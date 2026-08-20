import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

final class OwnerStateDecodeResilienceTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// A profile the current build cannot decode must not take its neighbours with it.
    /// Before this fix the whole dictionary decoded as one value, so one bad entry returned [:].
    func testCorruptProfileDoesNotEvictHealthyProfiles() throws {
        let defaults = makeDefaults()
        let store = AccountOwnerStateStore(defaults: defaults)

        let healthy = try SeedLoader.loadOwnerState()
        try store.activate(healthy, forUserID: "good-user")

        // Splice an undecodable sibling in beside the healthy one, exactly as a future
        // shape change would produce on an older build.
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(
            with: XCTUnwrap(defaults.data(forKey: "ca.pickme.owner-state-profiles.v1"))
        ) as? [String: Any])
        raw["bad-user"] = ["ownerStateVersion": "1.0", "unexpectedShape": true]
        defaults.set(try JSONSerialization.data(withJSONObject: raw),
                     forKey: "ca.pickme.owner-state-profiles.v1")

        XCTAssertEqual(store.state(forUserID: "good-user"), healthy)
        XCTAssertNil(store.state(forUserID: "bad-user"))
    }

    func testEntirelyUnreadableBlobStillReturnsEmpty() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "ca.pickme.owner-state-profiles.v1")
        XCTAssertNil(AccountOwnerStateStore(defaults: defaults).state(forUserID: "anyone"))
    }
}
