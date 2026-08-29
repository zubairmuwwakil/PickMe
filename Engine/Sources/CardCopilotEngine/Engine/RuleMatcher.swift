import Foundation

public enum RuleResolution: Equatable, Sendable {
    /// The winning rule, plus the capabilities named by rules that would have matched this same
    /// purchase had this build supported them. The card is still scored on what the engine can
    /// honour; the list is what it had to leave on the table, and saying so is the whole point —
    /// a rule that vanishes without a trace is indistinguishable from a rule that lost.
    case applied(EarnRule, unsupportedCapabilities: [String])
    /// Why the card is out, and which warning says so. The warning travels with the reason
    /// because `RuleMatcher` is the only thing that knows the difference between "your account
    /// state rules this out" and "this build cannot check this rule" — and sending an owner to
    /// re-check settings over an engine gap is a lie with a support ticket attached.
    case cardExcluded(reason: String, warning: Warning)
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
        let purchase = purchase.canonicalized()
        let state = ownerState.cardStates[card.cardId] ?? CardState()
        // One matching pass, then partitioned on capability. Asking "which rules matched" and
        // "which matched but for a capability" in two separate passes would let the two drift,
        // and the warning would start naming rules that never applied to this purchase.
        let matching = card.earnRules.filter { rule in
            isScheduleLive(rule, asOf: asOf)
                && conditionsResolveTrue(rule.ownerConditions, state: state)
                && matches(rule.predicate, purchase: purchase, state: state)
        }
        let gaps = Set(matching.flatMap { capabilityGap($0) ?? [] }).sorted()
        let candidates = matching.filter { capabilityGap($0) == nil }

        guard let best = candidates.max(by: { rawEarn($0.earn) < rawEarn($1.earn) }) else {
            // A capability gap is the more specific cause and outranks the generic one: it names
            // something the engine can fix, where owner state names something only the owner can.
            guard gaps.isEmpty else {
                return .cardExcluded(
                    reason: "earn rule needs \(gaps.joined(separator: ", ")), "
                          + "which this build does not support",
                    warning: .unsupportedCapability)
            }
            return .cardExcluded(reason: "no scorable earn rule (unresolved or inactive owner state)",
                                 warning: .unresolvedOwnerState)
        }
        return .applied(best, unsupportedCapabilities: gaps)
    }

    public static func activeFxRule(for card: CardProduct, asOf: String) -> FxRule? {
        card.fxRules.first { rule in
            (rule.effectiveFrom.map { $0 <= asOf } ?? true)
                && (rule.effectiveTo.map { asOf <= $0 } ?? true)
        }
    }

    /// Scorable right now: in its date window, not permanently out of scope, and needing nothing
    /// this build lacks.
    static func isLive(_ rule: EarnRule, asOf: String) -> Bool {
        isScheduleLive(rule, asOf: asOf) && capabilityGap(rule) == nil
    }

    /// Everything about liveness that is NOT about capability — dates, `scoredInV1`, and the
    /// permanent `outOfScope` verdict. Split out so `resolve` can tell a rule that lost from a
    /// rule this build could not run: the second is reportable, the first is not, and the third
    /// (`outOfScope`) is deliberately neither, because "never" is not a gap awaiting a fix.
    static func isScheduleLive(_ rule: EarnRule, asOf: String) -> Bool {
        if rule.outOfScope != nil { return false }
        guard rule.scoredInV1 != false else { return false }
        let fromOk = rule.effectiveFrom.map { $0 <= asOf } ?? true
        let toOk = rule.effectiveTo.map { asOf <= $0 } ?? true
        return fromOk && toOk
    }

    /// The capability names this rule needs and this build does not have, or nil when it is fully
    /// supported. Unknown strings fail closed and are reported by name: an unrecognised capability
    /// is a data error, and assuming support would score a rule the engine cannot honour.
    static func capabilityGap(_ rule: EarnRule) -> [String]? {
        guard let requires = rule.requires else { return nil }
        let missing = requires.filter { name in
            guard let capability = EngineCapability(rawValue: name) else { return true }
            return !EngineCapability.supported.contains(capability)
        }
        return missing.isEmpty ? nil : missing
    }

    /// Owner conditions resolve from `CardState.resolvedFlags`, keyed by the catalogue's own ids,
    /// so declaring a new one in `contracts/owner-conditions.json` needs no code here at all.
    ///
    /// Tangerine keeps an explicit case: `selectedCategories` is structural state that specific
    /// engine logic reads (`matchesOwnerSelection`), not a yes/no answer (spec §3.2).
    ///
    /// Fails closed on anything unanswered — an absent key is "not asked", never "no". This used
    /// to be a switch over three hardcoded names with `default: return false`, which is how
    /// `amazonEligiblePrimeLinked` shipped in the catalogue and never fired in any build.
    static func conditionsResolveTrue(_ conditions: [String]?, state: CardState) -> Bool {
        guard let conditions else { return true }
        let flags = state.resolvedFlags
        return conditions.allSatisfy { condition in
            switch condition {
            case "tangerineCategorySelected": return state.selectedCategories != nil
            default: return flags[condition] ?? false
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
            case "ownerSelectedTangerineCategory", "ownerSelectedCategory":
                // Generalized 2026-08-26 for US selectable-category cards — the mechanism
                // (CardState.selectedCategories) was never Tangerine-specific, only the string
                // naming it was. Both names are accepted so no existing catalogue rule needs
                // rewriting.
                return matchesOwnerSelection(purchase: purchase, state: state)
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

    private static func matchesOwnerSelection(purchase: PurchaseContext,
                                               state: CardState) -> Bool {
        guard let selections = state.selectedCategories else { return false }
        let selected = Set(selections)
        let purchaseCategories = Set(
            [purchase.category] + (categoryParents[purchase.category] ?? [])
        )

        if !selected.isDisjoint(with: purchaseCategories) { return true }
        if purchase.recurringIndicator,
           selected.contains(TangerineMoneyBackCategory.recurring.rawValue) {
            return true
        }
        if purchase.currency.uppercased() != "CAD",
           selected.contains(TangerineMoneyBackCategory.foreignCurrency.rawValue) {
            return true
        }

        // Backward compatibility for owner-state files that used Tangerine's label-shaped id
        // before the setup screen adopted the engine's canonical `lodging` category.
        return purchaseCategories.contains(TangerineMoneyBackCategory.lodging.rawValue)
            && selected.contains("hotelMotel")
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
