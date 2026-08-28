# Wallet Editor Redesign + Owner Conditions as Data — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild PickMe's "Edit wallet" screen around the wallet the owner actually holds instead of the whole catalogue, fix three data-losing bugs in the save path, and make an owner condition a data edit rather than a six-file code change.

**Architecture:** The picker stops treating the 133-record catalogue as a menu — it filters to `isPublished` cards in the owner's market (41 today) and moves catalogue browsing into its own sheet. The three-page wizard is deleted; one screen serves both first run and edit, with per-card conditions expanded inline and a checklist banner that persists past onboarding. `OwnerStateBuilder.make` splits into `firstRun` and `apply`, so an edit folds into existing owner state instead of reconstructing it from scratch. Owner conditions move to a new `contracts/owner-conditions.json` registry with answers stored in `CardState.flags`, mirroring the `programs.json` precedent set for valuations.

**Tech Stack:** Swift 5.10 (Engine) / 6.0 (Store), SwiftUI (App, iOS 18), XCTest, SPM resource bundles. Kotlin twin at `android/core/engine` with kotlinx.serialization. JSON Schema (Draft 2020-12) for contracts.

**Spec:** No separate spec file — the design was settled conversationally on 2026-08-28 and is restated in full in "Design Decisions" below. Parent design: [`docs/plans/2026-08-20-catalogue-scalability-program-design.md`](../../plans/2026-08-20-catalogue-scalability-program-design.md) §3.2, which this plan implements with one deliberate divergence recorded in D3.

---

## Design Decisions

These were settled with the product owner before this plan was written. They are not open.

- **D1 — Picker scope.** Published cards only, scoped to market, with a CA / US / Both segmented control. Residency is inferred from `Locale.current.region`, stored in `OwnerState.market`, and corrected in place via that control. "Both" is a device-local view preference and never reaches the engine (`Market` is a closed two-case enum).
- **D2 — No wizard.** One screen for first run and edit. A checklist banner listing unanswered setup items persists after onboarding, because `RuleMatcher` fails closed and an unanswered condition otherwise costs the owner a bonus rate invisibly and permanently.
- **D3 — Registry, not inline objects.** Spec §3.2 changes `EarnRule.ownerConditions` from `[String]` to `[{conditionId, prompt}]`. That is a breaking element-type change requiring `catalogueVersion` MAJOR 2→3 across a content-addressed release with four vendored copies. This plan instead ships a sidecar `contracts/owner-conditions.json`, exactly as `programs.json` solved the identical open-set problem for valuations one section earlier in the same spec. `ownerConditions` stays `[String]`. Additive: MINOR 2.7 → 2.8.
- **D4 — Legacy fields stay for one release.** `CardState.rogersEligibleServiceLinked` and `cryptoLevelUpProActive` are NOT deleted. They remain as legacy storage, mirrored from `flags` on write, folded into `flags` on read. MoneyTalks stores owner state and has not been audited for what it reads; carrying two keys for one release is cheaper than guessing. Deleting them is a follow-up gated on that audit.
- **D5 — Prompts are localized in the app, not the contract.** The registry's `prompt` is the English source string. The app renders `String(localized: "ownerCondition.<id>.prompt", defaultValue: registryPrompt)`. The app ships en + fr-CA across 612 strings; prompts living only in JSON would hand French-Canadian users English questions on a Canadian product. A new condition ships working in English on day one and picks up fr-CA on the next translation pass with no contract release.
- **D6 — Apply immediately.** No Save button in edit mode. Every change writes local owner state at once; server upload is debounced. Card removal shows an undo affordance. First run keeps one explicit commit (`Start using PickMe`) because flipping `walletIsFirstRun` is a real state transition.
- **D7 — No new `Warning` case.** The checklist derives unanswered conditions from catalogue + `flags` in the App layer. A `Warning` case for unresolved conditions would require two exhaustive Swift switches plus the Kotlin explainer for something the UI computes directly.

---

## Global Constraints

Copied verbatim from `CLAUDE.md`, the parent spec's plan, and `.github/workflows/ci.yml`. Every task's requirements implicitly include this section.

- **`contracts/` is canonical.** NEVER edit `Engine/Sources/CardCopilotEngine/Resources/*.json` or `android/core/engine/src/main/resources/**` directly. Edit `contracts/`, then run `scripts/sync-contracts-into-engine.sh` and `scripts/sync-contracts-into-android.sh`. `ContractsSyncTests` fails on byte drift.
- **Fixture changes are API changes.** The 28 existing cases in `contracts/engine-fixtures.json` must pass with their expectations **byte-unchanged**. Any diff is a bug, not an expectation update.
- **`catalogueVersion` MAJOR stays `2`.** Every change here is additive. Bump MINOR `2.7` → `2.8` exactly once, in Task 8. `fixturesVersion` `1.2` → `1.3`, also once, in Task 8.
- **Every contracts edit updates `contracts/CHANGELOG.md`** with a dated entry, newest first.
- **`scripts/release-catalogue.sh` must be re-run** after any contracts change, and its `FILES` list is duplicated in MoneyTalks — note any addition in the CHANGELOG so the hub can follow.
- **Fail closed, never guess.** House rule from `RuleMatcher`: unresolved owner state skips a rule rather than assuming a value. New code follows it.
- **No `Co-Authored-By` trailer on commits.**
- **Point values are disclosed assumptions, not facts.** Any copy touching valuations preserves that framing.
- **Deep analytics and dashboards belong on the web hub** (`ECOSYSTEM.md` A5). This screen stays a control centre.
- **Verification commands** (all must be green before any commit):
  - `cd Engine && swift test`
  - `cd Store && swift test`
  - `cd android && ./gradlew --no-daemon :core:engine:test`
  - `cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot -configuration Debug -destination "id=$SIM_UDID" CODE_SIGNING_ALLOWED=NO`
    - Resolve `SIM_UDID` with `xcrun simctl list devices available | grep iPhone | head -1`.
    - **Never pass `-sdk iphonesimulator`.** It overrides `SDKROOT` for every target including the embedded watch app, and `actool` fails the build before any Swift compiles. Use `-scheme`, never `-target`.
- **`App/CardCopilot.xcodeproj` uses `PBXFileSystemSynchronizedRootGroup`.** New `.swift` files under `App/CardCopilot/Views/` are picked up automatically. Do NOT hand-edit `project.pbxproj`.
- **Another session works in this repo and commits with `git add -A`.** Stage explicitly by path in every commit step. Never `git add -A`, never `git add .`.

---

## Recommended Model and Effort per Phase

The product owner asked for this explicitly. Rationale is what the phase actually demands, not its line count.

| Phase | Tasks | Model | Effort | Why |
|---|---|---|---|---|
| **0 — Save-path bugs** | 1–2 | **Opus 5** | **High** | Reasoning about what must be *preserved* across a state rebuild, where the failure mode is silent data loss rather than a compile error. Getting `apply` subtly wrong reintroduces the bug the phase exists to fix, and the test has to assert absence of loss — the kind of test that is easy to write vacuously. |
| **1 — Picker filtering** | 3 | **Sonnet 5** | **Medium** | A pure function, two new predicates, table-driven tests against known counts. Fully specified, mechanically verifiable. |
| **2 — Conditions as data** | 4–8 | **Opus 5** | **High** | Cross-language contract change with a migration path, a digest-pinned release, and a consumer in another repo. Kotlin and Swift must agree exactly or CI's cross-language fixture gate fails in a way that reads as a scoring bug. Highest blast radius in the plan. |
| **3 — The UI** | 9–13 | **Sonnet 5** | **High** | Volume SwiftUI against a settled design, following existing patterns in `Views/`. Effort is high because of breadth (five files, accessibility, both themes, en + fr-CA), but each decision is already made. Escalate Task 12 to **Opus 5** if the debounce/undo interaction with `CopilotEnvironment` proves fiddly. |

**Overall sequencing:** Phase 0 and Phase 1 are independent of everything else and ship alone — land them first for immediate value. Phase 3 depends on Phase 2 for the registry. Do not start Phase 3 before Phase 2 is green on all four CI jobs.

---

## File Structure

**Created:**

| File | Responsibility |
|---|---|
| `contracts/owner-conditions.json` | The condition registry: id → answer kind, English prompt, detail. The single place a new owner condition is declared. |
| `contracts/schema/owner-conditions.schema.json` | Schema for the above, wired into `scripts/validate-catalogue-schema.py`. |
| `Engine/Sources/CardCopilotEngine/Models/OwnerCondition.swift` | `OwnerCondition`, `OwnerConditionAnswerKind`, `OwnerConditionRegistry`. Separate file because both the engine and the App's setup UI consume it — same reasoning that gave `ProgramValuation.swift` its own file. |
| `Engine/Tests/CardCopilotEngineTests/OwnerConditionRegistryTests.swift` | Registry decode, and that every catalogue `ownerConditions` id resolves. |
| `android/core/engine/src/main/kotlin/com/cardcopilot/engine/models/OwnerCondition.kt` | Kotlin twin of the registry model. |
| `App/CardCopilot/Views/Wallet/WalletEditorView.swift` | The one screen. Owns layout and the apply-immediately write path. |
| `App/CardCopilot/Views/Wallet/AddCardSheet.swift` | Catalogue browsing: search, market scope control, issuer grouping, request form. |
| `App/CardCopilot/Views/Wallet/WalletChecklistBanner.swift` | The persistent "finish setting up" banner and its item derivation. |
| `App/CardCopilot/Views/Wallet/OwnerConditionEditor.swift` | One condition's tri-state row plus Tangerine's category selector. Data-driven from the registry. |
| `App/CardCopilot/Views/Wallet/WalletCardCatalogue.swift` | Pure filtering + grouping + market scope persistence. No SwiftUI, so it is unit-testable. |
| `App/CardCopilotTests/WalletCardCatalogueTests.swift` | Tests for the above. |
| `App/CardCopilotTests/WalletChecklistTests.swift` | Tests for checklist derivation. |
| `Store/Tests/CardCopilotStoreTests/OwnerStateApplyTests.swift` | The regression tests bugs #1 and #2 never had. |

**Modified:**

| File | Change |
|---|---|
| `Engine/Sources/CardCopilotEngine/Models/OwnerState.swift:44-58` | `CardState` gains `flags` and `resolvedFlags`. |
| `Engine/Sources/CardCopilotEngine/Engine/RuleMatcher.swift:94-104` | `conditionsResolveTrue` dispatches through `resolvedFlags`. |
| `Engine/Sources/CardCopilotEngine/Loading/SeedLoader.swift` | `loadOwnerConditions()` + cached `ownerConditions`. |
| `Engine/Tests/CardCopilotEngineTests/CatalogueIntegrityTests.swift:22-28` | `knownUnhandledConditions` → empty; `handledConditions` replaced by a registry check. |
| `Store/Sources/CardCopilotStore/OwnerStateSetup.swift:6-77` | `WalletSetup` reshaped; `make` → `firstRun` + `apply`. |
| `App/CardCopilot/State/CopilotEnvironment.swift:234-236` | Route edits through `apply`; add debounced upload. |
| `App/CardCopilot/Views/CheckoutFlowView.swift:295-304` | Present `WalletEditorView`. |
| `App/CardCopilot/Views/WalletSetupView.swift` | Deleted at the end of Task 12. |
| `App/CardCopilotTests/WalletSetupSearchTests.swift` | Retargeted at `WalletCardCatalogue`. |
| `android/.../models/OwnerState.kt:66-79` | `CardState` gains `flags` and `resolvedFlags`. |
| `android/.../engine/RuleMatcher.kt:121-131` | Kotlin twin of the Swift change. |
| `scripts/sync-contracts-into-engine.sh`, `scripts/sync-contracts-into-android.sh`, `scripts/release-catalogue.sh`, `scripts/validate-catalogue-schema.py` | Add `owner-conditions.json`. |
| `contracts/CHANGELOG.md`, `contracts/card-catalogue.json`, `contracts/engine-fixtures.json`, `contracts/RELEASE.json` | Version bumps, new fixture cases, restamp. |
| `App/CardCopilot/Localizable.xcstrings` | New UI strings + `ownerCondition.*.prompt` keys. |

---

# Phase 0 — Save-path bugs

**Model: Opus 5 · Effort: High.** Ships alone. No contract change, no UI change.

### Task 1: `apply` preserves what a rebuild destroyed

Today `OwnerStateBuilder.make` is a constructor: it builds a fresh `OwnerState` from `WalletSetup` alone, so anything `WalletSetup` cannot express is structurally guaranteed to be lost. Three things fall through that gap — `capProgress` (live data written by `MoneyTalksSync.merging`), `carry`, and `market`. Every "Save changes" from the wallet editor zeroes all three.

**Files:**
- Modify: `Store/Sources/CardCopilotStore/OwnerStateSetup.swift:6-77`
- Test: `Store/Tests/CardCopilotStoreTests/OwnerStateApplyTests.swift` (create)

**Interfaces:**
- Consumes: `OwnerState`, `CardState`, `Carry`, `Catalogue`, `Market` from `CardCopilotEngine`.
- Produces:
  - `WalletSetup.market: Market?`
  - `OwnerStateBuilder.firstRun(setup:catalogue:version:) -> OwnerState`
  - `OwnerStateBuilder.apply(_:to:catalogue:version:) -> OwnerState`
  - `OwnerStateBuilder.make` is removed. Task 2 updates its only production caller.

- [ ] **Step 1: Write the failing test**

Create `Store/Tests/CardCopilotStoreTests/OwnerStateApplyTests.swift`:

```swift
import XCTest
@testable import CardCopilotStore
import CardCopilotEngine

/// `make` rebuilt owner state from setup answers alone, so every "Save changes" zeroed cap
/// progress, emptied carry and dropped market — none of which WalletSetup can express. These
/// tests are the regression guard that absence-of-loss actually holds.
final class OwnerStateApplyTests: XCTestCase {

    private func catalogue() throws -> Catalogue { try SeedLoader.loadCatalogue() }

    /// A wallet with real cap usage, as MoneyTalksSync.merging would leave it.
    /// Cap ids are REAL ones from the catalogue — verify with:
    ///   python3 -c "import json;d=json.load(open('contracts/card-catalogue.json'));
    ///   print([[x['capId'] for x in c.get('caps',[])] for c in d['cards']
    ///   if c['cardId']=='scotia-momentum-vi-plus'])"
    /// scotia-momentum-vi-plus carries TWO caps, which is what makes the
    /// fills-only-untracked-caps test below meaningful.
    private func existingWallet(catalogue: Catalogue) -> OwnerState {
        var state = CardState()
        state.capProgress = ["momentum-4pct-accountYear": 1_250.00]
        return OwnerState(
            ownerStateVersion: "test-1",
            ownedCardIds: ["scotia-momentum-vi-plus", "amex-cobalt"],
            defaultCardId: "amex-cobalt",
            switchThreshold: OwnerStateBuilder.defaultSwitchThreshold,
            carry: Carry(drawerCards: ["amex-cobalt"]),
            cardStates: ["scotia-momentum-vi-plus": state],
            valuationsCad: Valuations(programs: [:]),
            market: "CA")
    }

    func testApplyPreservesCapProgressForCardsStillOwned() throws {
        let catalogue = try catalogue()
        let existing = existingWallet(catalogue: catalogue)
        var setup = OwnerStateBuilder.setup(from: existing)
        setup.ownedCardIds.append("rogers-red-we")   // the edit: add one card

        let result = OwnerStateBuilder.apply(setup, to: existing, catalogue: catalogue)

        XCTAssertEqual(result.cardStates["scotia-momentum-vi-plus"]?
            .capProgress?["momentum-4pct-accountYear"], 1_250.00,
            "adding a card must not reset another card's cap progress")
    }

    /// A cap the owner has no figure for is filled at zero; one already tracked keeps its number.
    /// Both halves matter — the first handles a cap added to the catalogue since the last save,
    /// and a single-cap fixture would never exercise it.
    func testApplyFillsOnlyUntrackedCaps() throws {
        let catalogue = try catalogue()
        let existing = existingWallet(catalogue: catalogue)
        let setup = OwnerStateBuilder.setup(from: existing)

        let result = OwnerStateBuilder.apply(setup, to: existing, catalogue: catalogue)

        let progress = try XCTUnwrap(result.cardStates["scotia-momentum-vi-plus"]?.capProgress)
        XCTAssertEqual(progress["momentum-4pct-accountYear"], 1_250.00)
        XCTAssertEqual(progress["momentum-2pct-accountYear"], 0)
    }

    func testApplyPreservesCarry() throws {
        let catalogue = try catalogue()
        let existing = existingWallet(catalogue: catalogue)
        let setup = OwnerStateBuilder.setup(from: existing)

        let result = OwnerStateBuilder.apply(setup, to: existing, catalogue: catalogue)

        XCTAssertEqual(result.carry.drawerCards, ["amex-cobalt"])
    }

    func testApplyPreservesMarket() throws {
        let catalogue = try catalogue()
        let existing = existingWallet(catalogue: catalogue)
        let setup = OwnerStateBuilder.setup(from: existing)

        let result = OwnerStateBuilder.apply(setup, to: existing, catalogue: catalogue)

        XCTAssertEqual(result.resolvedMarket, .ca)
        XCTAssertEqual(result.market, "CA")
    }

    func testSetupRoundTripsMarket() throws {
        let existing = existingWallet(catalogue: try catalogue())
        XCTAssertEqual(OwnerStateBuilder.setup(from: existing).market, .ca,
                       "market must survive the OwnerState -> WalletSetup projection")
    }

    /// A card the owner did not previously hold has no history to preserve, so it starts clean.
    func testNewlyAddedCardStartsWithZeroedCaps() throws {
        let catalogue = try catalogue()
        let existing = existingWallet(catalogue: catalogue)
        var setup = OwnerStateBuilder.setup(from: existing)
        setup.ownedCardIds.append("scotia-gold-amex")

        let result = OwnerStateBuilder.apply(setup, to: existing, catalogue: catalogue)

        let added = try XCTUnwrap(result.cardStates["scotia-gold-amex"])
        XCTAssertTrue((added.capProgress ?? [:]).values.allSatisfy { $0 == 0 })
    }

    /// First run has nothing to preserve. This is the behaviour `make` documented and got right.
    func testFirstRunStartsEverythingAtZero() throws {
        let catalogue = try catalogue()
        let setup = WalletSetup(ownedCardIds: ["scotia-momentum-vi-plus"],
                                defaultCardId: "scotia-momentum-vi-plus",
                                conditionAnswers: [:],
                                switchThreshold: OwnerStateBuilder.defaultSwitchThreshold,
                                valuationsCad: Valuations(programs: [:]),
                                market: .ca)

        let result = OwnerStateBuilder.firstRun(setup: setup, catalogue: catalogue)

        XCTAssertEqual(result.carry.drawerCards, [])
        XCTAssertTrue((result.cardStates["scotia-momentum-vi-plus"]?.capProgress ?? [:])
            .values.allSatisfy { $0 == 0 })
    }

    /// A removed card's state goes with it — it is not owner history worth keeping.
    func testRemovedCardStateIsDropped() throws {
        let catalogue = try catalogue()
        let existing = existingWallet(catalogue: catalogue)
        var setup = OwnerStateBuilder.setup(from: existing)
        setup.ownedCardIds.removeAll { $0 == "scotia-momentum-vi-plus" }
        setup.defaultCardId = "amex-cobalt"

        let result = OwnerStateBuilder.apply(setup, to: existing, catalogue: catalogue)

        XCTAssertNil(result.cardStates["scotia-momentum-vi-plus"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Store && swift test --filter OwnerStateApplyTests
```

Expected: FAIL to compile — `apply`, `firstRun`, `WalletSetup.market` and `conditionAnswers` do not exist yet. A compile failure is the correct red here; do not stub anything to make it link.

- [ ] **Step 3: Reshape `WalletSetup`**

In `Store/Sources/CardCopilotStore/OwnerStateSetup.swift`, replace the struct at lines 6–29:

```swift
/// The editable projection of an owner's wallet. Deliberately NOT a full `OwnerState`: it carries
/// what a person answers, never what the system observes. Cap progress, carry and account anchors
/// are observations and live only in `OwnerState` — which is precisely why `apply` folds this into
/// an existing state rather than constructing a new one from it.
public struct WalletSetup: Equatable, Sendable {
    public var ownedCardIds: [String]
    public var defaultCardId: String
    /// Boolean owner-condition answers, keyed cardId → conditionId. An absent key is UNANSWERED,
    /// which `RuleMatcher` fails closed on. Never default a missing answer to `false`: "no" and
    /// "not asked" buy the owner different rates and must stay distinguishable.
    public var conditionAnswers: [String: [String: Bool]]
    public var tangerineSelectedCategories: [String]?
    public var switchThreshold: SwitchThreshold
    public var valuationsCad: Valuations
    /// The owner's residency. Nil means unresolved; `OwnerState.resolvedMarket` defaults to `.ca`.
    /// Present here so an edit round-trips it — `make` dropped it, silently resetting every US
    /// owner to Canada on save.
    public var market: Market?

    public init(ownedCardIds: [String], defaultCardId: String,
                conditionAnswers: [String: [String: Bool]] = [:],
                tangerineSelectedCategories: [String]? = nil,
                switchThreshold: SwitchThreshold,
                valuationsCad: Valuations,
                market: Market? = nil) {
        self.ownedCardIds = ownedCardIds
        self.defaultCardId = defaultCardId
        self.conditionAnswers = conditionAnswers
        self.tangerineSelectedCategories = tangerineSelectedCategories
        self.switchThreshold = switchThreshold
        self.valuationsCad = valuationsCad
        self.market = market
    }
}
```

- [ ] **Step 4: Replace `setup(from:)` and `make` with `firstRun` / `apply`**

Replace lines 39–75 of the same file:

```swift
    public static func setup(from ownerState: OwnerState) -> WalletSetup {
        var answers: [String: [String: Bool]] = [:]
        for (cardId, state) in ownerState.cardStates {
            let flags = state.resolvedFlags
            if !flags.isEmpty { answers[cardId] = flags }
        }
        return WalletSetup(
            ownedCardIds: ownerState.ownedCardIds,
            defaultCardId: ownerState.defaultCardId,
            conditionAnswers: answers,
            tangerineSelectedCategories:
                ownerState.cardStates["tangerine-moneyback-world"]?.selectedCategories,
            switchThreshold: ownerState.switchThreshold,
            valuationsCad: ownerState.valuationsCad,
            market: ownerState.market.flatMap(Market.init(rawValue:)))
    }

    /// A wallet built from nothing. Caps start at zero and carry is empty because there is no
    /// history yet — the documented intent of the old `make`, now stated in its name so it can
    /// never be reached from an edit by accident.
    public static func firstRun(setup: WalletSetup, catalogue: Catalogue,
                                version: String = "wallet-setup-1") -> OwnerState {
        apply(setup, to: nil, catalogue: catalogue, version: version)
    }

    /// Fold setup answers INTO an existing wallet. Everything `WalletSetup` cannot express —
    /// cap progress, carry, account anchors, market — is carried across untouched.
    ///
    /// `existing == nil` is first run and reproduces the old `make` exactly.
    public static func apply(_ setup: WalletSetup, to existing: OwnerState?,
                             catalogue: Catalogue,
                             version: String = "wallet-setup-1") -> OwnerState {
        let availableIDs = Set(catalogue.cards.map(\.cardId))
        let owned = Array(NSOrderedSet(array: setup.ownedCardIds))
            .compactMap { $0 as? String }
            .filter { availableIDs.contains($0) }
        let defaultCardId = owned.contains(setup.defaultCardId)
            ? setup.defaultCardId : (owned.first ?? "")

        var cardStates: [String: CardState] = [:]
        for card in catalogue.cards where owned.contains(card.cardId) {
            // Start from what is already known about this card. A card the owner already held
            // keeps its observations; a newly added one starts clean, which is correct.
            var state = existing?.cardStates[card.cardId] ?? CardState()

            let capIDs = card.caps.map(\.capId)
            if !capIDs.isEmpty {
                var progress = state.capProgress ?? [:]
                // Fill only caps we have no figure for. A cap added to the catalogue since the
                // last save appears at zero; one already tracked keeps its number.
                for capID in capIDs where progress[capID] == nil { progress[capID] = 0 }
                state.capProgress = progress
            }

            let answers = setup.conditionAnswers[card.cardId] ?? [:]
            state.flags = answers.isEmpty ? nil : answers

            if card.cardId == "tangerine-moneyback-world" {
                state.selectedCategories = setup.tangerineSelectedCategories?.isEmpty == false
                    ? setup.tangerineSelectedCategories : nil
            }

            cardStates[card.cardId] = mirroringLegacyFlags(state)
        }

        return OwnerState(ownerStateVersion: existing?.ownerStateVersion ?? version,
                          ownedCardIds: owned,
                          defaultCardId: defaultCardId,
                          switchThreshold: setup.switchThreshold,
                          carry: existing?.carry ?? Carry(drawerCards: []),
                          cardStates: cardStates,
                          valuationsCad: setup.valuationsCad,
                          market: setup.market?.rawValue ?? existing?.market)
    }

    /// Copies the two legacy named booleans back out of `flags`, so an owner state written by
    /// this build stays fully readable by a consumer that predates `flags`. MoneyTalks stores
    /// owner state and has not been audited for what it reads (D4). Delete this, and the two
    /// `CardState` properties it writes, once that audit is done.
    static func mirroringLegacyFlags(_ state: CardState) -> CardState {
        var mirrored = state
        mirrored.rogersEligibleServiceLinked = state.flags?["rogersEligibleServiceLinked"]
        mirrored.cryptoLevelUpProActive = state.flags?["cryptoLevelUpProActive"]
        return mirrored
    }
```

> **Note for the implementer:** `resolvedFlags` and `CardState.flags` do not exist until Task 5. To keep Phase 0 shippable on its own, add this temporary shim at the bottom of `OwnerStateSetup.swift` and DELETE it in Task 5 Step 4:
>
> ```swift
> // TEMPORARY (delete in Task 5): lets Phase 0 ship before CardState.flags exists.
> extension CardState {
>     var resolvedFlags: [String: Bool] {
>         var merged: [String: Bool] = [:]
>         if let v = rogersEligibleServiceLinked { merged["rogersEligibleServiceLinked"] = v }
>         if let v = cryptoLevelUpProActive { merged["cryptoLevelUpProActive"] = v }
>         return merged
>     }
>     var flags: [String: Bool]? {
>         get { resolvedFlags.isEmpty ? nil : resolvedFlags }
>         set {
>             rogersEligibleServiceLinked = newValue?["rogersEligibleServiceLinked"]
>             cryptoLevelUpProActive = newValue?["cryptoLevelUpProActive"]
>         }
>     }
> }
> ```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd Store && swift test --filter OwnerStateApplyTests
```

Expected: 7 tests PASS.

- [ ] **Step 6: Fix the existing setup tests**

```bash
cd Store && swift test 2>&1 | grep -E "error:|failed"
```

`Store/Tests/CardCopilotStoreTests/OwnerStateSetupTests.swift` calls `make` and the old `WalletSetup` initializer. Update each call site: `make(setup:catalogue:)` → `firstRun(setup:catalogue:)`, and replace `rogersEligibleServiceLinked: true` style arguments with `conditionAnswers: ["rogers-red-we": ["rogersEligibleServiceLinked": true]]`. Do not weaken any existing assertion.

- [ ] **Step 7: Run the full Store and Engine suites**

```bash
cd Store && swift test && cd ../Engine && swift test
```

Expected: **Store 329 tests, Engine 296 tests, 0 failures each** (measured 2026-08-28 — CLAUDE.md's
"Engine 164 / Store 69" is stale). Engine takes 4–8 minutes from cold; run it in the background.

- [ ] **Step 8: Commit**

```bash
git add Store/Sources/CardCopilotStore/OwnerStateSetup.swift \
        Store/Tests/CardCopilotStoreTests/OwnerStateApplyTests.swift \
        Store/Tests/CardCopilotStoreTests/OwnerStateSetupTests.swift
git commit -m "fix(store): wallet edits no longer wipe cap progress, carry and market

OwnerStateBuilder.make rebuilt OwnerState from WalletSetup alone, so every save
discarded everything WalletSetup cannot express. Cap progress is live data written
by MoneyTalksSync.merging, so an owner who added a card was scored as if every
capped bonus were unspent until the next successful sync — and permanently, offline.

Splits into firstRun (nothing to preserve) and apply (folds into existing state)."
```

---

### Task 2: Route edits through `apply`

> **Verified 2026-08-28 during execution.** `OwnerStateBuilder.make` has call sites in **tests as
> well as production**, and an earlier draft of this task listed only the production one — the App
> target failed to build on four missed call sites in `InstantRepeatAdvisorTests`. Before editing
> anything, enumerate them all:
> ```bash
> grep -rn "OwnerStateBuilder.make" --include="*.swift" . | grep -v "\.build/"
> ```
> Re-run that grep after Step 1; it must return nothing but doc-comment prose.

**Files:**
- Modify: `App/CardCopilot/State/CopilotEnvironment.swift:216,236` (two call sites, not one)
- Modify: `App/CardCopilotTests/InstantRepeatAdvisorTests.swift:18,49,80,109` — all four build a
  wallet from scratch, so `firstRun` is the correct replacement
- Modify: `App/CardCopilot/Views/WalletSetupView.swift` — its `binding(_ keyPath:)` helper targets
  the removed named booleans and must be bridged onto `conditionAnswers` to compile. Minimal only;
  the file is deleted in Task 12.

**Interfaces:**
- Consumes: `OwnerStateBuilder.apply(_:to:catalogue:version:)` from Task 1.
- Produces: no new API. `saveWalletSetup` keeps its signature.

- [ ] **Step 1: Change the one call site**

Replace line 236 of `App/CardCopilot/State/CopilotEnvironment.swift`:

```swift
        // First run has no prior wallet to fold into; an edit does, and folding is what keeps
        // cap progress, carry and market alive across a save.
        let owner = walletIsFirstRun
            ? OwnerStateBuilder.firstRun(setup: setup, catalogue: graph.catalogue)
            : OwnerStateBuilder.apply(setup, to: graph.ownerState, catalogue: graph.catalogue)
```

- [ ] **Step 2: Build the App target**

```bash
SIM_UDID=$(xcrun simctl list devices available | grep -m1 -o "[0-9A-F-]\{36\}")
cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot \
  -configuration Debug -destination "id=$SIM_UDID" CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED, tests PASS. If `WalletSetupView.swift` fails to compile on the old `WalletSetup` fields, update it minimally — it is replaced wholesale in Task 12 and needs only to compile here.

- [ ] **Step 3: Commit**

```bash
git add App/CardCopilot/State/CopilotEnvironment.swift App/CardCopilot/Views/WalletSetupView.swift
git commit -m "fix(app): route wallet edits through OwnerStateBuilder.apply"
```

---

# Phase 1 — Picker filtering

**Model: Sonnet 5 · Effort: Medium.** Independent of Phase 0 and Phase 2.

### Task 3: Published-only, market-scoped card selection

`WalletSetupView` renders `ForEach(catalogue.cards)` over all 133 records. 84 are `status: draft`, which `Scorer.swift:87` excludes outright with an explainer reading "should not have been scorable" — a message written on the assumption the state was unreachable. 87 are US cards shown to a Canadian owner.

**Files:**
- Create: `App/CardCopilot/Views/Wallet/WalletCardCatalogue.swift`
- Create: `App/CardCopilotTests/WalletCardCatalogueTests.swift`
- Modify: `App/CardCopilotTests/WalletSetupSearchTests.swift`

**Interfaces:**
- Produces:
  - `enum MarketScope: String, CaseIterable { case canada, unitedStates, both }`
  - `MarketScope.markets: Set<Market>`
  - `MarketScope.default(for residency: Market) -> MarketScope`
  - `enum WalletCardCatalogue { static func selectable(_:scope:) -> [CardProduct]; static func filter(_:matching:) -> [CardProduct]; static func groupedByIssuer(_:) -> [(issuer: String, cards: [CardProduct])] }`

- [ ] **Step 1: Write the failing test**

Create `App/CardCopilotTests/WalletCardCatalogueTests.swift`:

```swift
import XCTest
@testable import CardCopilot
import CardCopilotEngine

/// The picker used to render the whole catalogue. A draft record is excluded by Scorer with
/// "should not have been scorable" — a message written assuming the state was unreachable, which
/// an unfiltered picker made reachable in one tap.
final class WalletCardCatalogueTests: XCTestCase {

    private func allCards() throws -> [CardProduct] { try SeedLoader.loadCatalogue().cards }

    func testDraftCardsAreNeverSelectable() throws {
        let selectable = WalletCardCatalogue.selectable(try allCards(), scope: .both)
        XCTAssertFalse(selectable.contains { !$0.isPublished },
                       "a draft record cannot be scored, so it must not be selectable")
    }

    func testCanadaScopeExcludesUnitedStatesCards() throws {
        let selectable = WalletCardCatalogue.selectable(try allCards(), scope: .canada)
        XCTAssertFalse(selectable.isEmpty)
        XCTAssertTrue(selectable.allSatisfy { $0.market == .ca })
    }

    func testUnitedStatesScopeExcludesCanadianCards() throws {
        let selectable = WalletCardCatalogue.selectable(try allCards(), scope: .unitedStates)
        XCTAssertTrue(selectable.allSatisfy { $0.market == .us })
    }

    func testBothScopeIsTheUnionAndStillPublishedOnly() throws {
        let cards = try allCards()
        let both = WalletCardCatalogue.selectable(cards, scope: .both)
        let ca = WalletCardCatalogue.selectable(cards, scope: .canada)
        let us = WalletCardCatalogue.selectable(cards, scope: .unitedStates)
        XCTAssertEqual(both.count, ca.count + us.count)
        XCTAssertTrue(both.allSatisfy(\.isPublished))
    }

    func testScopeDefaultsToResidency() {
        XCTAssertEqual(MarketScope.default(for: .ca), .canada)
        XCTAssertEqual(MarketScope.default(for: .us), .unitedStates)
    }

    func testGroupingByIssuerIsAlphabeticalAndComplete() throws {
        let cards = WalletCardCatalogue.selectable(try allCards(), scope: .canada)
        let groups = WalletCardCatalogue.groupedByIssuer(cards)
        XCTAssertEqual(groups.map(\.issuer), groups.map(\.issuer).sorted())
        XCTAssertEqual(groups.reduce(0) { $0 + $1.cards.count }, cards.count,
                       "grouping must not drop or duplicate a card")
    }

    /// Search runs over an already-scoped array, so a draft can never re-enter through search.
    func testSearchCannotResurrectADraft() throws {
        let scoped = WalletCardCatalogue.selectable(try allCards(), scope: .canada)
        let results = WalletCardCatalogue.filter(scoped, matching: "visa")
        XCTAssertTrue(results.allSatisfy { $0.isPublished && $0.market == .ca })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
SIM_UDID=$(xcrun simctl list devices available | grep -m1 -o "[0-9A-F-]\{36\}")
cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot \
  -configuration Debug -destination "id=$SIM_UDID" CODE_SIGNING_ALLOWED=NO \
  -only-testing:CardCopilotTests/WalletCardCatalogueTests
```

Expected: compile failure — `WalletCardCatalogue` does not exist.

- [ ] **Step 3: Write the implementation**

Create `App/CardCopilot/Views/Wallet/WalletCardCatalogue.swift`:

```swift
import Foundation
import CardCopilotEngine

/// Which markets the card list is showing. A VIEW preference, not owner state: `Market` is a
/// closed two-case enum and `.both` is not a residency anyone has. Residency lives in
/// `OwnerState.market` and drives AcquisitionAnalyzer; this only decides what the list renders.
enum MarketScope: String, CaseIterable, Sendable {
    case canada, unitedStates, both

    var markets: Set<Market> {
        switch self {
        case .canada: return [.ca]
        case .unitedStates: return [.us]
        case .both: return [.ca, .us]
        }
    }

    static func `default`(for residency: Market) -> MarketScope {
        switch residency {
        case .ca: return .canada
        case .us: return .unitedStates
        }
    }

    var title: String {
        switch self {
        case .canada: return String(localized: "Canada")
        case .unitedStates: return String(localized: "US")
        case .both: return String(localized: "Both")
        }
    }
}

/// Pure catalogue shaping for the wallet UI. No SwiftUI, so every rule here is unit-testable —
/// which matters because these two predicates are the difference between offering someone a card
/// PickMe can advise on and one the Scorer will refuse to score for the life of their wallet.
enum WalletCardCatalogue {

    /// Cards a person may actually add. Two gates, both non-negotiable:
    /// `isPublished` (a draft is research-grade and `Scorer` excludes it) and market.
    static func selectable(_ cards: [CardProduct], scope: MarketScope) -> [CardProduct] {
        let markets = scope.markets
        return cards.filter { $0.isPublished && markets.contains($0.market) }
    }

    /// Token search over an ALREADY-SCOPED array. Every token must match some field, so
    /// "scotia visa" narrows rather than widens. Unchanged from the original implementation.
    static func filter(_ cards: [CardProduct], matching query: String) -> [CardProduct] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cards }
        let tokens = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return cards.filter { card in
            let style = CardVisualTheme.style(for: card.cardId)
            let searchableFields = [
                card.officialName, card.issuer, card.network.rawValue, card.cardId,
                style.shortName, style.issuer, style.network.rawValue
            ]
            return tokens.allSatisfy { token in
                searchableFields.contains { $0.localizedCaseInsensitiveContains(token) }
            }
        }
    }

    /// Issuer sections, alphabetical, cards alphabetical within each. Grouping is what makes a
    /// list of this size scannable — 41 cards today, and the catalogue's stated horizon is
    /// thousands.
    static func groupedByIssuer(_ cards: [CardProduct]) -> [(issuer: String, cards: [CardProduct])] {
        Dictionary(grouping: cards, by: \.issuer)
            .map { (issuer: $0.key, cards: $0.value.sorted { $0.officialName < $1.officialName }) }
            .sorted { $0.issuer < $1.issuer }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
SIM_UDID=$(xcrun simctl list devices available | grep -m1 -o "[0-9A-F-]\{36\}")
cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot \
  -configuration Debug -destination "id=$SIM_UDID" CODE_SIGNING_ALLOWED=NO \
  -only-testing:CardCopilotTests/WalletCardCatalogueTests
```

Expected: 7 tests PASS.

- [ ] **Step 5: Retarget the existing search tests**

In `App/CardCopilotTests/WalletSetupSearchTests.swift`, replace every `WalletSetupView.filterCards(` with `WalletCardCatalogue.filter(`. The signature and behaviour are identical, so no assertion changes. Keep all 10 existing tests.

- [ ] **Step 6: Run the full App suite**

```bash
SIM_UDID=$(xcrun simctl list devices available | grep -m1 -o "[0-9A-F-]\{36\}")
cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot \
  -configuration Debug -destination "id=$SIM_UDID" CODE_SIGNING_ALLOWED=NO
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add App/CardCopilot/Views/Wallet/WalletCardCatalogue.swift \
        App/CardCopilotTests/WalletCardCatalogueTests.swift \
        App/CardCopilotTests/WalletSetupSearchTests.swift
git commit -m "feat(app): card selection is published-only and market-scoped

The picker rendered all 133 catalogue records. 84 are status: draft, which Scorer
excludes with 'should not have been scorable' — written assuming the state was
unreachable. 87 are US cards shown to Canadian owners. Now 41 by default."
```

---

# Phase 2 — Owner conditions as data

**Model: Opus 5 · Effort: High.** Cross-language contract change. Do not begin until Phase 0 is green.

### Task 4: The `owner-conditions.json` registry

**Files:**
- Create: `contracts/owner-conditions.json`
- Create: `contracts/schema/owner-conditions.schema.json`
- Create: `Engine/Sources/CardCopilotEngine/Models/OwnerCondition.swift`
- Create: `Engine/Tests/CardCopilotEngineTests/OwnerConditionRegistryTests.swift`
- Modify: `Engine/Sources/CardCopilotEngine/Loading/SeedLoader.swift`
- Modify: `scripts/sync-contracts-into-engine.sh`, `scripts/sync-contracts-into-android.sh`, `scripts/release-catalogue.sh`, `scripts/validate-catalogue-schema.py`

**Interfaces:**
- Produces: `OwnerConditionAnswerKind`, `OwnerCondition`, `OwnerConditionRegistry`, `SeedLoader.loadOwnerConditions()`, `SeedLoader.ownerConditions: [String: OwnerCondition]`.

- [ ] **Step 1: Write the failing test**

Create `Engine/Tests/CardCopilotEngineTests/OwnerConditionRegistryTests.swift`:

```swift
import XCTest
@testable import CardCopilotEngine

/// The registry is the answer to "adding a condition took six edits across two languages".
/// Its one hard invariant: every id the catalogue references must be declared here, or the
/// setup UI has no way to ask the question and the rule fails closed forever — which is exactly
/// how amazonEligiblePrimeLinked shipped unanswerable.
final class OwnerConditionRegistryTests: XCTestCase {

    func testRegistryDecodes() throws {
        let registry = try SeedLoader.loadOwnerConditions()
        XCTAssertFalse(registry.conditions.isEmpty)
    }

    func testEveryCatalogueConditionIsDeclared() throws {
        let declared = Set(try SeedLoader.loadOwnerConditions().conditions.keys)
        let referenced = Set(try SeedLoader.loadCatalogue().cards
            .flatMap(\.earnRules)
            .compactMap(\.ownerConditions)
            .flatMap { $0 })
        XCTAssertEqual(referenced.subtracting(declared), [],
                       "catalogue references a condition the registry does not declare")
    }

    func testBooleanConditionsCarryAPrompt() throws {
        let registry = try SeedLoader.loadOwnerConditions()
        for (id, condition) in registry.conditions where condition.answerKind == .boolean {
            XCTAssertFalse((condition.prompt ?? "").isEmpty,
                           "\(id) is answered yes/no but has no question to ask")
        }
    }

    func testAmazonPrimeIsNowDeclared() throws {
        let registry = try SeedLoader.loadOwnerConditions()
        XCTAssertNotNil(registry.conditions["amazonEligiblePrimeLinked"],
                        "the condition that shipped unanswerable is the reason this file exists")
    }

    func testCachedAccessorMatchesTheFile() throws {
        XCTAssertEqual(SeedLoader.ownerConditions, try SeedLoader.loadOwnerConditions().conditions)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Engine && swift test --filter OwnerConditionRegistryTests
```

Expected: compile failure — `loadOwnerConditions` does not exist.

- [ ] **Step 3: Write `contracts/owner-conditions.json`**

```json
{
  "conditionsVersion": "1.0",
  "_provenance": "Owner conditions are facts about an ACCOUNT, not a product: whether a card's higher rate applies to this particular holder. RuleMatcher fails closed on an unanswered one, so a condition with no entry here is a rate the owner can never unlock. Declared here rather than inline on the earn rule so adding one stays a data edit; see docs/plans/2026-08-20-catalogue-scalability-program-design.md §3.2 and the 2026-08-28 CHANGELOG entry for why this is a sidecar registry rather than that section's inline object shape.",
  "_localization": "`prompt` and `detail` are ENGLISH SOURCE STRINGS, not display strings. Consumers resolve ownerCondition.<id>.prompt from their own string catalogue and fall back to these. A new condition therefore ships working in English immediately and picks up translations without a contract release.",
  "conditions": {
    "rogersEligibleServiceLinked": {
      "answerKind": "boolean",
      "prompt": "Is an eligible Rogers, Fido, Shaw, Comwave or Sportsnet+ service linked to your account?",
      "detail": "The higher 2% rate requires an eligible service on the same account."
    },
    "cryptoLevelUpProActive": {
      "answerKind": "boolean",
      "prompt": "Is your Level Up Pro plan active?",
      "detail": "The 3% CRO reward applies only while Level Up Pro is active."
    },
    "amazonEligiblePrimeLinked": {
      "answerKind": "boolean",
      "prompt": "Is an active Amazon Prime membership linked to this card?",
      "detail": "The 2.5x rate applies only while Prime is linked to the account holding this card."
    },
    "tangerineCategorySelected": {
      "answerKind": "categorySelection",
      "maxSelections": 3,
      "detail": "Tangerine pays 2% on the categories you have selected on your account. Leave all unselected if you are not sure."
    }
  }
}
```

- [ ] **Step 4: Write `contracts/schema/owner-conditions.schema.json`**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://pickme.local/schema/owner-conditions.schema.json",
  "title": "Owner condition registry",
  "description": "Declares every ownerConditions id the card catalogue may reference, and how it is answered. Deliberately a SIDECAR rather than an inline object on EarnRule: ownerConditions is a published [String] array inside a content-addressed release with four vendored copies, and changing its element type would be a MAJOR catalogue bump. This mirrors programs.json, which solved the same open-set-as-closed-set problem for valuations.",
  "type": "object",
  "required": ["conditionsVersion", "conditions"],
  "additionalProperties": false,
  "properties": {
    "conditionsVersion": {
      "type": "string",
      "pattern": "^[0-9]+\\.[0-9]+$",
      "description": "MAJOR.MINOR. Bump MINOR when adding a condition; MAJOR only on a breaking shape change."
    },
    "_provenance": { "type": "string" },
    "_localization": { "type": "string" },
    "conditions": {
      "type": "object",
      "description": "Keyed by the ownerConditions id used in card-catalogue.json earn rules.",
      "propertyNames": { "pattern": "^[a-zA-Z][a-zA-Z0-9]*$" },
      "additionalProperties": {
        "type": "object",
        "required": ["answerKind"],
        "additionalProperties": false,
        "properties": {
          "answerKind": {
            "enum": ["boolean", "categorySelection"],
            "description": "boolean answers land in CardState.flags. categorySelection is Tangerine's existing selection machinery, which stays structural because specific engine logic reads it (spec §3.2)."
          },
          "prompt": {
            "type": "string",
            "description": "English source string for the question. Required for answerKind boolean; consumers localize by id and fall back to this."
          },
          "detail": { "type": "string" },
          "maxSelections": {
            "type": "integer",
            "minimum": 1,
            "description": "categorySelection only: how many categories the issuer permits."
          }
        },
        "allOf": [{
          "if": { "properties": { "answerKind": { "const": "boolean" } } },
          "then": { "required": ["prompt"] }
        }]
      }
    }
  }
}
```

- [ ] **Step 5: Write `Engine/Sources/CardCopilotEngine/Models/OwnerCondition.swift`**

```swift
import Foundation

/// How a condition is answered, and therefore which owner-state field carries the answer.
///
/// `boolean` answers live in `CardState.flags`, keyed by condition id — so a new yes/no condition
/// is a registry entry and nothing else. `categorySelection` is Tangerine's existing selection
/// machinery, which stays structural because specific engine logic reads it (`selectedCategories`,
/// `treatAsAllSelected`, `thirdCategoryUnlocked`, `nextChangeEffectiveDate`) rather than generic
/// condition resolution. Spec §3.2 draws that line and this enum encodes it.
public enum OwnerConditionAnswerKind: String, Codable, Equatable, Sendable {
    case boolean
    case categorySelection
}

/// One owner condition, as declared in `contracts/owner-conditions.json`.
public struct OwnerCondition: Codable, Equatable, Sendable {
    public var answerKind: OwnerConditionAnswerKind
    /// The ENGLISH SOURCE string, not the display string. Consumers resolve
    /// `ownerCondition.<id>.prompt` from their own string catalogue and fall back to this, so a
    /// new condition ships working in English and picks up translations with no contract release.
    public var prompt: String?
    public var detail: String?
    /// `categorySelection` only: how many categories the issuer permits.
    public var maxSelections: Int?

    public init(answerKind: OwnerConditionAnswerKind, prompt: String? = nil,
                detail: String? = nil, maxSelections: Int? = nil) {
        self.answerKind = answerKind
        self.prompt = prompt
        self.detail = detail
        self.maxSelections = maxSelections
    }
}

/// The registry file. Same shape and role as `ProgramCatalogue`: an open set, declared as data,
/// with a machine check that the catalogue never references an entry that is missing.
public struct OwnerConditionRegistry: Codable, Equatable, Sendable {
    public var conditionsVersion: String
    public var conditions: [String: OwnerCondition]

    public init(conditionsVersion: String = "1.0", conditions: [String: OwnerCondition] = [:]) {
        self.conditionsVersion = conditionsVersion
        self.conditions = conditions
    }
}
```

- [ ] **Step 6: Add the loader**

In `Engine/Sources/CardCopilotEngine/Loading/SeedLoader.swift`, directly after `loadPrograms()`:

```swift
    /// The owner-condition registry. Every `ownerConditions` id the catalogue references must
    /// resolve here — `OwnerConditionRegistryTests` and the CI gate enforce it.
    public static func loadOwnerConditions() throws -> OwnerConditionRegistry {
        try load("owner-conditions")
    }

    /// Decoded once and reused. Traps rather than falling back to `[:]`, for the same reason
    /// `programValuationDefaults` does: an empty fallback would make every condition unanswerable
    /// and every conditional rate silently unreachable, which is the exact failure this registry
    /// exists to prevent.
    public static let ownerConditions: [String: OwnerCondition] = {
        do { return try loadOwnerConditions().conditions }
        catch { preconditionFailure("contracts/owner-conditions.json is unreadable: \(error)") }
    }()
```

- [ ] **Step 7: Wire the registry into the four scripts**

In `scripts/sync-contracts-into-engine.sh`, after the `programs.json` block:

```bash
cp "$root/contracts/owner-conditions.json" \
   "$root/Engine/Sources/CardCopilotEngine/Resources/owner-conditions.json"
```

In `scripts/sync-contracts-into-android.sh`, add the matching `cp` alongside its `programs.json` line, targeting `android/core/engine/src/main/resources/com/cardcopilot/engine/owner-conditions.json`.

In `scripts/release-catalogue.sh`, add to the `FILES` array (line 33) after `programs.json`:

```bash
  "owner-conditions.json"
  "schema/owner-conditions.schema.json"
```

In `scripts/validate-catalogue-schema.py`, add to the pairs list (line ~39):

```python
    ("owner-conditions.json", "owner-conditions.schema.json"),
```

- [ ] **Step 8: Sync and run**

```bash
./scripts/sync-contracts-into-engine.sh
./scripts/sync-contracts-into-android.sh
pip install jsonschema && python3 scripts/validate-catalogue-schema.py
cd Engine && swift test --filter OwnerConditionRegistryTests
```

Expected: schema validation passes; 5 tests PASS.

> If `ContractsSyncTests` fails on the new file, it enumerates the synced set explicitly — add `owner-conditions.json` to its list.

- [ ] **Step 9: Commit**

```bash
git add contracts/owner-conditions.json contracts/schema/owner-conditions.schema.json \
        Engine/Sources/CardCopilotEngine/Models/OwnerCondition.swift \
        Engine/Sources/CardCopilotEngine/Loading/SeedLoader.swift \
        Engine/Sources/CardCopilotEngine/Resources/owner-conditions.json \
        Engine/Tests/CardCopilotEngineTests/OwnerConditionRegistryTests.swift \
        android/core/engine/src/main/resources/com/cardcopilot/engine/owner-conditions.json \
        scripts/sync-contracts-into-engine.sh scripts/sync-contracts-into-android.sh \
        scripts/release-catalogue.sh scripts/validate-catalogue-schema.py
git commit -m "feat(contracts): owner-conditions.json declares every condition as data

Mirrors the programs.json precedent for the same open-set-as-closed-set defect.
Sidecar rather than spec 3.2's inline object: ownerConditions is a published
[String] inside a content-addressed release, so changing its element type would
be a MAJOR bump across four vendored copies."
```

---

### Task 5: `CardState.flags`

**Files:**
- Modify: `Engine/Sources/CardCopilotEngine/Models/OwnerState.swift:44-58`
- Modify: `Store/Sources/CardCopilotStore/OwnerStateSetup.swift` (delete the Task 1 shim)
- Test: `Engine/Tests/CardCopilotEngineTests/OwnerConditionRegistryTests.swift` (extend)

**Interfaces:**
- Produces: `CardState.flags: [String: Bool]?`, `CardState.resolvedFlags: [String: Bool]`.

- [ ] **Step 1: Write the failing test**

Append to `OwnerConditionRegistryTests.swift`:

```swift
    // MARK: - flags and legacy migration

    /// An owner state written before `flags` existed must keep working untouched. The legacy
    /// named booleans are not deleted (D4): MoneyTalks stores owner state and has not been
    /// audited for what it reads, so they stay, mirrored, for one release.
    func testLegacyNamedBooleansFoldIntoResolvedFlags() throws {
        let json = #"{"rogersEligibleServiceLinked":true,"cryptoLevelUpProActive":false}"#
        let state = try JSONDecoder().decode(CardState.self, from: Data(json.utf8))
        XCTAssertEqual(state.resolvedFlags["rogersEligibleServiceLinked"], true)
        XCTAssertEqual(state.resolvedFlags["cryptoLevelUpProActive"], false)
    }

    func testFlagsWinOverAStaleMirroredLegacyKey() throws {
        let json = #"{"rogersEligibleServiceLinked":false,"flags":{"rogersEligibleServiceLinked":true}}"#
        let state = try JSONDecoder().decode(CardState.self, from: Data(json.utf8))
        XCTAssertEqual(state.resolvedFlags["rogersEligibleServiceLinked"], true,
                       "flags is the newer field and must not be overwritten by a stale mirror")
    }

    func testUnansweredConditionIsAbsentNotFalse() throws {
        let state = try JSONDecoder().decode(CardState.self, from: Data("{}".utf8))
        XCTAssertNil(state.resolvedFlags["rogersEligibleServiceLinked"],
                     "'not asked' and 'no' buy different rates and must stay distinguishable")
    }

    func testFlagsRoundTrip() throws {
        var state = CardState()
        state.flags = ["amazonEligiblePrimeLinked": true]
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(CardState.self, from: data)
        XCTAssertEqual(decoded.resolvedFlags["amazonEligiblePrimeLinked"], true)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Engine && swift test --filter OwnerConditionRegistryTests
```

Expected: compile failure — `flags` and `resolvedFlags` do not exist on `CardState`.

- [ ] **Step 3: Add `flags` and `resolvedFlags`**

In `Engine/Sources/CardCopilotEngine/Models/OwnerState.swift`, replace the `CardState` struct at lines 44–58:

```swift
public struct CardState: Codable, Equatable, Sendable {
    public var capProgress: [String: Double]?
    public var scotiaAccountYearAnchorMonth: Int?
    public var selectedCategories: [String]?
    public var treatAsAllSelected: Bool?
    public var thirdCategoryUnlocked: Bool?
    public var nextChangeEffectiveDate: String?
    public var rogersAccountAnniversaryMonth: Int?
    public var feeWaiverActive: Bool?
    public var croHandling: String?   // "autoSell" | "hold" | nil (unresolved)

    /// Boolean owner-condition answers, keyed by the catalogue's `ownerConditions` id.
    ///
    /// An ABSENT key is unresolved and `RuleMatcher` fails closed on it; `false` is a real answer
    /// meaning "no". The two are not interchangeable — they buy the owner different rates.
    ///
    /// Replaces the named per-card booleans below, so a new yes/no condition is an entry in
    /// `contracts/owner-conditions.json` and nothing else. Four conditions shipped against three
    /// hardcoded `RuleMatcher` cases before this existed, and the fourth
    /// (`amazonEligiblePrimeLinked`) was unanswerable in every build.
    public var flags: [String: Bool]?

    /// LEGACY, retained for one release (D4). Not read by the engine — `resolvedFlags` folds them
    /// into `flags`, and `OwnerStateBuilder.mirroringLegacyFlags` writes them back out so a
    /// consumer predating `flags` still sees an answer. MoneyTalks stores owner state and has not
    /// been audited for what it reads. Delete both once it has.
    public var rogersEligibleServiceLinked: Bool?
    public var cryptoLevelUpProActive: Bool?

    public init() {}

    /// `flags` with the legacy named booleans folded in. `flags` wins on conflict: it is the
    /// newer field, so a state written by a newer build and read here must not be clobbered by
    /// a stale mirror.
    public var resolvedFlags: [String: Bool] {
        var merged: [String: Bool] = [:]
        if let value = rogersEligibleServiceLinked { merged["rogersEligibleServiceLinked"] = value }
        if let value = cryptoLevelUpProActive { merged["cryptoLevelUpProActive"] = value }
        if let flags { merged.merge(flags) { _, newer in newer } }
        return merged
    }
}
```

> Synthesized `Codable` still applies — `flags` is additive and every property stays optional, so an owner state written by any prior build decodes unchanged.

- [ ] **Step 4: Delete the Phase 0 shim**

Remove the `// TEMPORARY (delete in Task 5)` extension from the bottom of `Store/Sources/CardCopilotStore/OwnerStateSetup.swift`. `mirroringLegacyFlags` stays — it is permanent until the D4 audit.

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd Engine && swift test && cd ../Store && swift test
```

Expected: Engine 164+ PASS, Store 76+ PASS. The 28 fixture cases must be unchanged — legacy keys in fixture owner overrides still decode via the retained properties.

- [ ] **Step 6: Commit**

```bash
git add Engine/Sources/CardCopilotEngine/Models/OwnerState.swift \
        Engine/Tests/CardCopilotEngineTests/OwnerConditionRegistryTests.swift \
        Store/Sources/CardCopilotStore/OwnerStateSetup.swift
git commit -m "feat(engine): CardState.flags carries owner-condition answers by id

Legacy named booleans retained and mirrored for one release — MoneyTalks stores
owner state and has not been audited for what it reads."
```

---

### Task 6: `RuleMatcher` dispatches through `flags`

**Files:**
- Modify: `Engine/Sources/CardCopilotEngine/Engine/RuleMatcher.swift:94-104`
- Modify: `Engine/Tests/CardCopilotEngineTests/CatalogueIntegrityTests.swift:22-28`

**Interfaces:**
- Consumes: `CardState.resolvedFlags` from Task 5, `SeedLoader.ownerConditions` from Task 4.
- Produces: no signature change to `conditionsResolveTrue`.

- [ ] **Step 1: Write the failing test**

Append to `Engine/Tests/CardCopilotEngineTests/OwnerConditionRegistryTests.swift`:

```swift
    // MARK: - RuleMatcher dispatch

    func testAnyDeclaredConditionResolvesFromFlags() {
        var state = CardState()
        state.flags = ["amazonEligiblePrimeLinked": true]
        XCTAssertTrue(RuleMatcher.conditionsResolveTrue(["amazonEligiblePrimeLinked"], state: state),
                      "this is the rule that could never fire before the registry existed")
    }

    func testUnansweredConditionFailsClosed() {
        XCTAssertFalse(RuleMatcher.conditionsResolveTrue(["amazonEligiblePrimeLinked"],
                                                         state: CardState()))
    }

    func testExplicitNoFailsClosed() {
        var state = CardState()
        state.flags = ["rogersEligibleServiceLinked": false]
        XCTAssertFalse(RuleMatcher.conditionsResolveTrue(["rogersEligibleServiceLinked"], state: state))
    }

    func testTangerineStaysOnItsStructuralField() {
        var state = CardState()
        state.selectedCategories = ["grocery"]
        XCTAssertTrue(RuleMatcher.conditionsResolveTrue(["tangerineCategorySelected"], state: state))
        XCTAssertFalse(RuleMatcher.conditionsResolveTrue(["tangerineCategorySelected"],
                                                         state: CardState()))
    }

    func testAllConditionsMustHoldTogether() {
        var state = CardState()
        state.flags = ["rogersEligibleServiceLinked": true]
        XCTAssertFalse(RuleMatcher.conditionsResolveTrue(
            ["rogersEligibleServiceLinked", "amazonEligiblePrimeLinked"], state: state))
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Engine && swift test --filter testAnyDeclaredConditionResolvesFromFlags
```

Expected: FAIL — `amazonEligiblePrimeLinked` hits `default: return false`.

- [ ] **Step 3: Rewrite `conditionsResolveTrue`**

Replace lines 94–104 of `Engine/Sources/CardCopilotEngine/Engine/RuleMatcher.swift`:

```swift
    /// Owner conditions resolve from `CardState.flags`, keyed by the catalogue's own ids, so a
    /// new condition needs an entry in `contracts/owner-conditions.json` and no code at all.
    ///
    /// Tangerine keeps its own case: `selectedCategories` is structural state that specific
    /// engine logic reads (`matchesOwnerSelection`), not a yes/no answer (spec §3.2).
    ///
    /// Fails closed on anything unanswered — an absent key is "not asked", never "no".
    static func conditionsResolveTrue(_ conditions: [String]?, state: CardState) -> Bool {
        guard let conditions else { return true }
        let flags = state.resolvedFlags
        return conditions.allSatisfy { condition in
            switch condition {
            case "tangerineCategorySelected": return state.selectedCategories != nil
            default: return flags[condition] ?? false
            }
        }
    }
```

- [ ] **Step 4: Shrink the integrity ratchet to empty**

Replace lines 21–28 of `Engine/Tests/CardCopilotEngineTests/CatalogueIntegrityTests.swift`:

```swift
    /// Owner conditions declared in the catalogue with no way to answer them.
    /// EMPTY since 2026-08-28: conditions resolve from `CardState.flags` against
    /// `contracts/owner-conditions.json`, so the registry — not a Swift switch — is the gate.
    /// `amazonEligiblePrimeLinked` sat here from the day it shipped; it is now answerable.
    /// Keep this empty. An entry means shipping a card whose rate the owner cannot unlock.
    static let knownUnhandledConditions: Set<String> = []

    /// Conditions the engine resolves structurally rather than from `flags`. Mirrors
    /// RuleMatcher.conditionsResolveTrue's remaining explicit case, kept here rather than made
    /// internal so the test fails when the two drift — which is the point.
    static let structuralConditions: Set<String> = ["tangerineCategorySelected"]
```

Then update the test in that file that consumed `handledConditions` so it reads the registry instead:

```swift
    /// Data may not outrun code. Every condition the catalogue references must be declared in
    /// the registry, and every registry entry must be resolvable — structurally, or from flags.
    func testEveryDeclaredConditionIsAnswerable() throws {
        let registry = try SeedLoader.loadOwnerConditions().conditions
        let referenced = Set(try publishedCards()
            .flatMap(\.earnRules).compactMap(\.ownerConditions).flatMap { $0 })

        let undeclared = referenced.subtracting(registry.keys).subtracting(Self.knownUnhandledConditions)
        XCTAssertEqual(undeclared, [], "catalogue references conditions the registry does not declare")

        for (id, condition) in registry where condition.answerKind == .categorySelection {
            XCTAssertTrue(Self.structuralConditions.contains(id),
                          "\(id) needs engine logic to resolve, not just a registry entry")
        }
    }
```

> If the existing test has a different name, keep the existing name and replace its body.

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd Engine && swift test
```

Expected: all PASS, including the 28 fixture cases byte-unchanged.

- [ ] **Step 6: Commit**

```bash
git add Engine/Sources/CardCopilotEngine/Engine/RuleMatcher.swift \
        Engine/Tests/CardCopilotEngineTests/CatalogueIntegrityTests.swift \
        Engine/Tests/CardCopilotEngineTests/OwnerConditionRegistryTests.swift
git commit -m "feat(engine): owner conditions resolve from flags; unhandled list is empty

amazonEligiblePrimeLinked shipped with no RuleMatcher case, so the Amazon Prime
2.5x rule could never fire in any build. It is now answerable."
```

---

### Task 7: Kotlin parity

The Kotlin engine re-implements these semantics and CI runs the same fixtures against it. Without this, a catalogue change lands green on Swift while Android scores a different winner.

**Files:**
- Modify: `android/core/engine/src/main/kotlin/com/cardcopilot/engine/models/OwnerState.kt:66-79`
- Modify: `android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/RuleMatcher.kt:121-131`
- Create: `android/core/engine/src/main/kotlin/com/cardcopilot/engine/models/OwnerCondition.kt`

**Interfaces:**
- Consumes: the same `contracts/owner-conditions.json` synced in Task 4 Step 7.
- Produces: `CardState.flags`, `CardState.resolvedFlags`, `OwnerConditionRegistry`.

- [ ] **Step 1: Write the failing test**

Create `android/core/engine/src/test/kotlin/com/cardcopilot/engine/OwnerConditionTest.kt`:

```kotlin
package com.cardcopilot.engine

import com.cardcopilot.engine.engine.RuleMatcher
import com.cardcopilot.engine.models.CardState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Kotlin twin of OwnerConditionRegistryTests. Both engines must agree exactly or the shared
 *  fixture gate reports a scoring difference that is really a parity bug. */
class OwnerConditionTest {

    @Test
    fun `any declared condition resolves from flags`() {
        val state = CardState(flags = mapOf("amazonEligiblePrimeLinked" to true))
        assertTrue(RuleMatcher.conditionsResolveTrue(listOf("amazonEligiblePrimeLinked"), state))
    }

    @Test
    fun `unanswered condition fails closed`() {
        assertFalse(RuleMatcher.conditionsResolveTrue(listOf("amazonEligiblePrimeLinked"), CardState()))
    }

    @Test
    fun `explicit no fails closed`() {
        val state = CardState(flags = mapOf("rogersEligibleServiceLinked" to false))
        assertFalse(RuleMatcher.conditionsResolveTrue(listOf("rogersEligibleServiceLinked"), state))
    }

    @Test
    fun `legacy named booleans fold into resolved flags`() {
        val state = CardState(rogersEligibleServiceLinked = true)
        assertEquals(true, state.resolvedFlags["rogersEligibleServiceLinked"])
        assertTrue(RuleMatcher.conditionsResolveTrue(listOf("rogersEligibleServiceLinked"), state))
    }

    @Test
    fun `flags win over a stale mirrored legacy key`() {
        val state = CardState(rogersEligibleServiceLinked = false,
                              flags = mapOf("rogersEligibleServiceLinked" to true))
        assertEquals(true, state.resolvedFlags["rogersEligibleServiceLinked"])
    }

    @Test
    fun `tangerine stays on its structural field`() {
        val state = CardState(selectedCategories = listOf("grocery"))
        assertTrue(RuleMatcher.conditionsResolveTrue(listOf("tangerineCategorySelected"), state))
        assertFalse(RuleMatcher.conditionsResolveTrue(listOf("tangerineCategorySelected"), CardState()))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd android && ./gradlew --no-daemon :core:engine:test --tests '*OwnerConditionTest*'
```

Expected: compile failure — `flags` is not a `CardState` parameter.

- [ ] **Step 3: Add `flags` and `resolvedFlags` to Kotlin `CardState`**

Replace the `CardState` data class at `android/core/engine/src/main/kotlin/com/cardcopilot/engine/models/OwnerState.kt:66-79`:

```kotlin
@Serializable
data class CardState(
    val capProgress: Map<String, Double>? = null,
    val scotiaAccountYearAnchorMonth: Int? = null,
    val selectedCategories: List<String>? = null,
    val treatAsAllSelected: Boolean? = null,
    val thirdCategoryUnlocked: Boolean? = null,
    val nextChangeEffectiveDate: String? = null,
    val rogersAccountAnniversaryMonth: Int? = null,
    val feeWaiverActive: Boolean? = null,
    val croHandling: String? = null, // "autoSell" | "hold" | null
    /**
     * Boolean owner-condition answers keyed by the catalogue's `ownerConditions` id. An ABSENT
     * key is unresolved and RuleMatcher fails closed on it; `false` is a real "no". Swift twin:
     * CardState.flags in Engine/Sources/CardCopilotEngine/Models/OwnerState.swift.
     */
    val flags: Map<String, Boolean>? = null,
    /** LEGACY, retained for one release (D4). Read only through [resolvedFlags]. */
    val rogersEligibleServiceLinked: Boolean? = null,
    val cryptoLevelUpProActive: Boolean? = null
) {
    /** [flags] with the legacy named booleans folded in; [flags] wins on conflict. */
    val resolvedFlags: Map<String, Boolean>
        get() {
            val merged = LinkedHashMap<String, Boolean>()
            rogersEligibleServiceLinked?.let { merged["rogersEligibleServiceLinked"] = it }
            cryptoLevelUpProActive?.let { merged["cryptoLevelUpProActive"] = it }
            flags?.let { merged.putAll(it) }
            return merged
        }
}
```

- [ ] **Step 4: Rewrite the Kotlin `conditionsResolveTrue`**

Replace lines 121–131 of `android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/RuleMatcher.kt`:

```kotlin
    /**
     * Twin of Swift's RuleMatcher.conditionsResolveTrue. Conditions resolve from
     * [CardState.resolvedFlags] keyed by the catalogue's own ids; Tangerine keeps an explicit
     * case because `selectedCategories` is structural state, not a yes/no answer. Fails closed
     * on anything unanswered.
     */
    fun conditionsResolveTrue(conditions: List<String>?, state: CardState): Boolean {
        if (conditions == null) return true
        val flags = state.resolvedFlags
        return conditions.all { condition ->
            when (condition) {
                "tangerineCategorySelected" -> state.selectedCategories != null
                else -> flags[condition] ?: false
            }
        }
    }
```

- [ ] **Step 5: Add the Kotlin registry model**

Create `android/core/engine/src/main/kotlin/com/cardcopilot/engine/models/OwnerCondition.kt`:

```kotlin
package com.cardcopilot.engine.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Twin of Swift's OwnerConditionAnswerKind. */
@Serializable
enum class OwnerConditionAnswerKind {
    @SerialName("boolean") BOOLEAN,
    @SerialName("categorySelection") CATEGORY_SELECTION
}

/** One owner condition as declared in contracts/owner-conditions.json. */
@Serializable
data class OwnerCondition(
    val answerKind: OwnerConditionAnswerKind,
    /** English source string, not a display string — consumers localize by id. */
    val prompt: String? = null,
    val detail: String? = null,
    val maxSelections: Int? = null
)

@Serializable
data class OwnerConditionRegistry(
    val conditionsVersion: String = "1.0",
    val conditions: Map<String, OwnerCondition> = emptyMap()
)
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd android && ./gradlew --no-daemon :core:engine:test
```

Expected: all PASS, including `FixtureHarnessTest` with expectations byte-unchanged.

> `FixtureHarnessTest.kt:48,124,132` references `rogersEligibleServiceLinked` in its override plumbing. Those keep working — the property is retained. Do not delete them.

- [ ] **Step 7: Commit**

```bash
git add android/core/engine/src/main/kotlin/com/cardcopilot/engine/models/OwnerState.kt \
        android/core/engine/src/main/kotlin/com/cardcopilot/engine/models/OwnerCondition.kt \
        android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/RuleMatcher.kt \
        android/core/engine/src/test/kotlin/com/cardcopilot/engine/OwnerConditionTest.kt
git commit -m "feat(engine-kotlin): owner conditions resolve from flags, mirroring Swift"
```

---

### Task 8: Fixtures, version bumps, release stamp

**Files:**
- Modify: `contracts/engine-fixtures.json`, `contracts/card-catalogue.json`, `contracts/CHANGELOG.md`, `contracts/RELEASE.json`

- [ ] **Step 1: Add the two fixture cases**

In `contracts/engine-fixtures.json`, bump `fixturesVersion` to `"1.3"` and append to `cases`. Match the existing case shape exactly — read a neighbouring case first and mirror its keys; do not invent fields.

The two cases, both on `amazon-ca-rewards-mastercard` at an Amazon purchase:

1. `"amazon-prime-linked-fires-2_5x"` — owner override sets `flags: { "amazonEligiblePrimeLinked": true }` on that card; expectation is the 2.5x rule winning. **This case is the pin: it could not have passed in any prior build.**
2. `"amazon-prime-unanswered-fails-closed"` — no override; expectation is the base rule, not 2.5x.

Do not touch any of the 28 existing cases.

- [ ] **Step 2: Bump `catalogueVersion`**

In `contracts/card-catalogue.json`, change `"catalogueVersion": "2.7"` to `"2.8"`. Change nothing else in that file — no card record's bytes move in this release.

- [ ] **Step 3: Write the CHANGELOG entry**

Prepend to `contracts/CHANGELOG.md` under the title, following the existing entry's structure and tone:

```markdown
## 2026-08-28 — card-catalogue 2.8, owner-conditions 1.0 & fixtures 1.3: owner conditions become data

**Additive throughout.** No card record's bytes change; `card-catalogue.json` moves only its
`catalogueVersion` string. Two new fixture cases, no existing expectation touched.

- **New `owner-conditions.json` + schema, both in the release digest.** Declares every
  `ownerConditions` id: how it is answered, and the English source prompt to ask it with.
  This is a **sidecar registry, not spec §3.2's inline `[{conditionId, prompt}]` shape**.
  `EarnRule.ownerConditions` is a published `[String]` inside a content-addressed release with
  four vendored copies across two repos; changing its element type is a MAJOR bump. `programs.json`
  solved the identical open-set problem for valuations one section earlier in the same spec, and
  this follows that precedent instead.
- **`amazonEligiblePrimeLinked` is answerable for the first time.** It shipped in the catalogue
  with no `RuleMatcher` case, so `amazon-ca-prime-2_5x` fell to `default: return false` and could
  never fire in any build. `CatalogueIntegrityTests.knownUnhandledConditions` is now **empty**.
  Owners of that card who confirm a linked Prime membership will begin seeing 2.5x — a behaviour
  change, and an intended one.
- **`CardState.flags: [String: Bool]?`** carries answers by condition id in both engines. The
  named `rogersEligibleServiceLinked` / `cryptoLevelUpProActive` properties are **retained and
  mirrored** for one release: MoneyTalks stores owner state and has not been audited for which
  keys it reads. Legacy states decode unchanged; `flags` wins on conflict. Removing the named
  properties is a follow-up gated on that audit.
- **`FILES` in `release-catalogue.sh` gained two entries** (`owner-conditions.json`,
  `schema/owner-conditions.schema.json`). **MoneyTalks' `FILES` list must be updated to match**
  or its `contracts.test.ts` digest check will fail against this release.
- Prompts are English source strings, not display strings. Consumers resolve
  `ownerCondition.<id>.prompt` from their own catalogue and fall back to the registry, so a new
  condition ships working immediately and picks up translations without a contract release.
```

- [ ] **Step 4: Sync, restamp, and verify everything**

```bash
./scripts/sync-contracts-into-engine.sh
./scripts/sync-contracts-into-android.sh
./scripts/release-catalogue.sh
./scripts/release-catalogue.sh --check
python3 scripts/validate-catalogue-schema.py
./scripts/check-id-permanence.sh
cd Engine && swift test && cd ../Store && swift test
cd ../android && ./gradlew --no-daemon :core:engine:test
```

Expected: stamp check passes, schemas validate, all three suites green with the 28 original fixture expectations unchanged and 2 new cases passing.

- [ ] **Step 5: Commit**

```bash
git add contracts/ Engine/Sources/CardCopilotEngine/Resources/ \
        Engine/Tests/CardCopilotEngineTests/Fixtures/ \
        android/core/engine/src/main/resources/
git commit -m "chore(contracts): release card-contracts@2.8 — owner conditions as data

Pins amazonEligiblePrimeLinked with a fixture case that could not have passed in
any prior build. MoneyTalks' FILES list needs the two new entries."
```

---

# Phase 3 — The UI

**Model: Sonnet 5 · Effort: High** (escalate Task 12 to Opus 5 if the debounce/undo interaction proves fiddly). Do not begin until Phase 2 is green on all four CI jobs.

### Task 9: The condition editor

**Files:**
- Create: `App/CardCopilot/Views/Wallet/OwnerConditionEditor.swift`

**Interfaces:**
- Consumes: `SeedLoader.ownerConditions`, `OwnerCondition`, `OwnerConditionAnswerKind`.
- Produces: `OwnerConditionEditor` (a `View` taking `cardId`, `conditionIds: [String]`, `answers: Binding<[String: Bool]>`, `tangerineCategories: Binding<[String]?>`); `WalletConditions.ids(for:catalogue:) -> [String]`.

- [ ] **Step 1: Write the failing test**

Create `App/CardCopilotTests/WalletConditionsTests.swift`:

```swift
import XCTest
@testable import CardCopilot
import CardCopilotEngine

final class WalletConditionsTests: XCTestCase {

    func testConditionIdsComeFromTheCardsOwnRules() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        XCTAssertEqual(WalletConditions.ids(for: "rogers-red-we", catalogue: catalogue),
                       ["rogersEligibleServiceLinked"])
        XCTAssertEqual(WalletConditions.ids(for: "cryptocom-royal-indigo", catalogue: catalogue),
                       ["cryptoLevelUpProActive"])
    }

    func testACardWithNoConditionsReturnsNothing() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        XCTAssertTrue(WalletConditions.ids(for: "amex-cobalt", catalogue: catalogue).isEmpty)
    }

    /// No card id is hardcoded anywhere: adding a conditional card to the catalogue must make
    /// its question appear with no App change at all.
    func testAmazonCardSurfacesItsConditionWithNoCodeChange() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        XCTAssertEqual(WalletConditions.ids(for: "amazon-ca-rewards-mastercard", catalogue: catalogue),
                       ["amazonEligiblePrimeLinked"])
    }

    func testPromptFallsBackToTheRegistryWhenUntranslated() {
        let prompt = WalletConditions.prompt(for: "amazonEligiblePrimeLinked")
        XCTAssertFalse(prompt.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
SIM_UDID=$(xcrun simctl list devices available | grep -m1 -o "[0-9A-F-]\{36\}")
cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot \
  -configuration Debug -destination "id=$SIM_UDID" CODE_SIGNING_ALLOWED=NO \
  -only-testing:CardCopilotTests/WalletConditionsTests
```

Expected: compile failure — `WalletConditions` does not exist.

- [ ] **Step 3: Write the implementation**

Create `App/CardCopilot/Views/Wallet/OwnerConditionEditor.swift`:

```swift
import SwiftUI
import CardCopilotEngine

/// Which conditions a card raises, and how to word them. Derived entirely from the catalogue and
/// the registry — no card id appears in this file. Adding a conditional card to the catalogue
/// makes its question appear with no App change, which is the whole point of the registry.
enum WalletConditions {

    static func ids(for cardId: String, catalogue: Catalogue) -> [String] {
        guard let card = catalogue.cards.first(where: { $0.cardId == cardId }) else { return [] }
        var seen: Set<String> = []
        return card.earnRules
            .compactMap(\.ownerConditions)
            .flatMap { $0 }
            .filter { seen.insert($0).inserted }
    }

    static func condition(_ id: String) -> OwnerCondition? { SeedLoader.ownerConditions[id] }

    /// Localized question, falling back to the registry's English source string. A condition
    /// added to the contract is askable the day it lands and picks up fr-CA on the next
    /// translation pass, with no contract release in between.
    static func prompt(for id: String) -> String {
        let fallback = condition(id)?.prompt ?? id
        return String(localized: String.LocalizationValue("ownerCondition.\(id).prompt"),
                      defaultValue: String.LocalizationValue(fallback))
    }

    static func detail(for id: String) -> String? {
        guard let fallback = condition(id)?.detail else { return nil }
        return String(localized: String.LocalizationValue("ownerCondition.\(id).detail"),
                      defaultValue: String.LocalizationValue(fallback))
    }

    /// Conditions on owned cards with no answer recorded. Drives the checklist banner and the
    /// per-card badge. Only `boolean` conditions count — a category selection legitimately has
    /// no answer when the owner has selected nothing.
    static func unanswered(ownedCardIds: [String], catalogue: Catalogue,
                           answers: [String: [String: Bool]]) -> [(cardId: String, conditionId: String)] {
        ownedCardIds.flatMap { cardId in
            ids(for: cardId, catalogue: catalogue)
                .filter { condition($0)?.answerKind == .boolean }
                .filter { answers[cardId]?[$0] == nil }
                .map { (cardId: cardId, conditionId: $0) }
        }
    }
}

/// One card's conditions, rendered inline beneath it in the wallet editor.
struct OwnerConditionEditor: View {
    let cardId: String
    let conditionIds: [String]
    @Binding var answers: [String: Bool]
    @Binding var tangerineCategories: [String]?

    var body: some View {
        ForEach(conditionIds, id: \.self) { id in
            if let condition = WalletConditions.condition(id) {
                switch condition.answerKind {
                case .boolean: booleanRow(id, condition)
                case .categorySelection: categoryRows(condition)
                }
            }
        }
    }

    private func booleanRow(_ id: String, _ condition: OwnerCondition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(WalletConditions.prompt(for: id))
                .font(.subheadline)
            if let detail = WalletConditions.detail(for: id) {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            // Tri-state, never two. "I'm not sure" is a real answer that keeps the rule skipped;
            // collapsing it into "No" would tell the engine something the owner never said.
            Picker(WalletConditions.prompt(for: id), selection: triState(id)) {
                Text("Yes").tag("yes")
                Text("No").tag("no")
                Text("I'm not sure").tag("unknown")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private func triState(_ id: String) -> Binding<String> {
        Binding(
            get: { answers[id].map { $0 ? "yes" : "no" } ?? "unknown" },
            set: { answers[id] = $0 == "unknown" ? nil : ($0 == "yes") })
    }

    @ViewBuilder
    private func categoryRows(_ condition: OwnerCondition) -> some View {
        let limit = condition.maxSelections ?? 3
        if let detail = condition.detail {
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        ForEach(TangerineMoneyBackCategory.allCases, id: \.rawValue) { category in
            Toggle(category.setupLabel, isOn: categoryBinding(category, limit: limit))
                .disabled(!isSelected(category) && (tangerineCategories?.count ?? 0) >= limit)
        }
    }

    private func isSelected(_ category: TangerineMoneyBackCategory) -> Bool {
        tangerineCategories?.contains(category.rawValue) == true
    }

    private func categoryBinding(_ category: TangerineMoneyBackCategory,
                                 limit: Int) -> Binding<Bool> {
        Binding(
            get: { isSelected(category) },
            set: { selected in
                var categories = tangerineCategories ?? []
                if selected, !categories.contains(category.rawValue), categories.count < limit {
                    categories.append(category.rawValue)
                } else {
                    categories.removeAll { $0 == category.rawValue }
                }
                tangerineCategories = categories.isEmpty ? nil : categories
            })
    }
}

extension TangerineMoneyBackCategory {
    var setupLabel: LocalizedStringKey {
        switch self {
        case .grocery: "Grocery"
        case .dining: "Restaurants"
        case .gasStation: "Gas"
        case .entertainment: "Entertainment"
        case .furniture: "Furniture"
        case .lodging: "Hotel-Motel"
        case .drugStore: "Drug Store"
        case .recurring: "Recurring Bill Payments"
        case .homeImprovement: "Home Improvement"
        case .transit: "Public Transportation and Parking"
        case .eGames: "E-Games"
        case .fitness: "Fitness and Sports Clubs"
        case .foreignCurrency: "Foreign Currency Spend"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
SIM_UDID=$(xcrun simctl list devices available | grep -m1 -o "[0-9A-F-]\{36\}")
cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot \
  -configuration Debug -destination "id=$SIM_UDID" CODE_SIGNING_ALLOWED=NO \
  -only-testing:CardCopilotTests/WalletConditionsTests
```

Expected: 4 tests PASS.

> `TangerineMoneyBackCategory.setupLabel` currently lives in a private extension at the bottom of `WalletSetupView.swift`. Delete that extension in this step to avoid a duplicate-symbol error; the copy above replaces it verbatim.

- [ ] **Step 5: Commit**

```bash
git add App/CardCopilot/Views/Wallet/OwnerConditionEditor.swift \
        App/CardCopilotTests/WalletConditionsTests.swift \
        App/CardCopilot/Views/WalletSetupView.swift
git commit -m "feat(app): owner conditions render from the registry, not hardcoded card ids"
```

---

### Task 10: The checklist banner

**Files:**
- Create: `App/CardCopilot/Views/Wallet/WalletChecklistBanner.swift`
- Create: `App/CardCopilotTests/WalletChecklistTests.swift`

**Interfaces:**
- Consumes: `WalletConditions.unanswered(ownedCardIds:catalogue:answers:)` from Task 9.
- Produces: `WalletChecklistItem`, `WalletChecklist.items(setup:catalogue:) -> [WalletChecklistItem]`, `WalletChecklistBanner`.

- [ ] **Step 1: Write the failing test**

Create `App/CardCopilotTests/WalletChecklistTests.swift`:

```swift
import XCTest
@testable import CardCopilot
import CardCopilotEngine
import CardCopilotStore

/// RuleMatcher fails closed, so an unanswered condition costs the owner a bonus rate silently
/// and permanently. The banner exists to make that visible, and to KEEP being visible — a card
/// added six months after onboarding raises its question the same way.
final class WalletChecklistTests: XCTestCase {

    private func setup(cards: [String], answers: [String: [String: Bool]] = [:],
                       defaultCard: String = "") -> WalletSetup {
        WalletSetup(ownedCardIds: cards, defaultCardId: defaultCard,
                    conditionAnswers: answers,
                    switchThreshold: OwnerStateBuilder.defaultSwitchThreshold,
                    valuationsCad: Valuations(programs: [:]))
    }

    func testEmptyWalletAsksForACard() throws {
        let items = WalletChecklist.items(setup: setup(cards: []),
                                          catalogue: try SeedLoader.loadCatalogue())
        XCTAssertTrue(items.contains { $0.kind == .addCards })
    }

    func testUnansweredConditionAppears() throws {
        let items = WalletChecklist.items(setup: setup(cards: ["rogers-red-we"],
                                                       defaultCard: "rogers-red-we"),
                                          catalogue: try SeedLoader.loadCatalogue())
        XCTAssertTrue(items.contains { $0.kind == .answerCondition })
    }

    func testAnsweredConditionDisappears() throws {
        let answers = ["rogers-red-we": ["rogersEligibleServiceLinked": false]]
        let items = WalletChecklist.items(setup: setup(cards: ["rogers-red-we"],
                                                       answers: answers,
                                                       defaultCard: "rogers-red-we"),
                                          catalogue: try SeedLoader.loadCatalogue())
        XCTAssertFalse(items.contains { $0.kind == .answerCondition },
                       "'no' is an answer — the item is done, not still outstanding")
    }

    func testFullySetUpWalletHasNoItems() throws {
        let items = WalletChecklist.items(setup: setup(cards: ["amex-cobalt"],
                                                       defaultCard: "amex-cobalt"),
                                          catalogue: try SeedLoader.loadCatalogue())
        XCTAssertTrue(items.isEmpty)
    }

    func testMissingDefaultCardIsFlagged() throws {
        let items = WalletChecklist.items(setup: setup(cards: ["amex-cobalt"], defaultCard: ""),
                                          catalogue: try SeedLoader.loadCatalogue())
        XCTAssertTrue(items.contains { $0.kind == .chooseDefault })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
SIM_UDID=$(xcrun simctl list devices available | grep -m1 -o "[0-9A-F-]\{36\}")
cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot \
  -configuration Debug -destination "id=$SIM_UDID" CODE_SIGNING_ALLOWED=NO \
  -only-testing:CardCopilotTests/WalletChecklistTests
```

Expected: compile failure — `WalletChecklist` does not exist.

- [ ] **Step 3: Write the implementation**

Create `App/CardCopilot/Views/Wallet/WalletChecklistBanner.swift`:

```swift
import SwiftUI
import CardCopilotEngine
import CardCopilotStore

struct WalletChecklistItem: Identifiable, Equatable {
    enum Kind: Equatable { case addCards, chooseDefault, answerCondition }

    let id: String
    let kind: Kind
    let title: String
    /// What answering it buys. An item that cannot say why it matters does not belong here.
    let payoff: String?
    let cardId: String?
}

/// Derives what is still outstanding, from catalogue + setup. Not persisted and not dismissible:
/// it is a live view of state, so it disappears by being resolved rather than by being ignored.
enum WalletChecklist {

    static func items(setup: WalletSetup, catalogue: Catalogue) -> [WalletChecklistItem] {
        var items: [WalletChecklistItem] = []

        if setup.ownedCardIds.isEmpty {
            items.append(WalletChecklistItem(
                id: "addCards", kind: .addCards,
                title: String(localized: "Add your cards"),
                payoff: String(localized: "PickMe only recommends cards you add."),
                cardId: nil))
            return items   // nothing else is answerable yet
        }

        if setup.defaultCardId.isEmpty || !setup.ownedCardIds.contains(setup.defaultCardId) {
            items.append(WalletChecklistItem(
                id: "chooseDefault", kind: .chooseDefault,
                title: String(localized: "Choose a default card"),
                payoff: String(localized: "Used when no card is clearly better."),
                cardId: nil))
        }

        for gap in WalletConditions.unanswered(ownedCardIds: setup.ownedCardIds,
                                               catalogue: catalogue,
                                               answers: setup.conditionAnswers) {
            let name = catalogue.cards.first { $0.cardId == gap.cardId }?.officialName ?? gap.cardId
            items.append(WalletChecklistItem(
                id: "\(gap.cardId).\(gap.conditionId)",
                kind: .answerCondition,
                title: String(localized: "Answer 1 question about \(name)"),
                payoff: WalletConditions.detail(for: gap.conditionId),
                cardId: gap.cardId))
        }

        return items
    }
}

struct WalletChecklistBanner: View {
    let items: [WalletChecklistItem]
    let totalSteps: Int
    let onSelect: (WalletChecklistItem) -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Finish setting up · \(totalSteps - items.count) of \(totalSteps)")
                    .font(.subheadline.weight(.semibold))

                ForEach(items) { item in
                    Button { onSelect(item) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.footnote.weight(.medium))
                                if let payoff = item.payoff {
                                    Text(payoff).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Opens the item that needs an answer"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.accentColor.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.35)))
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
SIM_UDID=$(xcrun simctl list devices available | grep -m1 -o "[0-9A-F-]\{36\}")
cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot \
  -configuration Debug -destination "id=$SIM_UDID" CODE_SIGNING_ALLOWED=NO \
  -only-testing:CardCopilotTests/WalletChecklistTests
```

Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add App/CardCopilot/Views/Wallet/WalletChecklistBanner.swift \
        App/CardCopilotTests/WalletChecklistTests.swift
git commit -m "feat(app): a setup checklist that outlives onboarding

RuleMatcher fails closed, so an unanswered condition silently costs a bonus rate
forever. This is the only place that says so."
```

---

### Task 11: The Add-a-card sheet

**Files:**
- Create: `App/CardCopilot/Views/Wallet/AddCardSheet.swift`

**Interfaces:**
- Consumes: `WalletCardCatalogue`, `MarketScope` (Task 3); `CardArtView`; `PendingCardRequest`.
- Produces: `AddCardSheet(catalogue:ownedCardIds:residency:onAdd:onRequestCard:onDismiss:)`.

- [ ] **Step 1: Write the view**

Create `App/CardCopilot/Views/Wallet/AddCardSheet.swift`:

```swift
import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// Catalogue browsing, deliberately separate from wallet editing. The catalogue's stated horizon
/// is thousands of cards; keeping it behind its own surface is what stops that growth from
/// becoming the wallet screen's problem.
struct AddCardSheet: View {
    let catalogue: Catalogue
    let ownedCardIds: [String]
    let residency: Market
    let onAdd: (String) -> Void
    let onRequestCard: (PendingCardRequest) async -> Bool
    let onDismiss: () -> Void

    @AppStorage("ca.pickme.wallet.market-scope") private var storedScope: String = ""
    @State private var searchText = ""
    @State private var issuer = ""
    @State private var cardName = ""
    @State private var requestMessage: String?

    private var scope: MarketScope {
        MarketScope(rawValue: storedScope) ?? .default(for: residency)
    }

    private var results: [(issuer: String, cards: [CardProduct])] {
        let selectable = WalletCardCatalogue.selectable(catalogue.cards, scope: scope)
        return WalletCardCatalogue.groupedByIssuer(
            WalletCardCatalogue.filter(selectable, matching: searchText))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Market", selection: Binding(
                        get: { scope },
                        set: { storedScope = $0.rawValue })) {
                        ForEach(MarketScope.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                if results.isEmpty {
                    requestSection
                } else {
                    ForEach(results, id: \.issuer) { group in
                        Section(group.issuer) {
                            ForEach(group.cards) { card in row(card) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: Text("Search cards"))
            .navigationTitle("Add a card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done", action: onDismiss) }
            }
        }
    }

    private func row(_ card: CardProduct) -> some View {
        let owned = ownedCardIds.contains(card.cardId)
        return Button { if !owned { onAdd(card.cardId) } } label: {
            HStack(spacing: 12) {
                CardArtView(cardId: card.cardId, officialName: card.officialName, isHero: false)
                    .frame(width: 52)
                VStack(alignment: .leading, spacing: 2) {
                    // Full name, wrapping. The identifying text is the one thing that must never
                    // be truncated — the old row cut off 4 of 8 visible card names.
                    Text(card.officialName)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(feeLabel(card))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: owned ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(owned ? Color.secondary : Color.accentColor)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(owned)
        .accessibilityLabel(Text(card.officialName))
        .accessibilityValue(Text(owned ? "Already in your wallet" : "Not added"))
        .accessibilityHint(owned ? Text("") : Text("Adds this card to your wallet"))
    }

    /// One card's own fee in its own billing currency — never converted, because this is not a
    /// cross-card sum (see ReportingCurrency.swift).
    private func feeLabel(_ card: CardProduct) -> String {
        let amount = card.fee.annual?.amount ?? 0
        let currency = card.billingCurrency.rawValue
        return amount == 0
            ? String(localized: "\(card.network.rawValue.capitalized) · No annual fee")
            : String(localized: "\(card.network.rawValue.capitalized) · \(currency) \(Int(amount))/yr")
    }

    private var requestSection: some View {
        Section("My card isn't listed") {
            if !searchText.isEmpty {
                Text("No cards found for \"\(searchText)\"")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            TextField("Issuer", text: $issuer).textInputAutocapitalization(.words)
            TextField("Card name", text: $cardName).textInputAutocapitalization(.words)
            Button("Request this card") {
                Task {
                    let sent = await onRequestCard(
                        PendingCardRequest(issuer: issuer, cardName: cardName))
                    requestMessage = sent
                        ? String(localized: "Request sent. Thank you.")
                        : String(localized: "Saved on this iPhone. Sign in from Settings to send it.")
                    if sent { issuer = ""; cardName = "" }
                }
            }
            .disabled(issuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || cardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let requestMessage {
                Text(requestMessage).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
SIM_UDID=$(xcrun simctl list devices available | grep -m1 -o "[0-9A-F-]\{36\}")
cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot \
  -configuration Debug -destination "id=$SIM_UDID" CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED, all tests PASS.

- [ ] **Step 3: Commit**

```bash
git add App/CardCopilot/Views/Wallet/AddCardSheet.swift
git commit -m "feat(app): catalogue browsing moves to its own sheet, grouped by issuer"
```

---

### Task 12: The wallet editor

**Files:**
- Create: `App/CardCopilot/Views/Wallet/WalletEditorView.swift`
- Modify: `App/CardCopilot/Views/CheckoutFlowView.swift:295-304`
- Modify: `App/CardCopilot/State/CopilotEnvironment.swift`
- Delete: `App/CardCopilot/Views/WalletSetupView.swift`

**Interfaces:**
- Consumes: everything from Tasks 3, 9, 10, 11; `OwnerStateBuilder.firstRun` / `apply`.
- Produces: `WalletEditorView(catalogue:existing:isFirstRun:onChange:onCommitFirstRun:onRequestCard:onDone:)`.

- [ ] **Step 1: Write the view**

Create `App/CardCopilot/Views/Wallet/WalletEditorView.swift`:

```swift
import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// The wallet editor. One screen for first run and edit — the three-page wizard is gone, because
/// paging exists to sequence questions and there are no longer questions to sequence: conditions
/// live on the card that raises them, and everything else has a working default.
///
/// Edits apply immediately (D6). There is no staged copy to discard, which is why "Done" is safe
/// here and was not before.
struct WalletEditorView: View {
    let catalogue: Catalogue
    let existing: OwnerState?
    let isFirstRun: Bool
    let onChange: (WalletSetup) -> Void
    let onCommitFirstRun: (WalletSetup) async -> Void
    let onRequestCard: (PendingCardRequest) async -> Bool
    let onDone: () -> Void

    @State private var setup: WalletSetup
    @State private var expandedCardId: String?
    @State private var showingAddSheet = false
    @State private var lastRemoved: (cardId: String, setup: WalletSetup)?

    init(catalogue: Catalogue, existing: OwnerState?, isFirstRun: Bool,
         onChange: @escaping (WalletSetup) -> Void,
         onCommitFirstRun: @escaping (WalletSetup) async -> Void,
         onRequestCard: @escaping (PendingCardRequest) async -> Bool,
         onDone: @escaping () -> Void) {
        self.catalogue = catalogue
        self.existing = existing
        self.isFirstRun = isFirstRun
        self.onChange = onChange
        self.onCommitFirstRun = onCommitFirstRun
        self.onRequestCard = onRequestCard
        self.onDone = onDone

        var initial = existing.map(OwnerStateBuilder.setup(from:))
            ?? WalletSetup(ownedCardIds: [], defaultCardId: "",
                           switchThreshold: OwnerStateBuilder.defaultSwitchThreshold,
                           valuationsCad: Valuations(programs: [:]))
        // Residency is inferred, then corrected in place (D1). A bundled seed is a developer
        // fallback, never a new customer's wallet.
        if initial.market == nil { initial.market = Self.inferredResidency() }
        _setup = State(initialValue: initial)
    }

    static func inferredResidency() -> Market {
        Locale.current.region?.identifier == "US" ? .us : .ca
    }

    private var ownedCards: [CardProduct] {
        setup.ownedCardIds.compactMap { id in catalogue.cards.first { $0.cardId == id } }
    }

    private var checklistItems: [WalletChecklistItem] {
        WalletChecklist.items(setup: setup, catalogue: catalogue)
    }

    var body: some View {
        List {
            if !checklistItems.isEmpty {
                Section {
                    WalletChecklistBanner(items: checklistItems, totalSteps: 3) { item in
                        if let cardId = item.cardId { expandedCardId = cardId }
                        else if item.kind == .addCards { showingAddSheet = true }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            Section {
                if ownedCards.isEmpty {
                    ContentUnavailableView(
                        "No cards yet", systemImage: "creditcard",
                        description: Text("PickMe only recommends cards you add here."))
                } else {
                    ForEach(ownedCards) { card in cardRow(card) }
                }
                Button { showingAddSheet = true } label: {
                    Label("Add a card", systemImage: "plus.circle.fill")
                }
            } header: {
                HStack {
                    Text("Your cards")
                    Spacer()
                    if !ownedCards.isEmpty { Text("\(ownedCards.count)") }
                }
            }

            preferencesSection
        }
        .navigationTitle(isFirstRun ? "Set up your wallet" : "Edit wallet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isFirstRun {
                ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onDone) }
            }
        }
        .safeAreaInset(edge: .bottom) { firstRunCommitBar }
        .sheet(isPresented: $showingAddSheet) {
            AddCardSheet(catalogue: catalogue, ownedCardIds: setup.ownedCardIds,
                         residency: setup.market ?? .ca,
                         onAdd: add(_:), onRequestCard: onRequestCard,
                         onDismiss: { showingAddSheet = false })
        }
        .overlay(alignment: .bottom) { undoBar }
    }

    private func cardRow(_ card: CardProduct) -> some View {
        let conditionIds = WalletConditions.ids(for: card.cardId, catalogue: catalogue)
        let unanswered = conditionIds.filter {
            WalletConditions.condition($0)?.answerKind == .boolean
                && setup.conditionAnswers[card.cardId]?[$0] == nil
        }
        return DisclosureGroup(isExpanded: expansion(card.cardId)) {
            OwnerConditionEditor(
                cardId: card.cardId, conditionIds: conditionIds,
                answers: answersBinding(card.cardId),
                tangerineCategories: Binding(
                    get: { setup.tangerineSelectedCategories },
                    set: { setup.tangerineSelectedCategories = $0; commit() }))

            Toggle("Use by default", isOn: Binding(
                get: { setup.defaultCardId == card.cardId },
                set: { if $0 { setup.defaultCardId = card.cardId; commit() } }))

            Button("Remove from wallet", role: .destructive) { remove(card.cardId) }
        } label: {
            HStack(spacing: 12) {
                CardArtView(cardId: card.cardId, officialName: card.officialName, isHero: false)
                    .frame(width: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.officialName)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(card.issuer).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if setup.defaultCardId == card.cardId {
                    Text("DEFAULT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
                if !unanswered.isEmpty {
                    Text("\(unanswered.count) ASK")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                        .accessibilityLabel(Text("\(unanswered.count) unanswered question"))
                }
            }
        }
    }

    private var preferencesSection: some View {
        Section("Preferences") {
            Picker("Showing cards from", selection: Binding(
                get: { setup.market ?? .ca },
                set: { setup.market = $0; commit() })) {
                Text("Canada").tag(Market.ca)
                Text("United States").tag(Market.us)
            }
            DisclosureGroup("Advanced switch threshold") {
                Stepper("At least \(setup.switchThreshold.minAdvantagePercentagePoints, specifier: "%.1f") percentage points better",
                        value: Binding(get: { setup.switchThreshold.minAdvantagePercentagePoints },
                                       set: { setup.switchThreshold.minAdvantagePercentagePoints = $0; commit() }),
                        in: 0...10, step: 0.1)
                Stepper("At least $\(setup.switchThreshold.minAdvantageCad, specifier: "%.2f") more",
                        value: Binding(get: { setup.switchThreshold.minAdvantageCad },
                                       set: { setup.switchThreshold.minAdvantageCad = $0; commit() }),
                        in: 0...20, step: 0.05)
                Text("Both must be true before PickMe suggests switching cards.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var firstRunCommitBar: some View {
        if isFirstRun {
            Button("Start using PickMe") { Task { await onCommitFirstRun(setup) } }
                .buttonStyle(.borderedProminent)
                .disabled(setup.ownedCardIds.isEmpty)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }

    @ViewBuilder
    private var undoBar: some View {
        if let removed = lastRemoved {
            let name = catalogue.cards.first { $0.cardId == removed.cardId }?.officialName ?? ""
            HStack {
                Text("Removed \(name)").font(.footnote).lineLimit(1)
                Spacer()
                Button("Undo") { setup = removed.setup; lastRemoved = nil; commit() }
                    .font(.footnote.weight(.semibold))
            }
            .padding(12)
            .background(.regularMaterial, in: Capsule())
            .padding(.horizontal)
            .padding(.bottom, isFirstRun ? 72 : 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: removed.cardId) {
                try? await Task.sleep(for: .seconds(6))
                withAnimation { lastRemoved = nil }
            }
        }
    }

    // MARK: - Mutations

    private func expansion(_ cardId: String) -> Binding<Bool> {
        Binding(get: { expandedCardId == cardId },
                set: { expandedCardId = $0 ? cardId : nil })
    }

    private func answersBinding(_ cardId: String) -> Binding<[String: Bool]> {
        Binding(get: { setup.conditionAnswers[cardId] ?? [:] },
                set: { setup.conditionAnswers[cardId] = $0.isEmpty ? nil : $0; commit() })
    }

    private func add(_ cardId: String) {
        guard !setup.ownedCardIds.contains(cardId) else { return }
        setup.ownedCardIds.append(cardId)
        normalizeDefault()
        commit()
    }

    private func remove(_ cardId: String) {
        let before = setup
        setup.ownedCardIds.removeAll { $0 == cardId }
        setup.conditionAnswers[cardId] = nil
        normalizeDefault()
        withAnimation { lastRemoved = (cardId: cardId, setup: before) }
        commit()
    }

    private func normalizeDefault() {
        if !setup.ownedCardIds.contains(setup.defaultCardId) {
            setup.defaultCardId = setup.ownedCardIds.first ?? ""
        }
    }

    /// Apply immediately. First run holds its changes until the explicit commit, because until
    /// then there is no wallet to update and `walletIsFirstRun` has not flipped.
    private func commit() {
        guard !isFirstRun else { return }
        onChange(setup)
    }
}
```

- [ ] **Step 2: Add the debounced write path**

In `App/CardCopilot/State/CopilotEnvironment.swift`, add alongside `saveWalletSetup`:

```swift
    private var walletWriteTask: Task<Void, Never>?

    /// Applies a wallet edit immediately to local state, then debounces the durable save and
    /// server upload. Local-first is deliberate: the device copy is the checkout source of truth
    /// while offline, and a person who toggles three things in four seconds should produce one
    /// upload, not three.
    func applyWalletEdit(_ setup: WalletSetup, session: CopilotSession, router: CheckoutRouter) {
        guard let graph else { return }
        let owner = OwnerStateBuilder.apply(setup, to: graph.ownerState, catalogue: graph.catalogue)
        rebuild(ownerState: owner)
        session.refresh(using: self.graph!)

        walletWriteTask?.cancel()
        walletWriteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            await self.saveWalletSetup(setup, session: session, router: router)
        }
    }
```

> `saveWalletSetup` ends with `if router.path.last == .walletSetup { router.pop() }`. That must not fire on a debounced autosave — it would eject the user mid-edit. Guard it: `if walletIsFirstRun == false && router.path.last == .walletSetup { }` is NOT sufficient. Add a `popsOnSave: Bool = true` parameter to `saveWalletSetup` and pass `false` from `applyWalletEdit`.

- [ ] **Step 3: Present the new view**

In `App/CardCopilot/Views/CheckoutFlowView.swift`, replace the `.walletSetup` case body (lines 295–304):

```swift
        case .walletSetup:
            if let graph = environment.graph {
                WalletEditorView(
                    catalogue: graph.catalogue,
                    existing: environment.walletIsFirstRun ? nil : graph.ownerState,
                    isFirstRun: environment.walletIsFirstRun,
                    onChange: { setup in
                        environment.applyWalletEdit(setup, session: session, router: router)
                    },
                    onCommitFirstRun: { setup in
                        await environment.saveWalletSetup(setup, session: session, router: router)
                    },
                    onRequestCard: { request in await environment.requestCard(request) },
                    onDone: { router.pop() })
            }
```

- [ ] **Step 4: Delete the old view**

```bash
git rm App/CardCopilot/Views/WalletSetupView.swift
```

- [ ] **Step 5: Build and run everything**

```bash
SIM_UDID=$(xcrun simctl list devices available | grep -m1 -o "[0-9A-F-]\{36\}")
cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot \
  -configuration Debug -destination "id=$SIM_UDID" CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED, all tests PASS. `seed` and `onSave` are no longer parameters — remove any now-unused plumbing the compiler flags.

- [ ] **Step 6: Commit**

```bash
git add App/CardCopilot/Views/Wallet/WalletEditorView.swift \
        App/CardCopilot/Views/CheckoutFlowView.swift \
        App/CardCopilot/State/CopilotEnvironment.swift
git rm --cached App/CardCopilot/Views/WalletSetupView.swift 2>/dev/null || true
git commit -m "feat(app): one wallet editor, no wizard, edits apply immediately

Deletes the 3-page TabView. Conditions live on the card that raises them; the
Done button can no longer discard work because there is no staged copy to discard."
```

---

### Task 13: Strings and a device pass

**Files:**
- Modify: `App/CardCopilot/Localizable.xcstrings`

- [x] **Step 1: Build to populate the string catalogue**

```bash
SIM_UDID=$(xcrun simctl list devices available | grep -m1 -o "[0-9A-F-]\{36\}")
cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot \
  -configuration Debug -destination "id=$SIM_UDID" CODE_SIGNING_ALLOWED=NO
```

Xcode extracts new `String(localized:)` keys automatically. Confirm the additions:

```bash
python3 -c "
import json
d = json.load(open('App/CardCopilot/Localizable.xcstrings'))
new = [k for k in d['strings'] if 'ownerCondition.' in k or k in
       ('Add a card','Your cards','Edit wallet','Finish setting up · %lld of %lld',
        'Use by default','Remove from wallet','No cards yet','Start using PickMe')]
print(len(d['strings']), 'total;', len(new), 'from this work')
for k in sorted(new): print(' ', k)
"
```

- [x] **Step 2: Add fr-CA translations**

Every new key needs an `fr-CA` localization. The app ships en + fr-CA across 612 strings; a Canadian product must not ask French-Canadian users an English question. Add each `ownerCondition.<id>.prompt` and `.detail` key explicitly — those fall back to English registry text if absent, so a missing translation is silent rather than a build error.

- [x] **Step 3: Real-device or simulator pass**

Verify by hand, in both light and dark:

1. First run with an empty wallet → checklist shows "Add your cards" → sheet → add two cards.
2. Add `rogers-red-we` → amber "1 ASK" badge appears on its row AND as a checklist line.
3. Answer "I'm not sure" → the badge and checklist line **stay** (unresolved, not answered).
4. Answer "No" → both clear.
5. Market toggle CA → US → Both changes the sheet's contents; no draft card appears in any of the three.
6. Remove a card → undo bar → Undo restores it with its condition answers intact.
7. Leave via Done mid-edit, re-enter → every change is still there.
8. VoiceOver: each card row announces its name, default status and unanswered count.

- [ ] **Step 4: Full CI parity run**

```bash
cd Engine && swift test && cd ../Store && swift test
cd ../android && ./gradlew --no-daemon :core:engine:test
./scripts/release-catalogue.sh --check
python3 scripts/validate-catalogue-schema.py
SIM_UDID=$(xcrun simctl list devices available | grep -m1 -o "[0-9A-F-]\{36\}")
cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot \
  -configuration Debug -destination "id=$SIM_UDID" CODE_SIGNING_ALLOWED=NO
```

Expected: every one green.

- [ ] **Step 5: Commit**

```bash
git add App/CardCopilot/Localizable.xcstrings
git commit -m "chore(app): en + fr-CA strings for the wallet editor"
```

---

## Follow-ups this plan deliberately leaves open

Each is real, each is out of scope, none blocks shipping.

1. **The D4 audit.** Confirm what MoneyTalks reads from `cardStates`, then delete `rogersEligibleServiceLinked` / `cryptoLevelUpProActive` and `mirroringLegacyFlags`. Cross-repo.
2. **MoneyTalks' `FILES` list** needs `owner-conditions.json` and its schema, or its `contracts.test.ts` digest check fails against `card-contracts@2.8`. Flagged in the CHANGELOG; someone must act on it.
3. **Cap anchors → `CardState.anchors`** (spec §3.3). Identical open-set-as-closed-set defect, and `knownUnresolvableAnchors` still carries `amexAccountAnniversaryMonth` and `rbcAccountAnniversaryMonth` — two cards whose cap windows silently return nil.
4. **A `Warning` case for unresolved conditions**, so the *checkout* screen can say "this card could be 2% if you answered" rather than only the wallet editor. Deferred under D7: two exhaustive Swift switches plus the Kotlin explainer.
5. **79 draft US cards** are now correctly hidden. They stay invisible until someone clears D3's sourcing bar per card — a data task, not a code one.

---

## Self-Review

Run against the design decisions above.

**Coverage.** D1 → Tasks 3, 11, 12 (`preferencesSection`, `inferredResidency`). D2 → Tasks 10, 12. D3 → Task 4. D4 → Tasks 1, 5, 7. D5 → Tasks 9, 13. D6 → Tasks 1, 2, 12. D7 → Task 10, and recorded as follow-up 4. Bug #1 → Task 1. Bug #2 → Task 1. Bug #3 → Task 12 (dissolved, not patched). Draft-card bug → Task 3. Amazon Prime → Tasks 4, 6, 8.

**Placeholders.** None. Every code step carries the literal content. Task 8 Step 1 describes the two fixture cases rather than transcribing them, because `engine-fixtures.json`'s case shape must be copied from a live neighbour — the step says so explicitly and names both case ids and both expectations.

**Type consistency.** `WalletSetup.conditionAnswers: [String: [String: Bool]]` is used identically in Tasks 1, 9, 10, 12. `MarketScope` is defined in Task 3 and consumed in Task 11. `WalletConditions.ids(for:catalogue:)` is defined in Task 9 and consumed in Tasks 10 and 12. `CardState.resolvedFlags` is shimmed in Task 1, made real in Task 5, and the shim's deletion is an explicit step in Task 5. `mirroringLegacyFlags` is introduced in Task 1 and survives Task 5 deliberately.

**Known ordering hazard.** Task 1 depends on `CardState.flags`, which Task 5 creates. This is resolved by the temporary shim in Task 1 Step 3, deleted in Task 5 Step 4 — chosen so Phase 0's data-loss fix can ship on its own rather than waiting behind a contract release.
