package com.cardcopilot.engine

import com.cardcopilot.engine.engine.RecommendationEngine
import com.cardcopilot.engine.engine.RuleMatcher
import com.cardcopilot.engine.engine.RuleResolution
import com.cardcopilot.engine.engine.Scorer
import com.cardcopilot.engine.loading.SeedLoader
import com.cardcopilot.engine.models.CandidateScore
import com.cardcopilot.engine.models.CardProduct
import com.cardcopilot.engine.models.Earn
import com.cardcopilot.engine.models.EarnRule
import com.cardcopilot.engine.models.EngineCapability
import com.cardcopilot.engine.models.OutOfScope
import com.cardcopilot.engine.models.Predicate
import com.cardcopilot.engine.models.Program
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.RecommendationOutcome
import com.cardcopilot.engine.models.RuleStatus
import com.cardcopilot.engine.models.SourceType
import com.cardcopilot.engine.models.Warning
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The Kotlin twin of `Engine/Tests/CardCopilotEngineTests/CapabilityGatingTests.swift`.
 *
 * Rules declare what they need; the engine declares what it has. A mismatch must skip the rule,
 * never score it — a rule the engine cannot honour produces a number nobody can defend. Both
 * engines read the same catalogue, so both must gate the same rules.
 */
class CapabilityGatingTest {

    private val asOf = "2026-08-20"
    private val grocery = PurchaseContext(amountCad = 100.0, category = "grocery")

    private fun rule(requires: List<String>? = null, outOfScope: OutOfScope? = null) = EarnRule(
        ruleId = "r",
        status = RuleStatus.CURRENT,
        sourceType = SourceType.ISSUER_CONFIRMED,
        earn = Earn.Cashback(rate = 0.02),
        requires = requires,
        outOfScope = outOfScope
    )

    @Test
    fun ruleRequiringASupportedCapabilityIsLive() {
        assertTrue(RuleMatcher.isLive(rule(requires = listOf("cap.calendarYear")), asOf))
    }

    @Test
    fun ruleRequiringAnUnsupportedCapabilityIsNotLive() {
        assertFalse(RuleMatcher.isLive(rule(requires = listOf("cap.statementYear")), asOf))
    }

    /**
     * An unknown capability string is a data error and must fail closed — never be assumed
     * supported because the engine does not recognise it.
     */
    @Test
    fun unknownCapabilityStringIsNotLive() {
        assertFalse(RuleMatcher.isLive(rule(requires = listOf("cap.inventedYesterday")), asOf))
    }

    @Test
    fun outOfScopeRuleIsNeverLive() {
        assertFalse(RuleMatcher.isLive(rule(outOfScope = OutOfScope("online booking channel")), asOf))
    }

    /**
     * "Not yet" and "never" must stay distinguishable, or a future reader builds a capability
     * because an out-of-scope rule appeared to ask for it.
     */
    @Test
    fun outOfScopeIsNotExpressedAsARequirement() {
        // Every product, candidates included — they are the same corpus since 2026-08-24
        // (SeedLoader.loadCandidateCatalogue returns id references, not a second set of cards).
        val all = SeedLoader.loadCatalogue().cards.flatMap { it.earnRules }

        for (r in all.filter { it.outOfScope != null }) {
            assertTrue(
                r.requires == null,
                "${r.ruleId}: a permanently out-of-scope rule must not also declare requires"
            )
        }
        for (name in all.mapNotNull { it.requires }.flatten()) {
            assertTrue(
                EngineCapability.fromRaw(name) != null,
                "$name is not a known EngineCapability"
            )
        }
    }

    /**
     * The capability vocabulary and the supported set are a cross-language contract. If Swift
     * ships `cap.statementYear` and Kotlin does not, a card scores on one platform and vanishes
     * on the other with the same catalogue underneath.
     */
    @Test
    fun supportedCapabilitiesMatchTheSwiftTwin() {
        assertEquals(
            listOf(
                "cap.accountYear", "cap.calendarMonth", "cap.calendarQuarter", "cap.calendarYear",
                "predicate.ownerSelectedCategory"
            ),
            EngineCapability.supported.map { it.rawValue }.sorted()
        )
        assertEquals(
            listOf(
                "cap.accountYear", "cap.calendarMonth", "cap.calendarQuarter", "cap.calendarYear",
                "cap.globalGroup", "cap.statementYear", "earn.marginal", "earn.perLitre",
                "predicate.mccStrict", "predicate.merchantPartnerList",
                "predicate.ownerSelectedCategory"
            ),
            EngineCapability.entries.map { it.rawValue }.sorted()
        )
        assertTrue(
            EngineCapability.entries.none { it.rawValue == "predicate.channelIdentity" },
            "channelIdentity is deliberately absent — a capability in the enum invites someone to build it"
        )
    }

    /**
     * A real, valued card with its earn rules replaced — cheaper than hand-building a
     * CardProduct, and it keeps the network, program and fee fields honest.
     */
    private fun card(rules: List<EarnRule>): CardProduct =
        SeedLoader.loadCatalogue().cards.first { it.cardId == "scotia-momentum-vi-plus" }
            .copy(earnRules = rules, caps = emptyList())

    private fun groceryRule(
        ruleId: String,
        rate: Double,
        requires: List<String>? = null,
        outOfScope: OutOfScope? = null,
        categories: List<String> = listOf("grocery")
    ) = EarnRule(
        ruleId = ruleId,
        status = RuleStatus.CURRENT,
        sourceType = SourceType.ISSUER_CONFIRMED,
        earn = Earn.Cashback(rate = rate),
        predicate = Predicate(categories = categories),
        requires = requires,
        outOfScope = outOfScope
    )

    private fun score(card: CardProduct): CandidateScore =
        Scorer.score(card, grocery, SeedLoader.loadOwnerState(), asOf)

    /**
     * The card still scores on the rule the engine can honour — but the owner is told a better
     * rule exists that this build cannot check, rather than being shown the lesser number as
     * though it were the whole story.
     */
    @Test
    fun capabilityBlockedRuleWarnsOnACardThatStillScores() {
        val s = score(
            card(
                listOf(
                    groceryRule("live-2pct", 0.02),
                    groceryRule("blocked-6pct", 0.06, requires = listOf("cap.statementYear"))
                )
            )
        )

        assertFalse(s.excluded)
        assertEquals("live-2pct", s.appliedRuleId, "the blocked rule must not win")
        assertEquals(2.00, s.netValueCad, 0.005)
        assertTrue(s.warnings.contains(Warning.UNSUPPORTED_CAPABILITY))
    }

    /**
     * When the blocked rule was the only one that matched, the card drops out — and the reason
     * must name the capability. "unresolved or inactive owner state" would send the owner to
     * check settings that have nothing to do with it.
     */
    @Test
    fun cardWithOnlyCapabilityBlockedRulesExcludesAndNamesTheCapability() {
        val s = score(card(listOf(groceryRule("blocked-6pct", 0.06, requires = listOf("cap.statementYear")))))

        assertTrue(s.excluded)
        assertTrue(s.warnings.contains(Warning.UNSUPPORTED_CAPABILITY))
        assertFalse(s.warnings.contains(Warning.UNRESOLVED_OWNER_STATE))
        assertTrue(
            s.exclusionReason?.contains("cap.statementYear") == true,
            "the reason must name what is missing: ${s.exclusionReason}"
        )
    }

    /**
     * An unknown capability name is a data error, and the owner-facing symptom must be the same
     * as a known-but-unbuilt one — never a silently scored rule.
     */
    @Test
    fun unknownCapabilityAlsoWarnsRatherThanScoring() {
        val s = score(
            card(
                listOf(
                    groceryRule("live-2pct", 0.02),
                    groceryRule("typo-6pct", 0.06, requires = listOf("cap.inventedYesterday"))
                )
            )
        )

        assertEquals("live-2pct", s.appliedRuleId)
        assertTrue(s.warnings.contains(Warning.UNSUPPORTED_CAPABILITY))
    }

    /**
     * "Never" must not surface as "not yet". An out-of-scope rule is not a gap waiting to be
     * filled, and warning about it would advertise work nobody intends to do.
     */
    @Test
    fun outOfScopeRuleDoesNotWarnAboutACapability() {
        val s = score(
            card(
                listOf(
                    groceryRule("live-2pct", 0.02),
                    groceryRule("never-6pct", 0.06, outOfScope = OutOfScope("online booking channel"))
                )
            )
        )

        assertEquals("live-2pct", s.appliedRuleId)
        assertFalse(s.warnings.contains(Warning.UNSUPPORTED_CAPABILITY))
    }

    /** Every gap is reported once, in a stable order, however many rules named it. */
    @Test
    fun reportedGapsAreDeduplicatedAndSorted() {
        val resolution = RuleMatcher.resolve(
            card(
                listOf(
                    groceryRule("live", 0.02),
                    groceryRule("a", 0.03, requires = listOf("cap.statementYear")),
                    groceryRule("b", 0.04, requires = listOf("cap.statementYear", "cap.globalGroup"))
                )
            ),
            grocery,
            SeedLoader.loadOwnerState(),
            asOf
        )

        val applied = resolution as? RuleResolution.Applied
            ?: throw AssertionError("expected Applied, got $resolution")
        assertEquals(listOf("cap.globalGroup", "cap.statementYear"), applied.unsupportedCapabilities)
    }

    /**
     * A rule the owner could never trigger anyway is not a capability gap. Warning about it
     * would report a gap closing which would change nothing for this owner.
     */
    @Test
    fun capabilityGapIsNotReportedForARuleThatWouldNotHaveMatched() {
        val s = score(
            card(
                listOf(
                    groceryRule("live-2pct", 0.02),
                    groceryRule(
                        "blocked-but-irrelevant", 0.09,
                        requires = listOf("cap.statementYear"),
                        categories = listOf("dining")
                    )
                )
            )
        )

        assertEquals("live-2pct", s.appliedRuleId)
        assertFalse(
            s.warnings.contains(Warning.UNSUPPORTED_CAPABILITY),
            "a dining rule is no gap on a grocery purchase"
        )
    }

    /**
     * Every rule the engine skips must say why in a machine-readable way. A bare
     * scoredInV1:false carries no reason and cannot turn itself on when the blocker is fixed.
     */
    @Test
    fun noRuleIsDisabledWithoutAMachineReadableReason() {
        val allowed = setOf(
            "scotia-gold-gas-transit-3x" // spec §9.1 — blocker unconfirmed
        )
        val bare = SeedLoader.loadCatalogue().cards
            .flatMap { it.earnRules }
            .filter { it.scoredInV1 == false && it.requires == null && it.outOfScope == null }
            .map { it.ruleId }
            .filter { it !in allowed }
            .sorted()

        assertTrue(bare.isEmpty(), "rules disabled with no declared blocker: $bare")
    }

    /**
     * A card whose program has no valuation is excluded with a reason, not scored at zero. Zero
     * is a number the owner cannot tell apart from a considered one.
     */
    @Test
    fun cardOnAnUnvaluedProgramIsExcludedRatherThanScoredAtZero() {
        val s = score(card(listOf(groceryRule("live-2pct", 0.02)))
            .copy(program = Program(programId = "unknownProgram", unit = "point")))

        assertTrue(s.excluded)
        assertTrue(s.warnings.contains(Warning.UNSUPPORTED_PROGRAM))
        assertTrue(
            s.exclusionReason?.contains("unknownProgram") == true,
            "the reason must name the program: ${s.exclusionReason}"
        )
    }

    /** A wallet where nothing can be scored must refuse, not crash and not invent a winner. */
    @Test
    fun walletOfEntirelyUnvaluedCardsCannotAdvise() {
        val catalogue = SeedLoader.loadCatalogue().let { c ->
            c.copy(cards = c.cards.map { it.copy(program = Program("unknownProgram", "point")) })
        }
        val owner = SeedLoader.loadOwnerState().copy(ownedCardIds = catalogue.cards.map { it.cardId })

        val outcome = RecommendationEngine(catalogue, owner)
            .recommend(PurchaseContext(amountCad = 50.0, category = "grocery"), asOf)

        val refusal = outcome as? RecommendationOutcome.CannotAdvise
            ?: throw AssertionError("expected CannotAdvise, got $outcome")
        assertTrue(refusal.reasons.isNotEmpty(), "a refusal must say why")
    }

    @Test
    fun emptyWalletCannotAdviseFromTheCatalogue() {
        val catalogue = SeedLoader.loadCatalogue()
        val owner = SeedLoader.loadOwnerState().copy(ownedCardIds = emptyList(), defaultCardId = "")

        val outcome = RecommendationEngine(catalogue, owner)
            .recommend(PurchaseContext(amountCad = 50.0, category = "grocery"), asOf)

        val refusal = outcome as? RecommendationOutcome.CannotAdvise
            ?: throw AssertionError("expected CannotAdvise, got $outcome")
        assertEquals(listOf("Add a card to your wallet to get checkout advice."), refusal.reasons)
    }
}
