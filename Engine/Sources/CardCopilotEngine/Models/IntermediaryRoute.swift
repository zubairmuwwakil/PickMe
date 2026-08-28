import Foundation

/// Type of payment intermediary / rail in Canada.
public enum IntermediaryType: String, Codable, Sendable {
    case creditIntermediary
    case cardDirectBillPay
    case fintechAccountRouting
    case standardEft
}

/// Catalog entry for an intermediary loaded from contracts.
public struct BillIntermediary: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let type: IntermediaryType
    public let feeRate: Double
    public let mccTrigger: String?
    public let directRewardRate: Double?
    public let directRewardProgramId: String?
    public let holdingApy: Double?
    public let hasPartnerPerks: Bool?
    public let settlementDays: Int
    public let restrictedCardPrograms: [String]?
    public let supportedCategories: [String]
    public let requiresCardMultiplier: Bool?
    public let description: String

    public init(
        id: String,
        name: String,
        type: IntermediaryType,
        feeRate: Double,
        mccTrigger: String? = nil,
        directRewardRate: Double? = nil,
        directRewardProgramId: String? = nil,
        holdingApy: Double? = nil,
        hasPartnerPerks: Bool? = nil,
        settlementDays: Int,
        restrictedCardPrograms: [String]? = nil,
        supportedCategories: [String],
        requiresCardMultiplier: Bool? = nil,
        description: String
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.feeRate = feeRate
        self.mccTrigger = mccTrigger
        self.directRewardRate = directRewardRate
        self.directRewardProgramId = directRewardProgramId
        self.holdingApy = holdingApy
        self.hasPartnerPerks = hasPartnerPerks
        self.settlementDays = settlementDays
        self.restrictedCardPrograms = restrictedCardPrograms
        self.supportedCategories = supportedCategories
        self.requiresCardMultiplier = requiresCardMultiplier
        self.description = description
    }
}

public struct BillIntermediariesCatalogue: Codable, Sendable {
    public let billIntermediariesVersion: String
    public let intermediaries: [BillIntermediary]
}

/// A ranked recommendation for paying a specific bill payee.
public struct RouteRecommendation: Identifiable, Equatable, Sendable {
    public var id: String { "\(intermediary.id)_\(cardId ?? "direct")" }
    public let intermediary: BillIntermediary
    public let cardId: String?
    public let cardOfficialName: String?
    public let grossRewardRate: Double
    public let feeRate: Double
    public let floatYieldRate: Double
    public let netSpreadRate: Double
    public let annualSpendCad: Double
    public let estimatedAnnualNetCad: Double
    public let isOptimal: Bool
    public let headline: String
    public let mathBreakdown: String
    public let instruction: String

    public init(
        intermediary: BillIntermediary,
        cardId: String? = nil,
        cardOfficialName: String? = nil,
        grossRewardRate: Double,
        feeRate: Double,
        floatYieldRate: Double = 0.0,
        annualSpendCad: Double,
        isOptimal: Bool,
        headline: String,
        mathBreakdown: String,
        instruction: String
    ) {
        self.intermediary = intermediary
        self.cardId = cardId
        self.cardOfficialName = cardOfficialName
        self.grossRewardRate = grossRewardRate
        self.feeRate = feeRate
        self.floatYieldRate = floatYieldRate
        let net = grossRewardRate - feeRate + floatYieldRate
        self.netSpreadRate = net
        self.annualSpendCad = annualSpendCad
        self.estimatedAnnualNetCad = annualSpendCad * net
        self.isOptimal = isOptimal
        self.headline = headline
        self.mathBreakdown = mathBreakdown
        self.instruction = instruction
    }
}
