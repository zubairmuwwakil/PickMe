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

    /// Filters cards by bank / provider tile ID.
    static func filter(_ cards: [CardProduct], bankFilter: String) -> [CardProduct] {
        guard bankFilter != "All" else { return cards }
        return cards.filter { matchesBankFilter($0, bankFilter: bankFilter) }
    }

    /// Determines if a card matches the given bank filter identifier.
    static func matchesBankFilter(_ card: CardProduct, bankFilter: String) -> Bool {
        let style = CardVisualTheme.style(for: card.cardId)
        let issuer = card.issuer
        let styleIssuer = style.issuer
        let name = card.officialName
        let cid = card.cardId

        switch bankFilter {
        case "All":
            return true
        case "Amex":
            return issuer.localizedCaseInsensitiveContains("American Express")
                || styleIssuer.localizedCaseInsensitiveContains("American Express")
                || styleIssuer.localizedCaseInsensitiveContains("Amex")
                || card.network == .amex
                || cid.localizedCaseInsensitiveContains("amex")
                || cid.localizedCaseInsensitiveContains("american-express")
        case "Scotiabank":
            return issuer.localizedCaseInsensitiveContains("Scotia")
                || styleIssuer.localizedCaseInsensitiveContains("Scotia")
                || cid.localizedCaseInsensitiveContains("scotia")
        case "RBC":
            return issuer.localizedCaseInsensitiveContains("RBC")
                || issuer.localizedCaseInsensitiveContains("Royal Bank")
                || styleIssuer.localizedCaseInsensitiveContains("RBC")
                || cid.localizedCaseInsensitiveContains("rbc")
        case "TD":
            return issuer.localizedCaseInsensitiveContains("TD")
                || styleIssuer.localizedCaseInsensitiveContains("TD")
                || cid.localizedCaseInsensitiveContains("td-")
                || cid.hasPrefix("td")
        case "BMO":
            return issuer.localizedCaseInsensitiveContains("BMO")
                || issuer.localizedCaseInsensitiveContains("Bank of Montreal")
                || styleIssuer.localizedCaseInsensitiveContains("BMO")
                || cid.localizedCaseInsensitiveContains("bmo")
        case "CIBC":
            return issuer.localizedCaseInsensitiveContains("CIBC")
                || issuer.localizedCaseInsensitiveContains("Simplii")
                || styleIssuer.localizedCaseInsensitiveContains("CIBC")
                || cid.localizedCaseInsensitiveContains("cibc")
                || cid.localizedCaseInsensitiveContains("simplii")
        case "MBNA":
            return issuer.localizedCaseInsensitiveContains("MBNA")
                || styleIssuer.localizedCaseInsensitiveContains("MBNA")
                || cid.localizedCaseInsensitiveContains("mbna")
        case "Tangerine":
            return issuer.localizedCaseInsensitiveContains("Tangerine")
                || styleIssuer.localizedCaseInsensitiveContains("Tangerine")
                || cid.localizedCaseInsensitiveContains("tangerine")
        case "Rogers":
            return issuer.localizedCaseInsensitiveContains("Rogers")
                || styleIssuer.localizedCaseInsensitiveContains("Rogers")
                || cid.localizedCaseInsensitiveContains("rogers")
        case "Desjardins":
            return issuer.localizedCaseInsensitiveContains("Desjardins")
                || styleIssuer.localizedCaseInsensitiveContains("Desjardins")
                || cid.localizedCaseInsensitiveContains("desjardins")
        case "National Bank":
            return issuer.localizedCaseInsensitiveContains("National Bank")
                || issuer.localizedCaseInsensitiveContains("Banque Nationale")
                || styleIssuer.localizedCaseInsensitiveContains("National Bank")
                || cid.localizedCaseInsensitiveContains("nbc")
                || cid.localizedCaseInsensitiveContains("national-bank")
        case "PC Financial":
            return issuer.localizedCaseInsensitiveContains("President's Choice")
                || issuer.localizedCaseInsensitiveContains("PC Financial")
                || styleIssuer.localizedCaseInsensitiveContains("PC")
                || cid.hasPrefix("pc-")
                || cid.localizedCaseInsensitiveContains("pc-financial")
        case "Triangle":
            return issuer.localizedCaseInsensitiveContains("Canadian Tire")
                || name.localizedCaseInsensitiveContains("Triangle")
                || cid.localizedCaseInsensitiveContains("triangle")
        case "Wealthsimple":
            return issuer.localizedCaseInsensitiveContains("Wealthsimple")
                || styleIssuer.localizedCaseInsensitiveContains("Wealthsimple")
                || cid.localizedCaseInsensitiveContains("wealthsimple")
        case "Neo":
            return issuer.localizedCaseInsensitiveContains("Neo")
                || styleIssuer.localizedCaseInsensitiveContains("Neo")
                || cid.localizedCaseInsensitiveContains("neo")
        case "Capital One":
            return issuer.localizedCaseInsensitiveContains("Capital One")
                || styleIssuer.localizedCaseInsensitiveContains("Capital One")
                || cid.localizedCaseInsensitiveContains("capital-one")
        case "Chase":
            return issuer.localizedCaseInsensitiveContains("Chase")
                || issuer.localizedCaseInsensitiveContains("JPMorgan")
                || styleIssuer.localizedCaseInsensitiveContains("Chase")
                || cid.localizedCaseInsensitiveContains("chase")
        case "Citi":
            return issuer.localizedCaseInsensitiveContains("Citi")
                || styleIssuer.localizedCaseInsensitiveContains("Citi")
                || cid.localizedCaseInsensitiveContains("citi")
        case "Bank of America":
            return issuer.localizedCaseInsensitiveContains("Bank of America")
                || issuer.localizedCaseInsensitiveContains("BofA")
                || styleIssuer.localizedCaseInsensitiveContains("Bank of America")
                || cid.localizedCaseInsensitiveContains("bank-of-america")
        case "Discover":
            return issuer.localizedCaseInsensitiveContains("Discover")
                || card.network == .discover
                || styleIssuer.localizedCaseInsensitiveContains("Discover")
                || cid.localizedCaseInsensitiveContains("discover")
        case "Wells Fargo":
            return issuer.localizedCaseInsensitiveContains("Wells Fargo")
                || styleIssuer.localizedCaseInsensitiveContains("Wells Fargo")
                || cid.localizedCaseInsensitiveContains("wells-fargo")
        case "Barclays":
            return issuer.localizedCaseInsensitiveContains("Barclays")
                || styleIssuer.localizedCaseInsensitiveContains("Barclays")
                || cid.localizedCaseInsensitiveContains("barclays")
        case "U.S. Bank":
            return issuer.localizedCaseInsensitiveContains("U.S. Bank")
                || issuer.localizedCaseInsensitiveContains("US Bank")
                || styleIssuer.localizedCaseInsensitiveContains("U.S. Bank")
                || cid.localizedCaseInsensitiveContains("u-s-bank")
                || cid.localizedCaseInsensitiveContains("us-bank")
        case "Apple":
            return name.localizedCaseInsensitiveContains("Apple")
                || issuer.localizedCaseInsensitiveContains("Goldman Sachs")
                || cid.localizedCaseInsensitiveContains("apple")
        case "Bilt":
            return name.localizedCaseInsensitiveContains("Bilt")
                || issuer.localizedCaseInsensitiveContains("Column")
                || cid.localizedCaseInsensitiveContains("bilt")
        case "No Fee":
            return (card.fee.annual?.amount ?? 0) == 0
        default:
            return issuer.localizedCaseInsensitiveContains(bankFilter)
                || name.localizedCaseInsensitiveContains(bankFilter)
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

