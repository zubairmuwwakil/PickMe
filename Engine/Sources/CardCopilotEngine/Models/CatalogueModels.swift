import Foundation

/// The payment network a card runs on. `privateLabel` means it runs on NONE — a store card
/// accepted only by its own merchant. It is never a member of a purchase's `acceptedNetworks`
/// (see `PurchaseContext`'s default), so a `privateLabel` card that forgot to declare
/// `acceptance` fails closed: excluded everywhere rather than recommended everywhere. The
/// schema's if/then invariant makes that unreachable; this makes it harmless if it ever were.
public enum Network: String, Codable, Sendable {
    case amex, visa, mastercard, discover, privateLabel
}

/// How a card is accepted. Absent on a `CardProduct` means `openLoop` — which is every card in
/// the catalogue as of card-contracts@2.4, so no existing record changes a byte. The case exists
/// in code as that coalescing default; the schema deliberately refuses to let data spell it out,
/// because an `openLoop` record would have to carry a `merchants` list `Scorer` never reads.
public enum AcceptanceScope: String, Codable, Sendable { case openLoop, closedLoop }

/// A closed-loop card's acceptance list, in the same lowercase kebab-case merchant tokens
/// `RuleMatcher` matches `merchantInclude` against — and pinned by the same integrity test, since
/// a token that cannot match is a card that can never be picked.
public struct Acceptance: Codable, Equatable, Sendable {
    public var scope: AcceptanceScope
    public var merchants: [String]

    public init(scope: AcceptanceScope, merchants: [String]) {
        self.scope = scope
        self.merchants = merchants
    }
}
public enum CardKind: String, Codable, Sendable { case credit, charge, prepaid }
public enum RuleStatus: String, Codable, Sendable { case current, announced }
public enum SourceType: String, Codable, Sendable { case issuerConfirmed, ownerObserved, inferred }

/// The country a card product is sold in. NOT, by itself, an eligibility claim beyond "this is the
/// market the card is sold in" — see `Eligibility.residency` for the rare card sold in more than
/// one. A closed enum: a third market is a deliberate scope decision (ECOSYSTEM.md's horizon), not
/// a data entry, so an unrecognised value fails to decode rather than silently passing through.
public enum Market: String, Codable, Equatable, Sendable { case ca = "CA", us = "US" }

/// The two currencies this catalogue represents. Used both for `CardProduct.billingCurrency` (what
/// currency a purchase is measured in for THIS card's own earn rules and caps) and for `Money`
/// (what currency a stated fee/credit amount is actually in). Adding a third market's currency is a
/// schema + engine change — `ReportingCurrency.toReporting` needs a pinned rate for it.
public enum Currency: String, Codable, Equatable, Sendable { case cad = "CAD", usd = "USD" }

/// A currency-tagged monetary figure. Replaces the old bare CAD-assuming numbers
/// (`Fee.annualCad`/`monthlyCad`, `CardCredit.valueCad`) — see ReportingCurrency.swift for why a
/// price without a currency must never be summed with one that has it, and how the two are
/// reconciled into the engine's fixed CAD reporting currency at the point of use.
public struct Money: Codable, Equatable, Sendable {
    public var amount: Double
    public var currency: Currency

    public init(amount: Double, currency: Currency) {
        self.amount = amount
        self.currency = currency
    }
}

public enum Earn: Equatable, Sendable {
    /// Points per unit of the card's OWN `billingCurrency` — 1 point per USD billed for a
    /// USD-billing card, not per CAD unconditionally. Renamed from `pointsPerCad` in catalogue 2.0.
    case points(pointsPerUnit: Double)
    case cashback(rate: Double, rewardCurrency: String?)
    case centsPerLitre   // informational only; never scored
}

extension Earn: Codable {
    private enum CodingKeys: String, CodingKey { case type, pointsPerUnit, rate, rewardCurrency }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "points":
            self = .points(pointsPerUnit: try c.decode(Double.self, forKey: .pointsPerUnit))
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
            try c.encode(p, forKey: .pointsPerUnit)
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
    @available(*, deprecated, message: "Use capIds instead")
    public var capId: String?
    public var capIds: [String]?
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

    public var effectiveCapIds: [String] {
        if let capIds = capIds { return capIds }
        if let capId = capId { return [capId] }
        return []
    }

    public init(ruleId: String, status: RuleStatus, effectiveFrom: String? = nil,
                effectiveTo: String? = nil, sourceType: SourceType, earn: Earn,
                predicate: Predicate, capId: String? = nil, capIds: [String]? = nil, ownerConditions: [String]? = nil,
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
        self.capIds = capIds
        self.ownerConditions = ownerConditions
        self.scoredInV1 = scoredInV1
        self.requires = requires
        self.outOfScope = outOfScope
    }
}

/// `spendCad` renamed to `spendNative` in catalogue 2.0: the amount is measured in the CARD's own
/// `billingCurrency` (CAD for a CAD-billing card, USD for a USD-billing card), not CAD
/// unconditionally. `spendUsdEquivalent` is unchanged and stays meaningful even for a non-USD-
/// billing card whose cap is stated in a third reference currency (Crypto.com's CAD-billing card
/// with a USD-denominated cap is exactly why the two measures stay distinct).
public enum CapMeasure: String, Codable, Sendable { case spendNative, spendUsdEquivalent }
/// `calendarQuarter` added for US rotating-category cards (e.g. 5x groceries up to $1,500/quarter)
/// — a shape this catalogue could not previously express at all. Gated the same way as the other
/// periods: `EngineCapability.capCalendarQuarter`.
public enum CapPeriod: String, Codable, Sendable { case calendarMonth, calendarQuarter, calendarYear, accountYear, statementYear }

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
    /// `annualCad: Double?` renamed to `annual: Money?` in catalogue 2.0 — a US card's fee is
    /// stated in USD, never converted to CAD at authoring time (Phase 1: never convert a USD
    /// amount into a CAD-labelled field merely to satisfy the schema). Not read by `Scorer` at
    /// all (fee has no bearing on a single checkout pick); `PortfolioAnalyzer`/`AcquisitionAnalyzer`
    /// convert it to the engine's CAD reporting currency via `ReportingCurrency.toReporting`.
    public var annual: Money?
    public var monthly: Money?
    public var billing: String?
    public var waiver: String?

    public init(annual: Money? = nil, monthly: Money? = nil, billing: String? = nil,
                waiver: String? = nil) {
        self.annual = annual
        self.monthly = monthly
        self.billing = billing
        self.waiver = waiver
    }
}

public struct Program: Codable, Equatable, Sendable {
    public var programId: String
    public var unit: String

    public init(programId: String, unit: String) {
        self.programId = programId
        self.unit = unit
    }
}

public enum CreditScheduleBasis: String, Codable, Equatable, Sendable {
    case calendar, accountAnniversary, rolling
}

public enum CreditScheduleUnit: String, Codable, Equatable, Sendable {
    case month, quarter, halfYear, year
}

/// A credit's reset rule. This is deliberately separate from `CapPeriod`: statement-credit
/// eligibility includes rolling 48/54-month reimbursements and account anniversaries, neither of
/// which is an earn-cap window. `intervalMonths` is required by the contract for anniversary and
/// rolling schedules; `interval` defaults to one for calendar schedules.
public struct CreditSchedule: Codable, Equatable, Sendable {
    public var basis: CreditScheduleBasis
    public var unit: CreditScheduleUnit?
    public var interval: Int?
    public var intervalMonths: Int?
    public var resetTimeZone: String?

    public init(basis: CreditScheduleBasis, unit: CreditScheduleUnit? = nil,
                interval: Int? = nil, intervalMonths: Int? = nil,
                resetTimeZone: String? = nil) {
        self.basis = basis
        self.unit = unit
        self.interval = interval
        self.intervalMonths = intervalMonths
        self.resetTimeZone = resetTimeZone
    }
}

public enum CreditRedemptionMethod: String, Codable, Equatable, Sendable {
    case statementCredit, portalCredit, accountCredit, reimbursement
}

public enum CreditEnrollmentChannel: String, Codable, Equatable, Sendable {
    case issuerPortal, issuerApp, partnerAccount, phone
}

public struct CreditEnrollment: Codable, Equatable, Sendable {
    public var required: Bool
    public var channel: CreditEnrollmentChannel?
    public var url: String?

    public init(required: Bool, channel: CreditEnrollmentChannel? = nil, url: String? = nil) {
        self.required = required
        self.channel = channel
        self.url = url
    }
}

public enum CreditCoverageStatus: String, Codable, Equatable, Sendable {
    case complete, partial, unknown
}

public struct CreditCoverage: Codable, Equatable, Sendable {
    public var status: CreditCoverageStatus
    public var lastReviewedAt: String

    public init(status: CreditCoverageStatus, lastReviewedAt: String) {
        self.status = status
        self.lastReviewedAt = lastReviewedAt
    }
}

/// A standard recurring monetary credit. `value` is the issuer maximum PER WINDOW, not an
/// annualized marketing total and not a forecast of owner use. Targeted offers and non-monetary
/// certificates do not belong here. Owner consumption/posting state lives in `OwnerState`.
public struct CardCredit: Codable, Equatable, Identifiable, Sendable {
    public var creditId: String
    public var label: String
    public var value: Money
    /// Legacy cadence. New and corrected records use `schedule`.
    public var period: CapPeriod?
    public var schedule: CreditSchedule?
    public var redemptionMethod: CreditRedemptionMethod?
    public var purchasePredicate: Predicate?
    public var minimumTransaction: Money?
    public var allowsPartialUse: Bool?
    public var enrollment: CreditEnrollment?
    public var effectiveFrom: String?
    public var effectiveTo: String?
    public var sourceType: SourceType
    public var lastVerifiedAt: String
    public var sources: [String]?

    public var id: String { creditId }

    public init(creditId: String, label: String, value: Money, period: CapPeriod? = nil,
                schedule: CreditSchedule? = nil,
                redemptionMethod: CreditRedemptionMethod? = nil,
                purchasePredicate: Predicate? = nil, minimumTransaction: Money? = nil,
                allowsPartialUse: Bool? = nil, enrollment: CreditEnrollment? = nil,
                effectiveFrom: String? = nil, effectiveTo: String? = nil,
                sourceType: SourceType, lastVerifiedAt: String, sources: [String]? = nil) {
        self.creditId = creditId
        self.label = label
        self.value = value
        self.period = period
        self.schedule = schedule
        self.redemptionMethod = redemptionMethod
        self.purchasePredicate = purchasePredicate
        self.minimumTransaction = minimumTransaction
        self.allowsPartialUse = allowsPartialUse
        self.enrollment = enrollment
        self.effectiveFrom = effectiveFrom
        self.effectiveTo = effectiveTo
        self.sourceType = sourceType
        self.lastVerifiedAt = lastVerifiedAt
        self.sources = sources
    }

    public var effectiveSchedule: CreditSchedule? {
        if let schedule { return schedule }
        switch period {
        case .calendarMonth: return CreditSchedule(basis: .calendar, unit: .month)
        case .calendarQuarter: return CreditSchedule(basis: .calendar, unit: .quarter)
        case .calendarYear: return CreditSchedule(basis: .calendar, unit: .year)
        case .accountYear: return CreditSchedule(basis: .accountAnniversary, intervalMonths: 12)
        case .statementYear: return CreditSchedule(basis: .accountAnniversary, intervalMonths: 12)
        case nil: return nil
        }
    }
}

/// Which market(s) a resident must be in to hold a card. Absent on a `CardProduct` means "assume
/// `[market]`" — `AcquisitionAnalyzer.eligibleMarkets` falls back to the card's own `market` when
/// this is nil. Deliberately thin: only `residency` gates anything today; the rest are
/// documentation-only capture points for a later pass, matching the catalogue's existing rule for
/// `CardCredit`/`FxRule` provenance — represent unknown as absent, never invent a value.
public struct Eligibility: Codable, Equatable, Sendable {
    public var residency: [Market]?

    public init(residency: [Market]? = nil) {
        self.residency = residency
    }
}

/// `published` (absent decodes as this — backward compatible with every pre-2.0 card) is a
/// checkout-eligible product that has cleared this catalogue's issuer-confirmed sourcing bar (D3).
/// `draft` is a research-grade record that has NOT: `RecommendationEngine.recommend` and
/// `PortfolioAnalyzer` refuse to consider a draft card even if it somehow ended up in
/// `ownedCardIds`, so a draft record can never produce a checkout pick or a keep/cancel number.
/// `AcquisitionAnalyzer` and compare/browse surfaces MAY show draft cards, clearly labelled —
/// comparing an unowned candidate is lower-stakes than telling someone what to tap. Promoting
/// draft → published is a data edit (re-verify against the issuer, flip the field), never an
/// engine change.
public enum CardStatus: String, Codable, Equatable, Sendable { case published, draft }

/// Product availability is independent of research quality. A published card can later be
/// withdrawn; keeping the two axes separate preserves both historical scoring and draft gating.
/// Absent means active for catalogues written before tombstoning existed.
public enum ProductLifecycleStatus: String, Codable, Equatable, Sendable { case active, withdrawn }

public struct CardProduct: Codable, Equatable, Identifiable, Sendable {
    public var cardId: String
    public var officialName: String
    public var issuer: String
    /// The country this product is sold in. See `Eligibility.residency` for the (rare) card sold
    /// in more than one market.
    public var market: Market
    /// The currency a purchase is measured in for THIS card's own earn rules and caps — see
    /// `Earn.points(pointsPerUnit:)` and `CapMeasure.spendNative`. Independent of `market`: a
    /// CA-market card could in principle bill in USD (none do today), which is why this is its
    /// own field rather than derived from `market`.
    public var billingCurrency: Currency
    public var network: Network
    /// Absent for every open-loop card, which is all of them today — so this decodes a pre-2.5
    /// catalogue unchanged, exactly as `credits` and `lifecycleStatus` do. `Scorer` switches on
    /// it: `openLoop` guards on `network`, `closedLoop` guards on `purchase.merchantBrand`.
    public var acceptance: Acceptance?
    public var kind: CardKind
    /// Absent decodes as `.published` — see `CardStatus`.
    public var status: CardStatus?
    public var eligibility: Eligibility?
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
    /// Whether issuer materials were reviewed comprehensively for recurring monetary credits.
    /// Without `.complete`, an absent `credits` array means unreviewed rather than "none".
    public var creditCoverage: CreditCoverage?
    /// Set when the issuer has discontinued the product. The card is never deleted from the
    /// catalogue and its id is never reused: ledgers, prediction rows, and other repos' vendored
    /// copies all key on that id, and an id that stops resolving turns history into orphans.
    public var lifecycleStatus: ProductLifecycleStatus?
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
        guard lifecycleStatus == .withdrawn else { return true }
        guard let effectiveTo else { return false }
        return asOf <= effectiveTo
    }

    /// Scorable right now (D3's sourcing bar cleared) — `.published`, or absent, which decodes the
    /// same way. Named for the same "resolve, don't guess" spirit as `RuleMatcher.isLive`.
    public var isPublished: Bool { (status ?? .published) == .published }

    public init(cardId: String, officialName: String, issuer: String, market: Market = .ca,
                billingCurrency: Currency = .cad, network: Network,
                acceptance: Acceptance? = nil, kind: CardKind,
                status: CardStatus? = nil, eligibility: Eligibility? = nil, fee: Fee,
                program: Program, fxRules: [FxRule], earnRules: [EarnRule], caps: [Cap],
                perTransactionRewardVisibility: String, lastVerifiedAt: String,
                credits: [CardCredit]? = nil,
                creditCoverage: CreditCoverage? = nil,
                lifecycleStatus: ProductLifecycleStatus? = nil, effectiveTo: String? = nil) {
        self.cardId = cardId
        self.officialName = officialName
        self.issuer = issuer
        self.market = market
        self.billingCurrency = billingCurrency
        self.network = network
        self.acceptance = acceptance
        self.kind = kind
        self.status = status
        self.eligibility = eligibility
        self.fee = fee
        self.program = program
        self.fxRules = fxRules
        self.earnRules = earnRules
        self.caps = caps
        self.perTransactionRewardVisibility = perTransactionRewardVisibility
        self.lastVerifiedAt = lastVerifiedAt
        self.credits = credits
        self.creditCoverage = creditCoverage
        self.lifecycleStatus = lifecycleStatus
        self.effectiveTo = effectiveTo
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
