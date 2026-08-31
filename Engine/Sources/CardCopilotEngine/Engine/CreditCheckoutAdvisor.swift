import Foundation

public struct CheckoutCreditMatch: Equatable, Sendable {
    public let cardId: String
    public let creditId: String
    public let label: String
    /// Defensible value of this credit on this purchase in PickMe's CAD reporting currency.
    public let valueCad: Double
    public let redemptionMethod: CreditRedemptionMethod
}

/// Finds an issuer-confirmed, enrolled, unused credit that this exact purchase can recover.
/// Missing merchant/category eligibility fails closed. At most one credit is counted because the
/// contract does not yet prove that two credits stack on the same transaction.
public enum CreditCheckoutAdvisor {
    public static func bestMatch(card: CardProduct, purchase: PurchaseContext,
                                 ownerState: OwnerState, asOf: String) -> CheckoutCreditMatch? {
        let cardState = ownerState.cardStates[card.cardId] ?? CardState()
        return bestMatch(cardId: card.cardId, credits: card.credits ?? [], cardState: cardState,
                         purchase: purchase, asOf: asOf)
    }

    public static func bestMatch(cardId: String, credits: [CardCredit], cardState: CardState,
                                 purchase: PurchaseContext, asOf: String) -> CheckoutCreditMatch? {
        let purchase = purchase.canonicalized()
        return credits.compactMap { credit -> CheckoutCreditMatch? in
            guard credit.sourceType == .issuerConfirmed,
                  let method = credit.redemptionMethod,
                  let predicate = credit.purchasePredicate,
                  RuleMatcher.matches(predicate, purchase: purchase, state: cardState),
                  let opportunity = CreditAdvisor.opportunity(cardId: cardId, credit: credit,
                                                              cardState: cardState, asOf: asOf),
                  opportunity.status == .available else { return nil }

            let purchaseCad = max(0, purchase.amountCad)
            if let minimum = credit.minimumTransaction,
               purchaseCad + 0.000_001 < ReportingCurrency.toReporting(minimum) { return nil }

            let remainingCad = ReportingCurrency.toReporting(
                Money(amount: opportunity.remainingAmount, currency: credit.value.currency)
            )
            let valueCad: Double
            if credit.allowsPartialUse == true {
                valueCad = min(remainingCad, purchaseCad)
            } else {
                guard purchaseCad + 0.000_001 >= remainingCad else { return nil }
                valueCad = remainingCad
            }
            guard valueCad > 0.000_001 else { return nil }
            return CheckoutCreditMatch(cardId: cardId, creditId: credit.creditId,
                                       label: credit.label, valueCad: valueCad,
                                       redemptionMethod: method)
        }
        .max { ($0.valueCad, $1.creditId) < ($1.valueCad, $0.creditId) }
    }
}
