import Foundation

/// Deterministic ranking engine that evaluates payment routes for Canadian bill payees.
public struct BillRouteScorer: Sendable {
    public let intermediaries: [BillIntermediary]

    public init(intermediaries: [BillIntermediary]) {
        self.intermediaries = intermediaries
    }

    /// Load default intermediaries bundled in the engine resources.
    public static func loadDefault() -> BillRouteScorer {
        guard let url = Bundle.module.url(forResource: "bill-intermediaries", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalogue = try? JSONDecoder().decode(BillIntermediariesCatalogue.self, from: data) else {
            return BillRouteScorer(intermediaries: fallbackIntermediaries)
        }
        return BillRouteScorer(intermediaries: catalogue.intermediaries)
    }

    public static let fallbackIntermediaries: [BillIntermediary] = [
        BillIntermediary(
            id: "chexy",
            name: "Chexy",
            type: .creditIntermediary,
            feeRate: 0.0175,
            mccTrigger: "RECURRING_BILL",
            settlementDays: 3,
            supportedCategories: ["utilities", "rent", "telecom", "insurance", "household"],
            requiresCardMultiplier: true,
            description: "Processes recurring payments via credit card (MCC 4900). Best with 4% recurring cards."
        ),
        BillIntermediary(
            id: "triangle-bill-pay",
            name: "Canadian Tire Triangle Bill Pay",
            type: .cardDirectBillPay,
            feeRate: 0.0,
            directRewardRate: 0.01,
            directRewardProgramId: "ctMoney",
            settlementDays: 3,
            restrictedCardPrograms: ["triangle-we", "triangle-mastercard"],
            supportedCategories: ["utilities", "property_tax", "tuition", "government", "household"],
            requiresCardMultiplier: false,
            description: "Direct electronic bill payment via Canadian Tire Bank portal (0% fee, 1% CT Money)."
        ),
        BillIntermediary(
            id: "neobanc",
            name: "Neo Financial (Neobanc)",
            type: .fintechAccountRouting,
            feeRate: 0.0,
            holdingApy: 0.025,
            hasPartnerPerks: true,
            settlementDays: 1,
            supportedCategories: ["utilities", "household", "telecom", "insurance", "rent", "property_tax"],
            requiresCardMultiplier: false,
            description: "Zero-fee direct bill payment with interest float and Neo partner perks."
        ),
        BillIntermediary(
            id: "standard-eft",
            name: "Standard Bank Bill Pay (EFT)",
            type: .standardEft,
            feeRate: 0.0,
            settlementDays: 2,
            supportedCategories: ["utilities", "household", "telecom", "insurance", "rent", "property_tax", "tuition", "government"],
            requiresCardMultiplier: false,
            description: "Direct chequing account EFT via traditional Big-5 bank (0% fee, 0% rewards)."
        )
    ]

    /// Evaluates and ranks all viable payment routes for a given bill payee and user's owned cards.
    public func scoreRoutes(
        for payee: BillPayee,
        ownedCardIds: [String] = []
    ) -> [RouteRecommendation] {
        let annualSpend = (payee.estimatedMonthlyCad ?? 150.0) * 12.0
        var routes: [RouteRecommendation] = []

        for intermediary in intermediaries {
            switch intermediary.type {
            case .creditIntermediary:
                // Check if user has Scotia Momentum VI (4%) or recurring card
                let hasScotiaMomentum = ownedCardIds.contains { $0.lowercased().contains("scotia") || $0.lowercased().contains("momentum") }
                let grossRate = hasScotiaMomentum ? 0.04 : 0.015
                let cardName = hasScotiaMomentum ? "Scotiabank Momentum Visa Infinite" : "Standard Cash Back Card"
                let cardId = hasScotiaMomentum ? "scotiabank-momentum-vi" : "standard-card"
                let netSpread = grossRate - intermediary.feeRate
                
                let mathText = String(format: "Earn %.1f%% - %.2f%% fee = %+.2f%% Net", grossRate * 100, intermediary.feeRate * 100, netSpread * 100)
                let instruction = hasScotiaMomentum
                    ? "Set up pre-authorized recurring payment on Chexy using your Scotia Momentum VI."
                    : "Caution: Using a lower-tier card may reduce net value due to the 1.75% processing fee."

                routes.append(
                    RouteRecommendation(
                        intermediary: intermediary,
                        cardId: cardId,
                        cardOfficialName: cardName,
                        grossRewardRate: grossRate,
                        feeRate: intermediary.feeRate,
                        annualSpendCad: annualSpend,
                        isOptimal: false,
                        headline: hasScotiaMomentum ? "Maximum Points / Cash Back Route" : "Credit Card Processing Route",
                        mathBreakdown: mathText,
                        instruction: instruction
                    )
                )

            case .cardDirectBillPay:
                let ownsTriangle = ownedCardIds.contains { $0.lowercased().contains("triangle") }
                let directRate = intermediary.directRewardRate ?? 0.01
                let mathText = String(format: "Direct Bill Pay (0%% fee) = +%.1f%% Net CT Money", directRate * 100)

                routes.append(
                    RouteRecommendation(
                        intermediary: intermediary,
                        cardId: ownsTriangle ? "triangle-we" : "triangle-mastercard-opportunity",
                        cardOfficialName: ownsTriangle ? "Triangle World Elite Mastercard" : "Canadian Tire Triangle Mastercard",
                        grossRewardRate: directRate,
                        feeRate: 0.0,
                        annualSpendCad: annualSpend,
                        isOptimal: false,
                        headline: ownsTriangle ? "Zero-Fee Card Direct Bill Pay" : "No-Fee Municipal Payee Loophole",
                        mathBreakdown: mathText,
                        instruction: "Log into Canadian Tire Bank portal and add this bill payee to earn 1% CT Money with 0% fees."
                    )
                )

            case .fintechAccountRouting:
                let floatRate = 0.0075 // Effective interest on held float + perks
                let mathText = "0% Fee + High-Yield Float Interest (~2.5% APY on held funds)"

                routes.append(
                    RouteRecommendation(
                        intermediary: intermediary,
                        cardId: nil,
                        cardOfficialName: "Neo Money Account",
                        grossRewardRate: 0.0,
                        feeRate: 0.0,
                        floatYieldRate: floatRate,
                        annualSpendCad: annualSpend,
                        isOptimal: false,
                        headline: "Smart Digital Cash / Yield Route",
                        mathBreakdown: mathText,
                        instruction: "Pay directly from Neo Money account to earn compound interest on your bill buffer before payment."
                    )
                )

            case .standardEft:
                routes.append(
                    RouteRecommendation(
                        intermediary: intermediary,
                        cardId: nil,
                        cardOfficialName: "Big-5 Chequing Account",
                        grossRewardRate: 0.0,
                        feeRate: 0.0,
                        annualSpendCad: annualSpend,
                        isOptimal: false,
                        headline: "Standard Chequing Bill Pay",
                        mathBreakdown: "0% Fees, $0.00 Rewards Baseline",
                        instruction: "Standard bank bill payment with no reward accrual."
                    )
                )
            }
        }

        // Sort descending by net dollar gain
        routes.sort { $0.estimatedAnnualNetCad > $1.estimatedAnnualNetCad }

        // Mark the top one as optimal
        if let top = routes.first {
            let updatedTop = RouteRecommendation(
                intermediary: top.intermediary,
                cardId: top.cardId,
                cardOfficialName: top.cardOfficialName,
                grossRewardRate: top.grossRewardRate,
                feeRate: top.feeRate,
                floatYieldRate: top.floatYieldRate,
                annualSpendCad: top.annualSpendCad,
                isOptimal: true,
                headline: top.headline,
                mathBreakdown: top.mathBreakdown,
                instruction: top.instruction
            )
            routes[0] = updatedTop
        }

        return routes
    }
}
