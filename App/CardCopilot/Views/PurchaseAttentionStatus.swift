import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// Specific attention issue or missing fact detected on a stored purchase.
public enum PurchaseAttentionIssue: Identifiable, Equatable, Hashable, Sendable {
    case missingAmount
    case missingCard
    case uncertainCategory(category: String?)
    case suboptimalCard(betterCardId: String, advantageCad: Double?)
    case unreconciled

    public var id: String {
        switch self {
        case .missingAmount: return "missingAmount"
        case .missingCard: return "missingCard"
        case .uncertainCategory: return "uncertainCategory"
        case .suboptimalCard(let cardId, _): return "suboptimalCard-\(cardId)"
        case .unreconciled: return "unreconciled"
        }
    }

    public var title: String {
        switch self {
        case .missingAmount: return "Amount Needed"
        case .missingCard: return "Card Not Recorded"
        case .uncertainCategory: return "Category Needs Review"
        case .suboptimalCard: return "Better Card Available"
        case .unreconciled: return "Ready for Statement"
        }
    }

    public var subtitle: String {
        switch self {
        case .missingAmount:
            return "Add the total charge & currency to enable rewards optimization."
        case .missingCard:
            return "Select which card you tapped at the till to track accurate points."
        case .uncertainCategory:
            return "Estimated fallback category. Tap to confirm or reclassify."
        case .suboptimalCard(_, let advantage):
            if let advantage, advantage > 0 {
                return String(format: "+$%.2f potential value missed on this purchase.", advantage)
            }
            return "A different wallet card offers higher return for this category."
        case .unreconciled:
            return "Purchase is complete and waiting for statement confirmation."
        }
    }

    public var icon: String {
        switch self {
        case .missingAmount: return "dollarsign.circle.fill"
        case .missingCard: return "creditcard.trianglebadge.exclamationmark.fill"
        case .uncertainCategory: return "tag.fill"
        case .suboptimalCard: return "arrow.up.right.circle.fill"
        case .unreconciled: return "tray.and.arrow.down.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .missingAmount: return .blue
        case .missingCard: return .orange
        case .uncertainCategory: return .purple
        case .suboptimalCard: return .orange
        case .unreconciled: return .teal
        }
    }

    public var isActionableNow: Bool {
        switch self {
        case .missingAmount, .missingCard, .uncertainCategory: return true
        case .suboptimalCard, .unreconciled: return false
        }
    }
}

/// Evaluator that scans stored purchases for missing facts, uncertain estimations, or discrepancies.
enum PurchaseAttentionEvaluator {
    static func issues(
        for purchase: StoredPurchase,
        graph: DependencyGraph? = nil,
        knownMerchants: [StoredMerchant] = [],
        walletFeedback: WalletFeedback? = nil
    ) -> [PurchaseAttentionIssue] {
        var issues: [PurchaseAttentionIssue] = []

        // 1. Missing Amount
        if purchase.amountCad == nil {
            issues.append(.missingAmount)
        }

        // 2. Missing Card
        if purchase.cardUsedId == nil {
            issues.append(.missingCard)
        }

        // 3. Category Uncertainty (Fallback / unverified without confirmed merchant)
        let hasObservation = purchase.observation != nil
        let confidence = purchase.categoryConfidence ?? purchase.prediction?.confidenceSource
        if !hasObservation && (confidence == .fallback || confidence == nil) {
            let cat = purchase.displayCategory
            issues.append(.uncertainCategory(category: cat))
        }

        // 4. Suboptimal Card Assessment
        if let graph {
            let assessment = PurchaseActivityEvaluator.cardAssessment(
                for: purchase,
                graph: graph,
                knownMerchants: knownMerchants,
                walletFeedback: walletFeedback
            )
            if case .better(let betterCardId, let advantageCad) = assessment {
                issues.append(.suboptimalCard(betterCardId: betterCardId, advantageCad: advantageCad))
            }
        }

        // 5. Unreconciled
        if purchase.isComplete && purchase.observation == nil && purchase.prediction != nil {
            issues.append(.unreconciled)
        }

        return issues
    }

    /// Whether this purchase requires immediate action (missing amount, missing card, or uncertain category).
    static func needsAttention(
        _ purchase: StoredPurchase,
        graph: DependencyGraph? = nil,
        knownMerchants: [StoredMerchant] = [],
        walletFeedback: WalletFeedback? = nil
    ) -> Bool {
        let all = issues(for: purchase, graph: graph, knownMerchants: knownMerchants, walletFeedback: walletFeedback)
        return all.contains(where: \.isActionableNow)
    }

    static func primaryIssue(
        for purchase: StoredPurchase,
        graph: DependencyGraph? = nil,
        knownMerchants: [StoredMerchant] = [],
        walletFeedback: WalletFeedback? = nil
    ) -> PurchaseAttentionIssue? {
        let all = issues(for: purchase, graph: graph, knownMerchants: knownMerchants, walletFeedback: walletFeedback)
        // Prioritize missing amount, then missing card, then category uncertainty, then suboptimal card, then unreconciled
        if let missingAmt = all.first(where: { $0 == .missingAmount }) { return missingAmt }
        if let missingCard = all.first(where: { $0 == .missingCard }) { return missingCard }
        if let uncertainCat = all.first(where: { if case .uncertainCategory = $0 { return true }; return false }) { return uncertainCat }
        return all.first
    }
}
