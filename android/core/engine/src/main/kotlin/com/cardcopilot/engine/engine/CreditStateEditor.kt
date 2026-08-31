package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.CardCredit
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.CreditEnrollmentStatus
import com.cardcopilot.engine.models.CreditScheduleBasis
import com.cardcopilot.engine.models.CreditState
import com.cardcopilot.engine.models.CreditWindowState
import com.cardcopilot.engine.models.OwnerState

sealed interface CreditStateAction {
    data class SetEnrollment(val status: CreditEnrollmentStatus) : CreditStateAction
    data class MarkConsumed(val amount: Double? = null) : CreditStateAction
    data class ConfirmRealized(val amount: Double? = null) : CreditStateAction
    data object ClearCurrentWindow : CreditStateAction
}

/** Aggregate, bounded owner-state edits; no transaction ledger is created here. */
object CreditStateEditor {
    fun applying(action: CreditStateAction, ownerState: OwnerState, cardId: String,
                 credit: CardCredit, asOf: String): OwnerState? {
        if (cardId !in ownerState.ownedCardIds) return null
        var cardState = ownerState.cardStates[cardId] ?: CardState()
        val states = (cardState.creditStates ?: emptyMap()).toMutableMap()
        var state = states[credit.creditId] ?: CreditState()

        when (action) {
            is CreditStateAction.SetEnrollment -> state = state.copy(enrollmentStatus = action.status)
            is CreditStateAction.MarkConsumed, is CreditStateAction.ConfirmRealized -> {
                val window = CreditAdvisor.currentWindow(credit, cardState, asOf) ?: return null
                if (window.id == "account-anniversary:unknown" ||
                    window.nextEligibleOn?.let { asOf < it } == true) return null
                val requested = when (action) {
                    is CreditStateAction.MarkConsumed -> action.amount
                    is CreditStateAction.ConfirmRealized -> action.amount
                }
                val amount = minOf(credit.value.amount, maxOf(0.0, requested ?: credit.value.amount))
                val windows = state.windows.toMutableMap()
                var usage = windows[window.id] ?: CreditWindowState(updatedAt = asOf)
                usage = usage.copy(consumedAmount = maxOf(usage.consumedAmount, amount), updatedAt = asOf)
                if (action is CreditStateAction.ConfirmRealized) {
                    usage = usage.copy(realizedAmount = maxOf(usage.realizedAmount, amount))
                    if (credit.effectiveSchedule?.basis == CreditScheduleBasis.ROLLING) {
                        state = state.copy(lastRedemptionAt = asOf)
                    }
                }
                windows[window.id] = usage
                state = state.copy(windows = windows)
            }
            CreditStateAction.ClearCurrentWindow -> {
                val window = CreditAdvisor.currentWindow(credit, cardState, asOf) ?: return null
                val windows = state.windows.toMutableMap().also { it.remove(window.id) }
                val clearsRolling = credit.effectiveSchedule?.basis == CreditScheduleBasis.ROLLING &&
                    state.lastRedemptionAt?.let { window.id == "rolling:$it" } == true
                state = state.copy(windows = windows,
                    lastRedemptionAt = if (clearsRolling) null else state.lastRedemptionAt)
            }
        }

        if (state.windows.size > 16) {
            val keep = state.windows.entries
                .sortedWith(compareByDescending<Map.Entry<String, CreditWindowState>> { it.value.updatedAt }
                    .thenByDescending { it.key })
                .take(16).associate { it.toPair() }
            state = state.copy(windows = keep)
        }
        states[credit.creditId] = state
        cardState = cardState.copy(creditStates = states)
        return ownerState.copy(cardStates = ownerState.cardStates + (cardId to cardState))
    }
}
