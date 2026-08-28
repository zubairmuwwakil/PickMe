import Foundation
import CardCopilotEngine

/// Which markets the card list is showing. A VIEW preference, not owner state: `Market` is a
/// closed two-case enum and `.both` is not a residency anyone has. Residency lives in
/// `OwnerState.market` and drives AcquisitionAnalyzer; this only decides what the list renders.
enum MarketScope: String, CaseIterable, Sendable {
    case canada, unitedStates, both

    var markets: Set<Market> {
        switch self {
        case .canada: return [.ca]
        case .unitedStates: return [.us]
        case .both: return [.ca, .us]
        }
    }

    static func `default`(for residency: Market) -> MarketScope {
        switch residency {
        case .ca: return .canada
        case .us: return .unitedStates
        }
    }

    var title: String {
        switch self {
        case .canada: return String(localized: "Canada")
        case .unitedStates: return String(localized: "US")
        case .both: return String(localized: "Both")
        }
    }
}

/// Pure catalogue shaping for the wallet UI. No SwiftUI, so every rule here is unit-testable —
/// which matters because these two predicates are the difference between offering someone a card
/// PickMe can advise on and one the Scorer will refuse to score for the life of their wallet.
enum WalletCardCatalogue {

    /// Cards a person may actually add. Two gates, both non-negotiable:
    /// `isPublished` (a draft is research-grade and `Scorer` excludes it) and market.
    static func selectable(_ cards: [CardProduct], scope: MarketScope) -> [CardProduct] {
        let markets = scope.markets
        return cards.filter { $0.isPublished && markets.contains($0.market) }
    }

    /// Token search over an ALREADY-SCOPED array. Every token must match some field, so
    /// "scotia visa" narrows rather than widens. Unchanged from the original implementation.
    static func filter(_ cards: [CardProduct], matching query: String) -> [CardProduct] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cards }
        let tokens = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return cards.filter { card in
            let style = CardVisualTheme.style(for: card.cardId)
            let searchableFields = [
                card.officialName, card.issuer, card.network.rawValue, card.cardId,
                style.shortName, style.issuer, style.network.rawValue
            ]
            return tokens.allSatisfy { token in
                searchableFields.contains { $0.localizedCaseInsensitiveContains(token) }
            }
        }
    }

    /// Issuer sections, alphabetical, cards alphabetical within each. Grouping is what makes a
    /// list of this size scannable — 41 cards today, and the catalogue's stated horizon is
    /// thousands.
    static func groupedByIssuer(_ cards: [CardProduct]) -> [(issuer: String, cards: [CardProduct])] {
        Dictionary(grouping: cards, by: \.issuer)
            .map { (issuer: $0.key, cards: $0.value.sorted { $0.officialName < $1.officialName }) }
            .sorted { $0.issuer < $1.issuer }
    }
}
