import XCTest
@testable import CardCopilotStore

/// The pure half of arrival resolution: where an arrival is measured from, and in what order the
/// candidates inside an area are considered. Both must degrade to the pre-fix behaviour exactly
/// when no fix landed, because a background region wake is not guaranteed to get one.
final class ArrivalResolutionTests: XCTestCase {
    // A synthetic plaza on a meridian: one degree of latitude is ~111 km, so these offsets are
    // tens of metres apart. Deliberately not a real place — no test may depend on real
    // coordinates or on the owner's device data.
    private let south = ArrivalSite(latitude: 45.0000, longitude: -75.0000)
    private let middle = ArrivalSite(latitude: 45.0010, longitude: -75.0000)
    private let north = ArrivalSite(latitude: 45.0020, longitude: -75.0000)

    private func fix(atLatitude latitude: Double, accuracy: Double = 10) -> ArrivalFix {
        ArrivalFix(latitude: latitude, longitude: -75.0000, horizontalAccuracyMeters: accuracy,
                   capturedAt: Date(timeIntervalSince1970: 0))
    }

    // MARK: - A2: nearest-first ordering

    func testNearestFirstOrderRanksByDistanceFromTheOwner() {
        let order = nearestFirstOrder([south, middle, north], from: fix(atLatitude: 45.0019))
        XCTAssertEqual(order, [2, 1, 0])
    }

    /// The whole defect this replaces: `clusterIntoAreas` sorts by `(latitude, longitude, id)` to
    /// keep region registration stable, and taking the first member made the southernmost store
    /// the answer. Ordering happens here, at the point of resolution, never at clustering.
    func testTheSouthernmostCandidateIsNotPrivilegedWhenTheOwnerIsInTheNorth() {
        let order = nearestFirstOrder([south, middle, north], from: fix(atLatitude: 45.0020))
        XCTAssertEqual(order.first, 2)
    }

    /// With no fix the input order is returned untouched, so an arrival that never got a fix
    /// resolves exactly as it did before this existed.
    func testOrderIsUnchangedWithoutAFix() {
        XCTAssertEqual(nearestFirstOrder([south, middle, north], from: nil), [0, 1, 2])
    }

    /// Stability matters for the same reason it matters in `clusterIntoAreas`: equal-distance
    /// candidates must not reorder between two wakes at the same plaza.
    func testEqualDistancesKeepTheirOriginalRelativeOrder() {
        let west = ArrivalSite(latitude: 45.0010, longitude: -75.0001)
        let east = ArrivalSite(latitude: 45.0010, longitude: -74.9999)
        let order = nearestFirstOrder([west, east], from: fix(atLatitude: 45.0010))
        XCTAssertEqual(order, [0, 1])
    }

    func testEmptyCandidateSetOrdersToNothing() {
        XCTAssertEqual(nearestFirstOrder([], from: fix(atLatitude: 45.0)), [])
    }

    // MARK: - A3: where rung 1 measures from

    /// A confirmed store near the edge of a 400 m plaza can never claim its own visit while the
    /// 60 m radius is measured from the centroid. Measured from the owner, it can.
    func testArrivalOriginIsTheOwnersFixWhenOneLanded() {
        let origin = arrivalOrigin(fix: fix(atLatitude: 45.0020),
                                   areaCentroidLatitude: 45.0000,
                                   areaCentroidLongitude: -75.0000)
        XCTAssertEqual(origin.latitude, 45.0020, accuracy: 1e-9)
        XCTAssertEqual(origin.longitude, -75.0000, accuracy: 1e-9)
    }

    func testArrivalOriginFallsBackToTheAreaCentroidWithoutAFix() {
        let origin = arrivalOrigin(fix: nil,
                                   areaCentroidLatitude: 45.0000,
                                   areaCentroidLongitude: -75.0000)
        XCTAssertEqual(origin.latitude, 45.0000, accuracy: 1e-9)
        XCTAssertEqual(origin.longitude, -75.0000, accuracy: 1e-9)
    }
}
