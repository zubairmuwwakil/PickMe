import XCTest
@testable import CardCopilot

@MainActor
final class AmbientVisitStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "AmbientVisitStoreTests.\(UUID().uuidString)")!
        return suite
    }

    func testDismissalFlagSurvivesAWriteAndReadCycle() {
        let store = AmbientVisitStore(defaults: makeDefaults())
        store.begin(AmbientVisit(enteredAt: .now, didEngage: false, purchaseId: nil,
                                 merchantName: "Loblaws"),
                    forRegionId: "area.1")

        XCTAssertEqual(store.visit(forRegionId: "area.1")?.liveActivityDismissed, false)

        store.update(regionId: "area.1") { $0.liveActivityDismissed = true }

        XCTAssertEqual(store.visit(forRegionId: "area.1")?.liveActivityDismissed, true)
    }

    /// Visits written before this field existed must still decode. Synthesised `Codable` throws
    /// on a missing key even when the property has a default, so the flag needs an explicit
    /// `decodeIfPresent` — without it every in-flight visit is silently dropped on upgrade.
    func testVisitsWrittenBeforeTheFieldExistedStillDecode() throws {
        let defaults = makeDefaults()
        let legacy = """
        {"area.1":{"enteredAt":0,"didEngage":false,"merchantName":"Loblaws"}}
        """
        defaults.set(Data(legacy.utf8), forKey: "ambientVisits.v1")

        let store = AmbientVisitStore(defaults: defaults)
        let visit = try XCTUnwrap(store.visit(forRegionId: "area.1"))
        XCTAssertEqual(visit.merchantName, "Loblaws")
        XCTAssertFalse(visit.liveActivityDismissed)
    }
}
