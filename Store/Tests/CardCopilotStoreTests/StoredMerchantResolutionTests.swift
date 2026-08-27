import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

/// Rung 1 of the arrival ladder: a merchant already stored on this device.
///
/// A stored merchant that has never been reconciled against a statement used to resolve to
/// `.unknown` — the tier `AmbientGate` suppresses unconditionally. Since `rotateRegions` spends
/// one of twenty geofence slots on each uncovered stored merchant, that slot bought a guaranteed
/// silence. Reconciliation still earns `.verified`; what changes is that its absence no longer
/// costs the merchant everything it would have earned as a plain discovered POI.
final class StoredMerchantResolutionTests: XCTestCase {

    func testAReconciledTerminalIsVerified() {
        let r = resolveStoredMerchant(name: "Sobeys", poiCategoryRaw: nil,
                                      confirmedCategory: "grocery", confirmationCount: 1)
        XCTAssertEqual(r.confidence, .verified)
        XCTAssertEqual(r.prediction.category, "grocery")
    }

    func testAnUnreconciledStoredMerchantFallsBackToRecognitionRatherThanSilence() {
        let r = resolveStoredMerchant(name: "Sobeys", poiCategoryRaw: nil,
                                      confirmedCategory: nil, confirmationCount: 0)
        XCTAssertEqual(r.confidence, .brandMatched)
        XCTAssertEqual(r.prediction.category, "grocery")
    }

    func testAnUnreconciledUnrecognisableStoredMerchantStaysUnknown() {
        let r = resolveStoredMerchant(name: "Bob's Hardware", poiCategoryRaw: nil,
                                      confirmedCategory: nil, confirmationCount: 0)
        XCTAssertEqual(r.confidence, .unknown)
    }

    /// The owner's own reconciled coding outranks the index, always. The index says Sobeys is
    /// grocery; if this owner's terminal reconciled as something else, the terminal wins.
    func testTheOwnersReconciledCodingOutranksTheIndex() {
        let r = resolveStoredMerchant(name: "Sobeys", poiCategoryRaw: nil,
                                      confirmedCategory: "dining", confirmationCount: 3)
        XCTAssertEqual(r.prediction.category, "dining")
        XCTAssertEqual(r.prediction.confidenceSource, .repeatedTerminal)
    }
}
