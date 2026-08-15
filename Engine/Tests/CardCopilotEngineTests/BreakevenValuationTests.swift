import XCTest
@testable import CardCopilotEngine

/// The Membership Rewards valuation at which the engine's *recommendation* changes.
///
/// This searches the real engine rather than comparing raw card values, so it accounts for
/// the switch threshold, acceptance, and caps — the raw-value comparison disagrees with what
/// the app would actually say, which makes it the wrong number to reason about.
/// Run with: swift test --filter BreakevenValuationTests
final class BreakevenValuationTests: XCTestCase {

    private func winner(_ catalogue: Catalogue, _ owner: OwnerState,
                        _ purchase: PurchaseContext, mr: Double) -> CandidateScore {
        var state = owner
        state.valuationsCad.amexMembershipRewards.centsPerPoint = mr
        return RecommendationEngine(catalogue: catalogue, ownerState: state)
            .recommend(purchase, asOf: "2026-08-20").winner
    }

    func testPrintRecommendationBreakevens() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadPinnedOwnerState()
        let names = Dictionary(uniqueKeysWithValues: catalogue.cards.map { ($0.cardId, $0.officialName) })
        let mrCards = Set(catalogue.cards
            .filter { $0.program.programId == "amexMembershipRewards" }
            .map(\.cardId))

        let checkouts: [(String, PurchaseContext)] = [
            ("Coffee $6", PurchaseContext(amountCad: 6, category: "dining", mcc: 5814)),
            ("Restaurant $50", PurchaseContext(amountCad: 50, category: "dining", mcc: 5812)),
            ("Groceries $140", PurchaseContext(amountCad: 140, category: "grocery", mcc: 5411,
                                               merchantBrand: "loblaws")),
            ("Netflix $15.49", PurchaseContext(amountCad: 15.49, category: "streaming", mcc: 5968,
                                               merchantBrand: "netflix", channel: "online",
                                               recurringIndicator: true)),
            ("Gas $70", PurchaseContext(amountCad: 70, category: "gasStation", mcc: 5541)),
            ("Taxi $25", PurchaseContext(amountCad: 25, category: "transit", mcc: 4121)),
            ("Flight $600", PurchaseContext(amountCad: 600, category: "travel", mcc: 3000)),
            ("Pharmacy $30", PurchaseContext(amountCad: 30, category: "drugStore", mcc: 5912)),
        ]

        print("\n═══ Valuation at which the RECOMMENDATION changes ═══")
        print("(current setting 1.8¢ · guaranteed cash floor 1.0¢ · switch threshold 0.5pp AND $0.25)\n")

        for (label, purchase) in checkouts {
            let atFloor = winner(catalogue, owner, purchase, mr: 1.0)
            let atCeiling = winner(catalogue, owner, purchase, mr: 4.0)
            let amexAtFloor = mrCards.contains(atFloor.cardId)
            let amexAtCeiling = mrCards.contains(atCeiling.cardId)

            let verdict: String
            if amexAtFloor {
                verdict = "always \(short(atFloor.cardId, names)) — valuation-proof"
            } else if !amexAtCeiling {
                verdict = "never Amex — \(short(atFloor.cardId, names)) regardless"
            } else {
                // The Amex value rises monotonically with the valuation, so the switch point
                // can be found by bisection on the engine's own answer.
                var low = 1.0, high = 4.0
                for _ in 0..<40 {
                    let mid = (low + high) / 2
                    if mrCards.contains(winner(catalogue, owner, purchase, mr: mid).cardId) {
                        high = mid
                    } else {
                        low = mid
                    }
                }
                verdict = String(format: "%@ below %.2f¢ · %@ above",
                                 short(atFloor.cardId, names), high, short(atCeiling.cardId, names))
            }
            print(String(format: "%-18@ %@", label as NSString, verdict))
        }
        print("")
    }

    private func short(_ cardId: String, _ names: [String: String]) -> String {
        (names[cardId] ?? cardId)
            .replacingOccurrences(of: "The Platinum Card from American Express", with: "Amex Platinum")
            .replacingOccurrences(of: "American Express ", with: "Amex ")
            .replacingOccurrences(of: "Wealthsimple Visa Infinite Privilege Credit Card",
                                  with: "Wealthsimple")
            .replacingOccurrences(of: " Mastercard", with: "")
            .replacingOccurrences(of: " Card", with: "")
    }
}
