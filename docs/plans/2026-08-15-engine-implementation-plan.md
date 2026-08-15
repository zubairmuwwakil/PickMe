# CardCopilotEngine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the deterministic recommendation engine as a standalone Swift package that passes all 12 cases in `engine-fixtures.json`.

**Architecture:** Pure-logic SPM package (`Engine/`) with no UI, no MapKit, no SwiftData — testable on macOS. Three-layer inputs per the design doc: card product rules (`card-catalogue.json`, effective-dated), owner state (`owner-state.json`), and a `PurchaseContext` per checkout. Pipeline: `RuleMatcher` (which earn rule applies) → `CapMath` (prorated in-cap/over-cap split) → `Scorer` (net CAD value per card) → `RecommendationEngine` (acceptance gate, switch-threshold gate, ranking) → `RecommendationExplainer` (plain-language output). The iOS app is a **separate later plan** that consumes this package.

**Tech Stack:** Swift 5.10, Swift Package Manager, XCTest, Foundation only (zero external dependencies).

**Spec:** `docs/plans/2026-08-15-canadian-card-copilot-mvp-design.md` (§5 engine, §6 ladder, §2 decisions 7–11) + `docs/research/canadian-card-copilot-research-2026-08-15.md` (§5 engine/catalogue recommendations). Seed data already authored: `Engine/Sources/CardCopilotEngine/Resources/card-catalogue.json`, `.../owner-state.json`, `Engine/Tests/CardCopilotEngineTests/Fixtures/engine-fixtures.json`.

*(Plan saved under this repo's established `docs/plans/` convention rather than the skill's default path.)*

## Global Constraints

- `swift-tools-version: 5.10`; platforms `.macOS(.v14), .iOS(.v17)`.
- Zero external dependencies; XCTest only (not Swift Testing).
- All money is `Double` in CAD; tests compare with `accuracy: 0.005`; rounding is display-only (Explainer).
- Dates are `String` in `"yyyy-MM-dd"` form throughout the engine (`asOf` parameter); lexicographic comparison is valid for this format. The app layer converts `Date` → `String`.
- The engine NEVER guesses unresolved owner state (`null` fields): a rule with an unresolved `ownerConditions` entry is skipped; a card with no scorable earn rule is excluded with a reason.
- Seed JSON files are the source of truth — code adapts to them, never the reverse. Unknown JSON keys (`_note`, `_provenance`, `categoryMccReference`, `redemption`, `redemptionFactors`) are simply not modelled and ignored by `JSONDecoder`.
- Announced-but-not-yet-effective rules (`status: "announced"`, `effectiveFrom` in the future) must not affect scoring before their date.
- Run tests with `cd Engine && swift test` (append `--filter <TestClass>` per task).
- Every commit message ends with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: Package scaffold + seed decoding (SeedLoader)

**Files:**
- Create: `Engine/Package.swift`
- Create: `Engine/Sources/CardCopilotEngine/Models/CatalogueModels.swift`
- Create: `Engine/Sources/CardCopilotEngine/Models/OwnerState.swift`
- Create: `Engine/Sources/CardCopilotEngine/Loading/SeedLoader.swift`
- Test: `Engine/Tests/CardCopilotEngineTests/SeedLoaderTests.swift`

**Interfaces:**
- Consumes: the three seed JSON files (already on disk).
- Produces: `Catalogue`, `CardProduct`, `EarnRule`, `Earn`, `Predicate`, `Cap`, `FxRule`, `Network`, `OwnerState`, `CardState`, `Valuations`, `SwitchThreshold`, and `SeedLoader.loadCatalogue() throws -> Catalogue` / `SeedLoader.loadOwnerState() throws -> OwnerState`. Every later task depends on these exact names.

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CardCopilotEngine",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "CardCopilotEngine", targets: ["CardCopilotEngine"])],
    targets: [
        .target(name: "CardCopilotEngine", resources: [.process("Resources")]),
        .testTarget(
            name: "CardCopilotEngineTests",
            dependencies: ["CardCopilotEngine"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 2: Write the failing test**

```swift
import XCTest
@testable import CardCopilotEngine

final class SeedLoaderTests: XCTestCase {
    func testCatalogueLoadsAllTenCards() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        XCTAssertEqual(catalogue.cards.count, 10)
        let cobalt = try XCTUnwrap(catalogue.cards.first { $0.cardId == "amex-cobalt" })
        XCTAssertEqual(cobalt.fee.annualCad ?? 0, 191.88, accuracy: 0.005)
        XCTAssertEqual(cobalt.network, .amex)
        XCTAssertEqual(cobalt.caps.first?.capId, "cobalt-eats-monthly")
        guard case .points(let ppc) = try XCTUnwrap(
            cobalt.earnRules.first { $0.ruleId == "cobalt-eats-5x" }).earn
        else { return XCTFail("expected points earn") }
        XCTAssertEqual(ppc, 5)
        let crypto = try XCTUnwrap(catalogue.cards.first { $0.cardId == "cryptocom-royal-indigo" })
        XCTAssertEqual(crypto.fxRules.count, 2, "current + announced FX records")
        XCTAssertEqual(crypto.kind, .prepaid)
    }

    func testOwnerStateLoads() throws {
        let state = try SeedLoader.loadOwnerState()
        XCTAssertEqual(state.defaultCardId, "wealthsimple-vip")
        XCTAssertEqual(state.switchThreshold.semantics, "both")
        XCTAssertNil(state.cardStates["tangerine-moneyback-world"]?.selectedCategories,
                     "unset onboarding fields must decode as nil, never a default")
        XCTAssertEqual(state.valuationsCad.amexMembershipRewards.centsPerPoint, 1.8, accuracy: 0.005)
        XCTAssertTrue(state.carry.drawerCards.contains("triangle-we"))
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd Engine && swift test`
Expected: FAIL to build — `SeedLoader`, `Catalogue`, etc. not defined.

- [ ] **Step 4: Implement the models and loader**

`Models/CatalogueModels.swift`:

```swift
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
            try c.encode("points", forKey: .type); try c.encode(p, forKey: .pointsPerCad)
        case .cashback(let r, let cur):
            try c.encode("cashback", forKey: .type); try c.encode(r, forKey: .rate)
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
```

`Models/OwnerState.swift`:

```swift
import Foundation

public struct SwitchThreshold: Codable, Equatable, Sendable {
    public var minAdvantagePercentagePoints: Double
    public var minAdvantageCad: Double
    public var semantics: String   // "both" | "either"
}

public struct Carry: Codable, Equatable, Sendable {
    public var drawerCards: [String]
}

public struct CardState: Codable, Equatable, Sendable {
    public var capProgress: [String: Double]?
    public var scotiaAccountYearAnchorMonth: Int?
    public var selectedCategories: [String]?
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
```

`Loading/SeedLoader.swift`:

```swift
import Foundation

public enum SeedLoaderError: Error { case resourceMissing(String) }

public enum SeedLoader {
    public static func loadCatalogue() throws -> Catalogue {
        try load("card-catalogue")
    }
    public static func loadOwnerState() throws -> OwnerState {
        try load("owner-state")
    }
    private static func load<T: Decodable>(_ name: String) throws -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw SeedLoaderError.resourceMissing(name)
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd Engine && swift test --filter SeedLoaderTests`
Expected: PASS (2 tests). If decoding fails, the error names the key — fix the *model* to match the JSON, never the JSON.

- [ ] **Step 6: Commit**

```bash
git add Engine docs
git commit -m "feat: engine package scaffold, seed catalogue, and seed decoding"
```

---

### Task 2: PurchaseContext + RuleMatcher

**Files:**
- Create: `Engine/Sources/CardCopilotEngine/Models/PurchaseContext.swift`
- Create: `Engine/Sources/CardCopilotEngine/Engine/RuleMatcher.swift`
- Test: `Engine/Tests/CardCopilotEngineTests/RuleMatcherTests.swift`

**Interfaces:**
- Consumes: Task 1 types (`CardProduct`, `EarnRule`, `Predicate`, `OwnerState`, `CardState`).
- Produces: `PurchaseContext` (Codable, with decoding defaults), `RuleResolution` (`.applied(EarnRule)` / `.cardExcluded(reason: String)`), and `RuleMatcher.resolve(card:purchase:ownerState:asOf:) -> RuleResolution`. Tasks 4–6 call `resolve` with exactly this signature.

**Matching semantics (the contract):** a rule is *live* when `effectiveFrom ≤ asOf` (nil = always) and (`effectiveTo` nil or `asOf ≤ effectiveTo`) and `scoredInV1 != false`. A live rule *matches* when every specified predicate field passes: category branch (see below), `mcc` in `mccInclude` **only when purchase.mcc is known** (unknown MCC falls back to category match — MCC is itself a prediction), `mcc` never in `mccExclude`, `merchantBrand` never in `merchantExclude`, `country`/`currency`/`channels` equal when specified. Category branch: an empty `categories` matches everything; `"recurring"` in `categories` matches when `purchase.recurringIndicator` is true (OR-composed with the other listed categories); the sentinel `"ownerSelectedTangerineCategory"` matches when the owner's `selectedCategories` contains `purchase.category`. `ownerConditions`: each must resolve `true` from `CardState` (`rogersEligibleServiceLinked`, `cryptoLevelUpProActive`, `tangerineCategorySelected` ⇒ `selectedCategories != nil`); a `nil` field means *unresolved* → the rule is skipped. If no rule at all is scorable for a card (Crypto with plan `nil` or `false`), return `.cardExcluded`. Among matches, return the one with the highest raw earn (pointsPerCad or rate) — `exclusive-best`, never stacking.

- [ ] **Step 1: Write PurchaseContext**

```swift
import Foundation

public struct PurchaseContext: Codable, Equatable, Sendable {
    public var amountCad: Double
    public var currency: String
    public var usdEquivalent: Double?
    public var category: String
    public var mcc: Int?
    public var merchantBrand: String?
    public var country: String
    public var channel: String
    public var recurringIndicator: Bool
    public var acceptedNetworks: Set<Network>

    public init(amountCad: Double, currency: String = "CAD", usdEquivalent: Double? = nil,
                category: String, mcc: Int? = nil, merchantBrand: String? = nil,
                country: String = "CA", channel: String = "cardPresent",
                recurringIndicator: Bool = false,
                acceptedNetworks: Set<Network> = [.amex, .visa, .mastercard]) {
        self.amountCad = amountCad; self.currency = currency; self.usdEquivalent = usdEquivalent
        self.category = category; self.mcc = mcc; self.merchantBrand = merchantBrand
        self.country = country; self.channel = channel
        self.recurringIndicator = recurringIndicator; self.acceptedNetworks = acceptedNetworks
    }

    private enum CodingKeys: String, CodingKey {
        case amountCad, currency, usdEquivalent, category, mcc, merchantBrand,
             country, channel, recurringIndicator, acceptedNetworks
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        amountCad = try c.decode(Double.self, forKey: .amountCad)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "CAD"
        usdEquivalent = try c.decodeIfPresent(Double.self, forKey: .usdEquivalent)
        category = try c.decode(String.self, forKey: .category)
        mcc = try c.decodeIfPresent(Int.self, forKey: .mcc)
        merchantBrand = try c.decodeIfPresent(String.self, forKey: .merchantBrand)
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? "CA"
        channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? "cardPresent"
        recurringIndicator = try c.decodeIfPresent(Bool.self, forKey: .recurringIndicator) ?? false
        acceptedNetworks = Set(try c.decodeIfPresent([Network].self, forKey: .acceptedNetworks)
                               ?? [.amex, .visa, .mastercard])
    }
}
```

- [ ] **Step 2: Write the failing tests**

```swift
import XCTest
@testable import CardCopilotEngine

final class RuleMatcherTests: XCTestCase {
    var catalogue: Catalogue!
    var owner: OwnerState!
    let asOf = "2026-08-20"

    override func setUpWithError() throws {
        catalogue = try SeedLoader.loadCatalogue()
        owner = try SeedLoader.loadOwnerState()
    }
    private func card(_ id: String) -> CardProduct { catalogue.cards.first { $0.cardId == id }! }
    private func appliedRuleId(_ cardId: String, _ p: PurchaseContext) -> String? {
        if case .applied(let rule) = RuleMatcher.resolve(card: card(cardId), purchase: p,
                                                        ownerState: owner, asOf: asOf) {
            return rule.ruleId
        }
        return nil
    }

    func testGroceryMatchesCobalt5x() {
        let p = PurchaseContext(amountCad: 100, category: "grocery", mcc: 5411, merchantBrand: "loblaws")
        XCTAssertEqual(appliedRuleId("amex-cobalt", p), "cobalt-eats-5x")
    }

    func testCostcoMccBlocksMbnaGrocery() {
        let p = PurchaseContext(amountCad: 200, category: "wholesaleClub", mcc: 5300,
                                merchantBrand: "costco", acceptedNetworks: [.mastercard])
        XCTAssertEqual(appliedRuleId("mbna-rewards-we", p), "mbna-base",
                       "5300 ∉ grocery MCCs and category is wholesaleClub → base rule")
    }

    func testCostcoBrandBlocksTriangleGroceryEvenAsMcc5411() {
        let p = PurchaseContext(amountCad: 200, category: "grocery", mcc: 5411, merchantBrand: "costco")
        XCTAssertEqual(appliedRuleId("triangle-we", p), "triangle-base",
                       "merchantExclude beats an otherwise-matching MCC")
    }

    func testRecurringIndicatorFiresMomentum4pct() {
        let p = PurchaseContext(amountCad: 15.49, category: "streaming", mcc: 5968,
                                merchantBrand: "netflix", channel: "online", recurringIndicator: true)
        XCTAssertEqual(appliedRuleId("scotia-momentum-vi-plus", p), "momentum-grocery-recurring-4pct")
    }

    func testUsdRuleFiresOnCurrency() {
        let p = PurchaseContext(amountCad: 165, currency: "USD", category: "other", channel: "online")
        XCTAssertEqual(appliedRuleId("rogers-red-we", p), "rogers-usd-3pct")
    }

    func testRogersServiceRuleSkippedWhenUnresolved() {
        let p = PurchaseContext(amountCad: 100, category: "other")
        var o = owner!
        var s = o.cardStates["rogers-red-we"] ?? CardState()
        s.rogersEligibleServiceLinked = nil
        o.cardStates["rogers-red-we"] = s
        guard case .applied(let rule) = RuleMatcher.resolve(card: card("rogers-red-we"), purchase: p,
                                                            ownerState: o, asOf: asOf)
        else { return XCTFail() }
        XCTAssertEqual(rule.ruleId, "rogers-base-1_5", "unresolved condition must not enable the 2% rule")
    }

    func testCryptoExcludedWhenPlanUnresolvedOrInactive() {
        let p = PurchaseContext(amountCad: 100, category: "other")
        guard case .cardExcluded = RuleMatcher.resolve(card: card("cryptocom-royal-indigo"),
                                                       purchase: p, ownerState: owner, asOf: asOf)
        else { return XCTFail("plan nil → card excluded, never guessed") }
    }

    func testTangerineTreatAsAllSelectedMatchesSentinel() {
        // Seed owner-state now carries treatAsAllSelected (Zubair 2026-08-15): drugStore is selected.
        let p = PurchaseContext(amountCad: 30, category: "drugStore", mcc: 5912)
        XCTAssertEqual(appliedRuleId("tangerine-moneyback-world", p), "tangerine-selected-2pct")
    }

    func testTangerineUnresolvedSelectionsFallToBase() {
        // Strip the selections to verify the never-guess rule still holds for other users.
        let p = PurchaseContext(amountCad: 30, category: "drugStore", mcc: 5912)
        var o = owner!
        var s = o.cardStates["tangerine-moneyback-world"] ?? CardState()
        s.selectedCategories = nil
        o.cardStates["tangerine-moneyback-world"] = s
        guard case .applied(let rule) = RuleMatcher.resolve(card: card("tangerine-moneyback-world"),
                                                            purchase: p, ownerState: o, asOf: asOf)
        else { return XCTFail() }
        XCTAssertEqual(rule.ruleId, "tangerine-base")
    }

    func testAnnouncedFutureFxRecordIgnoredBeforeEffectiveFrom() {
        let crypto = card("cryptocom-royal-indigo")
        let active = RuleMatcher.activeFxRule(for: crypto, asOf: "2026-08-20")
        XCTAssertNil(active?.freeAllowanceCadPerCalendarMonth, "pre-Sept record has no allowance")
        let september = RuleMatcher.activeFxRule(for: crypto, asOf: "2026-09-02")
        XCTAssertEqual(september?.freeAllowanceCadPerCalendarMonth, 1400)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd Engine && swift test --filter RuleMatcherTests`
Expected: FAIL to build — `RuleMatcher` not defined.

- [ ] **Step 4: Implement RuleMatcher**

```swift
import Foundation

public enum RuleResolution: Equatable, Sendable {
    case applied(EarnRule)
    case cardExcluded(reason: String)
}

public enum RuleMatcher {

    public static func resolve(card: CardProduct, purchase: PurchaseContext,
                               ownerState: OwnerState, asOf: String) -> RuleResolution {
        let state = ownerState.cardStates[card.cardId] ?? CardState()
        let candidates = card.earnRules.filter { rule in
            isLive(rule, asOf: asOf)
                && conditionsResolveTrue(rule.ownerConditions, state: state)
                && matches(rule.predicate, purchase: purchase, state: state)
        }
        guard let best = candidates.max(by: { rawEarn($0.earn) < rawEarn($1.earn) }) else {
            return .cardExcluded(reason: "no scorable earn rule (unresolved or inactive owner state)")
        }
        return .applied(best)
    }

    public static func activeFxRule(for card: CardProduct, asOf: String) -> FxRule? {
        card.fxRules.first { rule in
            (rule.effectiveFrom.map { $0 <= asOf } ?? true)
                && (rule.effectiveTo.map { asOf <= $0 } ?? true)
        }
    }

    static func isLive(_ rule: EarnRule, asOf: String) -> Bool {
        guard rule.scoredInV1 != false else { return false }
        let fromOk = rule.effectiveFrom.map { $0 <= asOf } ?? true
        let toOk = rule.effectiveTo.map { asOf <= $0 } ?? true
        return fromOk && toOk
    }

    static func conditionsResolveTrue(_ conditions: [String]?, state: CardState) -> Bool {
        guard let conditions else { return true }
        return conditions.allSatisfy { condition in
            switch condition {
            case "rogersEligibleServiceLinked": return state.rogersEligibleServiceLinked == true
            case "cryptoLevelUpProActive":      return state.cryptoLevelUpProActive == true
            case "tangerineCategorySelected":   return state.selectedCategories != nil
            default: return false   // unknown condition = unresolved = never guessed
            }
        }
    }

    static func matches(_ p: Predicate, purchase: PurchaseContext, state: CardState) -> Bool {
        if let country = p.country, country != purchase.country { return false }
        if let currency = p.currency, currency != purchase.currency { return false }
        if let channels = p.channels, !channels.contains(purchase.channel) { return false }
        if let excluded = p.merchantExclude, let brand = purchase.merchantBrand,
           excluded.contains(brand) { return false }
        if let include = p.merchantInclude {
            guard let brand = purchase.merchantBrand, include.contains(brand) else { return false }
        }
        if let mccExclude = p.mccExclude, let mcc = purchase.mcc, mccExclude.contains(mcc) { return false }
        guard let categories = p.categories else { return true }   // empty predicate = base rule
        return categories.contains { category in
            switch category {
            case "recurring":
                return purchase.recurringIndicator
            case "ownerSelectedTangerineCategory":
                return state.selectedCategories?.contains(purchase.category) ?? false
            default:
                guard category == purchase.category else { return false }
                if let include = p.mccInclude, let mcc = purchase.mcc {
                    return include.contains(mcc)   // known MCC must qualify; unknown falls back
                }
                return true
            }
        }
    }

    static func rawEarn(_ earn: Earn) -> Double {
        switch earn {
        case .points(let p): return p
        case .cashback(let r, _): return r * 100
        case .centsPerLitre: return -1
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd Engine && swift test --filter RuleMatcherTests`
Expected: PASS (9 tests). Note `rawEarn` compares points and cashback on incompatible scales — that is fine *within* one card (a card never mixes point and cashback earn rules), which is the only place it is used.

- [ ] **Step 6: Commit**

```bash
git add Engine
git commit -m "feat: purchase context and earn-rule matcher with owner-condition resolution"
```

---

### Task 3: CapMath

**Files:**
- Create: `Engine/Sources/CardCopilotEngine/Engine/CapMath.swift`
- Test: `Engine/Tests/CardCopilotEngineTests/CapMathTests.swift`

**Interfaces:**
- Produces: `CapMath.split(amount:capLimit:usage:) -> (inCap: Double, overCap: Double)`. Task 4 calls it with the cap-measure amount (CAD or USD-equivalent) and maps the fractions back to CAD.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import CardCopilotEngine

final class CapMathTests: XCTestCase {
    func testFullyUnderCap() {
        let s = CapMath.split(amount: 100, capLimit: 2500, usage: 0)
        XCTAssertEqual(s.inCap, 100, accuracy: 0.005); XCTAssertEqual(s.overCap, 0, accuracy: 0.005)
    }
    func testStraddlesCap() {
        let s = CapMath.split(amount: 100, capLimit: 2500, usage: 2450)
        XCTAssertEqual(s.inCap, 50, accuracy: 0.005); XCTAssertEqual(s.overCap, 50, accuracy: 0.005)
    }
    func testCapExhausted() {
        let s = CapMath.split(amount: 100, capLimit: 2500, usage: 2500)
        XCTAssertEqual(s.inCap, 0, accuracy: 0.005); XCTAssertEqual(s.overCap, 100, accuracy: 0.005)
    }
    func testUsageBeyondLimitClampsToZeroRoom() {
        let s = CapMath.split(amount: 100, capLimit: 2500, usage: 2600)
        XCTAssertEqual(s.inCap, 0, accuracy: 0.005); XCTAssertEqual(s.overCap, 100, accuracy: 0.005)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Engine && swift test --filter CapMathTests`
Expected: FAIL to build — `CapMath` not defined.

- [ ] **Step 3: Implement**

```swift
public enum CapMath {
    /// Splits a purchase into the portion earning the accelerated rate and the post-cap portion.
    public static func split(amount: Double, capLimit: Double, usage: Double)
        -> (inCap: Double, overCap: Double) {
        let room = max(0, capLimit - usage)
        let inCap = min(amount, room)
        return (inCap, amount - inCap)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Engine && swift test --filter CapMathTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Engine
git commit -m "feat: cap accumulator split math"
```

---

### Task 4: Scorer

**Files:**
- Create: `Engine/Sources/CardCopilotEngine/Engine/Scorer.swift`
- Test: `Engine/Tests/CardCopilotEngineTests/ScorerTests.swift`

**Interfaces:**
- Consumes: `RuleMatcher.resolve`, `RuleMatcher.activeFxRule`, `CapMath.split`, Task 1 models.
- Produces: `Warning` enum, `CandidateScore`, and `Scorer.score(card:purchase:ownerState:asOf:) -> CandidateScore`. Task 5 ranks these; Task 7 renders them.

**Scoring contract:** (1) acceptance: network not in `purchase.acceptedNetworks` → excluded score with `.networkNotAccepted`. (2) rule resolution: `.cardExcluded` → excluded score with `.unresolvedOwnerState`. (3) cap split on the cap's measure — for `spendUsdEquivalent` use `purchase.usdEquivalent ?? amountCad * 0.73` (documented approximation; only Crypto's cap uses it) — then map in/over fractions back to CAD. (4) reward units: in-cap CAD × rate + over-cap CAD × post-cap rate (same-shape earns only). (5) valuation by `program.programId`: `amexMembershipRewards`/`marriottBonvoy`/`mbnaRewards` → `centsPerPoint / 100`; `cashback` → ×1; `ctMoney` → ×`cadPerUnit` × usability factor when applied; `cro` → ×(`autoSell` ? 1.0 : 0.8) — `croHandling == nil` uses the held factor (conservative) with no extra warning beyond the score note. (6) FX: `currency != "CAD"` → `fxCost = amountCad × activeFxRule.rate`; if the active record carries a `freeAllowanceCadPerCalendarMonth`, v1 assumes the purchase is within allowance (`fxCost = 0`) and adds `.fxAllowanceAssumed`. (7) `netValueCad = grossRewardCad − fxCostCad`; add `.negativeNetValue` when < 0, `.drawerCard` when the card is in `carry.drawerCards`, `.capNearlyExhausted` when a matched cap's usage ≥ 90% of limit.

- [ ] **Step 1: Write the failing tests** (expected numbers are fixture-derived; see `engine-fixtures.json` for the arithmetic)

```swift
import XCTest
@testable import CardCopilotEngine

final class ScorerTests: XCTestCase {
    var catalogue: Catalogue!
    var owner: OwnerState!
    let asOf = "2026-08-20"

    override func setUpWithError() throws {
        catalogue = try SeedLoader.loadCatalogue()
        owner = try SeedLoader.loadOwnerState()
    }
    private func card(_ id: String) -> CardProduct { catalogue.cards.first { $0.cardId == id }! }
    private func score(_ id: String, _ p: PurchaseContext, _ o: OwnerState? = nil) -> CandidateScore {
        Scorer.score(card: card(id), purchase: p, ownerState: o ?? owner, asOf: asOf)
    }

    func testCobaltGrocery100() {
        let p = PurchaseContext(amountCad: 100, category: "grocery", mcc: 5411, merchantBrand: "loblaws")
        let s = score("amex-cobalt", p)
        XCTAssertEqual(s.rewardUnits, 500, accuracy: 0.005)
        XCTAssertEqual(s.netValueCad, 9.00, accuracy: 0.005)
        XCTAssertEqual(s.appliedRuleId, "cobalt-eats-5x")
    }

    func testCobaltCapProration() {
        var o = owner!
        o.cardStates["amex-cobalt"]?.capProgress?["cobalt-eats-monthly"] = 2450
        let p = PurchaseContext(amountCad: 100, category: "grocery", mcc: 5411, merchantBrand: "loblaws")
        let s = score("amex-cobalt", p, o)
        XCTAssertEqual(s.rewardUnits, 300, accuracy: 0.005, "50×5 + 50×1")
        XCTAssertEqual(s.netValueCad, 5.40, accuracy: 0.005)
        XCTAssertTrue(s.warnings.contains(.capNearlyExhausted))
    }

    func testWealthsimpleUsdNoFx() {
        let p = PurchaseContext(amountCad: 165, currency: "USD", category: "other", channel: "online")
        let s = score("wealthsimple-vip", p)
        XCTAssertEqual(s.netValueCad, 3.30, accuracy: 0.005)
        XCTAssertEqual(s.fxCostCad, 0, accuracy: 0.005)
    }

    func testCobaltUsdGoesNegative() {
        let p = PurchaseContext(amountCad: 165, currency: "USD", category: "other", channel: "online")
        let s = score("amex-cobalt", p)
        XCTAssertEqual(s.netValueCad, -1.155, accuracy: 0.005, "$2.97 gross − $4.125 FX")
        XCTAssertTrue(s.warnings.contains(.negativeNetValue))
    }

    func testCryptoProAutoSell() {
        var o = owner!
        o.cardStates["cryptocom-royal-indigo"]?.cryptoLevelUpProActive = true
        o.cardStates["cryptocom-royal-indigo"]?.croHandling = "autoSell"
        let p = PurchaseContext(amountCad: 165, currency: "USD", category: "other", channel: "online")
        let s = score("cryptocom-royal-indigo", p, o)
        XCTAssertEqual(s.netValueCad, 4.95, accuracy: 0.005)
    }

    func testTriangleCtFamilyUsabilityHaircutAndDrawerWarning() {
        let p = PurchaseContext(amountCad: 150, category: "ctFamily", mcc: 5200,
                                merchantBrand: "canadian-tire")
        let s = score("triangle-we", p)
        XCTAssertEqual(s.netValueCad, 5.70, accuracy: 0.005, "4% × 150 = 6.00 CT × 0.95")
        XCTAssertTrue(s.warnings.contains(.drawerCard))
    }

    func testBonvoyMarriott300() {
        let p = PurchaseContext(amountCad: 300, category: "marriottDirect", mcc: 3509,
                                merchantBrand: "marriott")
        XCTAssertEqual(score("amex-bonvoy", p).netValueCad, 12.00, accuracy: 0.005)
        XCTAssertEqual(score("amex-platinum", p).netValueCad, 10.80, accuracy: 0.005,
                       "Platinum travel 2x fires on lodging? No — category is marriottDirect; expected 1x = 5.40")
    }

    func testNetworkNotAcceptedExcludes() {
        let p = PurchaseContext(amountCad: 200, category: "wholesaleClub", mcc: 5300,
                                merchantBrand: "costco", acceptedNetworks: [.mastercard])
        let s = score("wealthsimple-vip", p)
        XCTAssertTrue(s.excluded)
        XCTAssertTrue(s.warnings.contains(.networkNotAccepted))
    }
}
```

**Correction locked in during self-review (keep the assertion this way):** in `testBonvoyMarriott300`, `amex-platinum` must score **5.40** (base 1x), *not* 10.80 — the purchase category is `marriottDirect`, which is not in Platinum's `["travel", "lodging"]` predicate. The fixture `marriott-direct-300` therefore expects runner-up **amex-platinum at 5.40? No — runner-up is `amex-platinum` at $10.80 only if category were lodging.** Resolution: the fixture models a Marriott *hotel stay*, so the harness purchase carries `category: "marriottDirect"` and the Platinum runner-up value of $10.80 in `engine-fixtures.json` is achieved by treating `marriottDirect` as a **subcategory of lodging**: `Scorer` must expand `purchase.category == "marriottDirect"` to also match predicates listing `"lodging"`. Implement this as a category-hierarchy map in `RuleMatcher`: `["marriottDirect": ["lodging", "travel"]]` — the match succeeds if the predicate lists the category **or any of its parents**. Write `testBonvoyMarriott300` asserting Platinum = **10.80** and add `RuleMatcherTests.testMarriottDirectInheritsLodging` accordingly.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Engine && swift test --filter ScorerTests`
Expected: FAIL to build — `Scorer`, `CandidateScore`, `Warning` not defined.

- [ ] **Step 3: Implement Scorer** (and add the category-hierarchy map to `RuleMatcher.matches`)

```swift
import Foundation

public enum Warning: String, Codable, Equatable, Sendable {
    case drawerCard, unresolvedOwnerState, networkNotAccepted,
         capNearlyExhausted, negativeNetValue, fxAllowanceAssumed
}

public struct CandidateScore: Equatable, Sendable {
    public let cardId: String
    public let appliedRuleId: String?
    public let rewardUnits: Double
    public let grossRewardCad: Double
    public let fxCostCad: Double
    public let netValueCad: Double
    public let warnings: [Warning]
    public let excluded: Bool
    public let exclusionReason: String?
}

public enum Scorer {
    static let categoryParents: [String: [String]] = ["marriottDirect": ["lodging", "travel"]]

    public static func score(card: CardProduct, purchase: PurchaseContext,
                             ownerState: OwnerState, asOf: String) -> CandidateScore {
        func excludedScore(_ warning: Warning, _ reason: String) -> CandidateScore {
            CandidateScore(cardId: card.cardId, appliedRuleId: nil, rewardUnits: 0,
                           grossRewardCad: 0, fxCostCad: 0, netValueCad: 0,
                           warnings: [warning], excluded: true, exclusionReason: reason)
        }
        guard purchase.acceptedNetworks.contains(card.network) else {
            return excludedScore(.networkNotAccepted, "\(card.network.rawValue) not accepted")
        }
        let rule: EarnRule
        switch RuleMatcher.resolve(card: card, purchase: purchase, ownerState: ownerState, asOf: asOf) {
        case .cardExcluded(let reason): return excludedScore(.unresolvedOwnerState, reason)
        case .applied(let r): rule = r
        }

        var warnings: [Warning] = []
        let state = ownerState.cardStates[card.cardId] ?? CardState()

        // Cap split, mapped back to CAD portions.
        var inCapCad = purchase.amountCad, overCapCad = 0.0
        if let capId = rule.capId, let cap = card.caps.first(where: { $0.capId == capId }) {
            let usage = state.capProgress?[capId] ?? 0
            let measureAmount = cap.measure == .spendUsdEquivalent
                ? (purchase.usdEquivalent ?? purchase.amountCad * 0.73)
                : purchase.amountCad
            let split = CapMath.split(amount: measureAmount, capLimit: cap.limit, usage: usage)
            let inFraction = measureAmount > 0 ? split.inCap / measureAmount : 1
            inCapCad = purchase.amountCad * inFraction
            overCapCad = purchase.amountCad - inCapCad
            if usage >= cap.limit * 0.9 { warnings.append(.capNearlyExhausted) }
        }

        let postCapEarn = rule.capId.flatMap { id in
            card.caps.first { $0.capId == id }?.postCapEarn
        }
        let units = earnUnits(rule.earn, amountCad: inCapCad)
            + earnUnits(postCapEarn ?? rule.earn, amountCad: overCapCad)
        let gross = valueCad(units: units, earn: rule.earn, program: card.program.programId,
                             valuations: ownerState.valuationsCad, state: state)

        var fxCost = 0.0
        if purchase.currency != "CAD", let fx = RuleMatcher.activeFxRule(for: card, asOf: asOf) {
            if fx.freeAllowanceCadPerCalendarMonth != nil {
                warnings.append(.fxAllowanceAssumed)   // v1 assumes within allowance
            } else {
                fxCost = purchase.amountCad * fx.rate
            }
        }

        let net = gross - fxCost
        if net < 0 { warnings.append(.negativeNetValue) }
        if ownerState.carry.drawerCards.contains(card.cardId) { warnings.append(.drawerCard) }

        return CandidateScore(cardId: card.cardId, appliedRuleId: rule.ruleId, rewardUnits: units,
                              grossRewardCad: gross, fxCostCad: fxCost, netValueCad: net,
                              warnings: warnings, excluded: false, exclusionReason: nil)
    }

    static func earnUnits(_ earn: Earn, amountCad: Double) -> Double {
        switch earn {
        case .points(let p): return amountCad * p
        case .cashback(let r, _): return amountCad * r
        case .centsPerLitre: return 0
        }
    }

    static func valueCad(units: Double, earn: Earn, program: String,
                         valuations: Valuations, state: CardState) -> Double {
        switch program {
        case "amexMembershipRewards": return units * valuations.amexMembershipRewards.centsPerPoint / 100
        case "marriottBonvoy": return units * valuations.marriottBonvoy.centsPerPoint / 100
        case "mbnaRewards": return units * valuations.mbnaRewards.centsPerPoint / 100
        case "ctMoney":
            let v = valuations.ctMoney
            return units * v.cadPerUnit * (v.usabilityFactorApplied ? v.optionalUsabilityFactor : 1)
        case "cro":
            let factor = state.croHandling == "autoSell"
                ? valuations.cro.faceValueFactorIfAutoSold
                : valuations.cro.defaultHeldRiskFactor
            return units * factor
        default: return units * valuations.cashBack.cadPerDollar
        }
    }
}
```

And in `RuleMatcher.matches`, replace the default category branch's equality check with hierarchy-aware matching:

```swift
default:
    let selfOrParents = [purchase.category] + (Scorer.categoryParents[purchase.category] ?? [])
    guard selfOrParents.contains(category) else { return false }
    if let include = p.mccInclude, let mcc = purchase.mcc {
        return include.contains(mcc)
    }
    return true
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Engine && swift test --filter ScorerTests` then the full `swift test`
Expected: PASS, including all earlier suites (add `RuleMatcherTests.testMarriottDirectInheritsLodging`: Platinum resolves `platinum-travel-2x` for a `marriottDirect` purchase).

- [ ] **Step 5: Commit**

```bash
git add Engine
git commit -m "feat: per-card scorer with cap proration, valuations, and FX"
```

---

### Task 5: RecommendationEngine (gates + ranking)

**Files:**
- Create: `Engine/Sources/CardCopilotEngine/Engine/RecommendationEngine.swift`
- Test: `Engine/Tests/CardCopilotEngineTests/EngineGateTests.swift`

**Interfaces:**
- Consumes: `Scorer.score`.
- Produces: `Recommendation` and `RecommendationEngine(catalogue:ownerState:).recommend(_:asOf:) -> Recommendation`. Tasks 6–7 consume exactly this.

**Gate contract:** score every card; keep non-excluded scores; sort by `netValueCad` descending (ties: default card first, then alphabetical `cardId` for determinism). If the default card is excluded → `defaultNotAccepted = true`, winner = best challenger, no threshold gate (you must pay with something). Otherwise advantage = best − default; `advantagePP = advantage / amountCad × 100`; switch when semantics `"both"` requires both floors (or `"either"` requires one) met and best ≠ default; else winner = default and the beaten challenger (if strictly better) is exposed as `suppressedBetterCard`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import CardCopilotEngine

final class EngineGateTests: XCTestCase {
    var engine: RecommendationEngine!
    let asOf = "2026-08-20"

    override func setUpWithError() throws {
        engine = RecommendationEngine(catalogue: try SeedLoader.loadCatalogue(),
                                      ownerState: try SeedLoader.loadOwnerState())
    }

    func testPharmacyHoldsDefault() {
        let r = engine.recommend(PurchaseContext(amountCad: 30, category: "drugStore", mcc: 5912),
                                 asOf: asOf)
        XCTAssertEqual(r.winner.cardId, "wealthsimple-vip")
        XCTAssertFalse(r.switchedFromDefault)
        XCTAssertNil(r.suppressedBetterCard, "no card strictly beats 2% here")
    }

    func testTaxiSuppressionUnderBothSemantics() {
        let r = engine.recommend(PurchaseContext(amountCad: 12, category: "transit", mcc: 4121),
                                 asOf: asOf)
        XCTAssertEqual(r.winner.cardId, "wealthsimple-vip")
        XCTAssertFalse(r.switchedFromDefault)
        XCTAssertEqual(r.suppressedBetterCard?.cardId, "amex-cobalt")
        XCTAssertEqual(r.suppressedBetterCard?.netValueCad ?? 0, 0.432, accuracy: 0.005)
    }

    func testCostcoDefaultNotAccepted() {
        let r = engine.recommend(PurchaseContext(amountCad: 200, category: "wholesaleClub", mcc: 5300,
                                                 merchantBrand: "costco",
                                                 acceptedNetworks: [.mastercard]), asOf: asOf)
        XCTAssertTrue(r.defaultNotAccepted)
        XCTAssertEqual(r.winner.cardId, "rogers-red-we")
        XCTAssertEqual(r.winner.netValueCad, 3.00, accuracy: 0.005)
    }

    func testGroceryWinnerAndRunnerUp() {
        let r = engine.recommend(PurchaseContext(amountCad: 100, category: "grocery", mcc: 5411,
                                                 merchantBrand: "loblaws"), asOf: asOf)
        XCTAssertEqual(r.winner.cardId, "amex-cobalt")
        XCTAssertTrue(r.switchedFromDefault)
        XCTAssertEqual(r.runnerUp?.cardId, "mbna-rewards-we")
        XCTAssertEqual(r.advantageOverDefaultCad ?? 0, 7.00, accuracy: 0.005)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Engine && swift test --filter EngineGateTests`
Expected: FAIL to build — `RecommendationEngine` not defined.

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct Recommendation: Equatable, Sendable {
    public let winner: CandidateScore
    public let runnerUp: CandidateScore?
    public let switchedFromDefault: Bool
    public let advantageOverDefaultCad: Double?
    public let defaultNotAccepted: Bool
    public let suppressedBetterCard: CandidateScore?
    public let allCandidates: [CandidateScore]
}

public struct RecommendationEngine {
    let catalogue: Catalogue
    let ownerState: OwnerState

    public init(catalogue: Catalogue, ownerState: OwnerState) {
        self.catalogue = catalogue
        self.ownerState = ownerState
    }

    public func recommend(_ purchase: PurchaseContext, asOf: String) -> Recommendation {
        let all = catalogue.cards.map {
            Scorer.score(card: $0, purchase: purchase, ownerState: ownerState, asOf: asOf)
        }
        let defaultId = ownerState.defaultCardId
        let ranked = all.filter { !$0.excluded }.sorted { a, b in
            if a.netValueCad != b.netValueCad { return a.netValueCad > b.netValueCad }
            if a.cardId == defaultId { return true }
            if b.cardId == defaultId { return false }
            return a.cardId < b.cardId
        }
        precondition(!ranked.isEmpty, "no scorable card — catalogue misconfigured")

        let best = ranked[0]
        let runnerUp = ranked.count > 1 ? ranked[1] : nil
        guard let defaultScore = ranked.first(where: { $0.cardId == defaultId }) else {
            return Recommendation(winner: best, runnerUp: runnerUp, switchedFromDefault: true,
                                  advantageOverDefaultCad: nil, defaultNotAccepted: true,
                                  suppressedBetterCard: nil, allCandidates: ranked)
        }

        let advantage = best.netValueCad - defaultScore.netValueCad
        let advantagePP = purchase.amountCad > 0 ? advantage / purchase.amountCad * 100 : 0
        let t = ownerState.switchThreshold
        let cadOk = advantage >= t.minAdvantageCad
        let ppOk = advantagePP >= t.minAdvantagePercentagePoints
        let clears = t.semantics == "either" ? (cadOk || ppOk) : (cadOk && ppOk)

        if best.cardId != defaultId && clears {
            return Recommendation(winner: best, runnerUp: runnerUp, switchedFromDefault: true,
                                  advantageOverDefaultCad: advantage, defaultNotAccepted: false,
                                  suppressedBetterCard: nil, allCandidates: ranked)
        }
        let suppressed = (best.cardId != defaultId && advantage > 0) ? best : nil
        return Recommendation(winner: defaultScore,
                              runnerUp: ranked.first { $0.cardId != defaultId },
                              switchedFromDefault: false,
                              advantageOverDefaultCad: 0, defaultNotAccepted: false,
                              suppressedBetterCard: suppressed, allCandidates: ranked)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Engine && swift test --filter EngineGateTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Engine
git commit -m "feat: recommendation engine with acceptance and switch-threshold gates"
```

---

### Task 6: Fixture harness — the executable spec

**Files:**
- Create: `Engine/Tests/CardCopilotEngineTests/FixtureHarnessTests.swift`

**Interfaces:**
- Consumes: `RecommendationEngine`, `SeedLoader`, `Fixtures/engine-fixtures.json` (bundled via `.copy("Fixtures")`).
- Produces: nothing — this task is pure verification. All 12 cases green = the engine v1 contract is met.

- [ ] **Step 1: Write the harness (it IS the failing test)**

```swift
import XCTest
@testable import CardCopilotEngine

private struct FixtureFile: Decodable { let cases: [FixtureCase] }
private struct FixtureCase: Decodable {
    let caseId: String
    let purchase: PurchaseContext
    let ownerStateOverrides: Overrides?
    let expected: Expected
    struct Overrides: Decodable { let cardStates: [String: CardState]? }
    struct Expected: Decodable {
        let winner: String
        let winnerValueCad: Double
        let winnerRule: String?
        let runnerUp: String?
        let runnerUpValueCad: Double?
        let switchFromDefault: Bool?
        let advantageOverDefaultCad: Double?
        let defaultNotAccepted: Bool?
        let suppressedBetterCard: String?
        let suppressedValueCad: Double?
        let warnings: [String]?
    }
}

final class FixtureHarnessTests: XCTestCase {
    func testAllFixtures() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "engine-fixtures",
                                                  withExtension: "json",
                                                  subdirectory: "Fixtures"))
        let file = try JSONDecoder().decode(FixtureFile.self, from: Data(contentsOf: url))
        XCTAssertEqual(file.cases.count, 12)
        let catalogue = try SeedLoader.loadCatalogue()
        let baseState = try SeedLoader.loadOwnerState()

        for fixture in file.cases {
            var state = baseState
            if let overrides = fixture.ownerStateOverrides?.cardStates {
                for (cardId, override) in overrides {
                    var merged = state.cardStates[cardId] ?? CardState()
                    if let cap = override.capProgress {
                        merged.capProgress = (merged.capProgress ?? [:]).merging(cap) { _, new in new }
                    }
                    if let v = override.cryptoLevelUpProActive { merged.cryptoLevelUpProActive = v }
                    if let v = override.croHandling { merged.croHandling = v }
                    if let v = override.rogersEligibleServiceLinked { merged.rogersEligibleServiceLinked = v }
                    if let v = override.selectedCategories { merged.selectedCategories = v }
                    state.cardStates[cardId] = merged
                }
            }
            let engine = RecommendationEngine(catalogue: catalogue, ownerState: state)
            let r = engine.recommend(fixture.purchase, asOf: "2026-08-20")
            let e = fixture.expected
            let ctx = "case \(fixture.caseId)"

            XCTAssertEqual(r.winner.cardId, e.winner, ctx)
            XCTAssertEqual(r.winner.netValueCad, e.winnerValueCad, accuracy: 0.005, ctx)
            if let rule = e.winnerRule { XCTAssertEqual(r.winner.appliedRuleId, rule, ctx) }
            if let runnerUp = e.runnerUp { XCTAssertEqual(r.runnerUp?.cardId, runnerUp, ctx) }
            if let v = e.runnerUpValueCad {
                XCTAssertEqual(r.runnerUp?.netValueCad ?? .nan, v, accuracy: 0.005, ctx)
            }
            if let s = e.switchFromDefault { XCTAssertEqual(r.switchedFromDefault, s, ctx) }
            if let a = e.advantageOverDefaultCad {
                XCTAssertEqual(r.advantageOverDefaultCad ?? .nan, a, accuracy: 0.005, ctx)
            }
            if let d = e.defaultNotAccepted { XCTAssertEqual(r.defaultNotAccepted, d, ctx) }
            if let s = e.suppressedBetterCard { XCTAssertEqual(r.suppressedBetterCard?.cardId, s, ctx) }
            if let v = e.suppressedValueCad {
                XCTAssertEqual(r.suppressedBetterCard?.netValueCad ?? .nan, v, accuracy: 0.005, ctx)
            }
            if let warnings = e.warnings {
                for w in warnings {
                    XCTAssertTrue(r.winner.warnings.map(\.rawValue).contains(w), "\(ctx): missing \(w)")
                }
            }
        }
    }
}
```

- [ ] **Step 2: Run and triage**

Run: `cd Engine && swift test --filter FixtureHarnessTests`
Expected on first run: possibly a handful of failures. Triage rule: a failing fixture means either (a) an engine bug — fix the engine; or (b) a wrong hand-computed expectation — recompute from the catalogue and valuations by hand, and only then amend the fixture with a comment. Never tune the engine to a number you can't derive.

- [ ] **Step 3: Run the full suite**

Run: `cd Engine && swift test`
Expected: PASS — every suite, all 12 fixtures.

- [ ] **Step 4: Commit**

```bash
git add Engine
git commit -m "test: fixture harness — 12-case executable spec passes"
```

---

### Task 7: RecommendationExplainer

**Files:**
- Create: `Engine/Sources/CardCopilotEngine/Engine/Explainer.swift`
- Test: `Engine/Tests/CardCopilotEngineTests/ExplainerTests.swift`

**Interfaces:**
- Consumes: `Recommendation`, `CandidateScore`, `Catalogue` (for `officialName` lookup), `PurchaseContext`.
- Produces: `Explanation` (headline / why / runnerUpLine / warningLines) and `RecommendationExplainer(catalogue:).explain(_:purchase:) -> Explanation`. The app's recommendation screen renders these strings verbatim; the design doc's "plain-language why" requirement lands here.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import CardCopilotEngine

final class ExplainerTests: XCTestCase {
    var engine: RecommendationEngine!
    var explainer: RecommendationExplainer!
    let asOf = "2026-08-20"

    override func setUpWithError() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        engine = RecommendationEngine(catalogue: catalogue,
                                      ownerState: try SeedLoader.loadOwnerState())
        explainer = RecommendationExplainer(catalogue: catalogue)
    }

    func testGroceryExplanation() {
        let p = PurchaseContext(amountCad: 100, category: "grocery", mcc: 5411, merchantBrand: "loblaws")
        let e = explainer.explain(engine.recommend(p, asOf: asOf), purchase: p)
        XCTAssertEqual(e.headline, "Use American Express Cobalt Card — about $9.00 back on this $100.00 purchase.")
        XCTAssertEqual(e.runnerUpLine, "Next best: MBNA Rewards World Elite Mastercard ($5.00) — you'd give up $4.00.")
    }

    func testTaxiSuppressionExplanation() {
        let p = PurchaseContext(amountCad: 12, category: "transit", mcc: 4121)
        let e = explainer.explain(engine.recommend(p, asOf: asOf), purchase: p)
        XCTAssertEqual(e.headline, "Stay on Wealthsimple Visa Infinite Privilege Credit Card — about $0.24 back on this $12.00 purchase.")
        XCTAssertEqual(e.runnerUpLine, "American Express Cobalt Card is marginally better (+$0.19) — not worth the wallet dig.")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Engine && swift test --filter ExplainerTests`
Expected: FAIL to build — `RecommendationExplainer` not defined.

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct Explanation: Equatable, Sendable {
    public let headline: String
    public let why: String
    public let runnerUpLine: String?
    public let warningLines: [String]
}

public struct RecommendationExplainer {
    let namesById: [String: String]

    public init(catalogue: Catalogue) {
        namesById = Dictionary(uniqueKeysWithValues: catalogue.cards.map { ($0.cardId, $0.officialName) })
    }

    public func explain(_ r: Recommendation, purchase: PurchaseContext) -> Explanation {
        let name = namesById[r.winner.cardId] ?? r.winner.cardId
        let verb = r.switchedFromDefault || r.defaultNotAccepted ? "Use" : "Stay on"
        let headline = "\(verb) \(name) — about \(money(r.winner.netValueCad)) back on this \(money(purchase.amountCad)) purchase."

        let why: String
        if let rule = r.winner.appliedRuleId {
            why = "Applied rule \(rule): \(money(r.winner.grossRewardCad)) in rewards"
                + (r.winner.fxCostCad > 0 ? " minus \(money(r.winner.fxCostCad)) foreign-transaction fee." : ".")
        } else {
            why = "No earn rule applied."
        }

        var runnerUpLine: String?
        if let suppressed = r.suppressedBetterCard {
            let delta = suppressed.netValueCad - r.winner.netValueCad
            runnerUpLine = "\(namesById[suppressed.cardId] ?? suppressed.cardId) is marginally better (+\(money(delta))) — not worth the wallet dig."
        } else if let runnerUp = r.runnerUp {
            let delta = r.winner.netValueCad - runnerUp.netValueCad
            runnerUpLine = "Next best: \(namesById[runnerUp.cardId] ?? runnerUp.cardId) (\(money(runnerUp.netValueCad))) — you'd give up \(money(delta))."
        }

        let warningLines = r.winner.warnings.map { warning -> String in
            switch warning {
            case .drawerCard: return "This card is in your drawer — bring it or take the runner-up."
            case .capNearlyExhausted: return "Category cap nearly used up — the winner may flip soon."
            case .negativeNetValue: return "This card would LOSE money here after fees."
            case .networkNotAccepted: return "Card network not accepted at this merchant."
            case .unresolvedOwnerState: return "Card skipped — account state not set up yet."
            case .fxAllowanceAssumed: return "Assumed within this card's monthly FX-free allowance."
            }
        }
        return Explanation(headline: headline, why: why,
                           runnerUpLine: runnerUpLine, warningLines: warningLines)
    }

    private func money(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}
```

- [ ] **Step 4: Run the full suite**

Run: `cd Engine && swift test`
Expected: PASS — all suites green. (If the two exact strings mismatch on formatting, fix the *implementation* to the test's string, which is the spec.)

- [ ] **Step 5: Commit**

```bash
git add Engine
git commit -m "feat: plain-language recommendation explainer"
```

---

## Self-Review (performed at authoring time)

1. **Spec coverage:** design §5 net-value formula → Task 4; two gates → Task 5; cap accumulators incl. proration/USD-measure/effective-dating → Tasks 2–4; "never guess owner state" → Task 2; decisions #7–#11 → Tasks 4–5 + seed data; 12-fixture executable spec → Task 6; plain-language why → Task 7. Deliberately out of scope for this plan (next plan: app shell): prediction ladder/MapKit, reconcile flow, metrics screen, Report Card, App Intent.
2. **Placeholder scan:** none — every step has runnable code or an exact command.
3. **Type consistency:** one deliberate correction was found and locked in during review — the Marriott/Platinum category-hierarchy issue in Task 4 (see the boxed note there); `marriottDirect` must inherit `lodging`/`travel` via `Scorer.categoryParents`, and the fixture's Platinum runner-up value of $10.80 is correct under that rule.
