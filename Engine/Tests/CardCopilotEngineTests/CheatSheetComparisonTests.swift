import XCTest
@testable import CardCopilotEngine

/// Runs the category cheat-sheet's advice through the engine using the owner's real state.
/// A static sheet cannot know cap progress, linked-service status, or that a card is in a
/// drawer — this is where a copilot has to earn its existence.
/// Run with: swift test --filter CheatSheetComparisonTests
final class CheatSheetComparisonTests: XCTestCase {

    func testPrintCheatSheetVersusEngine() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()   // live state: MR at floor, no Rogers service
        let engine = RecommendationEngine(catalogue: catalogue, ownerState: owner)
        let names = Dictionary(uniqueKeysWithValues: catalogue.cards.map { ($0.cardId, $0.officialName) })

        // (label, what the sheet says to use, purchase)
        let rows: [(String, String, PurchaseContext)] = [
            ("Restaurants $50", "amex-cobalt",
             PurchaseContext(amountCad: 50, category: "dining", mcc: 5812)),
            ("Groceries $140", "amex-cobalt",
             PurchaseContext(amountCad: 140, category: "grocery", mcc: 5411, merchantBrand: "loblaws")),
            ("Streaming $15.49", "amex-cobalt",
             PurchaseContext(amountCad: 15.49, category: "streaming", mcc: 5968,
                             merchantBrand: "netflix", channel: "online", recurringIndicator: true)),
            ("Phone/internet $150", "mbna-rewards-we",
             PurchaseContext(amountCad: 150, category: "householdUtilities", mcc: 4814,
                             recurringIndicator: true)),
            ("Insurance $200", "scotia-momentum-vi-plus",
             PurchaseContext(amountCad: 200, category: "recurring", mcc: 6300,
                             recurringIndicator: true)),
            ("Costco $220", "rogers-red-we",
             PurchaseContext(amountCad: 220, category: "wholesaleClub", mcc: 5300,
                             merchantBrand: "costco", acceptedNetworks: [.mastercard])),
            ("Everything else $100", "rogers-red-we",
             PurchaseContext(amountCad: 100, category: "other", mcc: nil)),
            ("Foreign currency $165", "wealthsimple-vip",
             PurchaseContext(amountCad: 165, currency: "USD", category: "other", mcc: nil,
                             channel: "online")),
            ("Property tax $2,000", "triangle-we",
             PurchaseContext(amountCad: 2000, category: "other", mcc: 9311)),
            ("Canadian Tire $150", "triangle-we",
             PurchaseContext(amountCad: 150, category: "ctFamily", mcc: 5200,
                             merchantBrand: "canadian-tire")),
            ("Marriott stay $300", "amex-bonvoy",
             PurchaseContext(amountCad: 300, category: "marriottDirect", mcc: 3509,
                             merchantBrand: "marriott")),
        ]

        var agree = 0
        print("\n═══ Cheat sheet vs engine (Zubair's actual owner state) ═══\n")
        for (label, sheetCard, purchase) in rows {
            let r = engine.recommend(purchase, asOf: "2026-08-20")
            let matches = r.winner.cardId == sheetCard
            if matches { agree += 1 }
            print(String(format: "%@ %-22@ sheet: %-26@ engine: %@ ($%.2f)",
                         matches ? "✓" : "✗", label as NSString,
                         short(sheetCard, names) as NSString,
                         short(r.winner.cardId, names), r.winner.netValueCad))
            if !matches, let sheetScore = r.allCandidates.first(where: { $0.cardId == sheetCard }) {
                print(String(format: "     └─ the sheet's pick returns $%.2f — a gap of $%.2f on this purchase",
                             sheetScore.netValueCad, r.winner.netValueCad - sheetScore.netValueCad))
            }
            if let v = r.breakevenCentsPerPoint, let d = r.valuationDirection {
                print(String(format: "     └─ %@ %.2f¢/pt this flips to %@",
                             d == .above ? "above" : "below", v,
                             short(r.alternateWinnerCardId ?? "", names)))
            }
        }
        print("\n\(agree)/\(rows.count) rows agree.\n")

        // Which cards never win anything in this wallet? A keep/cancel signal.
        let winners = Set(rows.map { engine.recommend($0.2, asOf: "2026-08-20").winner.cardId })
        let idle = catalogue.cards.map(\.cardId).filter { !winners.contains($0) }
        print("Never wins a category here: \(idle.map { short($0, names) }.joined(separator: ", "))\n")
    }

    private func short(_ id: String, _ names: [String: String]) -> String {
        (names[id] ?? id)
            .replacingOccurrences(of: "The Platinum Card from American Express", with: "Amex Platinum")
            .replacingOccurrences(of: "American Express ", with: "Amex ")
            .replacingOccurrences(of: "Wealthsimple Visa Infinite Privilege Credit Card", with: "Wealthsimple")
            .replacingOccurrences(of: " World Elite", with: "").replacingOccurrences(of: " Mastercard", with: "")
            .replacingOccurrences(of: " Visa Infinite +", with: "").replacingOccurrences(of: " Card", with: "")
    }
}
