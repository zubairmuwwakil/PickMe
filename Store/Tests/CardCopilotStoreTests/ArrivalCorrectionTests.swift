import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

/// The owner saying "not this store, that one".
///
/// The only ground truth in the instrument that does not require a purchase. Receipt joins label
/// perhaps a fifth of visits; this labels any visit the owner chooses to correct.
final class ArrivalCorrectionTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func merchant(_ name: String, metresNorth: Double) -> NearbyMerchant {
        NearbyMerchant(id: "\(name)@\(metresNorth)", name: name, poiCategoryRaw: nil,
                       latitude: 45 + metresNorth / 111_000, longitude: -75,
                       distanceMeters: metresNorth)
    }

    private var scan: ArrivalFieldRecord {
        radarFieldRecord(
            recordedAt: epoch,
            fix: ArrivalFix(latitude: 45, longitude: -75, horizontalAccuracyMeters: 10,
                            capturedAt: epoch),
            rawResultCount: 3,
            merchants: [merchant("Bergeron Notaries", metresNorth: 12),
                        merchant("Shoppers Drug Mart", metresNorth: 40),
                        merchant("Tim Hortons", metresNorth: 65)])
    }

    /// What was offered, what was rejected, what was chosen, and where the chosen store sat in the
    /// ranking. The rank is the payload: "the right answer was second" is a different finding from
    /// "the right answer was ninth".
    func testACorrectionNamesWhatWasOfferedRejectedAndChosenWithItsRank() throws {
        let corrected = scan.correcting(rejected: "Bergeron Notaries",
                                        chosen: "Shoppers Drug Mart",
                                        offered: ["Shoppers Drug Mart", "Tim Hortons"],
                                        at: epoch.addingTimeInterval(30))

        let correction = try XCTUnwrap(corrected.correction)
        XCTAssertEqual(correction.rejectedName, "Bergeron Notaries")
        XCTAssertEqual(correction.chosenName, "Shoppers Drug Mart")
        XCTAssertEqual(correction.offeredNames, ["Shoppers Drug Mart", "Tim Hortons"])
        XCTAssertEqual(correction.chosenCandidateIndex, 1)
        XCTAssertEqual(correction.correctedAt, epoch.addingTimeInterval(30))
    }

    /// The containment ceiling, established without a receipt. A store the owner had to reach by
    /// search was never in the candidate set, and no ranking could have found it.
    func testAStoreThatWasNeverACandidateHasNoRank() throws {
        let corrected = scan.correcting(rejected: "Bergeron Notaries",
                                        chosen: "Pharmaprix Ste-Foy",
                                        offered: ["Shoppers Drug Mart", "Tim Hortons"],
                                        at: epoch)

        XCTAssertNil(try XCTUnwrap(corrected.correction).chosenCandidateIndex)
    }

    /// Correcting changes nothing else about the record. It is an annotation on a decision already
    /// made, not a re-description of it — the chosen candidate stays what the app named, so the
    /// export can still say the app was wrong.
    func testCorrectingLeavesTheOriginalAnswerIntact() {
        let corrected = scan.correcting(rejected: "Bergeron Notaries",
                                        chosen: "Shoppers Drug Mart",
                                        offered: ["Shoppers Drug Mart"], at: epoch)

        XCTAssertEqual(corrected.chosenCandidateIndex, 0)
        XCTAssertEqual(corrected.resolvedMerchantName, "Bergeron Notaries")
        XCTAssertEqual(corrected.candidates, scan.candidates)
    }
}
