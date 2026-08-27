import Foundation

public enum Network: String, Codable, Sendable { case amex, visa, mastercard }
public enum CardKind: String, Codable, Sendable { case credit, charge, prepaid }
public enum RuleStatus: String, Codable, Sendable { case current, announced }
/// A card product's lifecycle, distinct from `RuleStatus` (which is `current`/`announced` and
/// describes a rule, not a product). Absent means active: a catalogue written before tombstoning
/// existed must keep scoring unchanged.
public enum CardStatus: String, Codable, Sendable { case active, withdrawn }
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
    /// Engine capabilities this rule needs, as `EngineCapability` raw values. Absent means none.
    /// A rule naming a capability this build lacks is skipped; it turns on by itself when that
    /// capability ships. Typed as `[String]` rather than `[EngineCapability]` so an unrecognised
    /// name is a gating decision made in code, not a decode failure that loses the whole
    /// catalogue — a card the engine cannot fully score is still a card it can partly score.
    public var requires: [String]?
    /// Set when the rule will never be scored. Mutually exclusive with `requires`.
    public var outOfScope: OutOfScope?

    public init(ruleId: String, status: RuleStatus, effectiveFrom: String? = nil,
                effectiveTo: String? = nil, sourceType: SourceType, earn: Earn,
                predicate: Predicate, capId: String? = nil, ownerConditions: [String]? = nil,
                scoredInV1: Bool? = nil, requires: [String]? = nil,
                outOfScope: OutOfScope? = nil) {
        self.ruleId = ruleId
        self.status = status
        self.effectiveFrom = effectiveFrom
        self.effectiveTo = effectiveTo
        self.sourceType = sourceType
        self.earn = earn
        self.predicate = predicate
        self.capId = capId
        self.ownerConditions = ownerConditions
        self.scoredInV1 = scoredInV1
        self.requires = requires
        self.outOfScope = outOfScope
    }
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

    public init(programId: String, unit: String) {
        self.programId = programId
        self.unit = unit
    }
}

/// A recurring statement credit the issuer grants for holding the card — Platinum's annual travel
/// and dining credits, Crypto.com's monthly streaming rebates. Deliberately NOT an earn rule: a
/// credit does not depend on what the purchase was, so it never enters the checkout pick. It is
/// keep/cancel and net-value input, which is why `RecommendationEngine` does not read it and the
/// golden fixtures are unaffected by its presence.
///
/// `valueCad` is the issuer's stated maximum, not a forecast of what the owner will actually use;
/// whether a credit was redeemed is owner activity and lives with the consumer, not here.
public struct CardCredit: Codable, Equatable, Identifiable, Sendable {
    public var creditId: String
    public var label: String
    public var valueCad: Double
    public var period: CapPeriod
    public var sourceType: SourceType
    public var lastVerifiedAt: String

    public var id: String { creditId }

    public init(creditId: String, label: String, valueCad: Double, period: CapPeriod,
                sourceType: SourceType, lastVerifiedAt: String) {
        self.creditId = creditId
        self.label = label
        self.valueCad = valueCad
        self.period = period
        self.sourceType = sourceType
        self.lastVerifiedAt = lastVerifiedAt
    }
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
    /// Absent for the majority of cards. Optional rather than defaulted so a catalogue written
    /// before credits existed still decodes, exactly as `sources` and `stacking` do by being
    /// absent from this struct entirely.
    public var credits: [CardCredit]?
    /// Set when the issuer has discontinued the product. The card is never deleted from the
    /// catalogue and its id is never reused: ledgers, prediction rows, and other repos' vendored
    /// copies all key on that id, and an id that stops resolving turns history into orphans.
    public var status: CardStatus?
    /// The date the product stopped being available. Scoring respects it, so an `asOf` before
    /// this date still scores the card exactly as it scored at the time.
    public var effectiveTo: String?

    public var id: String { cardId }

    /// Whether this product can win a pick on the given date.
    ///
    /// Dated rather than a flat boolean so that historical `asOf` queries stay truthful — a card
    /// withdrawn last month was a legitimate answer the month before. Compared as ISO-8601
    /// strings, which sort lexicographically, exactly as `RuleMatcher` compares rule windows.
    public func isScoreable(asOf: String) -> Bool {
        guard status == .withdrawn else { return true }
        guard let effectiveTo else { return false }
        return asOf <= effectiveTo
    }
}

/// The researched acquisition candidates, as references into `Catalogue` — never as card
/// definitions. Holding definitions here is what let the same card disagree with itself
/// (see SeedLoader.loadCandidateCatalogue).
public struct CandidateSet: Codable, Equatable, Sendable {
    public var candidateCatalogueVersion: String
    public var cardIds: [String]

    public init(candidateCatalogueVersion: String = "2.0", cardIds: [String] = []) {
        self.candidateCatalogueVersion = candidateCatalogueVersion
        self.cardIds = cardIds
    }

    public static var empty: CandidateSet { CandidateSet() }
}

public struct Catalogue: Codable, Equatable, Sendable {
    public var catalogueVersion: String
    public var currency: String
    public var cards: [CardProduct]

    public init(catalogueVersion: String = "1", currency: String = "CAD", cards: [CardProduct] = []) {
        self.catalogueVersion = catalogueVersion
        self.currency = currency
        self.cards = cards
    }

    public static var empty: Catalogue {
        Catalogue(catalogueVersion: "1", currency: "CAD", cards: [])
    }
}
