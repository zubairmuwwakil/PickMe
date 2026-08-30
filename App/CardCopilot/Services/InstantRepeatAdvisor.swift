import Foundation
import CardCopilotEngine
import CardCopilotStore

/// Evaluation summary for an Instant Repeat merchant at a specified spend amount.
public struct InstantRepeatEvaluation: Equatable, Sendable {
    public let merchantId: String
    public let merchantName: String
    public let category: String
    public let formattedCategory: String
    public let amountCad: Double
    public let winnerCardId: String
    public let winnerCardName: String
    public let returnCad: Double
    public let returnPercentage: Double
    public let multiplierText: String
    public let rewardUnitsText: String?
    public let calculationText: String
    public let advantageText: String?
    public let networkBadge: String?
    public let isDefaultCard: Bool
    public let switchedFromDefault: Bool
    public let isAmbiguous: Bool
    public let ambiguousCandidates: [String]
    public let recommendation: Recommendation

    public init(merchantId: String, merchantName: String, category: String, formattedCategory: String,
                amountCad: Double, winnerCardId: String, winnerCardName: String, returnCad: Double,
                returnPercentage: Double, multiplierText: String, rewardUnitsText: String?,
                calculationText: String, advantageText: String?, networkBadge: String?,
                isDefaultCard: Bool, switchedFromDefault: Bool, isAmbiguous: Bool,
                ambiguousCandidates: [String], recommendation: Recommendation) {
        self.merchantId = merchantId
        self.merchantName = merchantName
        self.category = category
        self.formattedCategory = formattedCategory
        self.amountCad = amountCad
        self.winnerCardId = winnerCardId
        self.winnerCardName = winnerCardName
        self.returnCad = returnCad
        self.returnPercentage = returnPercentage
        self.multiplierText = multiplierText
        self.rewardUnitsText = rewardUnitsText
        self.calculationText = calculationText
        self.advantageText = advantageText
        self.networkBadge = networkBadge
        self.isDefaultCard = isDefaultCard
        self.switchedFromDefault = switchedFromDefault
        self.isAmbiguous = isAmbiguous
        self.ambiguousCandidates = ambiguousCandidates
        self.recommendation = recommendation
    }
}

/// Evaluates real-time checkout advice for Instant Repeat merchants.
public enum InstantRepeatAdvisor {

    /// Default amounts offered on the interactive quick-selector bar.
    public static let presetAmounts: [Double] = [10, 25, 50, 100]

    public static func evaluate(
        merchant: StoredMerchant,
        amountCad: Double,
        catalogue: Catalogue,
        ownerState: OwnerState,
        engine: RecommendationEngine,
        asOf: String = Date().formatted(.iso8601.year().month().day())
    ) -> InstantRepeatEvaluation? {
        let prediction = predictionForKnownMerchant(merchant)
        let category = prediction.category
        let isAmbiguous = prediction.candidates.count > 1
        let brand = canonicalEngineBrand(merchant.name)
        let acceptedNetworks = knownAcceptedNetworks(for: brand, merchantName: merchant.name)

        let purchase = PurchaseContext(
            amountCad: amountCad,
            category: category,
            merchantBrand: brand,
            acceptedNetworks: acceptedNetworks
        )

        let outcome = engine.recommend(purchase, asOf: asOf)
        guard case .advised(let rec) = outcome else { return nil }

        let winner = rec.winner
        let winnerCard = catalogue.cards.first { $0.cardId == winner.cardId }
        let winnerCardName = winnerCard?.officialName ?? winner.cardId
        let returnCad = winner.netValueCad
        let returnPercentage = amountCad > 0 ? (returnCad / amountCad) * 100 : 0
        let isDefault = winner.cardId == ownerState.defaultCardId

        // Network acceptance badge
        let networkBadge: String? = {
            if !acceptedNetworks.contains(.amex) && acceptedNetworks.contains(.mastercard) && acceptedNetworks.contains(.visa) {
                return "MC / Visa Only"
            } else if acceptedNetworks == [.mastercard] {
                return "Mastercard Only"
            } else if acceptedNetworks == [.visa] {
                return "Visa Only"
            }
            return nil
        }()

        // Multiplier & earn rate
        var multiplierText = String(format: "%.1f%% return", returnPercentage)
        if let ruleId = winner.appliedRuleId,
           let rule = winnerCard?.earnRules.first(where: { $0.ruleId == ruleId }) {
            switch rule.earn {
            case .points(let perCad):
                let mult = perCad.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0fx", perCad)
                    : String(format: "%.1fx", perCad)
                multiplierText = "\(mult) Points"
            case .cashback(let rate, let curr):
                let pct = (rate * 100).truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f%%", rate * 100)
                    : String(format: "%.1f%%", rate * 100)
                multiplierText = (curr != nil && curr != "CAD") ? "\(pct) in \(curr!)" : "\(pct) Cash Back"
            case .centsPerLitre:
                multiplierText = "Fuel Savings"
            }
        }

        // Calculation & Advantage text
        var advantageText: String? = nil
        var calculationText = ""
        if rec.switchedFromDefault {
            if let adv = rec.advantageOverDefaultCad, adv > 0.005 {
                advantageText = String(format: "+$%.2f vs default", adv)
                calculationText = String(format: "$%.2f back (+$%.2f over default on $%.0f)", returnCad, adv, amountCad)
            } else if rec.defaultNotAccepted {
                advantageText = "Default not accepted"
                calculationText = String(format: "$%.2f back (%@ return on $%.0f)", returnCad, String(format: "%.1f%%", returnPercentage), amountCad)
            } else {
                calculationText = String(format: "$%.2f back (%@ return on $%.0f)", returnCad, String(format: "%.1f%%", returnPercentage), amountCad)
            }
        } else {
            if let suppressed = rec.suppressedBetterCard {
                let betterName = catalogue.cards.first { $0.cardId == suppressed.cardId }?.officialName ?? "Other card"
                advantageText = "Default card"
                calculationText = "Default card recommended · Switch to \(betterName) on larger amounts"
            } else {
                advantageText = "Default card"
                calculationText = String(format: "Default card is best · $%.2f back on $%.0f", returnCad, amountCad)
            }
        }

        // Reward Units
        var rewardUnitsText: String? = nil
        if winner.rewardUnits > 0 {
            switch winnerCard?.program.unit {
            case "point":
                rewardUnitsText = "\(Int(winner.rewardUnits)) pts"
            case "cad":
                rewardUnitsText = String(format: "$%.2f cash", winner.rewardUnits)
            case "ctDollar":
                rewardUnitsText = String(format: "$%.2f CT$", winner.rewardUnits)
            case "cro":
                rewardUnitsText = String(format: "%.1f CRO", winner.rewardUnits)
            default:
                rewardUnitsText = String(format: "%.1f units", winner.rewardUnits)
            }
        }

        let meta = CategoryVisuals.meta(for: category)
        let formattedCat = meta.displayName

        return InstantRepeatEvaluation(
            merchantId: merchant.identifier ?? merchant.id.uuidString,
            merchantName: merchant.name,
            category: category,
            formattedCategory: formattedCat,
            amountCad: amountCad,
            winnerCardId: winner.cardId,
            winnerCardName: winnerCardName,
            returnCad: returnCad,
            returnPercentage: returnPercentage,
            multiplierText: multiplierText,
            rewardUnitsText: rewardUnitsText,
            calculationText: calculationText,
            advantageText: advantageText,
            networkBadge: networkBadge,
            isDefaultCard: isDefault,
            switchedFromDefault: rec.switchedFromDefault,
            isAmbiguous: isAmbiguous,
            ambiguousCandidates: prediction.candidates,
            recommendation: rec
        )
    }
}
