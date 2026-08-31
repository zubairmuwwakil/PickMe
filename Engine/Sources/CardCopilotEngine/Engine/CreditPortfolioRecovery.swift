import Foundation

public struct CreditPortfolioRecovery: Equatable, Sendable {
    /// Credits the owner says actually posted, conservatively measured over the trailing year.
    public let realizedCad: Double
    /// Currently recoverable amount. Shown as upside, never counted toward a keep verdict.
    public let unspentPotentialCad: Double
}

public enum CreditPortfolioRecoveryCalculator {
    public static func recovery(card: CardProduct, cardState: CardState,
                                asOf: String) -> CreditPortfolioRecovery {
        recovery(cardId: card.cardId, credits: card.credits ?? [], cardState: cardState,
                 asOf: asOf)
    }

    public static func recovery(cardId: String, credits: [CardCredit], cardState: CardState,
                                asOf: String) -> CreditPortfolioRecovery {
        let trailingStart = date(asOf).flatMap {
            Calendar(identifier: .gregorian).date(byAdding: .month, value: -12, to: $0)
        }
        var realized = 0.0
        var potential = 0.0

        for credit in credits where credit.sourceType == .issuerConfirmed {
            let state = cardState.creditStates?[credit.creditId] ?? CreditState()
            let posted = state.windows.values.filter { $0.realizedAmount > 0 }
            if let months = credit.effectiveSchedule?.intervalMonths, months > 12,
               let mostRecent = posted.filter({ item in
                   guard let updated = date(item.updatedAt), let asOfDate = date(asOf),
                         let cycleStart = Calendar(identifier: .gregorian)
                           .date(byAdding: .month, value: -months, to: asOfDate) else { return false }
                   return updated >= cycleStart && updated <= asOfDate
               }).max(by: { $0.updatedAt < $1.updatedAt }) {
                // Multi-year reimbursements are not annual benefits at face value. Spread one
                // confirmed recovery over its contractual eligibility interval.
                realized += ReportingCurrency.toReporting(Money(
                    amount: mostRecent.realizedAmount * 12 / Double(months),
                    currency: credit.value.currency
                ))
            } else {
                realized += posted.filter { item in
                    guard let updated = date(item.updatedAt), let trailingStart else { return false }
                    return updated >= trailingStart && updated <= (date(asOf) ?? updated)
                }.reduce(0) { sum, item in
                    sum + ReportingCurrency.toReporting(Money(
                        amount: item.realizedAmount, currency: credit.value.currency
                    ))
                }
            }

            if let opportunity = CreditAdvisor.opportunity(cardId: cardId, credit: credit,
                                                            cardState: cardState, asOf: asOf),
               opportunity.status == .available || opportunity.status == .needsEnrollment {
                potential += ReportingCurrency.toReporting(Money(
                    amount: opportunity.remainingAmount, currency: credit.value.currency
                ))
            }
        }
        return CreditPortfolioRecovery(realizedCad: realized, unspentPotentialCad: potential)
    }

    private static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
