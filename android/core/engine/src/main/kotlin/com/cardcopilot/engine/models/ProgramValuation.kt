package com.cardcopilot.engine.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * What one reward currency is worth, keyed in owner state and the catalogue by `programId`.
 *
 * The Kotlin twin of Swift's `ProgramValuation` enum. Swift wraps four independent payload
 * structs in enum cases and hand-writes `Codable` to flatten the discriminator and the payload
 * into one JSON object; Kotlin gets that shape for free by making the payloads *be* the sealed
 * subclasses, so `classDiscriminator = "model"` on the `Json` instance emits and reads exactly
 * the same bytes. Both sides therefore agree on the wire format without agreeing on the
 * language mechanism.
 *
 * A sum type rather than a flattened struct of optional factors, for the same reason [Earn] is
 * one: CT Money's usability discount and CRO's hold-risk factor are different *models*, not
 * different values of one model. Flattening them into anonymous factors would destroy the
 * disclosure the valuation UI depends on — point values are disclosed assumptions, not facts.
 *
 * Deliberately NOT an expression language. A condition encoded as a string ("croHandling ==
 * autoSell") would need a parser, and the parser would be code — moving the closed set rather
 * than opening it. Model-specific behaviour stays in `Scorer`, keyed by subclass.
 *
 * No subclass may declare a property named `model`: kotlinx.serialization refuses a sealed
 * subclass whose property collides with the class discriminator. That is the same constraint
 * the Swift twin has, and it is why [CroValuation.redemptionModel] carries the name it does.
 */
@Serializable
sealed class ProgramValuation

@Serializable
@SerialName("points")
data class PointValuation(
    val centsPerPoint: Double,
    val floorCentsPerPoint: Double? = null,
    /**
     * Published benchmark value for this currency. Used only as a plausibility ceiling when
     * deciding whether an upside breakeven is worth disclosing — never for ranking.
     */
    val aspirationalCentsPerPoint: Double? = null,
    val low: Double? = null,
    val high: Double? = null,
    /** Where the number came from and which parts of it are assumptions. See the Swift twin. */
    val basis: String? = null
) : ProgramValuation()

@Serializable
@SerialName("ctMoney")
data class CtMoneyValuation(
    val cadPerUnit: Double,
    val optionalUsabilityFactor: Double,
    val usabilityFactorApplied: Boolean,
    /** Where the number came from and which parts of it are assumptions. See the Swift twin. */
    val basis: String? = null
) : ProgramValuation()

/**
 * A card with no rewards programme at all — MBNA True Line, Capital One Guaranteed Secured.
 *
 * Carries only its disclosure, because there is no number to configure: zero is not an assumption
 * anyone could hold differently. It exists so the difference [Scorer.valueCad] has always drawn
 * becomes expressible — a MISSING valuation answers null and excludes the card, because "we do not
 * know what this is worth" must never rank as "worth nothing"; this one answers 0.0 and the card
 * is scored, ranking last on merit rather than vanishing from a comparison it belongs in.
 *
 * Mirrors Swift's `NoRewardsValuation`.
 */
@Serializable
@SerialName("noRewards")
data class NoRewardsValuation(
    /** Where the number came from. Here: that it is a fact, not an estimate. */
    val basis: String? = null
) : ProgramValuation()

@Serializable
@SerialName("cro")
data class CroValuation(
    /**
     * How CRO converts to CAD — not the [ProgramValuation] discriminator, which is a separate
     * key at the same JSON level. Named `model` until 2026-08-20; renamed to free that key.
     */
    val redemptionModel: String,
    val faceValueFactorIfAutoSold: Double,
    val defaultHeldRiskFactor: Double,
    /** Where the number came from and which parts of it are assumptions. See the Swift twin. */
    val basis: String? = null
) : ProgramValuation()

@Serializable
@SerialName("cashback")
data class CashBackValuation(
    val cadPerDollar: Double,
    /** Where the number came from and which parts of it are assumptions. See the Swift twin. */
    val basis: String? = null
) : ProgramValuation()

/**
 * Catalogue-shipped default valuations, keyed by `programId`.
 *
 * Exists so that adding a rewards program is one data edit rather than two. Without defaults a
 * new program has to be valued in the catalogue *and* in every owner-state file that will ever
 * see it — which is how sixteen catalogue programIds came to face six valuations.
 *
 * [defaults] is deliberately allowed to be incomplete: a program with no default and no owner
 * override has no honest number, and inventing one is worse than admitting it. Callers must
 * treat a missing key as "no valuation" — `Scorer.valueCad` answers null for one, and
 * `Scorer.score` excludes the card with `Warning.UNSUPPORTED_PROGRAM` rather than scoring zero.
 */
@Serializable
data class ProgramCatalogue(
    val programsVersion: String = "1.0",
    val defaults: Map<String, ProgramValuation> = emptyMap()
)
