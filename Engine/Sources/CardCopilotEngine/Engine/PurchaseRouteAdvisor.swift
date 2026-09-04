import Foundation

/// Confidence/provenance for a purchase route. Route facts are deliberately distinct from
/// issuer-confirmed card contracts: gift-card inventory and merchant behaviour can vary by
/// location, so the UI must not present a community-observed route as guaranteed.
public enum PurchaseRouteEvidenceLevel: String, Codable, Equatable, Sendable {
    case retailerConfirmed
    case communityObserved
    case experimental
}

/// A known alternative way to fund a purchase. The route does not hard-code a card: the existing
/// `RecommendationEngine` re-scores the acquisition leg against the owner's actual wallet.
public struct AlternativePurchaseRoute: Codable, Equatable, Sendable, Identifiable {
    public let routeId: String
    public let destinationMerchantAliases: [String]
    public let instrumentLabel: String
    public let acquisitionMerchantLabel: String
    public let acquisitionCategory: String
    public let acquisitionMcc: Int?
    public let acquisitionMerchantBrand: String?
    public let acceptedNetworks: Set<Network>
    public let fixedFeeCad: Double
    public let estimatedFrictionCad: Double
    public let evidenceLevel: PurchaseRouteEvidenceLevel
    public let disclosure: String

    public var id: String { routeId }

    public init(routeId: String,
                destinationMerchantAliases: [String],
                instrumentLabel: String,
                acquisitionMerchantLabel: String,
                acquisitionCategory: String,
                acquisitionMcc: Int? = nil,
                acquisitionMerchantBrand: String? = nil,
                acceptedNetworks: Set<Network> = [.amex, .visa, .mastercard],
                fixedFeeCad: Double = 0,
                estimatedFrictionCad: Double = 0,
                evidenceLevel: PurchaseRouteEvidenceLevel,
                disclosure: String) {
        self.routeId = routeId
        self.destinationMerchantAliases = destinationMerchantAliases
        self.instrumentLabel = instrumentLabel
        self.acquisitionMerchantLabel = acquisitionMerchantLabel
        self.acquisitionCategory = CategoryTaxonomy.canonicalID(acquisitionCategory)
        self.acquisitionMcc = acquisitionMcc
        self.acquisitionMerchantBrand = acquisitionMerchantBrand
        self.acceptedNetworks = acceptedNetworks
        self.fixedFeeCad = fixedFeeCad
        self.estimatedFrictionCad = estimatedFrictionCad
        self.evidenceLevel = evidenceLevel
        self.disclosure = disclosure
    }

    public func matches(destinationMerchantName: String) -> Bool {
        let merchant = Self.normalized(destinationMerchantName)
        return destinationMerchantAliases.contains { alias in
            let candidate = Self.normalized(alias)
            return !candidate.isEmpty && merchant.contains(candidate)
        }
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// Separate from the card-switch threshold: an alternate route can require another stop or an
/// extra payment instrument, so it needs a materially higher bar than merely pulling another card.
public struct PurchaseRouteThreshold: Equatable, Sendable {
    public let minAdvantageCad: Double
    public let minAdvantagePercentagePoints: Double

    public init(minAdvantageCad: Double = 1,
                minAdvantagePercentagePoints: Double = 1) {
        self.minAdvantageCad = minAdvantageCad
        self.minAdvantagePercentagePoints = minAdvantagePercentagePoints
    }

    public static let shipped = PurchaseRouteThreshold()
}

public struct PurchaseRouteEvaluation: Equatable, Sendable {
    public let route: AlternativePurchaseRoute
    public let acquisitionRecommendation: Recommendation
    public let directValueCad: Double
    public let routeValueCad: Double
    public let advantageCad: Double
    public let advantagePercentagePoints: Double
}

/// Compares the best direct card with known alternate funding paths. This sits above
/// `RecommendationEngine`: it changes *how* the purchase is made, while the existing engine stays
/// the sole authority for which owned card wins each card-funded leg.
public enum PurchaseRouteAdvisor {
    public static func bestAlternative(
        directRecommendation: Recommendation,
        destination: PurchaseContext,
        destinationMerchantName: String,
        routes: [AlternativePurchaseRoute] = PurchaseRouteCatalogue.canadaV1,
        engine: RecommendationEngine,
        asOf: String,
        threshold: PurchaseRouteThreshold = .shipped
    ) -> PurchaseRouteEvaluation? {
        guard destination.amountCad > 0 else { return nil }

        let directValue = directRecommendation.winner.decisionValueCad
        var eligible: [PurchaseRouteEvaluation] = []

        for route in routes where route.matches(destinationMerchantName: destinationMerchantName) {
            let acquisition = PurchaseContext(
                amountCad: destination.amountCad,
                currency: destination.currency,
                usdEquivalent: destination.usdEquivalent,
                category: route.acquisitionCategory,
                mcc: route.acquisitionMcc,
                merchantBrand: route.acquisitionMerchantBrand,
                country: destination.country,
                channel: "cardPresent",
                recurringIndicator: false,
                acceptedNetworks: route.acceptedNetworks
            )

            guard case .advised(let recommendation) = engine.recommend(acquisition, asOf: asOf) else {
                continue
            }

            let routeValue = recommendation.winner.decisionValueCad
                - route.fixedFeeCad
                - route.estimatedFrictionCad
            let advantage = routeValue - directValue
            let advantagePP = advantage / destination.amountCad * 100

            // Require BOTH floors. A route that earns 4% more on a $5 purchase is still not worth
            // another checkout; a $5 gain on a $2,000 purchase can likewise be beneath the noise.
            guard advantage >= threshold.minAdvantageCad,
                  advantagePP >= threshold.minAdvantagePercentagePoints else { continue }

            eligible.append(PurchaseRouteEvaluation(
                route: route,
                acquisitionRecommendation: recommendation,
                directValueCad: directValue,
                routeValueCad: routeValue,
                advantageCad: advantage,
                advantagePercentagePoints: advantagePP
            ))
        }

        return eligible.max { lhs, rhs in
            if lhs.advantageCad != rhs.advantageCad {
                return lhs.advantageCad < rhs.advantageCad
            }
            return lhs.route.routeId > rhs.route.routeId
        }
    }
}

/// V1 keeps route knowledge intentionally small. The acquisition merchant is a *requirement*, not
/// a promise that every grocery store stocks the gift card. The merchant/MCC graph can later
/// resolve nearby terminals that satisfy this template without changing route-scoring semantics.
public enum PurchaseRouteCatalogue {
    public static let canadaV1: [AlternativePurchaseRoute] = [
        AlternativePurchaseRoute(
            routeId: "shoppers-gift-card-via-grocery-5411",
            destinationMerchantAliases: ["Shoppers Drug Mart", "Shoppers", "Pharmaprix"],
            instrumentLabel: "Shoppers Drug Mart gift card",
            acquisitionMerchantLabel: "an eligible grocery store that codes as MCC 5411",
            acquisitionCategory: "grocery",
            acquisitionMcc: 5411,
            evidenceLevel: .communityObserved,
            disclosure: "Gift-card inventory and issuer reward treatment can vary by store and transaction. Confirm availability before relying on this route."
        )
    ]
}
