import Foundation

public enum Network: String, Codable, Sendable { case amex, visa, mastercard }
public enum CardKind: String, Codable, Sendable { case credit, charge, prepaid }
public enum RuleStatus: String, Codable, Sendable { case current, announced }
public enum SourceType: String, Codable, Sendable { case issuerConfirmed, ownerObserved, inferred }

public enum Earn: Equatable, Sendable {
    case points(pointsPerCad: Double)
    case cashback(rate: Double, rewardCurrency: String?)
    case centsPerLitre   // informational only; never scored
}

extension Earn: Codable {
    private enum CodingKeys: String, CodingKey { case type, pointsPerCad, rate, rewardCurrency }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "points":
            self = .points(pointsPerCad: try c.decode(Double.self, forKey: .pointsPerCad))
        case "cashback":
            self = .cashback(rate: try c.decode(Double.self, forKey: .rate),
                             rewardCurrency: try c.decodeIfPresent(String.self, forKey: .rewardCurrency))
        case "centsPerLitre":
            self = .centsPerLitre
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                debugDescription: "unknown earn type: \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .points(let p):
            try c.encode("points", forKey: .type)
            try c.encode(p, forKey: .pointsPerCad)
        case .cashback(let r, let cur):
            try c.encode("cashback", forKey: .type)
            try c.encode(r, forKey: .rate)
            try c.encodeIfPresent(cur, forKey: .rewardCurrency)
        case .centsPerLitre:
            try c.encode("centsPerLitre", forKey: .type)
        }
    }
}

public struct Predicate: Codable, Equatable, Sendable {
    public var categories: [String]?
    public var mccInclude: [Int]?
    public var mccExclude: [Int]?
    public var merchantInclude: [String]?
    public var merchantExclude: [String]?
    public var country: String?
    public var currency: String?
    public var channels: [String]?
    public var recurringViaNetworkIndicator: Bool?

    public init() {}
}

public struct EarnRule: Codable, Equatable, Sendable {
    public var ruleId: String
    public var status: RuleStatus
    public var effectiveFrom: String?
    public var effectiveTo: String?
    public var sourceType: SourceType
    public var earn: Earn
    public var predicate: Predicate
    public var capId: String?
    public var ownerConditions: [String]?
    public var scoredInV1: Bool?
}

public enum CapMeasure: String, Codable, Sendable { case spendCad, spendUsdEquivalent }
public enum CapPeriod: String, Codable, Sendable { case calendarMonth, calendarYear, accountYear }

public struct Cap: Codable, Equatable, Sendable {
    public var capId: String
    public var measure: CapMeasure
    public var limit: Double
    public var period: CapPeriod
    public var anchor: String?
    public var resetTimeZone: String
    public var postCapEarn: Earn?
    public var proration: Bool
}

public struct FxRule: Codable, Equatable, Sendable {
    public var status: RuleStatus
    public var effectiveFrom: String?
    public var effectiveTo: String?
    public var rate: Double
    public var freeAllowanceCadPerCalendarMonth: Double?
    public var postAllowanceRate: Double?
}

public struct Fee: Codable, Equatable, Sendable {
    public var annualCad: Double?
    public var monthlyCad: Double?
    public var billing: String?
    public var waiver: String?
}

public struct Program: Codable, Equatable, Sendable {
    public var programId: String
    public var unit: String
}

public struct CardProduct: Codable, Equatable, Identifiable, Sendable {
    public var cardId: String
    public var officialName: String
    public var issuer: String
    public var network: Network
    public var kind: CardKind
    public var fee: Fee
    public var program: Program
    public var fxRules: [FxRule]
    public var earnRules: [EarnRule]
    public var caps: [Cap]
    public var perTransactionRewardVisibility: String
    public var lastVerifiedAt: String

    public var id: String { cardId }
}

public struct Catalogue: Codable, Equatable, Sendable {
    public var catalogueVersion: String
    public var currency: String
    public var cards: [CardProduct]
}
