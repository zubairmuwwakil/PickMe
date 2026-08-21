package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.CardProduct
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.Earn
import com.cardcopilot.engine.models.EarnRule
import com.cardcopilot.engine.models.EngineCapability
import com.cardcopilot.engine.models.FxRule
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.Predicate
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.TangerineMoneyBackCategory
import com.cardcopilot.engine.models.Warning

sealed interface RuleResolution {
    /**
     * The winning rule, plus the capabilities named by rules that would have matched this same
     * purchase had this build supported them. The card is still scored on what the engine can
     * honour; the list is what it had to leave on the table, and saying so is the whole point —
     * a rule that vanishes without a trace is indistinguishable from a rule that lost.
     */
    data class Applied(
        val rule: EarnRule,
        val unsupportedCapabilities: List<String> = emptyList()
    ) : RuleResolution

    /**
     * Why the card is out, and which warning says so. The warning travels with the reason
     * because [RuleMatcher] is the only thing that knows the difference between "your account
     * state rules this out" and "this build cannot check this rule" — and sending an owner to
     * re-check settings over an engine gap is a lie with a support ticket attached.
     */
    data class CardExcluded(val reason: String, val warning: Warning) : RuleResolution
}

object RuleMatcher {
    val categoryParents: Map<String, List<String>> = mapOf(
        "marriottDirect" to listOf("lodging", "travel")
    )

    fun resolve(
        card: CardProduct,
        purchase: PurchaseContext,
        ownerState: OwnerState,
        asOf: String
    ): RuleResolution {
        val state = ownerState.cardStates[card.cardId] ?: CardState()
        // One matching pass, then partitioned on capability. Asking "which rules matched" and
        // "which matched but for a capability" in two separate passes would let the two drift,
        // and the warning would start naming rules that never applied to this purchase.
        val matching = card.earnRules.filter { rule ->
            isScheduleLive(rule, asOf) &&
                conditionsResolveTrue(rule.ownerConditions, state) &&
                matches(rule.predicate, purchase, state)
        }
        val gaps = matching.flatMap { capabilityGap(it) ?: emptyList() }.distinct().sorted()
        val candidates = matching.filter { capabilityGap(it) == null }

        val best = candidates.maxByOrNull { rawEarn(it.earn) }
            ?: return if (gaps.isNotEmpty()) {
                // A capability gap is the more specific cause and outranks the generic one: it
                // names something the engine can fix, where owner state names something only the
                // owner can.
                RuleResolution.CardExcluded(
                    "earn rule needs ${gaps.joinToString(", ")}, which this build does not support",
                    Warning.UNSUPPORTED_CAPABILITY
                )
            } else {
                RuleResolution.CardExcluded(
                    "no scorable earn rule (unresolved or inactive owner state)",
                    Warning.UNRESOLVED_OWNER_STATE
                )
            }

        return RuleResolution.Applied(best, gaps)
    }

    fun activeFxRule(card: CardProduct, asOf: String): FxRule? {
        return card.fxRules.firstOrNull { rule ->
            (rule.effectiveFrom?.let { it <= asOf } ?: true) &&
                (rule.effectiveTo?.let { asOf <= it } ?: true)
        }
    }

    /**
     * Scorable right now: in its date window, not permanently out of scope, and needing nothing
     * this build lacks.
     */
    fun isLive(rule: EarnRule, asOf: String): Boolean =
        isScheduleLive(rule, asOf) && capabilityGap(rule) == null

    /**
     * Everything about liveness that is NOT about capability — dates, `scoredInV1`, and the
     * permanent `outOfScope` verdict. Split out so [resolve] can tell a rule that lost from a
     * rule this build could not run: the second is reportable, the first is not, and the third
     * (`outOfScope`) is deliberately neither, because "never" is not a gap awaiting a fix.
     */
    fun isScheduleLive(rule: EarnRule, asOf: String): Boolean {
        if (rule.outOfScope != null) return false
        if (rule.scoredInV1 == false) return false
        val fromOk = rule.effectiveFrom?.let { it <= asOf } ?: true
        val toOk = rule.effectiveTo?.let { asOf <= it } ?: true
        return fromOk && toOk
    }

    /**
     * The capability names this rule needs and this build does not have, or null when it is
     * fully supported. Unknown strings fail closed and are reported by name: an unrecognised
     * capability is a data error, and assuming support would score a rule the engine cannot
     * honour.
     */
    fun capabilityGap(rule: EarnRule): List<String>? {
        val requires = rule.requires ?: return null
        val missing = requires.filter { name ->
            val capability = EngineCapability.fromRaw(name) ?: return@filter true
            capability !in EngineCapability.supported
        }
        return missing.ifEmpty { null }
    }

    fun conditionsResolveTrue(conditions: List<String>?, state: CardState): Boolean {
        if (conditions == null) return true
        return conditions.all { condition ->
            when (condition) {
                "rogersEligibleServiceLinked" -> state.rogersEligibleServiceLinked == true
                "cryptoLevelUpProActive" -> state.cryptoLevelUpProActive == true
                "tangerineCategorySelected" -> state.selectedCategories != null
                else -> false
            }
        }
    }

    fun matches(p: Predicate, purchase: PurchaseContext, state: CardState): Boolean {
        if (p.country != null && p.country != purchase.country) return false
        if (p.currency != null && p.currency != purchase.currency) return false
        if (p.channels != null && !p.channels.contains(purchase.channel)) return false
        if (p.merchantExclude != null && purchase.merchantBrand != null && p.merchantExclude.contains(purchase.merchantBrand)) {
            return false
        }
        if (p.merchantInclude != null) {
            val brand = purchase.merchantBrand ?: return false
            if (!p.merchantInclude.contains(brand)) return false
        }
        if (p.mccExclude != null && purchase.mcc != null && p.mccExclude.contains(purchase.mcc)) {
            return false
        }

        val categories = p.categories ?: return true // no category clause = base rule
        return categories.any { category ->
            when (category) {
                "recurring" -> purchase.recurringIndicator
                "ownerSelectedTangerineCategory" -> matchesTangerineSelection(purchase, state)
                else -> {
                    val selfOrParents = listOf(purchase.category) + (categoryParents[purchase.category] ?: emptyList())
                    if (!selfOrParents.contains(category)) return@any false
                    if (p.mccInclude != null && purchase.mcc != null) {
                        return@any p.mccInclude.contains(purchase.mcc)
                    }
                    true
                }
            }
        }
    }

    private fun matchesTangerineSelection(purchase: PurchaseContext, state: CardState): Boolean {
        val selections = state.selectedCategories ?: return false
        val selected = selections.toSet()
        val purchaseCategories = (listOf(purchase.category) + (categoryParents[purchase.category] ?: emptyList())).toSet()

        if (selected.intersect(purchaseCategories).isNotEmpty()) return true
        if (purchase.recurringIndicator && selected.contains(TangerineMoneyBackCategory.RECURRING.rawValue)) {
            return true
        }
        if (purchase.currency.uppercase() != "CAD" && selected.contains(TangerineMoneyBackCategory.FOREIGN_CURRENCY.rawValue)) {
            return true
        }

        // Backward compatibility for owner-state files that used Tangerine's label-shaped id
        return purchaseCategories.contains(TangerineMoneyBackCategory.LODGING.rawValue) && selected.contains("hotelMotel")
    }

    fun rawEarn(earn: Earn): Double {
        return when (earn) {
            is Earn.Points -> earn.pointsPerCad
            is Earn.Cashback -> earn.rate * 100
            is Earn.CentsPerLitre -> -1.0
        }
    }
}
