# P1 Phase 0–1: Valuation dictionary + capability system — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a rewards program a data entry rather than a Swift/Kotlin struct field, and make it impossible for catalogue data to declare behaviour the engine lacks without the engine saying so out loud.

**Architecture:** `Valuations`' six hardcoded properties become `[String: ProgramValuation]` keyed by `programId`, with `ProgramValuation` a sum type decoded on a `model` discriminator — the pattern `Earn` already uses on `type`. Catalogue-level defaults ship in a new `contracts/programs.json`; owner state overrides them per key. Earn rules gain `requires: [EngineCapability]` (not-yet-built) and `outOfScope` (never-to-be-built), replacing the hand-maintained `scoredInV1` boolean. A card whose program has no valuation is *excluded* rather than silently valued at zero, which makes the existing `precondition(!scores.isEmpty)` reachable from data — so `recommend` returns a `RecommendationOutcome`.

**Tech Stack:** Swift 5.10 (Engine) / 6.0 (Store), XCTest, SPM resource bundles. Kotlin twin at `android/core/engine` with kotlinx.serialization.

**Spec:** [`docs/plans/2026-08-20-catalogue-scalability-program-design.md`](../../plans/2026-08-20-catalogue-scalability-program-design.md) — §3.1, §3.5, §3.6, §3.7, §3.9.

## Global Constraints

- **Fixture changes are API changes** (`CLAUDE.md`). The existing 27 cases in `contracts/engine-fixtures.json` must pass **byte-unchanged in their expectations**. Any diff is a bug, not an expectation update.
- **`contracts/` is canonical.** Never edit `Engine/Sources/CardCopilotEngine/Resources/*.json` or `android/core/engine/src/main/resources/**` directly. Edit `contracts/`, then run `scripts/sync-contracts-into-engine.sh` and `scripts/sync-contracts-into-android.sh`. `ContractsSyncTests` fails on byte drift.
- **Every catalogue edit updates `contracts/CHANGELOG.md`** with a dated entry, and `lastVerifiedAt` on any touched rule.
- **`catalogueVersion` MAJOR stays `1`.** Every change in this plan is additive; bump MINOR (`1.2` → `1.3`) once, in Task 5.
- **Verification commands:** `cd Engine && swift test` and `cd Store && swift test`. Both must be green before any commit. CI gate is `.github/workflows/ci.yml`.
- **Fail closed, never guess.** The house rule from `RuleMatcher`: unresolved owner state skips a rule rather than assuming. New code follows it.
- **No `Co-Authored-By` trailer on commits.**

## Scope

This plan covers **Phase 0** (two pre-work items that ship alone and protect everything after) and **Phase 1** (the valuation dictionary and capability system).

Deliberately **not** in this plan, each getting its own plan afterwards:

- Owner conditions → `CardState.flags`, and cap anchors → `CardState.anchors` (spec §3.2, §3.3)
- Merchant index and presentation registries → data (spec §3.4)
- `market` field, per-market block, `manifest.json` (spec §3.8)

Those are independently shippable and would triple this plan's length. Phase 1 stops at a working, testable boundary: every card in the catalogue produces an honest number or an honest refusal.

---

## File Structure

**Created:**

| File | Responsibility |
|---|---|
| `Engine/Sources/CardCopilotEngine/Models/ProgramValuation.swift` | The `ProgramValuation` sum type and its `Codable` conformance. Separate from `OwnerState.swift` because it is consumed by both owner state and the catalogue defaults. |
| `Engine/Sources/CardCopilotEngine/Models/EngineCapability.swift` | The capability vocabulary and the engine's supported set. One file so "what can this engine do" has a single answer. |
| `contracts/programs.json` | Catalogue-level default valuation per `programId`, with `basis` disclosure text. |
| `contracts/schema/programs.schema.json` | Schema for the above. |
| `Engine/Tests/CardCopilotEngineTests/CatalogueIntegrityTests.swift` | The ratchet gate: every `programId` resolves, every `ownerConditions` id is handled, every `cap.anchor` resolves — with an explicit shrinking allowlist. |
| `Engine/Tests/CardCopilotEngineTests/ProgramValuationTests.swift` | Sum-type round-trip and legacy-shape decode. |
| `Engine/Tests/CardCopilotEngineTests/CapabilityGatingTests.swift` | `requires` / `outOfScope` behaviour. |
| `Store/Tests/CardCopilotStoreTests/OwnerStateDecodeResilienceTests.swift` | Per-profile decode tolerance. |

**Modified:**

| File | Change |
|---|---|
| `Engine/Sources/CardCopilotEngine/Models/OwnerState.swift:87-94` | `Valuations` → dictionary, with dual-shape decode. |
| `Engine/Sources/CardCopilotEngine/Models/CatalogueModels.swift:62-74` | `EarnRule` gains `requires` and `outOfScope`. |
| `Engine/Sources/CardCopilotEngine/Engine/Scorer.swift:3-6` | `Warning` gains three cases. |
| `Engine/Sources/CardCopilotEngine/Engine/Scorer.swift:114-139` | `valueCad` switch → dictionary lookup returning an optional. |
| `Engine/Sources/CardCopilotEngine/Engine/RuleMatcher.swift:22-31` | Capability gating in `resolve`. |
| `Engine/Sources/CardCopilotEngine/Engine/RecommendationEngine.swift:47-54` | `RecommendationOutcome` return type. |
| `Engine/Sources/CardCopilotEngine/Loading/SeedLoader.swift` | `loadPrograms()`. |
| `Store/Sources/CardCopilotStore/AccountOwnerStateStore.swift:63-66,101-104` | Tolerant per-profile decode. |
| `android/core/engine/src/main/kotlin/com/cardcopilot/engine/models/OwnerState.kt:96-102` | Kotlin twin of `Valuations`. |
| `android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/Scorer.kt:144-161` | Kotlin twin of `valueCad`. |
| `contracts/card-catalogue.json` | `scoredInV1` → `requires` / `outOfScope` on 51 rules. |
| `contracts/schema/card-catalogue.schema.json` | Document the new fields; open the `ownerConditions` enum. |
| `scripts/sync-contracts-into-engine.sh`, `scripts/sync-contracts-into-android.sh` | Copy `programs.json`. |

---

# Phase 0 — Pre-work

Both tasks ship independently and are worth doing whether or not Phase 1 proceeds.

---

### Task 1: Tolerant per-profile owner-state decode

`AccountOwnerStateStore.profiles()` and `OwnerStateUploadQueue.records()` decode a dictionary of **all** profiles in one call, with `(try? …) ?? [:]`. One undecodable profile therefore returns **zero** profiles — every saved wallet lost, silently. This must be fixed before any `OwnerState` shape change.

**Files:**
- Modify: `Store/Sources/CardCopilotStore/AccountOwnerStateStore.swift:63-66` and `:101-104`
- Test: `Store/Tests/CardCopilotStoreTests/OwnerStateDecodeResilienceTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `AccountOwnerStateStore.profiles()` and `OwnerStateUploadQueue.records()` keep signature `-> [String: OwnerState]` but drop only unreadable entries.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

final class OwnerStateDecodeResilienceTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// A profile the current build cannot decode must not take its neighbours with it.
    /// Before this fix the whole dictionary decoded as one value, so one bad entry returned [:].
    func testCorruptProfileDoesNotEvictHealthyProfiles() throws {
        let defaults = makeDefaults()
        let store = AccountOwnerStateStore(defaults: defaults)

        let healthy = PinnedOwnerState.make()
        try store.activate(healthy, forUserID: "good-user")

        // Splice an undecodable sibling in beside the healthy one, exactly as a future
        // shape change would produce on an older build.
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(
            with: XCTUnwrap(defaults.data(forKey: "ca.pickme.owner-state-profiles.v1"))
        ) as? [String: Any])
        raw["bad-user"] = ["ownerStateVersion": "1.0", "unexpectedShape": true]
        defaults.set(try JSONSerialization.data(withJSONObject: raw),
                     forKey: "ca.pickme.owner-state-profiles.v1")

        XCTAssertEqual(store.state(forUserID: "good-user"), healthy)
        XCTAssertNil(store.state(forUserID: "bad-user"))
    }

    func testEntirelyUnreadableBlobStillReturnsEmpty() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "ca.pickme.owner-state-profiles.v1")
        XCTAssertNil(AccountOwnerStateStore(defaults: defaults).state(forUserID: "anyone"))
    }
}
```

`PinnedOwnerState` already exists at `Engine/Tests/CardCopilotEngineTests/PinnedOwnerState.swift`. If it is not visible to the Store test target, build the `OwnerState` inline in this test instead — do not add a cross-package test dependency.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Store && swift test --filter OwnerStateDecodeResilienceTests`
Expected: FAIL — `testCorruptProfileDoesNotEvictHealthyProfiles` gets `nil` for `good-user`, because the whole dictionary failed to decode.

- [ ] **Step 3: Write minimal implementation**

Replace `AccountOwnerStateStore.profiles()` (currently at `:63-66`):

```swift
    private func profiles() -> [String: OwnerState] {
        guard let data = defaults.data(forKey: profilesKey) else { return [:] }
        return Self.decodeTolerantly(data)
    }

    /// Decodes each profile independently so one unreadable entry — the shape a future
    /// migration produces on an older build — cannot evict every other account's wallet.
    /// The all-or-nothing `decode([String: OwnerState].self)` this replaces returned [:].
    static func decodeTolerantly(_ data: Data) -> [String: OwnerState] {
        guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return [:]
        }
        let decoder = JSONDecoder()
        return raw.reduce(into: [:]) { result, entry in
            guard let itemData = try? JSONSerialization.data(withJSONObject: entry.value),
                  let state = try? decoder.decode(OwnerState.self, from: itemData) else { return }
            result[entry.key] = state
        }
    }
```

Replace `OwnerStateUploadQueue.records()` (currently at `:101-104`) with the same body:

```swift
    private func records() -> [String: OwnerState] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return AccountOwnerStateStore.decodeTolerantly(data)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Store && swift test`
Expected: PASS — all Store tests including the two new ones.

- [ ] **Step 5: Commit**

```bash
git add Store/Sources/CardCopilotStore/AccountOwnerStateStore.swift \
        Store/Tests/CardCopilotStoreTests/OwnerStateDecodeResilienceTests.swift
git commit -m "fix(store): decode owner-state profiles independently

profiles() and records() decoded the whole dictionary in one call with
(try? ...) ?? [:], so a single undecodable profile returned zero profiles —
every saved wallet lost, with no error surfaced. Any OwnerState shape change
would have triggered exactly that on upgrade."
```

---

### Task 2: Catalogue integrity ratchet gate

A test asserting that every `programId` in the catalogue resolves to a valuation, every declared `ownerConditions` id has a handler, and every `cap.anchor` is resolvable. **It cannot be green today** — 10 programs and `amazonEligiblePrimeLinked` are already broken — so it takes an explicit allowlist of known gaps and fails when that list *grows*. Entries are deleted as Phase 1 lands.

**Files:**
- Test: `Engine/Tests/CardCopilotEngineTests/CatalogueIntegrityTests.swift` (create)

**Interfaces:**
- Consumes: `SeedLoader.loadCatalogue()`, `SeedLoader.loadCandidateCatalogue()`.
- Produces: `CatalogueIntegrityTests.knownUnvaluedPrograms` and `.knownUnhandledConditions` — allowlists that later tasks delete entries from.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CardCopilotEngine

/// Data may not outrun code silently. Every catalogue value the engine dispatches on must have a
/// handler; anything that does not is listed here explicitly, so a reviewer sees the gap at
/// authoring time instead of an owner discovering it as a $0.00 recommendation months later.
///
/// These lists may only SHRINK. Adding an entry means shipping a card the engine cannot score —
/// if that is genuinely intended, say so in contracts/CHANGELOG.md in the same commit.
final class CatalogueIntegrityTests: XCTestCase {

    /// Programs with no valuation. Each scores every purchase at $0.00 CAD today.
    /// Deleted by Task 7 as programs.json gains defaults.
    static let knownUnvaluedPrograms: Set<String> = [
        "scenePlus", "aeroplan", "rbcAvion", "tdRewards", "bmoRewards",
        "aventura", "nbcRewards", "pcOptimum", "westJetPoints", "amazonRewards",
    ]

    /// Owner conditions declared in the catalogue with no case in RuleMatcher.
    /// Each fails closed silently. Deleted when CardState.flags lands (spec §3.2).
    static let knownUnhandledConditions: Set<String> = ["amazonEligiblePrimeLinked"]

    /// Mirrors RuleMatcher.conditionsResolveTrue's switch. Kept here rather than made internal
    /// so the test fails when the switch and this list drift, which is the point.
    static let handledConditions: Set<String> = [
        "rogersEligibleServiceLinked", "cryptoLevelUpProActive", "tangerineCategorySelected",
    ]

    /// Mirrors CapWindow.anchorMonth's switch.
    static let resolvableAnchors: Set<String> = [
        "ownerState.scotiaAccountYearAnchorMonth", "ownerState.rogersAccountAnniversaryMonth",
    ]

    private func allCards() throws -> [CardProduct] {
        try SeedLoader.loadCatalogue().cards + SeedLoader.loadCandidateCatalogue().cards
    }

    func testEveryProgramIdIsValuedOrKnownUnvalued() throws {
        let valued: Set<String> = [
            "amexMembershipRewards", "marriottBonvoy", "mbnaRewards", "ctMoney", "cro", "cashback",
        ]
        let unhandled = Set(try allCards().map(\.program.programId))
            .subtracting(valued)
            .subtracting(Self.knownUnvaluedPrograms)
        XCTAssertTrue(unhandled.isEmpty,
            "programId(s) with no valuation and not on the known-gap list: \(unhandled.sorted()). "
          + "Scorer.valueCad would value these at $0.00. Add a valuation, or add to "
          + "knownUnvaluedPrograms with a CHANGELOG entry saying why.")
    }

    func testEveryOwnerConditionHasAHandler() throws {
        let declared = Set(try allCards().flatMap { $0.earnRules.compactMap(\.ownerConditions).flatMap { $0 } })
        let unhandled = declared
            .subtracting(Self.handledConditions)
            .subtracting(Self.knownUnhandledConditions)
        XCTAssertTrue(unhandled.isEmpty,
            "ownerCondition(s) with no handler in RuleMatcher: \(unhandled.sorted()). "
          + "These fail closed silently.")
    }

    func testEveryCapAnchorIsResolvable() throws {
        let declared = Set(try allCards().flatMap { $0.caps.compactMap(\.anchor) })
        let unresolvable = declared.subtracting(Self.resolvableAnchors)
        XCTAssertTrue(unresolvable.isEmpty,
            "cap.anchor path(s) CapWindow cannot resolve: \(unresolvable.sorted()). "
          + "Their windows return nil and the cap never applies.")
    }

    /// The allowlists are debt, not design. This pins their size so growth is a deliberate,
    /// reviewed act rather than a quiet regression.
    func testKnownGapListsDoNotGrow() {
        XCTAssertLessThanOrEqual(Self.knownUnvaluedPrograms.count, 10)
        XCTAssertLessThanOrEqual(Self.knownUnhandledConditions.count, 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd Engine && swift test --filter CatalogueIntegrityTests`
Expected: PASS — all four. The known gaps are on the allowlists; the assertions prove nothing *else* is broken.

If `testEveryCapAnchorIsResolvable` fails, that is a genuine bug this gate just found. Record the failing anchors and stop — do not add them to an allowlist without understanding them.

- [ ] **Step 3: Commit**

```bash
git add Engine/Tests/CardCopilotEngineTests/CatalogueIntegrityTests.swift
git commit -m "test(engine): ratchet gate on catalogue/engine agreement

Asserts every programId resolves to a valuation, every ownerCondition has a
RuleMatcher case, and every cap.anchor resolves in CapWindow. Known gaps are
explicit allowlists that may only shrink.

Would have failed the day scotia-gold-amex added programId scenePlus, again
for each of the nine programs after it, and again when amazonEligiblePrimeLinked
shipped with no handler."
```

---

# Phase 1 — Valuation dictionary and capability system

---

### Task 3: `ProgramValuation` sum type

**Files:**
- Create: `Engine/Sources/CardCopilotEngine/Models/ProgramValuation.swift`
- Test: `Engine/Tests/CardCopilotEngineTests/ProgramValuationTests.swift` (create)

**Interfaces:**
- Consumes: `PointValuation`, `CtMoneyValuation`, `CroValuation`, `CashBackValuation` from `OwnerState.swift` (unchanged).
- Produces: `enum ProgramValuation` with cases `.points(PointValuation)`, `.cashback(CashBackValuation)`, `.ctMoney(CtMoneyValuation)`, `.cro(CroValuation)`; `Codable` on a `model` string key with values `points` / `cashback` / `ctMoney` / `cro`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CardCopilotEngine

final class ProgramValuationTests: XCTestCase {

    private func roundTrip(_ value: ProgramValuation) throws -> ProgramValuation {
        try JSONDecoder().decode(ProgramValuation.self, from: JSONEncoder().encode(value))
    }

    func testPointsRoundTrips() throws {
        var p = PointValuation(centsPerPoint: 1.0)
        p.floorCentsPerPoint = 0.9
        p.aspirationalCentsPerPoint = 2.2
        p.basis = "cash floor"
        XCTAssertEqual(try roundTrip(.points(p)), .points(p))
    }

    func testCashbackRoundTrips() throws {
        XCTAssertEqual(try roundTrip(.cashback(CashBackValuation(cadPerDollar: 1.0))),
                       .cashback(CashBackValuation(cadPerDollar: 1.0)))
    }

    func testCtMoneyRoundTrips() throws {
        let v = CtMoneyValuation(cadPerUnit: 1.0, optionalUsabilityFactor: 0.95,
                                 usabilityFactorApplied: true)
        XCTAssertEqual(try roundTrip(.ctMoney(v)), .ctMoney(v))
    }

    func testCroRoundTrips() throws {
        let v = CroValuation(model: "reward-currency", faceValueFactorIfAutoSold: 1.0,
                             defaultHeldRiskFactor: 0.8)
        XCTAssertEqual(try roundTrip(.cro(v)), .cro(v))
    }

    func testDecodesFromModelDiscriminator() throws {
        let json = Data(#"{"model":"points","centsPerPoint":1.5}"#.utf8)
        guard case .points(let p) = try JSONDecoder().decode(ProgramValuation.self, from: json)
        else { return XCTFail("expected .points") }
        XCTAssertEqual(p.centsPerPoint, 1.5)
    }

    /// An unknown model is a hard decode failure, not a silent default. A valuation the engine
    /// cannot interpret must never be mistaken for one it can.
    func testUnknownModelIsADecodeError() {
        let json = Data(#"{"model":"cryptoKittyPoints","centsPerPoint":1}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ProgramValuation.self, from: json))
    }
}
```

`PointValuation`, `CtMoneyValuation`, `CroValuation` and `CashBackValuation` are currently declared without explicit memberwise initialisers but have `var` properties, so Swift synthesises `internal` memberwise inits available to `@testable import`. `PointValuation(centsPerPoint:)` will not compile because its other properties have no defaults — give the four structs explicit `public init`s with defaults in this task if the test does not compile:

```swift
public struct PointValuation: Codable, Equatable, Sendable {
    public var centsPerPoint: Double
    public var floorCentsPerPoint: Double?
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
```

Add equivalent `public init`s to `CtMoneyValuation(cadPerUnit:optionalUsabilityFactor:usabilityFactorApplied:)`, `CroValuation(model:faceValueFactorIfAutoSold:defaultHeldRiskFactor:)` and `CashBackValuation(cadPerDollar:)`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Engine && swift test --filter ProgramValuationTests`
Expected: FAIL to compile — `cannot find type 'ProgramValuation' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Engine/Sources/CardCopilotEngine/Models/ProgramValuation.swift`:

```swift
import Foundation

/// What one reward currency is worth, keyed in owner state and the catalogue by `programId`.
///
/// A sum type rather than a flattened struct of optional factors, for the same reason `Earn` is
/// one: CT Money's usability discount and CRO's hold-risk factor are different *models*, not
/// different values of one model. Flattening them into anonymous factors would destroy the
/// disclosure the valuation UI depends on — point values are disclosed assumptions, not facts,
/// and an owner has to be able to see which assumption is being made.
///
/// Deliberately NOT an expression language. A condition encoded as a string ("croHandling ==
/// autoSell") would need a parser, and the parser would be code — moving the closed set rather
/// than opening it. Model-specific behaviour stays in `Scorer`, keyed by case.
public enum ProgramValuation: Equatable, Sendable {
    case points(PointValuation)
    case cashback(CashBackValuation)
    case ctMoney(CtMoneyValuation)
    case cro(CroValuation)
}

extension ProgramValuation: Codable {
    private enum ModelKey: String, CodingKey { case model }

    public init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: ModelKey.self)
        switch try keyed.decode(String.self, forKey: .model) {
        case "points":   self = .points(try PointValuation(from: decoder))
        case "cashback": self = .cashback(try CashBackValuation(from: decoder))
        case "ctMoney":  self = .ctMoney(try CtMoneyValuation(from: decoder))
        case "cro":      self = .cro(try CroValuation(from: decoder))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .model, in: keyed,
                debugDescription: "unknown valuation model: \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var keyed = encoder.container(keyedBy: ModelKey.self)
        switch self {
        case .points(let v):   try keyed.encode("points", forKey: .model);   try v.encode(to: encoder)
        case .cashback(let v): try keyed.encode("cashback", forKey: .model); try v.encode(to: encoder)
        case .ctMoney(let v):  try keyed.encode("ctMoney", forKey: .model);  try v.encode(to: encoder)
        case .cro(let v):      try keyed.encode("cro", forKey: .model);      try v.encode(to: encoder)
        }
    }
}
```

`CroValuation` already has a `model: String` property holding `"reward-currency"`. That is a *different* field from this discriminator and must not be confused with it; the discriminator lives at the same JSON level, so `CroValuation`'s own `model` key would collide. Rename `CroValuation.model` to `redemptionModel` in this task, and update `owner-state.json`'s `cro` block and `contracts/schema/card-catalogue.schema.json` accordingly. If any test references `CroValuation.model`, update it.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Engine && swift test --filter ProgramValuationTests`
Expected: PASS — all six.

- [ ] **Step 5: Run the full suite**

Run: `cd Engine && swift test`
Expected: PASS. The `CroValuation.model` rename is the only thing that can break existing tests; fix any references.

- [ ] **Step 6: Commit**

```bash
git add Engine/Sources/CardCopilotEngine/Models/ProgramValuation.swift \
        Engine/Sources/CardCopilotEngine/Models/OwnerState.swift \
        Engine/Sources/CardCopilotEngine/Resources/owner-state.json \
        Engine/Tests/CardCopilotEngineTests/ProgramValuationTests.swift
git commit -m "feat(engine): ProgramValuation sum type on a model discriminator

Mirrors Earn's existing type-discriminated Codable. Each valuation model keeps
its own shape rather than flattening into anonymous factors, which the
valuation-disclosure UI depends on. Unknown model is a hard decode failure.

Renames CroValuation.model to redemptionModel to free the discriminator key."
```

---

### Task 4: `Valuations` becomes a keyed dictionary with dual-shape decode

**Files:**
- Modify: `Engine/Sources/CardCopilotEngine/Models/OwnerState.swift:87-94`
- Test: `Engine/Tests/CardCopilotEngineTests/ProgramValuationTests.swift` (extend)

**Interfaces:**
- Consumes: `ProgramValuation` from Task 3.
- Produces: `Valuations` with `public var programs: [String: ProgramValuation]`, `subscript(programId: String) -> ProgramValuation?`, and a `Codable` conformance accepting **either** the legacy named-field object **or** `{"programs": {...}}`, always encoding the latter.

- [ ] **Step 1: Write the failing test**

Append to `ProgramValuationTests.swift`:

```swift
extension ProgramValuationTests {

    /// Every wallet already on a device is written in the legacy shape. Failing to read it would
    /// evict the owner's declared valuations on upgrade.
    func testLegacyNamedFieldShapeStillDecodes() throws {
        let legacy = Data("""
        {
          "amexMembershipRewards": {"centsPerPoint": 1.0, "floorCentsPerPoint": 1.0},
          "marriottBonvoy": {"centsPerPoint": 0.8},
          "mbnaRewards": {"centsPerPoint": 1.0},
          "ctMoney": {"cadPerUnit": 1.0, "optionalUsabilityFactor": 0.95,
                      "usabilityFactorApplied": true},
          "cro": {"redemptionModel": "reward-currency", "faceValueFactorIfAutoSold": 1.0,
                  "defaultHeldRiskFactor": 0.8},
          "cashBack": {"cadPerDollar": 1.0}
        }
        """.utf8)
        let v = try JSONDecoder().decode(Valuations.self, from: legacy)

        guard case .points(let amex) = try XCTUnwrap(v["amexMembershipRewards"])
        else { return XCTFail("expected .points") }
        XCTAssertEqual(amex.centsPerPoint, 1.0)

        guard case .cashback(let cash) = try XCTUnwrap(v["cashback"])
        else { return XCTFail("expected .cashback") }
        XCTAssertEqual(cash.cadPerDollar, 1.0)

        guard case .cro(let cro) = try XCTUnwrap(v["cro"]) else { return XCTFail("expected .cro") }
        XCTAssertEqual(cro.defaultHeldRiskFactor, 0.8)
    }

    func testNewProgramsShapeDecodes() throws {
        let modern = Data("""
        {"programs": {"aeroplan": {"model": "points", "centsPerPoint": 1.9}}}
        """.utf8)
        let v = try JSONDecoder().decode(Valuations.self, from: modern)
        guard case .points(let p) = try XCTUnwrap(v["aeroplan"])
        else { return XCTFail("expected .points") }
        XCTAssertEqual(p.centsPerPoint, 1.9)
    }

    /// Legacy in, modern out — so a wallet upgrades itself the first time it is written back.
    func testLegacyShapeReEncodesAsProgramsDictionary() throws {
        let legacy = Data("""
        {"cashBack": {"cadPerDollar": 1.0}}
        """.utf8)
        let decoded = try JSONDecoder().decode(Valuations.self, from: legacy)
        let reencoded = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(decoded)) as? [String: Any]
        XCTAssertNotNil(reencoded?["programs"])
        XCTAssertNil(reencoded?["cashBack"])
    }

    /// The legacy file's `cashBack` key is `cashback` as a programId — the catalogue spells it
    /// lowercase. A mismatch here would silently unvalue every cash-back card.
    func testLegacyCashBackKeyMapsToCatalogueProgramId() throws {
        let legacy = Data(#"{"cashBack": {"cadPerDollar": 1.0}}"#.utf8)
        let v = try JSONDecoder().decode(Valuations.self, from: legacy)
        XCTAssertNotNil(v["cashback"], "catalogue programId is 'cashback', not 'cashBack'")
    }

    /// owner-state.json carries a `rogersEligibleServiceRedemption` block that is not a catalogue
    /// programId and has no ProgramValuation model. It must be ignored, not a decode failure.
    func testUnknownLegacyKeyIsIgnoredNotFatal() throws {
        let legacy = Data("""
        {"cashBack": {"cadPerDollar": 1.0},
         "rogersEligibleServiceRedemption": {"redemptionFactor": 1.5, "appliedAtCheckout": false}}
        """.utf8)
        let v = try JSONDecoder().decode(Valuations.self, from: legacy)
        XCTAssertNotNil(v["cashback"])
        XCTAssertNil(v["rogersEligibleServiceRedemption"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Engine && swift test --filter ProgramValuationTests`
Expected: FAIL to compile — `Valuations` has no `subscript` and no `programs`.

- [ ] **Step 3: Write minimal implementation**

Replace `Valuations` in `OwnerState.swift` (currently `:87-94`):

```swift
/// Reward-currency valuations, keyed by the catalogue's `programId`.
///
/// Was six hardcoded properties, which made every new rewards program a Swift change, a Kotlin
/// change, a schema-enum change and an owner-state migration. Ten programs shipped in the
/// catalogue against six properties before this was fixed, and every card on the other ten
/// scored $0.00.
public struct Valuations: Equatable, Sendable {
    public var programs: [String: ProgramValuation]

    public init(programs: [String: ProgramValuation] = [:]) {
        self.programs = programs
    }

    public subscript(programId: String) -> ProgramValuation? {
        get { programs[programId] }
        set { programs[programId] = newValue }
    }
}

extension Valuations: Codable {
    private enum Keys: String, CodingKey { case programs }

    /// Legacy owner states name each program as its own key at the top level. New ones nest a
    /// `programs` dictionary. Both decode; only the latter is written back, so a wallet upgrades
    /// itself on first save. Delete the legacy branch one full release cycle after ship, with a
    /// dated entry in contracts/CHANGELOG.md.
    private static let legacyKeyToProgramId: [String: String] = [
        "amexMembershipRewards": "amexMembershipRewards",
        "marriottBonvoy": "marriottBonvoy",
        "mbnaRewards": "mbnaRewards",
        "ctMoney": "ctMoney",
        "cro": "cro",
        "cashBack": "cashback",   // catalogue spells this programId lowercase
    ]

    private static let legacyModel: [String: String] = [
        "amexMembershipRewards": "points", "marriottBonvoy": "points", "mbnaRewards": "points",
        "ctMoney": "ctMoney", "cro": "cro", "cashBack": "cashback",
    ]

    public init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: Keys.self),
           let programs = try? keyed.decode([String: ProgramValuation].self, forKey: .programs) {
            self.init(programs: programs)
            return
        }
        // Legacy shape: re-read as raw JSON and inject the model discriminator each block lacks.
        let raw = try decoder.singleValueContainer().decode([String: [String: JSONPrimitive]].self)
        var programs: [String: ProgramValuation] = [:]
        for (legacyKey, body) in raw {
            guard let programId = Self.legacyKeyToProgramId[legacyKey],
                  let model = Self.legacyModel[legacyKey] else { continue }  // unknown block: ignore
            var object = body
            object["model"] = .string(model)
            let data = try JSONEncoder().encode(object)
            programs[programId] = try JSONDecoder().decode(ProgramValuation.self, from: data)
        }
        self.init(programs: programs)
    }

    public func encode(to encoder: Encoder) throws {
        var keyed = encoder.container(keyedBy: Keys.self)
        try keyed.encode(programs, forKey: .programs)
    }
}

/// Minimal JSON value, used only to re-serialise a legacy valuation block with an injected
/// `model` key. Not a general-purpose type — do not extend it for other uses.
enum JSONPrimitive: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else { self = .string(try c.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v):   try c.encode(v)
        case .null:          try c.encodeNil()
        }
    }
}
```

- [ ] **Step 4: Run the new tests**

Run: `cd Engine && swift test --filter ProgramValuationTests`
Expected: PASS — all eleven.

- [ ] **Step 5: Fix compilation across the package**

`Scorer.valueCad` still reads `valuations.amexMembershipRewards` and will not compile. Change it minimally *for now* — Task 6 rewrites it properly:

```swift
        switch program {
        case "amexMembershipRewards", "marriottBonvoy", "mbnaRewards":
            guard case .points(let v)? = valuations[program] else { return 0.0 }
            return units * cents(v) / 100
        case "ctMoney":
            guard case .ctMoney(let v)? = valuations[program] else { return 0.0 }
            return units * v.cadPerUnit * (v.usabilityFactorApplied ? v.optionalUsabilityFactor : 1)
        case "cro":
            guard case .cro(let v)? = valuations[program] else { return 0.0 }
            return units * (state.croHandling == "autoSell"
                            ? v.faceValueFactorIfAutoSold : v.defaultHeldRiskFactor)
        case "cashback":
            guard case .cashback(let v)? = valuations[program] else { return 0.0 }
            return units * v.cadPerDollar
        default: return 0.0
        }
```

Update `PinnedOwnerState.swift` and any test constructing `Valuations(...)` positionally.

- [ ] **Step 6: Run the full suite — the fixture gate**

Run: `cd Engine && swift test`
Expected: PASS, **including all 27 `FixtureHarnessTests` cases unchanged.** This is the proof that the refactor is behaviour-preserving. If any fixture's expected value moved, stop: the legacy decode is losing a valuation. Do not update the fixture.

- [ ] **Step 7: Commit**

```bash
git add Engine/Sources/CardCopilotEngine/Models/OwnerState.swift \
        Engine/Sources/CardCopilotEngine/Engine/Scorer.swift \
        Engine/Tests/CardCopilotEngineTests/
git commit -m "feat(engine): Valuations keyed by programId, dual-shape decode

Six hardcoded properties become [String: ProgramValuation]. Legacy named-field
owner states still decode and are rewritten in the new shape on first save, so
no device loses its declared valuations on upgrade.

All 27 golden fixtures pass unchanged, which is the proof this is
behaviour-preserving for the six programs that already had valuations."
```

---

### Task 5: `contracts/programs.json` — catalogue-level default valuations

Without catalogue defaults, adding a program stays a two-place change: the catalogue *and* every owner-state file. This is what makes a new program a single data edit.

**Files:**
- Create: `contracts/programs.json`, `contracts/schema/programs.schema.json`
- Modify: `Engine/Sources/CardCopilotEngine/Loading/SeedLoader.swift`, both sync scripts, `Engine/Tests/CardCopilotEngineTests/ContractsSyncTests.swift`, `contracts/CHANGELOG.md`, `contracts/card-catalogue.json` (version bump only)
- Test: `Engine/Tests/CardCopilotEngineTests/SeedLoaderTests.swift` (extend)

**Interfaces:**
- Consumes: `ProgramValuation` (Task 3), `Valuations` (Task 4).
- Produces: `SeedLoader.loadPrograms() throws -> ProgramCatalogue`, where
  `public struct ProgramCatalogue: Codable, Equatable, Sendable { public var programsVersion: String; public var defaults: [String: ProgramValuation] }`.

- [ ] **Step 1: Write `contracts/programs.json`**

Ten new defaults, plus the six existing programs so the file is the single authority. **Every `basis` must state the source and that it is an assumption** — these are disclosed assumptions, not facts, and the UI renders them.

```json
{
  "programsVersion": "1.0",
  "_provenance": "Defaults are DISCLOSED ASSUMPTIONS, not issuer facts. Each basis names its source. Owner state overrides any entry; see docs/plans/2026-08-20-catalogue-scalability-program-design.md §3.1.",
  "defaults": {
    "cashback":              {"model": "cashback", "cadPerDollar": 1.0},
    "amexMembershipRewards": {"model": "points", "centsPerPoint": 1.0, "floorCentsPerPoint": 1.0, "aspirationalCentsPerPoint": 2.2, "basis": "Cash floor (statement credit). Aspirational is the published Canadian benchmark, used only as a plausibility ceiling for upside disclosure, never for ranking."},
    "marriottBonvoy":        {"model": "points", "centsPerPoint": 0.8, "low": 0.6, "high": 1.0, "basis": "Hotel award nights actually used."},
    "mbnaRewards":           {"model": "points", "centsPerPoint": 1.0, "floorCentsPerPoint": 0.833333, "basis": "Travel redemption; cash floor."},
    "ctMoney":               {"model": "ctMoney", "cadPerUnit": 1.0, "optionalUsabilityFactor": 0.95, "usabilityFactorApplied": true},
    "cro":                   {"model": "cro", "redemptionModel": "reward-currency", "faceValueFactorIfAutoSold": 1.0, "defaultHeldRiskFactor": 0.8}
  }
}
```

**The ten new programs are deliberately absent from this first commit.** Adding them requires researched, sourced valuations, which is Task 7's job and needs a human. Shipping a guessed default would be exactly the failure this program exists to prevent — a number the owner cannot check, silently deciding recommendations.

- [ ] **Step 2: Write the failing test**

Append to `SeedLoaderTests.swift`:

```swift
extension SeedLoaderTests {
    func testLoadsProgramDefaults() throws {
        let programs = try SeedLoader.loadPrograms()
        XCTAssertEqual(programs.programsVersion, "1.0")
        guard case .cashback(let cash) = try XCTUnwrap(programs.defaults["cashback"])
        else { return XCTFail("expected .cashback") }
        XCTAssertEqual(cash.cadPerDollar, 1.0)
    }

    /// Owner overrides win; catalogue defaults fill the gaps. Neither alone is enough:
    /// defaults-only ignores the owner's declared value, overrides-only leaves new programs unvalued.
    func testOwnerOverrideBeatsCatalogueDefault() throws {
        let defaults = try SeedLoader.loadPrograms().defaults
        var owner = Valuations(programs: defaults)
        owner["cashback"] = .cashback(CashBackValuation(cadPerDollar: 0.5))
        guard case .cashback(let cash) = try XCTUnwrap(owner["cashback"])
        else { return XCTFail("expected .cashback") }
        XCTAssertEqual(cash.cadPerDollar, 0.5)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd Engine && swift test --filter SeedLoaderTests`
Expected: FAIL to compile — no `loadPrograms`.

- [ ] **Step 4: Implement**

Add to `SeedLoader.swift`:

```swift
    /// Catalogue-level default valuations. Owner state overrides any entry; a program present
    /// here is scoreable the moment a card declares it, with no owner-state edit.
    public static func loadPrograms() throws -> ProgramCatalogue {
        try load("programs")
    }
```

Add `ProgramCatalogue` to `ProgramValuation.swift`:

```swift
/// Catalogue-shipped default valuations, keyed by `programId`.
public struct ProgramCatalogue: Codable, Equatable, Sendable {
    public var programsVersion: String
    public var defaults: [String: ProgramValuation]

    public init(programsVersion: String = "1.0", defaults: [String: ProgramValuation] = [:]) {
        self.programsVersion = programsVersion
        self.defaults = defaults
    }
}
```

Add to both sync scripts, beside the existing `cp` lines:

```bash
cp "$root/contracts/programs.json" \
   "$root/Engine/Sources/CardCopilotEngine/Resources/programs.json"
```

```bash
cp "$root/contracts/programs.json" "$res_main/programs.json"
```

Add `programs.json` to `ContractsSyncTests`' checked file list. Write `contracts/schema/programs.schema.json` documenting `programsVersion`, `_provenance`, and `defaults` as an object whose values are the four `model` variants. Bump `catalogueVersion` `"1.2"` → `"1.3"` in `contracts/card-catalogue.json`, and add a dated `contracts/CHANGELOG.md` entry.

- [ ] **Step 5: Sync and run everything**

```bash
./scripts/sync-contracts-into-engine.sh
./scripts/sync-contracts-into-android.sh
cd Engine && swift test && cd ../Store && swift test
```
Expected: PASS, all 27 fixtures unchanged.

- [ ] **Step 6: Commit**

```bash
git add contracts/ scripts/ Engine/
git commit -m "feat(contracts): programs.json — catalogue-level default valuations

Owner state overrides any entry. Without defaults, adding a program stays a
two-place change: the catalogue and every owner-state file.

The ten unvalued programs are deliberately absent — a guessed default is a
number the owner cannot check silently deciding recommendations, which is the
failure this work exists to prevent. They land in Task 7 with sourced bases."
```

---

### Task 6: `Scorer.valueCad` returns an outcome; unsupported programs exclude the card

**Files:**
- Modify: `Engine/Sources/CardCopilotEngine/Engine/Scorer.swift:3-6` (the `Warning` enum) and `:112-139`
- Test: `Engine/Tests/CardCopilotEngineTests/ScorerTests.swift` (extend)

> ### ✅ RESOLVED 2026-08-20 — was: programs.json is never wired into production
>
> **Closed before Task 6 started.** `RecommendationEngine.init` now merges catalogue defaults
> beneath the owner's own declarations via `OwnerState.applyingCatalogueValuationDefaults()`,
> backed by `SeedLoader.programValuationDefaults`. Covered by `CatalogueDefaultValuationTests`,
> whose cases each remove a program from the owner state first — against the shipped seed the
> merge is a no-op, so a test written against it would pass with the wiring deleted.
>
> The original finding, kept because it explains why the merge point is where it is:
>
> **Nothing in this plan ever wired `contracts/programs.json` into the production path.**
> `SeedLoader.loadPrograms()` is called in exactly two places across all eleven tasks, and both
> are tests: one assertion in Task 5, and the `seedWithAllCardsOwned` helper in Task 7 Step 4.
> No production code path merges catalogue defaults under owner-state overrides.
>
> **Why it bites here.** Task 6 makes an unvalued program *exclude* the card. Task 7 then adds the
> ten valuations to `programs.json` and proves the fix with a test whose owner state is built as
> `Valuations(programs: try SeedLoader.loadPrograms().defaults)`. That test passes. But the app
> calls `loadOwnerState()`, which returns owner-state.json's six programs — so on shipped code the
> same 14 cards would flip from silently scoring $0.00 to being visibly excluded, with the suite
> green throughout and a passing test asserting the opposite. Same 14 cards, new symptom, now with
> cover.
>
> **The decision was *where* the merge belongs**, and the two candidates were not equivalent:
>
> - `SeedLoader.loadOwnerState()` — smallest change, closest to this plan's shape, but owner states
>   loaded from a device through `Store`'s `AccountOwnerStateStore` bypass it entirely. That is
>   every real user, so it would fix the seed and nobody else. **Rejected for that reason.**
> - `RecommendationEngine.init` — **chosen.** Every scoring path funnels through it:
>   PortfolioAnalyzer, RecurringAuditor, CategoryPickerAdvisor and Store's CheckoutService all
>   construct one, and `Scorer.score` has exactly one caller, which is inside it. Deliberately NOT
>   hidden inside `Scorer.valueCad`, which takes `valuations` as an explicit parameter and must
>   stay a pure function of it — Task 6's `testValueCadDistinguishesUnvaluedFromWorthless` builds
>   a bare `Valuations()` and would otherwise silently pick up catalogue defaults.
>
> **Timing argument for doing it before Task 7, not with it** — the reason it landed now: Merging defaults under owner-state
> overrides is *provably a no-op today* — verified 2026-08-20: `programs.json` and
> `owner-state.json` value exactly the same six programs and the owner wins every key, so the
> merged `Valuations` is equal to the owner's. Landing the wiring while it is still a no-op lets
> the 27 golden fixtures prove the wiring alone. Landing it together with Task 7's ten new
> valuations means wiring and data change in one commit, and the gate can no longer isolate which
> one moved a number.

**Interfaces:**
- Consumes: `Valuations` subscript (Task 4).
- Produces: `Warning` gains `.unsupportedProgram` and `.unsupportedCapability`. `Scorer.valueCad(units:program:valuations:state:band:) -> Double?` — `nil` means "no valuation for this program", distinct from `0.0` which means "worth nothing". `Scorer.score` returns an excluded `CandidateScore` with `exclusionReason` naming the program.

- [ ] **Step 1: Write the failing test**

```swift
extension ScorerTests {

    /// A program with no valuation must exclude the card, not value it at $0.00. Scoring zero
    /// makes an unscoreable card silently rank last behind every cash-back card, which reads to
    /// the owner as advice rather than as the refusal it actually is.
    func testUnvaluedProgramExcludesRatherThanScoringZero() throws {
        var card = try XCTUnwrap(SeedLoader.loadCatalogue().cards
            .first { $0.cardId == "scotia-momentum-vi-plus" })
        card.program = Program(programId: "programTheEngineHasNeverHeardOf", unit: "point")

        let score = Scorer.score(card: card,
                                 purchase: PurchaseContext(amountCad: 100, category: "grocery"),
                                 ownerState: PinnedOwnerState.make(), asOf: "2026-08-20")

        XCTAssertTrue(score.excluded)
        XCTAssertTrue(score.warnings.contains(.unsupportedProgram))
        XCTAssertEqual(score.netValueCad, 0)
        XCTAssertTrue(try XCTUnwrap(score.exclusionReason).contains("programTheEngineHasNeverHeardOf"),
                      "the reason must name the program so the gap is diagnosable")
    }

    /// nil (no valuation) and 0.0 (valued at nothing) are different answers.
    func testValueCadDistinguishesUnvaluedFromWorthless() {
        var valuations = Valuations()
        valuations["worthless"] = .cashback(CashBackValuation(cadPerDollar: 0.0))

        XCTAssertEqual(Scorer.valueCad(units: 100, program: "worthless",
                                       valuations: valuations, state: CardState()), 0.0)
        XCTAssertNil(Scorer.valueCad(units: 100, program: "absent",
                                     valuations: valuations, state: CardState()))
    }
}
```

`CardProduct.program` is a `var`, so the mutation in the first test compiles. `Program` needs a `public init(programId:unit:)` — add one if absent.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Engine && swift test --filter ScorerTests`
Expected: FAIL — `valueCad` returns non-optional `Double`; no `.unsupportedProgram` case.

- [ ] **Step 3: Implement**

Extend `Warning`:

```swift
public enum Warning: String, Codable, Equatable, Sendable {
    case drawerCard, unresolvedOwnerState, networkNotAccepted,
         capNearlyExhausted, negativeNetValue, fxAllowanceAssumed, hypotheticalSelection,
         /// This card's rewards program has no valuation. The card cannot be scored at all —
         /// distinct from being scored and losing.
         unsupportedProgram,
         /// An earn rule requires an engine capability this build does not have. The rule is
         /// skipped; the card is still scored on its remaining rules.
         unsupportedCapability
}
```

Make `valueCad` optional-returning:

```swift
    /// Nil means the program has no valuation — the card cannot be scored. Zero means the
    /// program is valued and this earn is worth nothing. Conflating them is how ten programs
    /// silently ranked last for four release batches.
    static func valueCad(units: Double, program: String,
                         valuations: Valuations, state: CardState,
                         band: ValuationBand = .declared) -> Double? {
        func cents(_ v: PointValuation) -> Double {
            switch band {
            case .declared: return v.centsPerPoint
            case .floor: return v.floorCentsPerPoint ?? v.centsPerPoint
            case .aspirational: return max(v.aspirationalCentsPerPoint ?? v.centsPerPoint,
                                           v.centsPerPoint)
            }
        }
        guard let valuation = valuations[program] else { return nil }
        switch valuation {
        case .points(let v):   return units * cents(v) / 100
        case .cashback(let v): return units * v.cadPerDollar
        case .ctMoney(let v):
            return units * v.cadPerUnit * (v.usabilityFactorApplied ? v.optionalUsabilityFactor : 1)
        case .cro(let v):
            return units * (state.croHandling == "autoSell"
                            ? v.faceValueFactorIfAutoSold : v.defaultHeldRiskFactor)
        }
    }
```

In `Scorer.score`, immediately after the rule resolves and before computing `gross`, add:

```swift
        guard Scorer.valueCad(units: 0, program: card.program.programId,
                              valuations: ownerState.valuationsCad, state: state) != nil else {
            return excludedScore(.unsupportedProgram,
                                 "no valuation for program \(card.program.programId)")
        }
```

Then force-unwrap the three `valueCad` calls at `:72`, `:74`, `:77` — the guard above proves they are non-nil. Use `!` with a comment rather than `?? 0`, so a future refactor that breaks the invariant crashes in tests instead of silently zeroing.

- [ ] **Step 4: Run tests**

Run: `cd Engine && swift test`
Expected: PASS, all 27 fixtures unchanged — every fixture card is on one of the six valued programs.

- [ ] **Step 5: Commit**

```bash
git add Engine/
git commit -m "feat(engine): unvalued programs exclude the card instead of scoring zero

valueCad returns Double? — nil is 'no valuation', 0.0 is 'valued at nothing'.
Conflating them is why 14 cards silently ranked last behind every cash-back
card for four release batches."
```

---

### Task 7: Populate the ten missing program valuations

**Blocked on a human.** Each default is a disclosed assumption an owner will see, so it needs a source, not a guess. Do not invent numbers.

**Files:**
- Modify: `contracts/programs.json`, `contracts/CHANGELOG.md`, `Engine/Tests/CardCopilotEngineTests/CatalogueIntegrityTests.swift`

- [ ] **Step 1: Research and record a sourced default for each**

`scenePlus` · `aeroplan` · `rbcAvion` · `tdRewards` · `bmoRewards` · `aventura` · `nbcRewards` · `pcOptimum` · `westJetPoints` · `amazonRewards`.

Each entry needs `model`, its valuation figure, and a `basis` naming the source and stating it is an assumption. Where a program has a guaranteed cash-out floor, set `floorCentsPerPoint` — the floor is what the valuation-sensitivity disclosure ranks against.

- [ ] **Step 2: Delete the allowlist entries**

Remove all ten from `CatalogueIntegrityTests.knownUnvaluedPrograms`, leaving `static let knownUnvaluedPrograms: Set<String> = []`, and change `testKnownGapListsDoNotGrow`'s bound from `10` to `0`.

- [ ] **Step 3: Run everything**

```bash
./scripts/sync-contracts-into-engine.sh && ./scripts/sync-contracts-into-android.sh
cd Engine && swift test && cd ../Store && swift test
```
Expected: PASS. `CatalogueIntegrityTests.testEveryProgramIdIsValuedOrKnownUnvalued` now passes with an empty allowlist.

- [ ] **Step 4: Verify the 14 cards actually score**

Add to `CatalogueIntegrityTests`:

```swift
    /// The headline outcome: no card in the catalogue is structurally unable to be scored.
    func testNoCatalogueCardIsExcludedForAnUnvaluedProgram() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try OwnerState.seedWithAllCardsOwned(catalogue: catalogue)
        let purchase = PurchaseContext(amountCad: 100, category: "other")
        for card in catalogue.cards {
            let score = Scorer.score(card: card, purchase: purchase,
                                     ownerState: owner, asOf: "2026-08-20")
            XCTAssertFalse(score.warnings.contains(.unsupportedProgram),
                           "\(card.cardId) still has no valuation")
        }
    }
```

Add the `OwnerState.seedWithAllCardsOwned(catalogue:)` test helper to `PinnedOwnerState.swift`: it returns `PinnedOwnerState.make()` with `ownedCardIds` set to every `cardId` and `valuationsCad` set to `Valuations(programs: try SeedLoader.loadPrograms().defaults)`.

> **⚠ This helper is the one place `loadPrograms()` reaches the scoring path, and it is a test.**
> **Superseded 2026-08-20.** The merge is now wired into `RecommendationEngine.init`, so this
> helper should no longer hand-assemble `Valuations(programs: loadPrograms().defaults)` — doing so
> would re-create the very blind spot it used to hide, testing the defaults rather than the path
> that reads them. Build it as `PinnedOwnerState.make()` with every `cardId` owned and leave
> `valuationsCad` alone; the engine supplies the defaults. See the resolved callout in Task 6.

- [ ] **Step 5: Commit**

```bash
git add contracts/ Engine/
git commit -m "feat(contracts): sourced default valuations for the ten unvalued programs

Every card in the catalogue now produces a real number. knownUnvaluedPrograms
is empty and the ratchet is set to zero, so a future card on a new program
fails CI at authoring time rather than shipping as a silent \$0.00."
```

---

### Task 8: `EngineCapability`, `requires` / `outOfScope`, and rule gating

**Files:**
- Create: `Engine/Sources/CardCopilotEngine/Models/EngineCapability.swift`, `Engine/Tests/CardCopilotEngineTests/CapabilityGatingTests.swift`
- Modify: `Engine/Sources/CardCopilotEngine/Models/CatalogueModels.swift:62-74`, `Engine/Sources/CardCopilotEngine/Engine/RuleMatcher.swift:22-31`

**Interfaces:**
- Consumes: `Warning.unsupportedCapability` (Task 6).
- Produces: `enum EngineCapability: String` with `static let supported: Set<EngineCapability>`; `EarnRule.requires: [String]?` and `EarnRule.outOfScope: OutOfScope?` where `public struct OutOfScope: Codable, Equatable, Sendable { public var reason: String }`; `RuleMatcher.isLive` gates on both.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CardCopilotEngine

final class CapabilityGatingTests: XCTestCase {

    private func rule(requires: [String]? = nil, outOfScope: OutOfScope? = nil) -> EarnRule {
        EarnRule(ruleId: "r", status: .current, effectiveFrom: nil, effectiveTo: nil,
                 sourceType: .issuerConfirmed, earn: .cashback(rate: 0.02, rewardCurrency: nil),
                 predicate: Predicate(), capId: nil, ownerConditions: nil, scoredInV1: nil,
                 requires: requires, outOfScope: outOfScope)
    }

    func testRuleRequiringASupportedCapabilityIsLive() {
        XCTAssertTrue(RuleMatcher.isLive(rule(requires: ["cap.calendarYear"]), asOf: "2026-08-20"))
    }

    func testRuleRequiringAnUnsupportedCapabilityIsNotLive() {
        XCTAssertFalse(RuleMatcher.isLive(rule(requires: ["cap.statementYear"]), asOf: "2026-08-20"))
    }

    /// An unknown capability string is a data error and must fail closed — never be assumed
    /// supported because the engine does not recognise it.
    func testUnknownCapabilityStringIsNotLive() {
        XCTAssertFalse(RuleMatcher.isLive(rule(requires: ["cap.inventedYesterday"]),
                                          asOf: "2026-08-20"))
    }

    func testOutOfScopeRuleIsNeverLive() {
        XCTAssertFalse(RuleMatcher.isLive(
            rule(outOfScope: OutOfScope(reason: "online booking channel")), asOf: "2026-08-20"))
    }

    /// "Not yet" and "never" must stay distinguishable, or a future reader builds a capability
    /// because an out-of-scope rule appeared to ask for it.
    func testOutOfScopeIsNotExpressedAsARequirement() throws {
        let all = try SeedLoader.loadCatalogue().cards.flatMap(\.earnRules)
        for r in all where r.outOfScope != nil {
            XCTAssertNil(r.requires,
                "\(r.ruleId): a permanently out-of-scope rule must not also declare requires")
        }
        for name in all.compactMap(\.requires).flatMap({ $0 }) {
            XCTAssertNotNil(EngineCapability(rawValue: name),
                            "\(name) is not a known EngineCapability")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Engine && swift test --filter CapabilityGatingTests`
Expected: FAIL to compile — no `EngineCapability`, no `requires`, no `OutOfScope`.

- [ ] **Step 3: Implement**

Create `EngineCapability.swift`:

```swift
import Foundation

/// What this engine build can actually do. Earn rules declare what they need; a rule needing
/// something absent here is skipped with a warning rather than scored wrongly.
///
/// Replaces the hand-set `scoredInV1` boolean, which had no machine meaning: nothing checked that
/// a rule marked true was supported, and enabling a capability meant hunting the catalogue for
/// every flag to flip. Adding a case here turns on every rule that declared it, with no catalogue
/// edit — the maintenance burden inverts from O(rules) to O(capabilities).
public enum EngineCapability: String, CaseIterable, Codable, Sendable {
    case capCalendarMonth    = "cap.calendarMonth"
    case capCalendarYear     = "cap.calendarYear"
    case capAccountYear      = "cap.accountYear"
    case capStatementYear    = "cap.statementYear"
    case capGlobalGroup      = "cap.globalGroup"
    case merchantPartnerList = "predicate.merchantPartnerList"
    case mccStrict           = "predicate.mccStrict"
    case unitPerLitre        = "earn.perLitre"
    case marginalEarn        = "earn.marginal"

    /// Capabilities this build implements. The rest are declared so rules can name them and turn
    /// on automatically when they ship. `predicate.channelIdentity` is deliberately absent from
    /// this enum entirely — online booking channels are permanently out of scope for an
    /// at-the-register copilot, so rules needing them use `outOfScope`, not `requires`.
    public static let supported: Set<EngineCapability> = [
        .capCalendarMonth, .capCalendarYear, .capAccountYear,
    ]
}

/// A rule that will never be scored, with the reason. Distinct from `requires`, which means
/// "not yet". Collapsing the two is how someone later builds a capability that was ruled out.
public struct OutOfScope: Codable, Equatable, Sendable {
    public var reason: String
    public init(reason: String) { self.reason = reason }
}
```

Add to `EarnRule` in `CatalogueModels.swift`, after `scoredInV1`:

```swift
    /// Engine capabilities this rule needs. Absent means none. A rule naming a capability this
    /// build lacks is skipped; it turns on by itself when that capability ships.
    public var requires: [String]?
    /// Set when the rule will never be scored. Mutually exclusive with `requires`.
    public var outOfScope: OutOfScope?
```

`EarnRule` has no explicit initialiser, so add a `public init` listing every property in declaration order, matching the test's call above.

Replace `RuleMatcher.isLive`:

```swift
    static func isLive(_ rule: EarnRule, asOf: String) -> Bool {
        if rule.outOfScope != nil { return false }
        guard rule.scoredInV1 != false else { return false }
        if let requires = rule.requires {
            // Unknown strings fail closed: an unrecognised capability is a data error, and
            // assuming support would score a rule the engine cannot honour.
            let needed = requires.map { EngineCapability(rawValue: $0) }
            guard needed.allSatisfy({ $0.map(EngineCapability.supported.contains) ?? false })
            else { return false }
        }
        let fromOk = rule.effectiveFrom.map { $0 <= asOf } ?? true
        let toOk = rule.effectiveTo.map { asOf <= $0 } ?? true
        return fromOk && toOk
    }
```

- [ ] **Step 4: Run tests**

Run: `cd Engine && swift test`
Expected: PASS, all 27 fixtures unchanged — no catalogue rule declares `requires` or `outOfScope` yet.

- [ ] **Step 5: Commit**

```bash
git add Engine/
git commit -m "feat(engine): EngineCapability with requires/outOfScope rule gating

Rules declare what they need; the engine declares what it has; a mismatch skips
the rule instead of scoring it wrongly. Adding a capability turns on every rule
that declared it, with no catalogue edit.

requires means 'not yet'; outOfScope means 'never'. Keeping them distinct is
what stops someone later building channel identity because a rule asked."
```

---

### Task 9: Migrate the 51 `scoredInV1: false` rules to `requires` / `outOfScope`

**Files:**
- Modify: `contracts/card-catalogue.json`, `contracts/schema/card-catalogue.schema.json`, `contracts/CHANGELOG.md`, `Engine/Tests/CardCopilotEngineTests/CapabilityGatingTests.swift`

Assignments come from spec §9.1 and each rule's `_note`.

- [ ] **Step 1: Assign every disabled rule**

For each of the 51 rules carrying `scoredInV1: false`, replace it with the appropriate marker and **keep the `_note`**:

| Blocker in `_note` | Replacement |
|---|---|
| statement-period / annual window | `"requires": ["cap.statementYear"]` |
| first-of-two / global / total-account-spend / monthly billing period tiering | `"requires": ["cap.globalGroup"]` |
| strict issuer-MCC matching | `"requires": ["predicate.mccStrict"]` |
| merchant normalization, partner/qualifying-merchant, provider list | `"requires": ["predicate.merchantPartnerList"]` |
| needs litres / points-per-litre | `"requires": ["earn.perLitre"]` |
| card-marginal earn vs member earn | `"requires": ["earn.marginal"]` |
| online booking channel (Expedia For TD, Amex Travel, CIBC Rewards Centre, aLaCarteTravel) | `"outOfScope": {"reason": "online booking channel; PickMe is an at-the-register copilot"}` |

Specific assignments for the ten rules whose `_note` names no blocker, per spec §9.1: `td-fct-dining-6x`, `td-fct-transit-6x`, `td-fct-recurring-digital-4x` → `cap.statementYear`; `nbc-we-recurring-2x` → `cap.globalGroup`; `nbc-we-a-la-carte-travel-2x` → `outOfScope`; `pc-insiders-joe-fresh-40ppd`, `westjet-rbc-direct-2x` → `predicate.merchantPartnerList`; `amazon-ca-prime-2_5x`, `amazon-ca-nonprime-1_5x` → leave `scoredInV1: false` with a `_note` saying they are unblocked by `CardState.flags` in the next plan.

**`scotia-gold-gas-transit-3x` needs a human answer** (spec §9.1) — leave it as `scoredInV1: false` and add `"_note": "Blocker unconfirmed; may be enableable — plain category predicate on a supported calendarYear cap. Verify against Scotia terms."`

- [ ] **Step 2: Update the schema**

Document `requires` (array of `EngineCapability` raw values) and `outOfScope` (object with required `reason`) in `contracts/schema/card-catalogue.schema.json`. Mark `scoredInV1` `"x-status": "deprecated — superseded by requires/outOfScope"`. Change `ownerConditions.items` from a closed `enum` to a documented open `string`, matching how benefits `family`/`kind` are handled.

- [ ] **Step 3: Add the regression test**

```swift
extension CapabilityGatingTests {
    /// Every rule the engine skips must say why in a machine-readable way. A bare
    /// scoredInV1:false carries no reason and cannot turn itself on when the blocker is fixed.
    func testNoRuleIsDisabledWithoutAMachineReadableReason() throws {
        let allowed: Set<String> = [
            "scotia-gold-gas-transit-3x",      // spec §9.1 — blocker unconfirmed
            "amazon-ca-prime-2_5x",            // unblocked by CardState.flags, next plan
            "amazon-ca-nonprime-1_5x",
        ]
        let bare = try SeedLoader.loadCatalogue().cards
            .flatMap(\.earnRules)
            .filter { $0.scoredInV1 == false && $0.requires == nil && $0.outOfScope == nil }
            .map(\.ruleId)
            .filter { !allowed.contains($0) }
        XCTAssertTrue(bare.isEmpty, "rules disabled with no declared blocker: \(bare.sorted())")
    }
}
```

- [ ] **Step 4: Sync and run**

```bash
./scripts/sync-contracts-into-engine.sh && ./scripts/sync-contracts-into-android.sh
cd Engine && swift test && cd ../Store && swift test
```
Expected: PASS, **all 27 fixtures unchanged.** `requires` on an unsupported capability produces the same skip that `scoredInV1: false` did, so no scoring outcome moves. If a fixture moves, an assignment is wrong.

- [ ] **Step 5: Commit**

```bash
git add contracts/ Engine/ android/
git commit -m "refactor(contracts): scoredInV1 becomes requires/outOfScope

All 51 disabled rules now declare their blocker in a machine-readable form, so
shipping a capability turns them on automatically instead of requiring a hunt
through the catalogue for flags to flip.

Five rules on online booking channels are marked outOfScope — permanently, not
pending. Three rules stay on scoredInV1 pending a human answer or the next plan.
All 27 fixtures unchanged: an unsupported requires skips exactly as the boolean did."
```

---

### Task 10: `RecommendationOutcome`

Task 6 made card exclusion reachable from data, so `RecommendationEngine.swift:54`'s `precondition(!scores.isEmpty)` is now a data-triggered crash for a wallet of entirely unvalued cards.

**Files:**
- Modify: `Engine/Sources/CardCopilotEngine/Engine/RecommendationEngine.swift:47-54`, and all 13 call sites
- Test: `Engine/Tests/CardCopilotEngineTests/CapabilityGatingTests.swift` (extend)

**Interfaces:**
- Produces: `public enum RecommendationOutcome: Sendable { case advised(Recommendation); case cannotAdvise(reasons: [String]) }`; `recommend(_:asOf:) -> RecommendationOutcome`; plus `recommendOrNil(_:asOf:) -> Recommendation?` as a convenience for the three in-Engine call sites that only want `allCandidates`.

- [ ] **Step 1: Write the failing test**

```swift
extension CapabilityGatingTests {
    /// A wallet where nothing can be scored must refuse, not crash and not invent a winner.
    func testWalletOfEntirelyUnvaluedCardsCannotAdvise() throws {
        var catalogue = try SeedLoader.loadCatalogue()
        catalogue.cards = catalogue.cards.map { card in
            var c = card
            c.program = Program(programId: "unknownProgram", unit: "point")
            return c
        }
        var owner = PinnedOwnerState.make()
        owner.ownedCardIds = catalogue.cards.map(\.cardId)

        let outcome = RecommendationEngine(catalogue: catalogue, ownerState: owner)
            .recommend(PurchaseContext(amountCad: 50, category: "grocery"), asOf: "2026-08-20")

        guard case .cannotAdvise(let reasons) = outcome
        else { return XCTFail("expected .cannotAdvise, got \(outcome)") }
        XCTAssertFalse(reasons.isEmpty, "a refusal must say why")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Engine && swift test --filter CapabilityGatingTests`
Expected: **crash** on the precondition, or a compile failure on `.cannotAdvise`. A crashing test is the point — that is the bug.

- [ ] **Step 3: Implement**

```swift
/// Either advice, or an explicit refusal. The engine can now be genuinely unable to advise —
/// a wallet whose every card is on an unvalued program — and inventing a $0.00 winner would
/// present a refusal as advice.
public enum RecommendationOutcome: Sendable {
    case advised(Recommendation)
    case cannotAdvise(reasons: [String])
}
```

In `recommend`, replace the `precondition` with:

```swift
        let scored = candidateCards
            .map { Scorer.score(card: $0, purchase: purchase, ownerState: ownerState, asOf: asOf) }
        let scores = scored.filter { !$0.excluded }
        guard !scores.isEmpty else {
            return .cannotAdvise(reasons: scored.compactMap(\.exclusionReason))
        }
```

Change the return type to `RecommendationOutcome` and wrap the existing return in `.advised(...)`. Add:

```swift
    /// For callers that only want `allCandidates` and treat a refusal as "no candidates".
    public func recommendOrNil(_ purchase: PurchaseContext, asOf: String) -> Recommendation? {
        guard case .advised(let r) = recommend(purchase, asOf: asOf) else { return nil }
        return r
    }
```

Update all 13 call sites:
- In-Engine (`PortfolioAnalyzer.swift:203`, `CategoryPickerAdvisor.swift:154`, `RecurringAuditor.swift:386`) — use `recommendOrNil`, treating `nil` as empty candidates.
- `Store/Sources/CardCopilotStore/CheckoutService.swift:103` — propagate; `CheckoutService.recommend` already `throws`, so throw a new `CheckoutError.cannotAdvise(reasons:)`.
- App/widget/watch/share sites — `if case .advised(let rec)`, with the existing failure UI for the other branch.

- [ ] **Step 4: Run everything**

```bash
cd Engine && swift test && cd ../Store && swift test
```
Expected: PASS, all 27 fixtures unchanged. Update `FixtureHarnessTests` to unwrap `.advised` — the fixtures' *expectations* stay byte-identical; only the harness's unwrapping changes.

- [ ] **Step 5: Commit**

```bash
git add Engine/ Store/ App/
git commit -m "feat(engine): recommend returns RecommendationOutcome

Excluding unvalued cards made precondition(!scores.isEmpty) reachable from data.
A wallet of entirely unscoreable cards now refuses explicitly instead of
crashing, and 'I cannot advise you, here is why' becomes expressible."
```

---

### Task 11: Kotlin parity

The catalogue and owner state are a cross-language contract. Android reads the same `owner-state.json` and `card-catalogue.json`, so it breaks on the new shapes until this lands.

**Files:**
- Modify: `android/core/engine/src/main/kotlin/com/cardcopilot/engine/models/OwnerState.kt:96-102`, `.../models/CatalogueModels.kt`, `.../engine/Scorer.kt:144-161`, `.../engine/RuleMatcher.kt`
- Create: `.../models/ProgramValuation.kt`, `.../models/EngineCapability.kt`

- [ ] **Step 1: Port the types**

`ProgramValuation` as a `@Serializable sealed class` with `@SerialName("points"/"cashback"/"ctMoney"/"cro")` subclasses and `classDiscriminator = "model"` on the `Json` instance. `Valuations` as `@Serializable data class Valuations(val programs: Map<String, ProgramValuation> = emptyMap())` with a custom serializer accepting the legacy shape, mirroring Task 4. `EngineCapability` enum with the same raw values and the same `supported` set. `EarnRule` gains `requires: List<String>? = null` and `outOfScope: OutOfScope? = null`.

- [ ] **Step 2: Port the logic**

`Scorer.valueCad` returns `Double?` with the same nil/zero distinction. `RuleMatcher.isLive` gains the same `outOfScope` and `requires` gating.

- [ ] **Step 3: Run the Kotlin fixture harness**

```bash
cd android && ./gradlew :core:engine:test
```
Expected: PASS, all 27 fixture cases unchanged — the same gate as Swift.

- [ ] **Step 4: Commit**

```bash
git add android/
git commit -m "feat(android): Kotlin parity for ProgramValuation and capability gating

Same sum type on the same model discriminator, same legacy-shape decode, same
requires/outOfScope gating. The catalogue is a cross-language contract; Android
reads the same owner-state.json and would fail to decode without this."
```

---

## Self-Review

**Spec coverage.** §3.1 valuations → Tasks 3–7. §3.5 capability system → Tasks 8–9. §3.6 warnings and the reachable crash → Tasks 6, 10. §3.7a/b tolerant and dual-shape decode → Tasks 1, 4. §3.7e Kotlin → Task 11. §3.9 testing → woven through; the "27 fixtures unchanged" gate appears in Tasks 4, 5, 6, 8, 9, 10, 11.

**Deliberately deferred to the next plan, and named in the Scope section:** §3.2 owner conditions, §3.3 cap anchors, §3.4 merchant and presentation registries, §3.8 market/manifest layout, §3.7c/d server coordination and `ownerStateVersion` gating.

**Two spec corrections this plan makes.** §3.6 proposed a new `EngineWarning` type with associated values; `Scorer.swift:3` already has a `Warning` enum and `CandidateScore.exclusionReason` for detail, so this plan extends those instead — smaller, and consistent with the existing pattern. And §3.5's `EngineCapability` listed `predicate.channelIdentity`; per spec §9.3 it is removed entirely, since a capability that exists in the enum invites someone to implement it.

**Known blocked steps:** Task 7 Step 1 needs sourced valuations for ten programs. Task 9 Step 1 needs a human answer on `scotia-gold-gas-transit-3x`. Both are called out at the point of use rather than hidden.
