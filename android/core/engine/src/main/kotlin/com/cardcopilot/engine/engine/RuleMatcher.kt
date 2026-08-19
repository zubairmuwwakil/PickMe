package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.CardProduct
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.Earn
import com.cardcopilot.engine.models.EarnRule
import com.cardcopilot.engine.models.FxRule
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.Predicate
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.TangerineMoneyBackCategory

sealed interface RuleResolution {
    data class Applied(val rule: EarnRule) : RuleResolution
    data class CardExcluded(val reason: String) : RuleResolution
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
        val candidates = card.earnRules.filter { rule ->
            isLive(rule, asOf) &&
                conditionsResolveTrue(rule.ownerConditions, state) &&
                matches(rule.predicate, purchase, state)
        }

        val best = candidates.maxByOrNull { rawEarn(it.earn) }
            ?: return RuleResolution.CardExcluded("no scorable earn rule (unresolved or inactive owner state)")

        return RuleResolution.Applied(best)
    }

    fun activeFxRule(card: CardProduct, asOf: String): FxRule? {
        return card.fxRules.firstOrNull { rule ->
            (rule.effectiveFrom?.let { it <= asOf } ?: true) &&
                (rule.effectiveTo?.let { asOf <= it } ?: true)
        }
    }

    fun isLive(rule: EarnRule, asOf: String): Boolean {
        if (rule.scoredInV1 == false) return false
        val fromOk = rule.effectiveFrom?.let { it <= asOf } ?: true
        val toOk = rule.effectiveTo?.let { asOf <= it } ?: true
        return fromOk && toOk
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
