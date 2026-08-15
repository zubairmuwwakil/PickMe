import Foundation

public struct SwitchThreshold: Codable, Equatable, Sendable {
    public var minAdvantagePercentagePoints: Double
    public var minAdvantageCad: Double
    public var semantics: String   // "both" | "either"
}

public struct Carry: Codable, Equatable, Sendable {
    public var drawerCards: [String]
}

/// Layer 2 of the three-layer model: per-card owner/account state.
/// A `nil` field means unresolved — the engine skips rules that depend on it rather than guessing.
public struct CardState: Codable, Equatable, Sendable {
    public var capProgress: [String: Double]?
    public var scotiaAccountYearAnchorMonth: Int?
    public var selectedCategories: [String]?
    public var treatAsAllSelected: Bool?
    public var thirdCategoryUnlocked: Bool?
    public var nextChangeEffectiveDate: String?
    public var rogersEligibleServiceLinked: Bool?
    public var rogersAccountAnniversaryMonth: Int?
    public var feeWaiverActive: Bool?
    public var cryptoLevelUpProActive: Bool?
    public var croHandling: String?   // "autoSell" | "hold" | nil (unresolved)

    public init() {}
}

public struct PointValuation: Codable, Equatable, Sendable {
    public var centsPerPoint: Double
    public var floorCentsPerPoint: Double?
    public var low: Double?
    public var high: Double?
    public var basis: String?
}

public struct CtMoneyValuation: Codable, Equatable, Sendable {
    public var cadPerUnit: Double
    public var optionalUsabilityFactor: Double
    public var usabilityFactorApplied: Bool
}

public struct CroValuation: Codable, Equatable, Sendable {
    public var model: String
    public var faceValueFactorIfAutoSold: Double
    public var defaultHeldRiskFactor: Double
}

public struct CashBackValuation: Codable, Equatable, Sendable {
    public var cadPerDollar: Double
}

public struct Valuations: Codable, Equatable, Sendable {
    public var amexMembershipRewards: PointValuation
    public var marriottBonvoy: PointValuation
    public var mbnaRewards: PointValuation
    public var ctMoney: CtMoneyValuation
    public var cro: CroValuation
    public var cashBack: CashBackValuation
}

public struct OwnerState: Codable, Equatable, Sendable {
    public var ownerStateVersion: String
    public var defaultCardId: String
    public var switchThreshold: SwitchThreshold
    public var carry: Carry
    public var cardStates: [String: CardState]
    public var valuationsCad: Valuations
}
