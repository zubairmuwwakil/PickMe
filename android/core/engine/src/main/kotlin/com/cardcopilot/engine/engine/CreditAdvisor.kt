package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.CardCredit
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.Catalogue
import com.cardcopilot.engine.models.CreditEnrollmentStatus
import com.cardcopilot.engine.models.CreditScheduleBasis
import com.cardcopilot.engine.models.CreditScheduleUnit
import com.cardcopilot.engine.models.CreditState
import com.cardcopilot.engine.models.Money
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.SourceType
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.temporal.ChronoUnit

@Serializable
enum class CreditOpportunityStatus {
    @SerialName("available") AVAILABLE,
    @SerialName("used") USED,
    @SerialName("needsEnrollment") NEEDS_ENROLLMENT,
    @SerialName("notYetEligible") NOT_YET_ELIGIBLE,
    @SerialName("scheduleUnresolved") SCHEDULE_UNRESOLVED
}

data class CreditWindow(
    val id: String,
    val startsOn: String? = null,
    val expiresOn: String? = null,
    val nextEligibleOn: String? = null
)

data class CreditOpportunity(
    val cardId: String,
    val creditId: String,
    val label: String,
    val value: Money,
    val window: CreditWindow,
    val consumedAmount: Double,
    val realizedAmount: Double,
    val remainingAmount: Double,
    val enrollmentStatus: CreditEnrollmentStatus,
    val status: CreditOpportunityStatus,
    val daysRemaining: Int?
)

object CreditAdvisor {
    fun opportunities(catalogue: Catalogue, ownerState: OwnerState, asOf: String): List<CreditOpportunity> {
        val owned = ownerState.ownedCardIds.toSet()
        return catalogue.cards
            .filter { it.cardId in owned && it.isPublished && it.isScoreable(asOf) }
            .flatMap { card ->
                val state = ownerState.cardStates[card.cardId] ?: CardState()
                (card.credits ?: emptyList()).mapNotNull { credit ->
                    opportunity(card.cardId, credit, state, asOf)
                }
            }
            .sortedWith(compareBy<CreditOpportunity> { it.daysRemaining == null }
                .thenBy { it.daysRemaining ?: Int.MAX_VALUE }
                .thenBy { it.label.lowercase() })
    }

    fun opportunity(cardId: String, credit: CardCredit, cardState: CardState,
                    asOf: String): CreditOpportunity? {
        if (credit.sourceType != SourceType.ISSUER_CONFIRMED) return null
        if (!isLive(credit, asOf)) return null
        val window = currentWindow(credit, cardState, asOf) ?: return null
        val creditState = cardState.creditStates?.get(credit.creditId) ?: CreditState()
        val usage = creditState.windows[window.id]
        val consumed = maxOf(0.0, usage?.consumedAmount ?: 0.0)
        val realized = maxOf(0.0, usage?.realizedAmount ?: 0.0)
        val enrollmentStatus = if (credit.enrollment?.required == true) {
            creditState.enrollmentStatus
        } else {
            CreditEnrollmentStatus.NOT_REQUIRED
        }
        val notYetEligible = window.nextEligibleOn?.let { asOf < it } ?: false
        val remaining = if (notYetEligible) 0.0 else maxOf(0.0, credit.value.amount - consumed)
        val status = when {
            notYetEligible -> CreditOpportunityStatus.NOT_YET_ELIGIBLE
            credit.effectiveSchedule?.basis == CreditScheduleBasis.ACCOUNT_ANNIVERSARY &&
                window.expiresOn == null -> CreditOpportunityStatus.SCHEDULE_UNRESOLVED
            credit.enrollment?.required == true && enrollmentStatus != CreditEnrollmentStatus.ENROLLED ->
                CreditOpportunityStatus.NEEDS_ENROLLMENT
            remaining <= 0.000001 -> CreditOpportunityStatus.USED
            else -> CreditOpportunityStatus.AVAILABLE
        }
        val days = window.expiresOn?.let {
            maxOf(0, ChronoUnit.DAYS.between(LocalDate.parse(asOf), LocalDate.parse(it)).toInt())
        }
        return CreditOpportunity(cardId, credit.creditId, credit.label, credit.value, window,
            consumed, realized, remaining, enrollmentStatus, status, days)
    }

    fun currentWindow(credit: CardCredit, cardState: CardState, asOf: String): CreditWindow? {
        val schedule = credit.effectiveSchedule ?: return null
        val date = LocalDate.parse(asOf)
        return when (schedule.basis) {
            CreditScheduleBasis.CALENDAR -> {
                val unit = schedule.unit ?: return null
                val startMonth: Int
                val spanMonths: Long
                val interval = maxOf(1, schedule.interval ?: 1).toLong()
                when (unit) {
                    CreditScheduleUnit.MONTH -> {
                        startMonth = date.monthValue
                        spanMonths = interval
                    }
                    CreditScheduleUnit.QUARTER -> {
                        startMonth = ((date.monthValue - 1) / 3) * 3 + 1
                        spanMonths = 3 * interval
                    }
                    CreditScheduleUnit.HALF_YEAR -> {
                        startMonth = if (date.monthValue <= 6) 1 else 7
                        spanMonths = 6 * interval
                    }
                    CreditScheduleUnit.YEAR -> {
                        startMonth = 1
                        spanMonths = 12 * interval
                    }
                }
                val start = LocalDate.of(date.year, startMonth, 1)
                val end = start.plusMonths(spanMonths).minusDays(1)
                CreditWindow("$start/$end", start.toString(), end.toString())
            }
            CreditScheduleBasis.ACCOUNT_ANNIVERSARY -> {
                val opened = cardState.accountOpenedAt?.let(LocalDate::parse)
                    ?: return CreditWindow("account-anniversary:unknown")
                val intervalMonths = schedule.intervalMonths?.takeIf { it > 0 }
                    ?: return CreditWindow("account-anniversary:unknown")
                var start = opened
                while (!start.plusMonths(intervalMonths.toLong()).isAfter(date)) {
                    start = start.plusMonths(intervalMonths.toLong())
                }
                val end = start.plusMonths(intervalMonths.toLong()).minusDays(1)
                CreditWindow("$start/$end", start.toString(), end.toString())
            }
            CreditScheduleBasis.ROLLING -> {
                val state = cardState.creditStates?.get(credit.creditId) ?: CreditState()
                val last = state.lastRedemptionAt?.let(LocalDate::parse)
                    ?: return CreditWindow("rolling:never-used")
                val months = schedule.intervalMonths?.takeIf { it > 0 }
                    ?: return CreditWindow("rolling:never-used")
                val next = last.plusMonths(months.toLong()).toString()
                CreditWindow("rolling:$last", startsOn = next, nextEligibleOn = next)
            }
        }
    }

    private fun isLive(credit: CardCredit, asOf: String): Boolean {
        if (credit.effectiveFrom?.let { asOf < it } == true) return false
        if (credit.effectiveTo?.let { asOf > it } == true) return false
        return true
    }
}
