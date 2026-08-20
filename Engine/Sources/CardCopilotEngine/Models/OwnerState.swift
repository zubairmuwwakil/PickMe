import Foundation

public struct SwitchThreshold: Codable, Equatable, Sendable {
    public var minAdvantagePercentagePoints: Double
    public var minAdvantageCad: Double
    public var semantics: String   // "both" | "either"

    public init(minAdvantagePercentagePoints: Double, minAdvantageCad: Double, semantics: String) {
        self.minAdvantagePercentagePoints = minAdvantagePercentagePoints
        self.minAdvantageCad = minAdvantageCad
        self.semantics = semantics
    }
}

public struct Carry: Codable, Equatable, Sendable {
    public var drawerCards: [String]

    public init(drawerCards: [String]) { self.drawerCards = drawerCards }
}

/// The Tangerine Money-Back categories an owner can select on their account.
///
/// Raw values use the engine's purchase vocabulary. Categories that depend on purchase facts
/// rather than a merchant category (`recurring` and `foreignCurrency`) are resolved explicitly
/// by `RuleMatcher`.
public enum TangerineMoneyBackCategory: String, CaseIterable, Codable, Sendable {
    case grocery
    case dining
    case gasStation
    case entertainment
    case furniture
    case lodging
    case drugStore
    case recurring
    case homeImprovement
    case transit
    case eGames
    case fitness
    case foreignCurrency
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

/// All four valuation models carry an optional `basis`: the string that tells the owner where a
/// number came from and which parts of it are assumptions rather than issuer facts. It is not
/// decoration — the disclosure UI renders it, and CLAUDE.md's valuation policy is that a point
/// value is a forecast of redemption behaviour, never a fact. ctMoney's usability factor and
/// cro's held-risk factor are the most assumption-laden numbers in the catalogue and need it most.
public extension OwnerState {
    /// This owner state with the catalogue's default valuations filled in *beneath* the owner's
    /// own. Every key the owner declares wins; defaults only fill gaps.
    ///
    /// A valuation is a personal forecast of redemption behaviour, so the catalogue may supply a
    /// number where the owner has none but must never overrule one they have declared. That
    /// direction is the whole contract.
    ///
    /// Applied at `RecommendationEngine.init`, which every scoring path funnels through —
    /// PortfolioAnalyzer, RecurringAuditor, CategoryPickerAdvisor and Store's CheckoutService all
    /// construct one. Merging at `SeedLoader.loadOwnerState()` instead would reach the shipped
    /// seed and nothing else: owner states restored from a device by
    /// `AccountOwnerStateStore` never pass through SeedLoader, and those are the real wallets.
    ///
    /// Idempotent, so re-merging an already-merged state (PortfolioAnalyzer builds sub-engines
    /// from a state it already holds) costs a dictionary merge and changes nothing.
    func applyingCatalogueValuationDefaults(
        _ defaults: [String: ProgramValuation] = SeedLoader.programValuationDefaults
    ) -> OwnerState {
        var merged = self
        merged.valuationsCad.programs = defaults
            .merging(valuationsCad.programs) { _, ownerDeclared in ownerDeclared }
        return merged
    }
}

public struct PointValuation: Codable, Equatable, Sendable {
    public var centsPerPoint: Double
    public var floorCentsPerPoint: Double?
    /// Published benchmark value for this currency. Used only as a plausibility ceiling when
    /// deciding whether an upside breakeven is worth disclosing — never for ranking.
    public var aspirationalCentsPerPoint: Double?
    public var low: Double?
    public var high: Double?
    public var basis: String?

    public init(centsPerPoint: Double, floorCentsPerPoint: Double? = nil,
                aspirationalCentsPerPoint: Double? = nil, low: Double? = nil,
                high: Double? = nil, basis: String? = nil) {
        self.centsPerPoint = centsPerPoint
        self.floorCentsPerPoint = floorCentsPerPoint
        self.aspirationalCentsPerPoint = aspirationalCentsPerPoint
        self.low = low
        self.high = high
        self.basis = basis
    }
}

public struct CtMoneyValuation: Codable, Equatable, Sendable {
    public var cadPerUnit: Double
    public var optionalUsabilityFactor: Double
    public var usabilityFactorApplied: Bool
    public var basis: String?

    public init(cadPerUnit: Double, optionalUsabilityFactor: Double,
                usabilityFactorApplied: Bool, basis: String? = nil) {
        self.cadPerUnit = cadPerUnit
        self.optionalUsabilityFactor = optionalUsabilityFactor
        self.usabilityFactorApplied = usabilityFactorApplied
        self.basis = basis
    }
}

public struct CroValuation: Codable, Equatable, Sendable {
    /// How CRO converts to CAD — not the `ProgramValuation` discriminator, which is a separate
    /// key at the same JSON level. Named `model` until 2026-08-20; renamed to free that key.
    public var redemptionModel: String
    public var faceValueFactorIfAutoSold: Double
    public var defaultHeldRiskFactor: Double
    public var basis: String?

    public init(redemptionModel: String, faceValueFactorIfAutoSold: Double,
                defaultHeldRiskFactor: Double, basis: String? = nil) {
        self.redemptionModel = redemptionModel
        self.faceValueFactorIfAutoSold = faceValueFactorIfAutoSold
        self.defaultHeldRiskFactor = defaultHeldRiskFactor
        self.basis = basis
    }
}

public struct CashBackValuation: Codable, Equatable, Sendable {
    public var cadPerDollar: Double
    public var basis: String?

    public init(cadPerDollar: Double, basis: String? = nil) {
        self.cadPerDollar = cadPerDollar
        self.basis = basis
    }
}

/// Reward-currency valuations, keyed by the catalogue's `programId`.
///
/// Was six hardcoded properties, which made every new rewards program a Swift change, a Kotlin
/// change, a schema-enum change and an owner-state migration. Sixteen programIds shipped in the
/// catalogue against those six properties before this was fixed, and every card on the other ten
/// scored $0.00 on every purchase while staying selectable in wallet setup.
public struct Valuations: Equatable, Sendable {
    public var programs: [String: ProgramValuation]

    public init(programs: [String: ProgramValuation] = [:]) {
        self.programs = programs
    }

    public subscript(programId: String) -> ProgramValuation? {
        get { programs[programId] }
        set { programs[programId] = newValue }
    }

    /// A points program's valuation, or `nil` when the program is absent or valued under a
    /// different model. Writing stores it as `.points`; writing `nil` removes the entry.
    ///
    /// Exists because cents-per-point is the one field callers routinely read and write — the
    /// valuation sandbox, wallet setup, and every sensitivity test. Without it each call site
    /// would repeat a `guard case .points` dance, and the sites that got it wrong would fail
    /// silently rather than loudly.
    public subscript(points programId: String) -> PointValuation? {
        get {
            guard case .points(let v)? = programs[programId] else { return nil }
            return v
        }
        set { programs[programId] = newValue.map(ProgramValuation.points) }
    }
}

extension Valuations: Codable {
    private enum Keys: String, CodingKey { case programs }

    /// Addresses a legacy top-level program key by name. Legacy owner states have no fixed key
    /// set at compile time from this type's point of view, so the container needs a dynamic key.
    private struct LegacyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Legacy owner states name each program as its own top-level key and carry no `model`
    /// discriminator — the model was implied by the key. New ones nest a `programs` dictionary.
    /// Both decode; only the latter is ever written back, so a wallet upgrades itself the first
    /// time it is saved. Delete the legacy branch one full release cycle after ship, with a dated
    /// entry in contracts/CHANGELOG.md.
    ///
    /// The legacy branch decodes key-by-key into the concrete payload type rather than
    /// re-serialising through an intermediate JSON value: the legacy key set is closed, so the
    /// model each key implies is known statically, and unlisted keys are skipped by construction.
    /// The modern branch is gated on key *presence* and then decodes without `try?`, so a
    /// malformed `programs` block throws instead of falling through to the legacy branch and
    /// quietly producing an empty wallet.
    public init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: Keys.self), keyed.contains(.programs) {
            self.init(programs: try keyed.decode([String: ProgramValuation].self, forKey: .programs))
            return
        }
        try self.init(legacy: decoder.container(keyedBy: LegacyKey.self))
    }

    private init(legacy container: KeyedDecodingContainer<LegacyKey>) throws {
        var programs: [String: ProgramValuation] = [:]

        func take<Payload: Decodable>(_ legacyKey: String,
                                      _ wrap: (Payload) -> ProgramValuation,
                                      as programId: String) throws {
            let key = LegacyKey(legacyKey)
            guard container.contains(key) else { return }
            programs[programId] = wrap(try container.decode(Payload.self, forKey: key))
        }

        try take("amexMembershipRewards", ProgramValuation.points, as: "amexMembershipRewards")
        try take("marriottBonvoy", ProgramValuation.points, as: "marriottBonvoy")
        try take("mbnaRewards", ProgramValuation.points, as: "mbnaRewards")
        try take("ctMoney", ProgramValuation.ctMoney, as: "ctMoney")
        try take("cro", ProgramValuation.cro, as: "cro")
        // The catalogue spells this programId lowercase while the legacy key is camelCase.
        // Getting this one mapping wrong silently unvalues every cash-back card.
        try take("cashBack", ProgramValuation.cashback, as: "cashback")

        // Anything else in a legacy block — `rogersEligibleServiceRedemption`, say — is not a
        // catalogue programId and has no ProgramValuation model. Ignored, never fatal.
        self.init(programs: programs)
    }

    public func encode(to encoder: Encoder) throws {
        var keyed = encoder.container(keyedBy: Keys.self)
        try keyed.encode(programs, forKey: .programs)
    }
}

public struct OwnerState: Codable, Equatable, Sendable {
    public var ownerStateVersion: String
    /// The product catalogue and the wallet are different concepts. Checkout currently receives
    /// only wallet products, while acquisition analysis also receives non-owned candidates; this
    /// explicit boundary prevents a candidate from silently becoming a checkout option.
    public var ownedCardIds: [String]
    public var defaultCardId: String
    public var switchThreshold: SwitchThreshold
    public var carry: Carry
    public var cardStates: [String: CardState]
    public var valuationsCad: Valuations

    public init(ownerStateVersion: String, ownedCardIds: [String], defaultCardId: String,
                switchThreshold: SwitchThreshold, carry: Carry, cardStates: [String: CardState],
                valuationsCad: Valuations) {
        self.ownerStateVersion = ownerStateVersion
        self.ownedCardIds = ownedCardIds
        self.defaultCardId = defaultCardId
        self.switchThreshold = switchThreshold
        self.carry = carry
        self.cardStates = cardStates
        self.valuationsCad = valuationsCad
    }
}
