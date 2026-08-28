package com.cardcopilot.engine.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * How a condition is answered, and therefore which owner-state field carries the answer.
 *
 * [BOOLEAN] answers live in [CardState.flags], keyed by condition id, so a new yes/no condition is
 * an entry in contracts/owner-conditions.json and nothing else. [CATEGORY_SELECTION] is Tangerine's
 * existing selection machinery, which stays structural because specific engine logic reads it.
 *
 * Swift twin: `OwnerConditionAnswerKind`.
 */
@Serializable
enum class OwnerConditionAnswerKind {
    @SerialName("boolean")
    BOOLEAN,

    @SerialName("categorySelection")
    CATEGORY_SELECTION
}

/**
 * One owner condition as declared in contracts/owner-conditions.json.
 *
 * [prompt] and [detail] are ENGLISH SOURCE strings, not display strings: consumers resolve
 * `ownerCondition.<id>.prompt` from their own string catalogue and fall back to these, so a new
 * condition is askable the day it lands and picks up translations without a contract release.
 */
@Serializable
data class OwnerCondition(
    val answerKind: OwnerConditionAnswerKind,
    val prompt: String? = null,
    val detail: String? = null,
    /** [OwnerConditionAnswerKind.CATEGORY_SELECTION] only: how many categories the issuer permits. */
    val maxSelections: Int? = null
)

/**
 * The registry file. Same shape and role as `ProgramCatalogue`: an open set declared as data, with
 * a machine check that the catalogue never references an entry that is missing.
 */
@Serializable
data class OwnerConditionRegistry(
    val conditionsVersion: String = "1.0",
    val conditions: Map<String, OwnerCondition> = emptyMap()
)
