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

        // 1. Check Pre-Indexed Canadian Merchants
        let preIndexed = CanadianMerchantPreIndex.search(trimmedQuery, limit: 1)
        if let merchant = preIndexed.first {
            let categoryName = merchant.category
            let networkInfo = merchant.acceptedNetworks.contains(.amex) ? "" : " (Note: \(merchant.name) doesn't take Amex)."
            let resultMessage = "For \(merchant.name) (\(categoryName)), check your top card in PickMe\(networkInfo)."
            return .result(dialog: IntentDialog(stringLiteral: resultMessage))
        }

        // 2. Fallback on general category
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
