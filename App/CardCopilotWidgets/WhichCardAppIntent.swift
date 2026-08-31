import AppIntents
import Foundation
import CardCopilotEngine
import CardCopilotStore

/// An App Intent providing sub-second card recommendation via Action Button, Siri, and Shortcuts.
public struct WhichCardIntent: AppIntent {
    public static let title: LocalizedStringResource = "Which Card Should I Use?"
    public static let description = IntentDescription("Suggests the optimal credit card for a given merchant or category.")

    @Parameter(title: "Merchant or Category", description: "The store or category you are buying from (e.g. Costco, Groceries, Dining, Shell).")
    public var query: String?

    public init() {}

    public init(query: String?) {
        self.query = query
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // If query is empty, prompt user or return generic response
        if trimmedQuery.isEmpty {
            return .result(dialog: "Open PickMe at checkout or specify a store like Costco, Tim Hortons, or Groceries.")
        }

        // Try to load engine dependencies
        guard let catalogue = try? SeedLoader.loadCatalogue() else {
            return .result(dialog: "PickMe could not load card rules. Open PickMe to try again.")
        }
        guard let ownerState = OwnerStateLocalStore().loadForRecommendation() else {
            return .result(dialog: "Your PickMe wallet is empty. Open PickMe to add your cards first.")
        }
        let today = Date().formatted(.iso8601.year().month().day())
        let engine = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)

        // 1. Check Pre-Indexed Canadian Merchants
        let preIndexed = CanadianMerchantPreIndex.search(trimmedQuery, limit: 1)
        if let merchant = preIndexed.first {
            let context = PurchaseContext(amountCad: 50.0, category: merchant.category, mcc: merchant.mcc, merchantBrand: merchant.merchantBrand, acceptedNetworks: merchant.acceptedNetworks)
            let outcome = engine.recommend(context, asOf: today)
            if case .advised(let rec) = outcome {
                let winnerCard = catalogue.cards.first { $0.cardId == rec.winner.cardId }?.officialName ?? rec.winner.cardId
                let networkWarning = merchant.acceptedNetworks.contains(.amex) ? "" : " (Note: \(merchant.name) does not take Amex)."
                let resultMessage = "For \(merchant.name), use your \(winnerCard)\(networkWarning)."
                return .result(dialog: IntentDialog(stringLiteral: resultMessage))
            }
        }

        // 2. Fallback on general category prediction
        let prediction = CardCopilotStore.predict(poiCategoryRaw: nil, merchantName: trimmedQuery)
        let context = PurchaseContext(amountCad: 50.0, category: prediction.category)
        let outcome = engine.recommend(context, asOf: today)
        if case .advised(let rec) = outcome {
            let winnerCard = catalogue.cards.first { $0.cardId == rec.winner.cardId }?.officialName ?? rec.winner.cardId
            let resultMessage = "For \(trimmedQuery), your best card is \(winnerCard)."
            return .result(dialog: IntentDialog(stringLiteral: resultMessage))
        }

        return .result(dialog: IntentDialog(stringLiteral: "Looking up the best card for \(trimmedQuery)... Open PickMe to see your wallet rank."))
    }
}

/// Automatically exposes PickMe's Siri Shortcuts to iOS without requiring manual Shortcut creation.
public struct CardCopilotShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhichCardIntent(),
            phrases: [
                "Which card in \(.applicationName)?",
                "Ask \(.applicationName) which card to use"
            ],
            shortTitle: "Which Card?",
            systemImageName: "creditcard.fill"
        )
    }
}
