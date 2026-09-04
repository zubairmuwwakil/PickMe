import AppIntents
import Foundation
import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// Visual snippet view rendered inside Spotlight, Siri, and Shortcuts dialogs.
public struct WhichCardSnippetView: View {
    public let merchantName: String
    public let cardName: String
    public let categoryName: String
    public let headline: String
    public let networkWarning: String?

    public nonisolated init(
        merchantName: String,
        cardName: String,
        categoryName: String,
        headline: String,
        networkWarning: String? = nil
    ) {
        self.merchantName = merchantName
        self.cardName = cardName
        self.categoryName = categoryName
        self.headline = headline
        self.networkWarning = networkWarning
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(merchantName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(categoryName.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "creditcard.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("OPTIMAL CARD")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(cardName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
            }

            if !headline.isEmpty {
                Text(headline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let networkWarning, !networkWarning.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(networkWarning)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(12)
    }
}

/// An App Intent providing sub-second card recommendation via Action Button, Siri, and Shortcuts.
public struct WhichCardIntent: AppIntent {
    public static let title: LocalizedStringResource = "Which Card Should I Use?"
    public static let description = IntentDescription("Suggests the optimal credit card for a given merchant or category.")

    @Parameter(title: "Merchant or Category", description: "The store or category you are buying from (e.g. Costco, Groceries, Dining, Shell).")
    public var query: String?

    @Parameter(title: "Amount", description: "The estimated purchase amount in CAD (optional).")
    public var amount: Double?

    public init() {}

    public init(query: String?, amount: Double? = nil) {
        self.query = query
        self.amount = amount
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let purchaseAmount = (amount ?? 50.0) > 0 ? (amount ?? 50.0) : 50.0

        // If query is empty, prompt user or return generic response
        if trimmedQuery.isEmpty {
            let prompt = "Open PickMe at checkout or specify a store like Costco, Tim Hortons, or Groceries."
            return .result(
                dialog: IntentDialog(stringLiteral: prompt),
                view: WhichCardSnippetView(
                    merchantName: "PickMe Checkout",
                    cardName: "Ready to check",
                    categoryName: "Enter store name",
                    headline: prompt
                )
            )
        }

        // Try to load engine dependencies
        guard let catalogue = try? SeedLoader.loadCatalogue() else {
            let errorMsg = "PickMe could not load card rules. Open PickMe to try again."
            return .result(
                dialog: IntentDialog(stringLiteral: errorMsg),
                view: WhichCardSnippetView(
                    merchantName: trimmedQuery,
                    cardName: "Card Rules Missing",
                    categoryName: "Error",
                    headline: errorMsg
                )
            )
        }
        guard let ownerState = OwnerStateLocalStore().loadForRecommendation() else {
            let emptyMsg = "Your PickMe wallet is empty. Open PickMe to add your cards first."
            return .result(
                dialog: IntentDialog(stringLiteral: emptyMsg),
                view: WhichCardSnippetView(
                    merchantName: trimmedQuery,
                    cardName: "Wallet Empty",
                    categoryName: "Setup Required",
                    headline: emptyMsg
                )
            )
        }
        let today = Date().formatted(.iso8601.year().month().day())
        let engine = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)
        let explainer = RecommendationExplainer(catalogue: catalogue)

        // 1. Check Pre-Indexed Canadian Merchants.
        //
        // Recognition first, search only as a fallback for fragments. `search` matches when the
        // query is a substring of the DISPLAY name, so it cannot see a brand inside a fuller
        // string — "Costco Wholesale Kanata" and "AMZN MKTP CA" both come back empty — while
        // `recognise` matches the pack's curated descriptor keys as whole words, longest first.
        // This block prints "Does not accept American Express", so the row it picks is an
        // affirmative claim, not a suggestion; the fallback survives only because `search` needs
        // the query to be a substring of a real brand name, which cannot reach a grocery banner
        // from an unrelated restaurant's name.
        let preIndexed = MerchantRecognizer.recognise(trimmedQuery)
            ?? CanadianMerchantPreIndex.search(trimmedQuery, limit: 1).first
        if let merchant = preIndexed {
            let context = PurchaseContext(
                amountCad: purchaseAmount,
                category: merchant.category,
                mcc: merchant.mcc,
                merchantBrand: merchant.merchantBrand,
                acceptedNetworks: merchant.acceptedNetworks
            )
            let outcome = engine.recommend(context, asOf: today)
            if case .advised(let rec) = outcome {
                let winnerCard = catalogue.cards.first { $0.cardId == rec.winner.cardId }?.officialName ?? rec.winner.cardId
                let explanation = explainer.explain(rec, purchase: context)
                let networkWarning = merchant.acceptedNetworks.contains(.amex) ? nil : "Does not accept American Express"
                let resultMessage = "For \(merchant.name), use your \(winnerCard)."
                return .result(
                    dialog: IntentDialog(stringLiteral: resultMessage),
                    view: WhichCardSnippetView(
                        merchantName: merchant.name,
                        cardName: winnerCard,
                        categoryName: merchant.category,
                        headline: explanation.headline,
                        networkWarning: networkWarning
                    )
                )
            }
        }

        // 2. Fallback on general category prediction
        let prediction = CardCopilotStore.predict(poiCategoryRaw: nil, merchantName: trimmedQuery)
        let context = PurchaseContext(amountCad: purchaseAmount, category: prediction.category)
        let outcome = engine.recommend(context, asOf: today)
        if case .advised(let rec) = outcome {
            let winnerCard = catalogue.cards.first { $0.cardId == rec.winner.cardId }?.officialName ?? rec.winner.cardId
            let explanation = explainer.explain(rec, purchase: context)
            let resultMessage = "For \(trimmedQuery), your best card is \(winnerCard)."
            return .result(
                dialog: IntentDialog(stringLiteral: resultMessage),
                view: WhichCardSnippetView(
                    merchantName: trimmedQuery,
                    cardName: winnerCard,
                    categoryName: prediction.category,
                    headline: explanation.headline
                )
            )
        }

        let fallbackMsg = "Looking up the best card for \(trimmedQuery)... Open PickMe to see your wallet rank."
        return .result(
            dialog: IntentDialog(stringLiteral: fallbackMsg),
            view: WhichCardSnippetView(
                merchantName: trimmedQuery,
                cardName: "Open PickMe",
                categoryName: "Unknown",
                headline: fallbackMsg
            )
        )
    }
}

/// An iOS 26 Apple Intelligence / Visual Intelligence Intent to analyze checkout screenshots and receipts.
public struct AnalyzeCartScreenshotIntent: AppIntent {
    public static let title: LocalizedStringResource = "Analyze Checkout Cart or Screenshot"
    public static let description = IntentDescription("Extracts merchant and cart total from a screenshot or text to suggest the best card.")

    @Parameter(title: "Cart or Receipt Text", description: "Text extracted from the checkout screen, receipt, or cart screenshot.")
    public var cartText: String?

    public init() {}

    public init(cartText: String?) {
        self.cartText = cartText
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let text = cartText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            return try await WhichCardIntent(query: nil).perform()
        }

        // Extract merchant and amount
        var detectedMerchant = "Online Checkout"
        var detectedAmount: Double = 50.0

        // Parse dollar amount if present ($XX.XX)
        let amountPattern = #"\$([0-9]+(?:\.[0-9]{2})?)"#
        if let regex = try? NSRegularExpression(pattern: amountPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            detectedAmount = Double(text[range]) ?? 50.0
        }

        // Scan against known Canadian merchants. `text` here is a whole sentence or a pasted
        // receipt line, which is the one shape `search` can never match — it asks whether the
        // query is inside a brand name, and this is the reverse question. Recognition is the
        // right tool and the reason this branch starts firing at all.
        if let merchant = MerchantRecognizer.recognise(text) {
            detectedMerchant = merchant.name
        }

        let delegateIntent = WhichCardIntent(query: detectedMerchant, amount: detectedAmount)
        return try await delegateIntent.perform()
    }
}

/// An App Intent to launch PickMe Radar directly from Action Button, Lock Screen, or Control Center.
public struct LaunchRadarIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open PickMe Radar"
    public static let description = IntentDescription("Opens PickMe and immediately scans for nearby merchants.")
    public static let openAppWhenRun: Bool = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        return .result()
    }
}

/// Automatically exposes PickMe's Siri Shortcuts and Apple Intelligence AI Actions to iOS.
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
        AppShortcut(
            intent: LaunchRadarIntent(),
            phrases: [
                "Scan nearby with \(.applicationName)",
                "Open \(.applicationName) Radar"
            ],
            shortTitle: "Checkout Radar",
            systemImageName: "location.magnifyingglass"
        )
        AppShortcut(
            intent: AnalyzeCartScreenshotIntent(),
            phrases: [
                "Analyze cart in \(.applicationName)",
                "Analyze checkout in \(.applicationName)"
            ],
            shortTitle: "Analyze Cart",
            systemImageName: "text.viewfinder"
        )
    }
}
