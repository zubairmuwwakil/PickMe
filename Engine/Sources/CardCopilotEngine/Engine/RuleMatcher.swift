import Foundation

public enum RuleResolution: Equatable, Sendable {
    case applied(EarnRule)
    case cardExcluded(reason: String)
}

/// Decides which earn rule a purchase triggers on one card.
///
/// Two rules govern everything here: a rule whose owner condition is unresolved is skipped
/// rather than guessed, and matching rules never stack — the best single rate wins.
public enum RuleMatcher {

    /// Categories that are a more specific case of a broader one. A predicate listing the
    /// parent matches a purchase in the child (a Marriott stay is also lodging and travel).
    static let categoryParents: [String: [String]] = [
        "marriottDirect": ["lodging", "travel"]
    ]

    public static func resolve(card: CardProduct, purchase: PurchaseContext,
                               ownerState: OwnerState, asOf: String) -> RuleResolution {
        let state = ownerState.cardStates[card.cardId] ?? CardState()
        let candidates = card.earnRules.filter { rule in
            isLive(rule, asOf: asOf)
                && conditionsResolveTrue(rule.ownerConditions, state: state)
                && matches(rule.predicate, purchase: purchase, state: state)
        }
        guard let best = candidates.max(by: { rawEarn($0.earn) < rawEarn($1.earn) }) else {
            return .cardExcluded(reason: "no scorable earn rule (unresolved or inactive owner state)")
        }
        return .applied(best)
    }

    public static func activeFxRule(for card: CardProduct, asOf: String) -> FxRule? {
        card.fxRules.first { rule in
            (rule.effectiveFrom.map { $0 <= asOf } ?? true)
                && (rule.effectiveTo.map { asOf <= $0 } ?? true)
        }
    }

    static func isLive(_ rule: EarnRule, asOf: String) -> Bool {
        guard rule.scoredInV1 != false else { return false }
        let fromOk = rule.effectiveFrom.map { $0 <= asOf } ?? true
        let toOk = rule.effectiveTo.map { asOf <= $0 } ?? true
        return fromOk && toOk
    }

    static func conditionsResolveTrue(_ conditions: [String]?, state: CardState) -> Bool {
        guard let conditions else { return true }
        return conditions.allSatisfy { condition in
            switch condition {
            case "rogersEligibleServiceLinked": return state.rogersEligibleServiceLinked == true
            case "cryptoLevelUpProActive": return state.cryptoLevelUpProActive == true
            case "tangerineCategorySelected": return state.selectedCategories != nil
            default: return false
            }
        }
    }

    static func matches(_ p: Predicate, purchase: PurchaseContext, state: CardState) -> Bool {
        if let country = p.country, country != purchase.country { return false }
        if let currency = p.currency, currency != purchase.currency { return false }
        if let channels = p.channels, !channels.contains(purchase.channel) { return false }
        if let excluded = p.merchantExclude, let brand = purchase.merchantBrand,
           excluded.contains(brand) { return false }
        if let include = p.merchantInclude {
            guard let brand = purchase.merchantBrand, include.contains(brand) else { return false }
        }
        if let mccExclude = p.mccExclude, let mcc = purchase.mcc, mccExclude.contains(mcc) { return false }

        guard let categories = p.categories else { return true }   // no category clause = base rule
        return categories.contains { category in
            switch category {
            case "recurring":
                return purchase.recurringIndicator
            case "ownerSelectedTangerineCategory":
                return state.selectedCategories?.contains(purchase.category) ?? false
            default:
                let selfOrParents = [purchase.category] + (categoryParents[purchase.category] ?? [])
                guard selfOrParents.contains(category) else { return false }
                if let include = p.mccInclude, let mcc = purchase.mcc {
                    return include.contains(mcc)   // a known MCC must qualify; unknown falls back
                }
                return true
            }
        }
    }

    /// Comparable only within one card — a card never mixes points and cashback earn rules.
    static func rawEarn(_ earn: Earn) -> Double {
        switch earn {
        case .points(let p): return p
        case .cashback(let r, _): return r * 100
        case .centsPerLitre: return -1
        }
    }
}
