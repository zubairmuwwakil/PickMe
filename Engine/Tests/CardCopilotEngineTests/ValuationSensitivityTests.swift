import XCTest
@testable import CardCopilotEngine

/// Answers one question: how much does the Membership Rewards valuation change the advice?
/// 1.8¢ assumes Aeroplan transfers actually happen; 1.0¢ is the statement-credit floor.
/// Run with: swift test --filter ValuationSensitivityTests
final class ValuationSensitivityTests: XCTestCase {

    private func state(_ base: OwnerState, mrCentsPerPoint: Double) -> OwnerState {
        var s = base
        s.valuationsCad.amexMembershipRewards.centsPerPoint = mrCentsPerPoint
        return s
    }

    func testPrintValuationSensitivity() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let base = try SeedLoader.loadPinnedOwnerState()
        let optimistic = RecommendationEngine(catalogue: catalogue,
                                              ownerState: state(base, mrCentsPerPoint: 1.8))
        let floor = RecommendationEngine(catalogue: catalogue,
                                         ownerState: state(base, mrCentsPerPoint: 1.0))
        let names = Dictionary(uniqueKeysWithValues: catalogue.cards.map { ($0.cardId, $0.officialName) })

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
            ("Marriott stay $300", PurchaseContext(amountCad: 300, category: "marriottDirect",
                                                   mcc: 3509, merchantBrand: "marriott")),
            ("Flight $600", PurchaseContext(amountCad: 600, category: "travel", mcc: 3000)),
            ("Pharmacy $30", PurchaseContext(amountCad: 30, category: "drugStore", mcc: 5912)),
        ]

        var flips = 0
        print("\n═══ Membership Rewards valuation sensitivity: 1.8¢ vs 1.0¢ floor ═══")
        for (label, purchase) in checkouts {
            let a = optimistic.recommend(purchase, asOf: "2026-08-20")
            let b = floor.recommend(purchase, asOf: "2026-08-20")
            let changed = a.winner.cardId != b.winner.cardId
            if changed { flips += 1 }
            let marker = changed ? "⚠ FLIPS" : "  same "
            print("\(marker)  \(label.padding(toLength: 20, withPad: " ", startingAt: 0))"
                  + " 1.8¢ → \(short(names[a.winner.cardId] ?? "")) "
                  + String(format: "$%.2f", a.winner.netValueCad)
                  + "   |   1.0¢ → \(short(names[b.winner.cardId] ?? "")) "
                  + String(format: "$%.2f", b.winner.netValueCad))
        }
        print("\n\(flips) of \(checkouts.count) recommendations depend on the MR valuation.\n")
    }

    private func short(_ name: String) -> String {
        name.replacingOccurrences(of: "American Express ", with: "Amex ")
            .replacingOccurrences(of: " Credit Card", with: "")
            .replacingOccurrences(of: " Mastercard", with: "")
            .replacingOccurrences(of: " Card", with: "")
            .padding(toLength: 34, withPad: " ", startingAt: 0)
    }
}
