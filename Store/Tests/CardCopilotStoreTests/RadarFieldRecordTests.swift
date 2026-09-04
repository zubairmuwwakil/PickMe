import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

/// The Radar scan's field record, against fixtures.
///
/// The foreground path is where the owner's reported failure actually lives — "I was standing in
/// Shoppers and it wouldn't even show under nearby locations" — and until now nothing on it wrote
/// a record. Every arrival below is a synthetic plaza on a meridian: no real coordinates, no
/// device data.
final class RadarFieldRecordTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// A fix at the plaza origin, good to ±10 m unless a test wants a worse one.
    private func fix(accuracy: Double = 10) -> ArrivalFix {
        ArrivalFix(latitude: 45, longitude: -75, horizontalAccuracyMeters: accuracy,
                   capturedAt: epoch)
    }

    private func merchant(_ name: String, metresNorth: Double,
                          poiCategoryRaw: String? = nil) -> NearbyPlace {
        NearbyPlace(id: "\(name)@\(metresNorth)", name: name, poiCategoryRaw: poiCategoryRaw,
                       latitude: 45 + metresNorth / 111_000, longitude: -75,
                       distanceMeters: metresNorth)
    }

    // MARK: - Record shape

    /// Every candidate, not just the winner. An export that carried only the chosen store could
    /// never say whether the anchor tenant was returned at all.
    func testARadarScanRecordsEveryCandidateReturned() {
        let record = radarFieldRecord(
            recordedAt: epoch, fix: fix(), rawResultCount: 3,
            merchants: [merchant("Shoppers Drug Mart", metresNorth: 40),
                        merchant("Bergeron Notaries", metresNorth: 12),
                        merchant("Tim Hortons", metresNorth: 65)])

        XCTAssertEqual(record.candidates.map(\.name),
                       ["Shoppers Drug Mart", "Bergeron Notaries", "Tim Hortons"])
        XCTAssertEqual(record.source, .radar)
    }

    /// The order Radar published is the order recorded, and the first of them is the one Home
    /// pointed at. "Which was ranked first" is the whole question when pin geometry is suspected.
    func testTheFirstCandidateIsTheOneRadarRankedFirst() {
        let record = radarFieldRecord(
            recordedAt: epoch, fix: fix(), rawResultCount: 2,
            merchants: [merchant("Bergeron Notaries", metresNorth: 12),
                        merchant("Shoppers Drug Mart", metresNorth: 40)])

        XCTAssertEqual(record.chosenCandidateIndex, 0)
        XCTAssertEqual(record.resolvedMerchantName, "Bergeron Notaries")
    }

    func testAnEmptyScanChoosesNothing() {
        let record = radarFieldRecord(recordedAt: epoch, fix: fix(), rawResultCount: 0,
                                      merchants: [])

        XCTAssertNil(record.chosenCandidateIndex)
        XCTAssertEqual(record.resolvedMerchantName, "")
        XCTAssertEqual(record.dedupedResultCount, 0)
    }

    /// A Radar scan never runs the gate: nothing was scheduled, nothing was suppressed, and no
    /// basket was guessed. Recording a zeroed gate input here would put a decision nobody made
    /// into the export and quietly corrupt every replay drawn from it.
    func testARadarScanCarriesNoGateDecision() {
        let record = radarFieldRecord(recordedAt: epoch, fix: fix(), rawResultCount: 1,
                                      merchants: [merchant("Shoppers Drug Mart", metresNorth: 40)])

        XCTAssertNil(record.gateInput)
        XCTAssertNil(record.deliveryTier)
        XCTAssertNil(record.policy)
        XCTAssertNil(record.estimatedAmountCad)
        XCTAssertNil(record.rung)
        XCTAssertTrue(record.suppressionReasons.isEmpty)
    }

    /// Distance is measured from the owner's own fix, exactly as the ambient path measures it —
    /// not carried over from whatever reference point MapKit was given.
    func testCandidateDistanceIsMeasuredFromTheFix() throws {
        let record = radarFieldRecord(recordedAt: epoch, fix: fix(), rawResultCount: 1,
                                      merchants: [merchant("Shoppers Drug Mart", metresNorth: 111,
                                                           poiCategoryRaw: "MKPOICategoryPharmacy")])

        let distance = try XCTUnwrap(record.candidates[0].distanceFromFixMeters)
        XCTAssertEqual(distance, 111, accuracy: 1)
    }

    func testAScanWithNoFixRecordsNoDistances() {
        let record = radarFieldRecord(recordedAt: epoch, fix: nil, rawResultCount: 1,
                                      merchants: [merchant("Shoppers Drug Mart", metresNorth: 40)])

        XCTAssertNil(record.candidates[0].distanceFromFixMeters)
        XCTAssertNil(record.discriminability)
    }

    /// Pack recognition, the resolved category and the confidence come from the same resolver the
    /// ambient path uses. Two paths answering "what kind of place is this?" differently is what
    /// this instrument exists to rule out, not to introduce.
    func testCandidatesCarryTheSameResolutionTheAmbientPathWouldGive() {
        let record = radarFieldRecord(recordedAt: epoch, fix: fix(), rawResultCount: 1,
                                      merchants: [merchant("Shoppers Drug Mart", metresNorth: 40)])
        let expected = resolveDiscoveredMerchant(name: "Shoppers Drug Mart", poiCategoryRaw: nil)

        XCTAssertTrue(record.candidates[0].recognisedByPack)
        XCTAssertEqual(record.candidates[0].resolvedCategory, expected.prediction.category)
        XCTAssertEqual(record.candidates[0].confidence, expected.confidence)
    }

    // MARK: - Raw versus deduped result counts

    /// A cap that truncates upstream is invisible once the list is deduped, so the size MapKit
    /// actually returned has to be recorded before `rankNearbyPlaces` touches it.
    func testTheRawResponseSizeIsRecordedAlongsideTheDedupedCount() {
        let record = radarFieldRecord(
            recordedAt: epoch, fix: fix(), rawResultCount: 25,
            merchants: [merchant("Shoppers Drug Mart", metresNorth: 40),
                        merchant("Tim Hortons", metresNorth: 65)])

        XCTAssertEqual(record.rawResultCount, 25)
        XCTAssertEqual(record.dedupedResultCount, 2)
    }

    // MARK: - Chain containment

    /// "Shoppers wasn't there" becomes a counted fact rather than a recollection. The pre-index
    /// row's id is recorded, not merely a boolean, so the export names which chain was present.
    func testACandidateResolvingToAPreIndexRowNamesThatRow() {
        let record = radarFieldRecord(
            recordedAt: epoch, fix: fix(), rawResultCount: 2,
            merchants: [merchant("Bergeron Notaries", metresNorth: 12),
                        merchant("Shoppers Drug Mart", metresNorth: 40)])

        XCTAssertNil(record.candidates[0].preIndexMerchantId)
        XCTAssertEqual(record.candidates[1].preIndexMerchantId, "shoppers drug mart")
        XCTAssertEqual(record.chainCandidateIndex, 1)
        XCTAssertTrue(record.containsRecognisedChain)
    }

    func testAScanOfNothingButUnknownStorefrontsContainsNoChain() {
        let record = radarFieldRecord(
            recordedAt: epoch, fix: fix(), rawResultCount: 2,
            merchants: [merchant("Bergeron Notaries", metresNorth: 12),
                        merchant("Atelier Vitrail Lachance", metresNorth: 30)])

        XCTAssertNil(record.chainCandidateIndex)
        XCTAssertFalse(record.containsRecognisedChain)
        XCTAssertFalse(record.topRankedMissedARecognisedChain)
    }

    /// **The signature that separates the two candidate mechanisms.** The anchor tenant was
    /// returned and still lost the top slot — result-set truncation cannot explain that, and pin
    /// geometry can.
    func testATopRankedNonChainWithAChainPresentIsThePinGeometrySignature() {
        let record = radarFieldRecord(
            recordedAt: epoch, fix: fix(), rawResultCount: 2,
            merchants: [merchant("Bergeron Notaries", metresNorth: 12),
                        merchant("Shoppers Drug Mart", metresNorth: 40)])

        XCTAssertTrue(record.topRankedMissedARecognisedChain)
    }

    func testAChainRankedFirstIsNotTheSignature() {
        let record = radarFieldRecord(
            recordedAt: epoch, fix: fix(), rawResultCount: 2,
            merchants: [merchant("Shoppers Drug Mart", metresNorth: 12),
                        merchant("Bergeron Notaries", metresNorth: 40)])

        XCTAssertTrue(record.containsRecognisedChain)
        XCTAssertFalse(record.topRankedMissedARecognisedChain)
    }

    // MARK: - Margin parity with the ambient path

    /// Foreground and background margins have to be the same number computed the same way, or the
    /// densest sample source in the build cannot be pooled with the one it is meant to explain.
    func testRadarMarginMatchesTheAmbientPathForTheSameGeometry() throws {
        let merchants = [merchant("Bergeron Notaries", metresNorth: 12),
                         merchant("Shoppers Drug Mart", metresNorth: 40)]
        let record = radarFieldRecord(recordedAt: epoch, fix: fix(accuracy: 65),
                                      rawResultCount: 2, merchants: merchants)

        let ambient = discriminability(
            candidates: merchants.map { ArrivalSite(latitude: $0.latitude,
                                                    longitude: $0.longitude) },
            fix: fix(accuracy: 65))

        XCTAssertEqual(record.discriminability, ambient)
        // 28 m apart, seen through a ±65 m fix: unanswerable by any algorithm on this hardware.
        XCTAssertEqual(try XCTUnwrap(record.discriminability).isResolvable, false)
    }

    // MARK: - Metrics

    /// A Radar scan is not an arrival. Pooling them would inflate the arrival denominator every
    /// accuracy figure in the export rests on — and Radar is tapped far more often than a
    /// geofence is crossed, so the inflation would swamp the real number.
    func testRadarScansAreCountedSeparatelyFromArrivals() {
        let scan = radarFieldRecord(
            recordedAt: epoch, fix: fix(), rawResultCount: 2,
            merchants: [merchant("Bergeron Notaries", metresNorth: 12),
                        merchant("Shoppers Drug Mart", metresNorth: 40)])

        let metrics = arrivalFieldMetrics([scan])

        XCTAssertEqual(metrics.arrivals, 0)
        XCTAssertEqual(metrics.radarScans, 1)
        XCTAssertEqual(metrics.radarScansWithARecognisedChain, 1)
        XCTAssertEqual(metrics.radarScansWhereTopRankedMissedAChain, 1)
    }

    /// A scan record has no gate input, so anything that replays one must skip it rather than
    /// throw or invent a decision.
    func testMetricsOverAMixedLogDoNotTripOverAScanWithNoGate() {
        let scan = radarFieldRecord(recordedAt: epoch, fix: fix(), rawResultCount: 1,
                                    merchants: [merchant("Shoppers Drug Mart", metresNorth: 40)])

        let metrics = arrivalFieldMetrics([scan])

        XCTAssertEqual(metrics.alertsEatenByTheEstimate, 0)
        XCTAssertNil(replayAtRealAmount(scan))
    }
}
