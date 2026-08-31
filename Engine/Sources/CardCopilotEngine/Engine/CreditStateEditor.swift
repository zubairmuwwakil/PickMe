import Foundation

public enum CreditStateAction: Equatable, Sendable {
    case setEnrollment(CreditEnrollmentStatus)
    case markConsumed(amount: Double? = nil)
    case confirmRealized(amount: Double? = nil)
    case clearCurrentWindow
}

/// Applies the small set of owner-declared credit facts PickMe needs. This edits aggregate windows,
/// never transactions, and keeps at most sixteen windows per credit so owner state stays bounded.
public enum CreditStateEditor {
    public static func applying(_ action: CreditStateAction, to ownerState: OwnerState,
                                cardId: String, credit: CardCredit,
                                asOf: String) -> OwnerState? {
        guard ownerState.ownedCardIds.contains(cardId) else { return nil }

        var owner = ownerState
        var cardState = owner.cardStates[cardId] ?? CardState()
        var states = cardState.creditStates ?? [:]
        var state = states[credit.creditId] ?? CreditState()

        switch action {
        case .setEnrollment(let status):
            state.enrollmentStatus = status

        case .markConsumed(let requested), .confirmRealized(let requested):
            guard let window = CreditAdvisor.currentWindow(for: credit, cardState: cardState,
                                                           asOf: asOf),
                  window.nextEligibleOn.map({ asOf >= $0 }) ?? true,
                  window.id != "account-anniversary:unknown" else { return nil }
            let amount = min(credit.value.amount, max(0, requested ?? credit.value.amount))
            var usage = state.windows[window.id]
                ?? CreditWindowState(updatedAt: asOf)
            usage.consumedAmount = max(usage.consumedAmount, amount)
            if case .confirmRealized = action {
                usage.realizedAmount = max(usage.realizedAmount, amount)
                if credit.effectiveSchedule?.basis == .rolling {
                    state.lastRedemptionAt = asOf
                }
            }
            usage.updatedAt = asOf
            state.windows[window.id] = usage

        case .clearCurrentWindow:
            guard let window = CreditAdvisor.currentWindow(for: credit, cardState: cardState,
                                                           asOf: asOf) else { return nil }
            state.windows.removeValue(forKey: window.id)
            if credit.effectiveSchedule?.basis == .rolling,
               let last = state.lastRedemptionAt,
               window.id == "rolling:\(last)" {
                state.lastRedemptionAt = nil
            }
        }

        if state.windows.count > 16 {
            let keep = Set(state.windows
                .sorted { ($0.value.updatedAt, $0.key) > ($1.value.updatedAt, $1.key) }
                .prefix(16).map(\.key))
            state.windows = state.windows.filter { keep.contains($0.key) }
        }
        states[credit.creditId] = state
        cardState.creditStates = states
        owner.cardStates[cardId] = cardState
        return owner
    }
}
