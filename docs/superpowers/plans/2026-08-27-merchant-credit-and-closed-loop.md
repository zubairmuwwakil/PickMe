# merchantCredit and Closed-Loop Acceptance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reclassify the 34 `deferredNotOneCurrency` co-brands from evidence, add a `merchantCredit` valuation model for merchant-locked store credit, and let a private-label card declare merchant acceptance instead of a payment network.

**Architecture:** Three independent changes sharing one release. The pipeline classifier is pure Python and ships alone. `merchantCredit` is a new `ProgramValuation` case declared *alongside* `ctMoney` (never folded into it). Closed-loop acceptance adds an optional `acceptance` object to `CardProduct` and a second branch to `Scorer`'s acceptance guard, leaving all 85 existing cards byte-identical.

**Tech Stack:** Swift 5.9 (canonical, `Engine/`), Kotlin + kotlinx.serialization (`android/core/engine/`), TypeScript (`MoneyTalks/src/engine/cards-twin/`), Python 3 (`catalogue-pipeline/scripts/`).

**Spec:** `docs/superpowers/specs/2026-08-27-merchant-credit-and-closed-loop-design.md`

## Global Constraints

- **Swift is canonical.** Every contract change lands Swift + fixtures FIRST, then Kotlin, then the TypeScript twin in MoneyTalks. Never the other way round.
- **Green baseline that must hold at every commit:** Swift **276**, Kotlin **46**, TypeScript **1095**.
- **Test commands:**
  - Swift: `cd Engine && swift test`
  - Kotlin: `cd android && ./gradlew :core:engine:test --offline`
  - TypeScript: `cd ../MoneyTalks && npx vitest run` and `npx tsc --noEmit`
- **`cardId`s are permanent.** `catalogue-pipeline/idmap.json` is append-only; `scripts/check-id-permanence.sh` must pass.
- **Any change to a file under `contracts/` requires the full release dance:** bump `catalogueVersion` → `scripts/release-catalogue.sh` → commit → push → `scripts/publish-catalogue.sh` → `MoneyTalks/scripts/sync-contracts.sh`. A published release id must NEVER describe two different byte-sets.
- **Target release:** `card-contracts@2.5`. Additive only — no existing card's score changes.
- **Drafts:** `status: "draft"` cards carry `earnRules: []` and are NEVER `issuerConfirmed`. `lastVerifiedAt` on a draft is the SNAPSHOT date.
- **Never guess `network` or `programId`.** Record a gap instead.
- **Merchant tokens are lowercase kebab-case** — pinned by `CatalogueIntegrityTests.testMerchantBrandTokensAreLowercaseKebabCase`. Any new merchant token must match `^[a-z0-9]+(-[a-z0-9]+)*$`.
- **Commit directly to `main`. No feature branches. NO `Co-Authored-By` trailers.**
- **A concurrent session commits in this repo.** Before every commit, run `git log --oneline -1` and stage explicitly by pathspec (`git commit -- <paths>`). Never `git add -A`.

---

## File Structure

**Phase 1 — pipeline (no contract change, no release)**
- Modify: `catalogue-pipeline/scripts/propose_programs.py` — replace two catch-all name regexes with an evidence classifier keyed on the cc-offers `category` field.
- Modify: `catalogue-pipeline/promote-refusals-us.json` — regenerated output.
- Modify: `catalogue-pipeline/programid-additions.proposed.json` — regenerated output.

**Phase 2 — schema integrity gate (prerequisite for Phase 3)**
- Modify: `contracts/schema/programs.schema.json` — add the missing `noRewards` variant.
- Create: `Engine/Tests/CardCopilotEngineTests/ProgramsSchemaTests.swift` — validate `programs.json` against its schema. Nothing does this today, which is why the drift shipped.

**Phase 3 — `merchantCredit` model**
- Modify: `Engine/Sources/CardCopilotEngine/Models/OwnerState.swift` — add `MerchantCreditValuation`.
- Modify: `Engine/Sources/CardCopilotEngine/Models/ProgramValuation.swift` — add the `.merchantCredit` case, decode, encode.
- Modify: `Engine/Sources/CardCopilotEngine/Engine/Scorer.swift` — add the `.merchantCredit` arm of `valueCad`.
- Create: `Engine/Tests/CardCopilotEngineTests/MerchantCreditProgramTests.swift`
- Modify: `contracts/schema/programs.schema.json` — add the `merchantCredit` variant.
- Modify: `android/core/engine/src/main/kotlin/com/cardcopilot/engine/models/ProgramValuation.kt`
- Modify: `android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/Scorer.kt`
- Create: `android/core/engine/src/test/kotlin/com/cardcopilot/engine/MerchantCreditProgramTest.kt`

**Phase 4 — closed-loop acceptance**
- Modify: `Engine/Sources/CardCopilotEngine/Models/CatalogueModels.swift` — `Network.privateLabel`, `Acceptance`, `CardProduct.acceptance`.
- Modify: `Engine/Sources/CardCopilotEngine/Engine/Scorer.swift` — replace the network guard with the acceptance switch; add `Warning.merchantNotAccepted`.
- Create: `Engine/Tests/CardCopilotEngineTests/ClosedLoopAcceptanceTests.swift`
- Modify: `contracts/schema/card-catalogue.schema.json` — `privateLabel`, `acceptance`, the `if/then` invariant.
- Modify: Kotlin `CatalogueModels.kt` + `Scorer.kt`; create `ClosedLoopAcceptanceTest.kt`.

**Phase 5 — release and vendor**
- Modify: `contracts/RELEASE.json`, `contracts/CHANGELOG.md`, both resource copies.
- MoneyTalks: `src/engine/cards-twin/models.ts`, `Scorer.ts`, plus new tests.

---

## Phase 1 — Reclassification

### Task 1: Replace the two catch-all regexes with an evidence classifier

**Files:**
- Modify: `catalogue-pipeline/scripts/propose_programs.py:89-91`
- Test: `catalogue-pipeline/scripts/test_propose_programs.py` (create)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `classify_from_evidence(row: dict) -> tuple[str, dict] | None`, where the first element is one of `"proposed"`, `"needsEnumValue"`, `"refused"`, and the dict carries `programId`/`unit`/`basis` for `proposed`, `currency`/`basis` for `needsEnumValue`, or `reason` for `refused`.

**Background the implementer needs:** `propose_programs.py` currently classifies a card by regex-matching its **name**. Lines 89 and 91 hold two catch-all rows whose "currency" value is a placeholder string (`"Store-specific rewards"`, `"Brand-specific rewards"`), not a currency. The `basis` recorded on every matched card is literally the regex alternation. The repo's licensed raw source, `catalogue-pipeline/raw/us/cc-offers/cc-offers-export-2026-08-27.json`, has a `rows` array where each row carries a `category` field that is a far better signal. Match a proposal row to a raw row on `card_offer`.

- [ ] **Step 1: Write the failing test**

Create `catalogue-pipeline/scripts/test_propose_programs.py`:

```python
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from propose_programs import classify_from_evidence


def test_cash_back_category_routes_to_cashback():
    row = {"card_offer": "AARP Essential Rewards Mastercard", "issuer": "Barclays",
           "category": "CASH_BACK"}
    kind, payload = classify_from_evidence(row)
    assert kind == "proposed"
    assert payload["programId"] == "cashback"
    assert "CASH_BACK" in payload["basis"]


def test_discover_issuer_routes_to_discover_cashback():
    row = {"card_offer": "NHL Discover it Credit Card", "issuer": "Discover",
           "category": "CASH_BACK"}
    kind, payload = classify_from_evidence(row)
    assert payload["programId"] == "discoverCashback"


def test_digital_wallet_cash_back_is_still_cash_back():
    row = {"card_offer": "PayPal Cashback Mastercard", "issuer": "Synchrony",
           "category": "DIGITAL_WALLET_CASH_BACK"}
    kind, payload = classify_from_evidence(row)
    assert payload["programId"] == "cashback"


def test_financing_category_routes_to_no_rewards():
    row = {"card_offer": "CareCredit Credit Card", "issuer": "Synchrony",
           "category": "HEALTH_WELLNESS_FINANCING"}
    kind, payload = classify_from_evidence(row)
    assert kind == "proposed"
    assert payload["programId"] == "noRewards"


def test_retail_rewards_needs_a_merchant_credit_decision():
    row = {"card_offer": "Gap Encore Mastercard", "issuer": "Barclays",
           "category": "RETAIL_REWARDS"}
    kind, payload = classify_from_evidence(row)
    assert kind == "needsEnumValue"
    assert payload["currency"] == "merchantCredit"


def test_no_category_is_refused_not_guessed():
    row = {"card_offer": "Kohl's Charge Card", "issuer": "Capital One", "category": None}
    kind, payload = classify_from_evidence(row)
    assert kind == "refused"
    assert payload["reason"] == "provenanceWithdrawn"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd catalogue-pipeline/scripts && python3 -m pytest test_propose_programs.py -v
```

Expected: FAIL with `ImportError: cannot import name 'classify_from_evidence'`.

- [ ] **Step 3: Delete the two catch-all rows**

In `catalogue-pipeline/scripts/propose_programs.py`, delete these two entries from `MISSING_ENUM_COBRAND` (they span lines 89-91):

```python
    (r"kohl|sam's club|sears|walgreens|\bgap\b|athleta|banana republic|nordstrom|target|bj's|old navy|barnes & noble|bed bath & beyond|ulta beauty|best buy|kroger",
     "Store-specific rewards"),
    (r"harley|h-d |verizon|carecredit|aarp|\bnhl\b|morgan stanley|robinhood|\bsofi\b|t-mobile|doordash|instacart|uber|\bxbox\b|alibaba|one key|onekey",
     "Brand-specific rewards"),
```

Leave every other entry in `MISSING_ENUM_COBRAND` untouched — they name real single currencies and are correct.

- [ ] **Step 4: Add the evidence classifier**

Add to `catalogue-pipeline/scripts/propose_programs.py`:

```python
# Evidence-driven classification, replacing the two catch-all NAME regexes deleted on
# 2026-08-27. Those recorded a `basis` that was literally the alternation which matched the
# card's name — no reward text was ever read — and the licensed cc-offers snapshot's own
# `category` field disagreed with them for 9 of the 19 cards whose provenance survived.
#
# This ROUTES a draft; it never VERIFIES one. A third-party category is not D3 evidence, so
# everything it produces lands `status: "draft"` with `earnRules: []`, never issuerConfirmed,
# and promotion still requires reading the issuer's own site.
CASH_BACK_CATEGORIES = {
    "CASH_BACK",
    "DIGITAL_WALLET_CASH_BACK",
    "WAREHOUSE_CLUB_CASH_BACK",
    "GAS_RESTAURANT_CASH_BACK",
    "TRAVEL_CASH_BACK",
    "EDUCATION_SAVINGS_CASH_BACK",
}

MERCHANT_LOCKED_CATEGORIES = {
    "RETAIL_REWARDS",
    "RETAIL_REWARDS_AND_FINANCING",
    "WAREHOUSE_CLUB_REWARDS",
    "WAREHOUSE_CLUB_CREDIT",
    "CRUISE_REWARDS",
    "HEALTH_WELLNESS_REWARDS",
}


def classify_from_evidence(row):
    """Classify one raw cc-offers row by its `category`, never by its name.

    Returns (kind, payload) where kind is "proposed", "needsEnumValue" or "refused".
    """
    category = row.get("category")
    if not category:
        return ("refused", {
            "reason": "provenanceWithdrawn",
            "basis": "no retained in-repo provenance; the opencard snapshot was removed by the "
                     "licence audit and this card must be re-sourced from issuer material",
        })

    if category in CASH_BACK_CATEGORIES:
        issuer = (row.get("issuer") or "").lower()
        program_id = "discoverCashback" if "discover" in issuer else "cashback"
        return ("proposed", {
            "programId": program_id,
            "unit": "cad",
            "basis": f"cc-offers category: {category} (routes a draft; does not verify it)",
        })

    if category.endswith("_FINANCING"):
        return ("proposed", {
            "programId": "noRewards",
            "unit": "cad",
            "basis": f"cc-offers category: {category} — a financing product, no rewards programme",
        })

    if category in MERCHANT_LOCKED_CATEGORIES:
        return ("needsEnumValue", {
            "currency": "merchantCredit",
            "basis": f"cc-offers category: {category} — merchant-locked; needs a per-brand "
                     f"programId and a published face value before it can be valued",
        })

    return ("refused", {
        "reason": "unclassifiedCategory",
        "basis": f"cc-offers category: {category} — no routing rule; needs issuer research",
    })
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd catalogue-pipeline/scripts && python3 -m pytest test_propose_programs.py -v
```

Expected: 6 passed.

- [ ] **Step 6: Regenerate the pipeline outputs and inspect the diff**

```bash
cd catalogue-pipeline && python3 scripts/propose_programs.py
```

Expected: `programid-additions.proposed.json` no longer contains a `deferredNotOneCurrency` key with `"Store-specific rewards"` or `"Brand-specific rewards"` placeholders. Read the diff before committing — if any card moved into `proposed` on a `programId` you cannot justify from its `category`, stop and record a gap instead.

- [ ] **Step 7: Verify no contract file changed**

```bash
git status --porcelain contracts/
```

Expected: empty output. Phase 1 touches no contract and needs no release.

- [ ] **Step 8: Commit**

```bash
git log --oneline -1
git commit -m "feat(catalogue-pipeline): classify co-brands on evidence, not on their names

The two catch-all rows in propose_programs.py matched a card's NAME and recorded
the matching regex as its basis. No reward text was ever read, and the licensed
cc-offers snapshot's own category field disagreed for 9 of the 19 cards whose
provenance survived the licence audit.

Routes on category instead: *_CASH_BACK to cashback (discoverCashback when the
issuer is Discover), *_FINANCING to noRewards, and the retail/warehouse/cruise
categories to a merchantCredit decision. A card with no category is refused as
provenanceWithdrawn rather than guessed.

The classifier ROUTES a draft; it never VERIFIES one. Everything it produces
lands draft with earnRules: [], never issuerConfirmed, and D3 still gates
promotion." -- catalogue-pipeline/scripts/propose_programs.py catalogue-pipeline/scripts/test_propose_programs.py catalogue-pipeline/promote-refusals-us.json catalogue-pipeline/programid-additions.proposed.json
```

---

## Phase 2 — Close the schema-integrity hole

### Task 2: Validate `programs.json` against its schema, and fix the `noRewards` drift

**Files:**
- Modify: `contracts/schema/programs.schema.json`
- Create: `Engine/Tests/CardCopilotEngineTests/ProgramsSchemaTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: a passing gate that Task 4 depends on — without it, adding a `merchantCredit` schema variant constrains nothing.

**Why this task exists.** `contracts/programs.json` at published release `card-contracts@2.4` **does not validate against `contracts/schema/programs.schema.json`**. The `noRewards` valuation shipped on 2026-08-27 without a corresponding schema variant, and the schema's `$defs` still holds only `points`, `cashback`, `ctMoney`, `cro` behind a 4-branch `oneOf`. Nothing in CI, Swift, Kotlin or `scripts/` validates that file, which is exactly why the drift shipped unnoticed. Note also that `programs.schema.json` and `merchant-pack.schema.json` are absent from `RELEASE.json`'s digest list, so they sit outside the release's integrity guarantee — worth raising separately, but out of scope here.

- [ ] **Step 1: Reproduce the failure**

```bash
python3 -c "
import json, jsonschema
from referencing import Registry, Resource
cat = json.load(open('contracts/schema/card-catalogue.schema.json'))
prog = json.load(open('contracts/schema/programs.schema.json'))
reg = Registry().with_resources([
    ('https://pickme.local/contracts/card-catalogue.schema.json', Resource.from_contents(cat)),
    ('card-catalogue.schema.json', Resource.from_contents(cat)),
])
errs = list(jsonschema.Draft202012Validator(prog, registry=reg).iter_errors(json.load(open('contracts/programs.json'))))
print('errors:', len(errs))
for e in errs: print(list(e.absolute_path))
"
```

Expected: `errors: 1` at path `['defaults', 'noRewards']`.

- [ ] **Step 2: Write the failing Swift test**

Create `Engine/Tests/CardCopilotEngineTests/ProgramsSchemaTests.swift`:

```swift
import XCTest
@testable import CardCopilotEngine

/// `contracts/programs.json` had no validation anywhere — not in CI, not in Swift, not in
/// Kotlin, not in `scripts/`. That is how the `noRewards` valuation shipped in
/// card-contracts@2.4 against a schema whose `oneOf` still listed only four models.
///
/// This is a structural check rather than a full JSON Schema implementation: every model name
/// appearing in the data must have a matching variant in the schema, and vice versa. That is the
/// exact class of drift that shipped, and it needs no schema engine to catch.
final class ProgramsSchemaTests: XCTestCase {

    private func loadJSON(_ relativePath: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CardCopilotEngineTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Engine
            .appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testEveryModelInProgramsJsonHasASchemaVariant() throws {
        let programs = try loadJSON("contracts/programs.json")
        let schema = try loadJSON("contracts/schema/programs.schema.json")

        let defaults = try XCTUnwrap(programs["defaults"] as? [String: Any])
        let dataModels = Set(defaults.values.compactMap { ($0 as? [String: Any])?["model"] as? String })

        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let schemaModels = Set(defs.compactMap { name, body -> String? in
            guard let body = body as? [String: Any],
                  let props = body["properties"] as? [String: Any],
                  let model = props["model"] as? [String: Any],
                  let constant = model["const"] as? String else { return nil }
            _ = name
            return constant
        })

        XCTAssertEqual(dataModels.subtracting(schemaModels), [],
            "programs.json declares valuation model(s) with no variant in programs.schema.json. "
            + "The data does not validate against its own schema.")
    }

    func testEverySchemaVariantIsReachableFromTheOneOf() throws {
        let schema = try loadJSON("contracts/schema/programs.schema.json")
        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let valuation = try XCTUnwrap(defs["programValuation"] as? [String: Any])
        let branches = try XCTUnwrap(valuation["oneOf"] as? [[String: Any]])
        let referenced = Set(branches.compactMap { $0["$ref"] as? String })

        let variantNames = defs.compactMap { name, body -> String? in
            guard let body = body as? [String: Any],
                  let props = body["properties"] as? [String: Any],
                  props["model"] != nil else { return nil }
            return "#/$defs/\(name)"
        }

        XCTAssertEqual(Set(variantNames).subtracting(referenced), [],
            "schema variant(s) defined but not listed in programValuation.oneOf, so no data can "
            + "ever match them.")
    }
}
```

- [ ] **Step 3: Run it to verify it fails**

```bash
cd Engine && swift test --filter ProgramsSchemaTests
```

Expected: FAIL on `testEveryModelInProgramsJsonHasASchemaVariant` reporting `["noRewards"]`.

- [ ] **Step 4: Add the `noRewards` variant to the schema**

In `contracts/schema/programs.schema.json`, add to `$defs` (alongside `points`, `cashback`, `ctMoney`, `cro`):

```json
"noRewards": {
  "type": "object",
  "required": ["model", "basis"],
  "additionalProperties": false,
  "patternProperties": { "^_": {} },
  "properties": {
    "model": { "const": "noRewards" },
    "basis": { "$ref": "#/$defs/basis" }
  },
  "description": "A card with no rewards programme at all. Carries no number because there is nothing to configure: Scorer.valueCad answers 0.0 and the card is SCORED, ranking last on merit. Distinct from a MISSING valuation, which answers nil and excludes the card entirely — \"we do not know what this is worth\" must never rank as \"worth nothing\"."
}
```

Then add `{ "$ref": "#/$defs/noRewards" }` to the `oneOf` array in `$defs.programValuation`.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd Engine && swift test --filter ProgramsSchemaTests
```

Expected: 2 tests PASS.

- [ ] **Step 6: Re-run the Python validation to confirm the data now validates**

Run the Step 1 command again. Expected: `errors: 0`.

- [ ] **Step 7: Run the full Swift suite**

```bash
cd Engine && swift test
```

Expected: **278** tests pass (276 baseline + 2 new). Record the new baseline.

- [ ] **Step 8: Commit**

```bash
git log --oneline -1
git commit -m "fix(contracts): programs.json did not validate against its own schema

The noRewards valuation shipped in card-contracts@2.4 with no matching variant
in programs.schema.json, whose oneOf still listed four models. Nothing anywhere
validated that file — not CI, not Swift, not Kotlin, not scripts/ — which is
precisely why the drift shipped unnoticed.

Adds the missing variant and a structural gate: every model name in the data
must have a schema variant, and every schema variant must be reachable from the
oneOf. Structural rather than a full JSON Schema run, because that is the exact
class of drift that occurred and it needs no schema engine to catch.

Separately noted, not fixed here: programs.schema.json and
merchant-pack.schema.json are absent from RELEASE.json's digest list, so they
sit outside the release integrity guarantee.

Swift 278/278." -- contracts/schema/programs.schema.json Engine/Tests/CardCopilotEngineTests/ProgramsSchemaTests.swift
```

---

## Phase 3 — The `merchantCredit` model

### Task 3: Swift `MerchantCreditValuation` and the `Scorer` arm

**Files:**
- Modify: `Engine/Sources/CardCopilotEngine/Models/OwnerState.swift:113` (add after `CtMoneyValuation`)
- Modify: `Engine/Sources/CardCopilotEngine/Models/ProgramValuation.swift:17,44,59`
- Modify: `Engine/Sources/CardCopilotEngine/Engine/Scorer.swift:224`
- Create: `Engine/Tests/CardCopilotEngineTests/MerchantCreditProgramTests.swift`

**Interfaces:**
- Consumes: Task 2's schema gate.
- Produces:
  - `public struct MerchantCreditValuation: Codable, Equatable, Sendable` with `cadPerUnit: Double`, `optionalUsabilityFactor: Double`, `usabilityFactorApplied: Bool`, `merchantScope: [String]`, `basis: String?`, and a memberwise `init(cadPerUnit:optionalUsabilityFactor:usabilityFactorApplied:merchantScope:basis:)` where `basis` defaults to `nil`.
  - `ProgramValuation.merchantCredit(MerchantCreditValuation)`.

**Critical constraint.** `merchantCredit` is declared **alongside** `ctMoney`, never folded into it. `ProgramValuation` hand-writes both `init(from:)` and `encode(to:)`, and `ProgramValuationTests.testCtMoneyRoundTrips` and `testModernShapeRoundTripsLosslessly` pin the round trip. A merged case would have to carry which spelling it arrived as, purely to preserve bytes, and Kotlin would need a hand-written `JsonContentPolymorphicSerializer` because `classDiscriminator` maps exactly one `@SerialName` per subclass. **Do not touch `CtMoneyValuation`, its case, its decode arm, its encode arm, or its tests.**

- [ ] **Step 1: Write the failing test**

Create `Engine/Tests/CardCopilotEngineTests/MerchantCreditProgramTests.swift`:

```swift
import XCTest
@testable import CardCopilotEngine

/// Merchant-locked store credit — a Gap Inc. point, a Sam's Cash dollar, a cruise line's onboard
/// credit. Same arithmetic as CT Money, deliberately NOT the same model: `ctMoney` is a published
/// name inside a digest-pinned release, and folding two wire formats into one case would cost a
/// spelling-provenance field in Swift and a custom polymorphic serializer in Kotlin.
///
/// The per-brand usability factor is the load-bearing part. A Sam's Club dollar (weekly
/// groceries) and a Harley-Davidson dollar (a motorcycle every few years) are not the same
/// dollar, and one shared factor across brands would value one brand's credit as another's —
/// the exact collapse the 2026-08-27 Option 1 ruling refused.
final class MerchantCreditProgramTests: XCTestCase {

    private func valuations(_ v: ProgramValuation) -> Valuations { ["gapInc": v] }

    func testFaceValueAppliesWhenTheUsabilityFactorIsNotApplied() {
        let v = ProgramValuation.merchantCredit(
            MerchantCreditValuation(cadPerUnit: 1.0, optionalUsabilityFactor: 0.8,
                                    usabilityFactorApplied: false,
                                    merchantScope: ["gap"], basis: "test"))
        let cad = Scorer.valueCad(units: 100, program: "gapInc",
                                  valuations: valuations(v), state: CardState())
        XCTAssertEqual(try XCTUnwrap(cad), 100.0, accuracy: 0.0001)
    }

    func testUsabilityFactorDiscountsAMerchantLockedDollar() {
        let v = ProgramValuation.merchantCredit(
            MerchantCreditValuation(cadPerUnit: 1.0, optionalUsabilityFactor: 0.8,
                                    usabilityFactorApplied: true,
                                    merchantScope: ["gap"], basis: "test"))
        let cad = Scorer.valueCad(units: 100, program: "gapInc",
                                  valuations: valuations(v), state: CardState())
        XCTAssertEqual(try XCTUnwrap(cad), 80.0, accuracy: 0.0001)
    }

    func testRoundTripsThroughItsOwnDiscriminator() throws {
        let original = ProgramValuation.merchantCredit(
            MerchantCreditValuation(cadPerUnit: 1.0, optionalUsabilityFactor: 0.9,
                                    usabilityFactorApplied: true,
                                    merchantScope: ["sams-club"], basis: "test"))
        let data = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "merchantCredit")
        XCTAssertEqual(try JSONDecoder().decode(ProgramValuation.self, from: data), original)
    }

    /// The whole reason this is a separate model. If a future change folds them, this fails.
    func testCtMoneyStillEncodesAsCtMoney() throws {
        let ct = ProgramValuation.ctMoney(
            CtMoneyValuation(cadPerUnit: 1.0, optionalUsabilityFactor: 0.95,
                             usabilityFactorApplied: true, basis: "test"))
        let data = try JSONEncoder().encode(ct)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "ctMoney",
                       "ctMoney is a published name in a digest-pinned release and must not be "
                       + "absorbed into merchantCredit.")
    }

    func testMerchantScopeTokensAreLowercaseKebabCase() throws {
        let pattern = try NSRegularExpression(pattern: "^[a-z0-9]+(-[a-z0-9]+)*$")
        let token = "sams-club"
        let range = NSRange(token.startIndex..., in: token)
        XCTAssertNotNil(pattern.firstMatch(in: token, range: range),
                        "merchantScope tokens share RuleMatcher's token convention.")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd Engine && swift test --filter MerchantCreditProgramTests
```

Expected: FAIL to compile — `cannot find 'MerchantCreditValuation' in scope`.

- [ ] **Step 3: Add the payload struct**

In `Engine/Sources/CardCopilotEngine/Models/OwnerState.swift`, immediately after `CtMoneyValuation` (which ends at line 126):

```swift
/// Merchant-locked store credit — a Gap Inc. point, a Sam's Cash dollar, a cruise line's onboard
/// credit. Face value times an optional usability discount, on the same stated ground as CT
/// Money: a dollar that spends only in one retailer's stores is not a dollar.
///
/// Declared ALONGSIDE `CtMoneyValuation` rather than replacing it. The arithmetic is identical,
/// but `ctMoney` is a published model name inside a digest-pinned release, and a name that has
/// shipped is a fact about the world rather than an implementation detail to normalize away.
/// Deduplicating behaviour is nearly always right; deduplicating a wire format is a different
/// operation, and this one would cost a spelling-provenance field here and a hand-written
/// polymorphic serializer in Kotlin.
///
/// `merchantScope` names where the credit spends, in the same lowercase kebab-case tokens
/// `RuleMatcher` matches `merchantInclude` on. It is disclosure, not dispatch — `Scorer` does not
/// read it — but a valuation that says "worth 80 cents" without saying "and only at Gap" is not
/// a disclosure an owner can check.
public struct MerchantCreditValuation: Codable, Equatable, Sendable {
    public var cadPerUnit: Double
    public var optionalUsabilityFactor: Double
    public var usabilityFactorApplied: Bool
    public var merchantScope: [String]
    public var basis: String?

    public init(cadPerUnit: Double, optionalUsabilityFactor: Double,
                usabilityFactorApplied: Bool, merchantScope: [String],
                basis: String? = nil) {
        self.cadPerUnit = cadPerUnit
        self.optionalUsabilityFactor = optionalUsabilityFactor
        self.usabilityFactorApplied = usabilityFactorApplied
        self.merchantScope = merchantScope
        self.basis = basis
    }
}
```

- [ ] **Step 4: Add the enum case, decode arm and encode arm**

In `Engine/Sources/CardCopilotEngine/Models/ProgramValuation.swift`:

After the `case ctMoney(CtMoneyValuation)` line, add:

```swift
    /// Merchant-locked store credit. Same arithmetic as `ctMoney`, deliberately a separate case —
    /// see `MerchantCreditValuation` for why a shipped wire-format name is not deduplicated.
    case merchantCredit(MerchantCreditValuation)
```

In `init(from:)`, after the `case "ctMoney":` line:

```swift
        case "merchantCredit": self = .merchantCredit(try MerchantCreditValuation(from: decoder))
```

In `encode(to:)`, after the `case .ctMoney(let v):` line:

```swift
        case .merchantCredit(let v): try keyed.encode("merchantCredit", forKey: .model); try v.encode(to: encoder)
```

- [ ] **Step 5: Add the `Scorer` arm**

In `Engine/Sources/CardCopilotEngine/Engine/Scorer.swift`, in `valueCad`'s switch, immediately after the `.ctMoney` case:

```swift
        case .merchantCredit(let v):
            return units * v.cadPerUnit * (v.usabilityFactorApplied ? v.optionalUsabilityFactor : 1)
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd Engine && swift test --filter MerchantCreditProgramTests
```

Expected: 5 tests PASS.

- [ ] **Step 7: Run the full Swift suite**

```bash
cd Engine && swift test
```

Expected: **283** tests pass (278 + 5). `ProgramValuationTests.testCtMoneyRoundTrips` and `testModernShapeRoundTripsLosslessly` must still pass untouched — if either fails, `ctMoney` was modified and must be reverted.

- [ ] **Step 8: Commit**

```bash
git log --oneline -1
git commit -m "feat(engine): merchantCredit — a valuation for merchant-locked store credit

A Gap Inc. point, a Sam's Cash dollar, a cruise line's onboard credit: face
value times an optional usability discount, on the same stated ground as CT
Money — a dollar that spends only in one retailer's stores is not a dollar.

Declared ALONGSIDE ctMoney, not folded into it. The arithmetic is identical, but
ProgramValuation hand-writes encode as well as decode, so a merged case would
have to carry which spelling it arrived as purely to preserve bytes, and Kotlin
would need a hand-written JsonContentPolymorphicSerializer because
classDiscriminator maps exactly one SerialName per subclass. ctMoney is a
published name inside a digest-pinned release; deduplicating behaviour is right,
deduplicating a shipped wire format is a different operation.

merchantScope is disclosure, not dispatch — Scorer never reads it — but a
valuation saying \"worth 80 cents\" without saying \"and only at Gap\" is not a
disclosure an owner can check.

No programs.json entry yet: the integrity ratchet refuses a valuation no card
declares, and per-brand face values need D3 issuer verification first.

Swift 283/283." -- Engine/Sources/CardCopilotEngine/Models/OwnerState.swift Engine/Sources/CardCopilotEngine/Models/ProgramValuation.swift Engine/Sources/CardCopilotEngine/Engine/Scorer.swift Engine/Tests/CardCopilotEngineTests/MerchantCreditProgramTests.swift
```

### Task 4: `merchantCredit` schema variant

**Files:**
- Modify: `contracts/schema/programs.schema.json`

**Interfaces:**
- Consumes: Task 2's `ProgramsSchemaTests` gate, Task 3's model.
- Produces: a schema variant the gate will hold to.

- [ ] **Step 1: Add the variant to `$defs`**

```json
"merchantCredit": {
  "type": "object",
  "required": ["model", "cadPerUnit", "optionalUsabilityFactor", "usabilityFactorApplied", "merchantScope", "basis"],
  "additionalProperties": false,
  "patternProperties": { "^_": {} },
  "properties": {
    "model": { "const": "merchantCredit" },
    "cadPerUnit": { "type": "number", "exclusiveMinimum": 0, "description": "Face value of one unit, in the card's billing currency. An ISSUER FACT — the published conversion the programme states, never a forecast. A brand that publishes no conversion has no honest value here and its cards stay in the research queue." },
    "optionalUsabilityFactor": { "type": "number", "exclusiveMinimum": 0, "maximum": 1, "description": "PER BRAND, and load-bearing. A dollar locked to one merchant is not a dollar, and how much less depends entirely on which merchant: a Sam's Club dollar (weekly groceries) is not a Harley-Davidson dollar (a motorcycle every few years). One shared factor across brands would value one brand's credit as another's — the collapse the 2026-08-27 Option 1 ruling refused." },
    "usabilityFactorApplied": { "type": "boolean", "description": "Whether Scorer applies the factor. False values the credit at face." },
    "merchantScope": { "type": "array", "minItems": 1, "items": { "type": "string", "pattern": "^[a-z0-9]+(-[a-z0-9]+)*$" }, "description": "Where the credit spends, in the same lowercase kebab-case tokens RuleMatcher matches merchantInclude on. Disclosure, not dispatch — Scorer never reads it." },
    "basis": { "$ref": "#/$defs/basis" }
  }
}
```

Add `{ "$ref": "#/$defs/merchantCredit" }` to `$defs.programValuation.oneOf`.

- [ ] **Step 2: Run the schema gate**

```bash
cd Engine && swift test --filter ProgramsSchemaTests
```

Expected: 2 PASS. `testEverySchemaVariantIsReachableFromTheOneOf` proves the `oneOf` entry was not forgotten.

- [ ] **Step 3: Commit**

```bash
git log --oneline -1
git commit -m "feat(contracts): merchantCredit schema variant

Mirrors the Swift model landed alongside ctMoney. cadPerUnit is documented as an
issuer fact rather than a forecast, and optionalUsabilityFactor as per-brand and
load-bearing — one shared factor across brands is the collapse Option 1 refused.
merchantScope reuses RuleMatcher's lowercase kebab-case token pattern." -- contracts/schema/programs.schema.json
```

### Task 5: Kotlin `MerchantCreditValuation`

**Files:**
- Modify: `android/core/engine/src/main/kotlin/com/cardcopilot/engine/models/ProgramValuation.kt`
- Modify: `android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/Scorer.kt`
- Create: `android/core/engine/src/test/kotlin/com/cardcopilot/engine/MerchantCreditProgramTest.kt`

**Interfaces:**
- Consumes: Task 3's Swift shape — field names and JSON discriminator must match exactly: `model = "merchantCredit"`, fields `cadPerUnit`, `optionalUsabilityFactor`, `usabilityFactorApplied`, `merchantScope`, `basis`.
- Produces: `MerchantCreditValuation` as a `ProgramValuation` sealed subclass.

**Background.** `ProgramValuation` is a `@Serializable sealed class`; `SeedLoader.kt:33` sets `classDiscriminator = "model"`, so each subclass's `@SerialName` IS the wire discriminator. No subclass may declare a property named `model`.

- [ ] **Step 1: Write the failing test**

Create `android/core/engine/src/test/kotlin/com/cardcopilot/engine/MerchantCreditProgramTest.kt`:

```kotlin
package com.cardcopilot.engine

import com.cardcopilot.engine.engine.Scorer
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.MerchantCreditValuation
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

class MerchantCreditProgramTest {

    @Test
    fun `face value applies when the usability factor is not applied`() {
        val v = MerchantCreditValuation(
            cadPerUnit = 1.0, optionalUsabilityFactor = 0.8,
            usabilityFactorApplied = false, merchantScope = listOf("gap"), basis = "test")
        val cad = Scorer.valueCad(100.0, "gapInc", mapOf("gapInc" to v), CardState())
        assertNotNull(cad)
        assertEquals(100.0, cad, 0.0001)
    }

    @Test
    fun `usability factor discounts a merchant-locked dollar`() {
        val v = MerchantCreditValuation(
            cadPerUnit = 1.0, optionalUsabilityFactor = 0.8,
            usabilityFactorApplied = true, merchantScope = listOf("gap"), basis = "test")
        val cad = Scorer.valueCad(100.0, "gapInc", mapOf("gapInc" to v), CardState())
        assertNotNull(cad)
        assertEquals(80.0, cad, 0.0001)
    }
}
```

If `Scorer.valueCad`'s Kotlin signature differs, read `Scorer.kt` and match it — do not change the production signature to suit the test.

- [ ] **Step 2: Run it to verify it fails**

```bash
cd android && ./gradlew :core:engine:test --offline
```

Expected: compilation failure — `Unresolved reference: MerchantCreditValuation`.

- [ ] **Step 3: Add the sealed subclass**

In `ProgramValuation.kt`, after `CtMoneyValuation` (which ends at line 56):

```kotlin
/**
 * Merchant-locked store credit — a Gap Inc. point, a Sam's Cash dollar, a cruise line's onboard
 * credit. Face value times an optional usability discount, on the same stated ground as CT
 * Money: a dollar that spends only in one retailer's stores is not a dollar.
 *
 * Declared ALONGSIDE [CtMoneyValuation], not replacing it. The arithmetic is identical, but
 * `ctMoney` is a published model name inside a digest-pinned release. Accepting two names for
 * one class here would need a hand-written JsonContentPolymorphicSerializer, because
 * `classDiscriminator` maps exactly one [SerialName] per subclass. See the Swift twin.
 *
 * [merchantScope] is disclosure, not dispatch — `Scorer` never reads it.
 */
@Serializable
@SerialName("merchantCredit")
data class MerchantCreditValuation(
    val cadPerUnit: Double,
    val optionalUsabilityFactor: Double,
    val usabilityFactorApplied: Boolean,
    val merchantScope: List<String>,
    /** Where the number came from and which parts of it are assumptions. See the Swift twin. */
    val basis: String? = null
) : ProgramValuation()
```

- [ ] **Step 4: Add the `Scorer` arm**

In `android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/Scorer.kt`, in `valueCad`'s `when`, after the `is CtMoneyValuation ->` branch:

```kotlin
            is MerchantCreditValuation ->
                units * valuation.cadPerUnit *
                    (if (valuation.usabilityFactorApplied) valuation.optionalUsabilityFactor else 1.0)
```

Add the import if the file imports valuation types individually.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd android && ./gradlew :core:engine:test --offline
```

Expected: **48** tests pass (46 + 2).

- [ ] **Step 6: Commit**

```bash
git log --oneline -1
git commit -m "feat(engine): Kotlin merchantCredit, mirroring the Swift model

Same wire format as the Swift twin: model discriminator merchantCredit, fields
cadPerUnit, optionalUsabilityFactor, usabilityFactorApplied, merchantScope,
basis. Declared alongside CtMoneyValuation for the reason spelled out there —
classDiscriminator maps one SerialName per subclass, so folding would need a
hand-written JsonContentPolymorphicSerializer to accept a published name.

Kotlin 48/48." -- android/core/engine/src/main/kotlin/com/cardcopilot/engine/models/ProgramValuation.kt android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/Scorer.kt android/core/engine/src/test/kotlin/com/cardcopilot/engine/MerchantCreditProgramTest.kt
```

---

## Phase 4 — Closed-loop acceptance

### Task 6: Swift `Acceptance`, `Network.privateLabel`, and the `Scorer` guard

**Files:**
- Modify: `Engine/Sources/CardCopilotEngine/Models/CatalogueModels.swift:3` (Network), `:263` (CardProduct)
- Modify: `Engine/Sources/CardCopilotEngine/Engine/Scorer.swift:4` (Warning), `:84` (the guard)
- Create: `Engine/Tests/CardCopilotEngineTests/ClosedLoopAcceptanceTests.swift`

**Interfaces:**
- Consumes: nothing from Phase 3 — this is independent.
- Produces:
  - `Network.privateLabel`
  - `public struct Acceptance: Codable, Equatable, Sendable` with `scope: AcceptanceScope` and `merchants: [String]`
  - `public enum AcceptanceScope: String, Codable, Sendable { case openLoop, closedLoop }`
  - `CardProduct.acceptance: Acceptance?`
  - `Warning.merchantNotAccepted`

**Background.** `Scorer.score` currently guards acceptance with one check at line 84:

```swift
guard purchase.acceptedNetworks.contains(card.network) else {
    return excludedScore(.networkNotAccepted, "\(card.network.rawValue) not accepted")
}
```

A private-label card (Kohl's Charge, Sam's Club Credit, Amazon Store Card) runs on no network, so there is no honest value for `network` and rule 3 forbids guessing one. `PurchaseContext.merchantBrand: String?` already exists and `RuleMatcher` already matches `merchantInclude` against it — this lifts that same predicate from "which rule applies" to "is this card usable here at all".

- [ ] **Step 1: Write the failing test**

Create `Engine/Tests/CardCopilotEngineTests/ClosedLoopAcceptanceTests.swift`:

```swift
import XCTest
@testable import CardCopilotEngine

/// A private-label card runs on no payment network. `network` is required with a closed enum, so
/// before `privateLabel` existed the only way to land one was to guess — and a Kohl's card
/// recorded as `visa` would be recommended at a gas station, where it is declined at the till.
///
/// The inversion worth keeping in view: a closed-loop card is the SHARPEST possible answer to
/// "which card should I tap right now" — at exactly one merchant it is often unbeatable — and it
/// was the one card the schema could not describe.
final class ClosedLoopAcceptanceTests: XCTestCase {

    private func closedLoopCard(merchants: [String]) -> CardProduct {
        var card = TestFixtures.minimalCard(cardId: "kohls-charge")
        card.network = .privateLabel
        card.acceptance = Acceptance(scope: .closedLoop, merchants: merchants)
        return card
    }

    func testAClosedLoopCardIsExcludedAtAnotherMerchant() {
        let card = closedLoopCard(merchants: ["kohls"])
        let purchase = PurchaseContext(amountCad: 50, category: "gasStation",
                                       merchantBrand: "petro-canada")
        let score = Scorer.score(card: card, purchase: purchase,
                                 ownerState: OwnerState.empty(), asOf: "2026-08-27")
        XCTAssertTrue(score.excluded)
        XCTAssertTrue(score.warnings.contains(.merchantNotAccepted))
    }

    func testAClosedLoopCardIsAcceptedAtItsOwnMerchant() {
        let card = closedLoopCard(merchants: ["kohls"])
        let purchase = PurchaseContext(amountCad: 50, category: "retail",
                                       merchantBrand: "kohls")
        let score = Scorer.score(card: card, purchase: purchase,
                                 ownerState: OwnerState.empty(), asOf: "2026-08-27")
        XCTAssertFalse(score.warnings.contains(.merchantNotAccepted))
    }

    /// The safe failure direction: silence beats recommending a card that gets declined.
    func testAnUnknownMerchantExcludesAClosedLoopCard() {
        let card = closedLoopCard(merchants: ["kohls"])
        let purchase = PurchaseContext(amountCad: 50, category: "retail", merchantBrand: nil)
        let score = Scorer.score(card: card, purchase: purchase,
                                 ownerState: OwnerState.empty(), asOf: "2026-08-27")
        XCTAssertTrue(score.excluded)
        XCTAssertTrue(score.warnings.contains(.merchantNotAccepted))
    }

    /// merchantNotAccepted is its own case because the two facts are different and the UI must
    /// not conflate them: "this card only works at Kohl's" is not "Visa isn't accepted here".
    func testTheNetworkWarningIsNotReusedForAMerchantRefusal() {
        let card = closedLoopCard(merchants: ["kohls"])
        let purchase = PurchaseContext(amountCad: 50, category: "retail",
                                       merchantBrand: "petro-canada")
        let score = Scorer.score(card: card, purchase: purchase,
                                 ownerState: OwnerState.empty(), asOf: "2026-08-27")
        XCTAssertFalse(score.warnings.contains(.networkNotAccepted))
    }

    /// Fail-closed: an open-loop card is untouched by any of this.
    func testAnOpenLoopCardStillGuardsOnNetwork() {
        var card = TestFixtures.minimalCard(cardId: "some-visa")
        card.network = .visa
        card.acceptance = nil
        let purchase = PurchaseContext(amountCad: 50, category: "retail",
                                       acceptedNetworks: [.mastercard])
        let score = Scorer.score(card: card, purchase: purchase,
                                 ownerState: OwnerState.empty(), asOf: "2026-08-27")
        XCTAssertTrue(score.excluded)
        XCTAssertTrue(score.warnings.contains(.networkNotAccepted))
    }

    func testEveryExistingCatalogueCardIsOpenLoop() throws {
        let cards = try SeedLoader.loadCatalogue().cards
        let closedLoop = cards.filter { $0.acceptance?.scope == .closedLoop }.map(\.cardId)
        XCTAssertEqual(closedLoop, [],
            "no catalogue card declares closed-loop acceptance yet; landing one is a separate, "
            + "research-gated change.")
    }
}
```

If `TestFixtures.minimalCard` and `OwnerState.empty()` do not exist under those names, read `Engine/Tests/CardCopilotEngineTests/Fixtures/` and use the established helpers rather than inventing new ones.

- [ ] **Step 2: Run it to verify it fails**

```bash
cd Engine && swift test --filter ClosedLoopAcceptanceTests
```

Expected: FAIL to compile — `type 'Network' has no member 'privateLabel'`.

- [ ] **Step 3: Add the model**

In `Engine/Sources/CardCopilotEngine/Models/CatalogueModels.swift`, replace line 3:

```swift
/// The payment network a card runs on. `privateLabel` means it runs on NONE — a store card
/// accepted only by its own merchant. It is never a member of a purchase's `acceptedNetworks`,
/// so a `privateLabel` card that forgot to declare `acceptance` fails closed: excluded
/// everywhere rather than recommended everywhere. The schema's if/then invariant makes that
/// unreachable; this makes it harmless if it ever were.
public enum Network: String, Codable, Sendable {
    case amex, visa, mastercard, discover, privateLabel
}

/// How a card is accepted. Absent on a `CardProduct` means `openLoop` — which is every card in
/// the catalogue as of card-contracts@2.4, so no existing record changes a byte.
public enum AcceptanceScope: String, Codable, Sendable { case openLoop, closedLoop }

/// A closed-loop card's acceptance list, in the same lowercase kebab-case merchant tokens
/// `RuleMatcher` matches `merchantInclude` against.
public struct Acceptance: Codable, Equatable, Sendable {
    public var scope: AcceptanceScope
    public var merchants: [String]

    public init(scope: AcceptanceScope, merchants: [String]) {
        self.scope = scope
        self.merchants = merchants
    }
}
```

In `CardProduct`, after `public var network: Network` (line 263):

```swift
    /// Absent for every open-loop card, which is all of them today — so this decodes a
    /// pre-2.5 catalogue unchanged, exactly as `credits` and `lifecycleStatus` do.
    public var acceptance: Acceptance?
```

- [ ] **Step 4: Add the warning case**

In `Engine/Sources/CardCopilotEngine/Engine/Scorer.swift`, in the `Warning` enum, after `networkNotAccepted`:

```swift
         /// A closed-loop card at a merchant it is not accepted by — or at a purchase whose
         /// merchant could not be resolved. Its own case rather than reusing
         /// `networkNotAccepted`: "this card only works at Kohl's" and "Visa isn't accepted
         /// here" are different facts and the UI must not conflate them.
         merchantNotAccepted,
```

- [ ] **Step 5: Replace the acceptance guard**

In `Scorer.score`, replace the guard at line 84:

```swift
        // Two acceptance mechanisms, not one. An open-loop card is accepted because the merchant
        // takes its network; a closed-loop card is accepted because the merchant IS its issuer's
        // store. Forcing the second through a network check is what made private-label cards
        // unrepresentable without guessing `network`.
        switch card.acceptance?.scope ?? .openLoop {
        case .openLoop:
            guard purchase.acceptedNetworks.contains(card.network) else {
                return excludedScore(.networkNotAccepted, "\(card.network.rawValue) not accepted")
            }
        case .closedLoop:
            let merchants = card.acceptance?.merchants ?? []
            guard let brand = purchase.merchantBrand, merchants.contains(brand) else {
                return excludedScore(.merchantNotAccepted,
                                     "accepted only at \(merchants.joined(separator: ", "))")
            }
        }
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd Engine && swift test --filter ClosedLoopAcceptanceTests
```

Expected: 6 tests PASS.

- [ ] **Step 7: Run the full Swift suite**

```bash
cd Engine && swift test
```

Expected: **289** tests pass (283 + 6). No existing test may change — every catalogue card is open-loop, so `Scorer`'s behaviour is identical for all 85.

- [ ] **Step 8: Commit**

```bash
git log --oneline -1
git commit -m "feat(engine): closed-loop acceptance — a card accepted by merchant, not by network

network was amex|visa|mastercard|discover and Scorer excluded on mismatch, so a
private-label card — Kohl's Charge, Sam's Club Credit, Amazon Store Card, PayPal
Credit, CareCredit — could only land by guessing a network it does not have.
Rule 3 forbids that, and the guess is not harmless: a Kohl's card recorded as
visa gets recommended at a gas station and declined at the till. The gap blocked
those cards under every option including deferral.

The inversion worth keeping in view is that a closed-loop card is the SHARPEST
answer to \"which card should I tap right now\" — at exactly one merchant it is
often unbeatable — and it was the one card the schema could not describe.

The machinery already existed: merchantBrand on PurchaseContext, merchantInclude
in RuleMatcher, acceptedNetworks in the merchant pack. This lifts that predicate
from \"which rule applies\" to \"is this card usable here at all\".

acceptance is optional and absent means openLoop, so all 85 existing cards are
byte-identical and score identically. privateLabel is never in a purchase's
acceptedNetworks, so a card that declared it without acceptance fails closed —
excluded everywhere, not recommended everywhere.

merchantNotAccepted is its own Warning: \"only works at Kohl's\" is not \"Visa
isn't accepted here\".

Swift 289/289." -- Engine/Sources/CardCopilotEngine/Models/CatalogueModels.swift Engine/Sources/CardCopilotEngine/Engine/Scorer.swift Engine/Tests/CardCopilotEngineTests/ClosedLoopAcceptanceTests.swift
```

### Task 7: Catalogue schema — `privateLabel`, `acceptance`, and the invariant

**Files:**
- Modify: `contracts/schema/card-catalogue.schema.json`

- [ ] **Step 1: Extend the `network` enum**

Change the `network` enum from `["amex", "visa", "mastercard", "discover"]` to `["amex", "visa", "mastercard", "discover", "privateLabel"]` and append to its description:

> `privateLabel` means the card runs on NO network — a store card accepted only by its own merchant. It is never a member of a purchase's `acceptedNetworks`, so `Scorer` would exclude such a card everywhere; the paired `acceptance` object is what makes it scoreable, and the if/then below makes the pair inseparable.

- [ ] **Step 2: Add the `acceptance` definition**

Add to `$defs`:

```json
"acceptance": {
  "type": "object",
  "required": ["scope", "merchants"],
  "additionalProperties": false,
  "patternProperties": { "^_": {} },
  "properties": {
    "scope": { "enum": ["openLoop", "closedLoop"] },
    "merchants": { "type": "array", "minItems": 1, "items": { "type": "string", "pattern": "^[a-z0-9]+(-[a-z0-9]+)*$" }, "description": "Lowercase kebab-case merchant tokens, the same convention RuleMatcher matches merchantInclude against. A token that cannot match is a card that can never be picked." }
  },
  "description": "How this card is accepted. ABSENT means openLoop, which is every card up to card-contracts@2.4 — so a pre-2.5 catalogue decodes unchanged. Scorer switches on this: openLoop guards on network, closedLoop guards on merchantBrand."
}
```

Add `"acceptance": { "$ref": "#/$defs/acceptance" }` to `CardProduct`'s properties.

- [ ] **Step 3: Add the if/then invariant**

On the card object, add:

```json
"allOf": [
  {
    "if": { "properties": { "network": { "const": "privateLabel" } }, "required": ["network"] },
    "then": { "required": ["acceptance"], "properties": { "acceptance": { "properties": { "scope": { "const": "closedLoop" } } } } }
  },
  {
    "if": { "properties": { "acceptance": { "properties": { "scope": { "const": "closedLoop" } }, "required": ["scope"] } }, "required": ["acceptance"] },
    "then": { "properties": { "network": { "const": "privateLabel" } } }
  }
]
```

If the card object already has an `allOf`, append these two members rather than replacing it.

- [ ] **Step 4: Verify the existing catalogue still validates**

```bash
cd /Users/zub/Documents/Github_Projects/PickMe && python3 -c "
import json, jsonschema
s = json.load(open('contracts/schema/card-catalogue.schema.json'))
d = json.load(open('contracts/card-catalogue.json'))
errs = list(jsonschema.Draft202012Validator(s).iter_errors(d))
print('errors:', len(errs))
for e in errs[:5]: print(' ', list(e.absolute_path), e.message[:140])
"
```

Expected: `errors: 0`. All 85 cards are open-loop with no `acceptance` key, so neither `if` fires.

- [ ] **Step 5: Run the full Swift suite**

```bash
cd Engine && swift test
```

Expected: 289 PASS.

- [ ] **Step 6: Commit**

```bash
git log --oneline -1
git commit -m "feat(contracts): privateLabel network and the acceptance object

network gains privateLabel; CardProduct gains an optional acceptance object.
Absent means openLoop, so all 85 existing cards validate unchanged.

Two if/then clauses make the pair inseparable: privateLabel requires
closedLoop acceptance, and closedLoop acceptance requires privateLabel. Neither
can be declared without the other, which removes the trap where a card claims no
network but never says where it IS accepted.

merchants reuses RuleMatcher's lowercase kebab-case token pattern — a token that
cannot match is a card that can never be picked." -- contracts/schema/card-catalogue.schema.json
```

### Task 8: Kotlin closed-loop acceptance

**Files:**
- Modify: `android/core/engine/src/main/kotlin/com/cardcopilot/engine/models/CatalogueModels.kt`
- Modify: `android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/Scorer.kt`
- Create: `android/core/engine/src/test/kotlin/com/cardcopilot/engine/ClosedLoopAcceptanceTest.kt`

**Interfaces:**
- Consumes: Task 6's Swift shape. JSON must match exactly: `network: "privateLabel"`, `acceptance: { "scope": "closedLoop", "merchants": [...] }`.
- Produces: `Network.PRIVATE_LABEL` (or the file's existing naming convention — read it first), `Acceptance`, `AcceptanceScope`, `CardProduct.acceptance`, `Warning.MERCHANT_NOT_ACCEPTED`.

- [ ] **Step 1: Read the Kotlin enum convention**

```bash
grep -n "enum class Network" -A 8 android/core/engine/src/main/kotlin/com/cardcopilot/engine/models/CatalogueModels.kt
grep -n "enum class Warning" -A 12 android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/Scorer.kt
```

Match whatever `@SerialName` convention is already used — do not introduce a new one.

- [ ] **Step 2: Write the failing test**

Create `android/core/engine/src/test/kotlin/com/cardcopilot/engine/ClosedLoopAcceptanceTest.kt`:

```kotlin
package com.cardcopilot.engine

import com.cardcopilot.engine.engine.Scorer
import com.cardcopilot.engine.engine.Warning
import com.cardcopilot.engine.models.Acceptance
import com.cardcopilot.engine.models.AcceptanceScope
import com.cardcopilot.engine.models.Network
import com.cardcopilot.engine.models.PurchaseContext
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * A private-label card runs on no payment network. Before `privateLabel` existed, the only way
 * to land one was to guess — and a Kohl's card recorded as `visa` gets recommended at a gas
 * station and declined at the till. See the Swift twin, ClosedLoopAcceptanceTests.
 */
class ClosedLoopAcceptanceTest {

    private fun closedLoopCard(merchants: List<String>) =
        TestFixtures.minimalCard(cardId = "kohls-charge").copy(
            network = Network.PRIVATE_LABEL,
            acceptance = Acceptance(scope = AcceptanceScope.CLOSED_LOOP, merchants = merchants))

    @Test
    fun `a closed-loop card is excluded at another merchant`() {
        val score = Scorer.score(
            closedLoopCard(listOf("kohls")),
            PurchaseContext(amountCad = 50.0, category = "gasStation", merchantBrand = "petro-canada"),
            OwnerState.empty(), "2026-08-27")
        assertTrue(score.excluded)
        assertTrue(Warning.MERCHANT_NOT_ACCEPTED in score.warnings)
    }

    @Test
    fun `a closed-loop card is accepted at its own merchant`() {
        val score = Scorer.score(
            closedLoopCard(listOf("kohls")),
            PurchaseContext(amountCad = 50.0, category = "retail", merchantBrand = "kohls"),
            OwnerState.empty(), "2026-08-27")
        assertFalse(Warning.MERCHANT_NOT_ACCEPTED in score.warnings)
    }

    /** The safe failure direction: silence beats recommending a card that gets declined. */
    @Test
    fun `an unknown merchant excludes a closed-loop card`() {
        val score = Scorer.score(
            closedLoopCard(listOf("kohls")),
            PurchaseContext(amountCad = 50.0, category = "retail", merchantBrand = null),
            OwnerState.empty(), "2026-08-27")
        assertTrue(score.excluded)
        assertTrue(Warning.MERCHANT_NOT_ACCEPTED in score.warnings)
    }

    @Test
    fun `the network warning is not reused for a merchant refusal`() {
        val score = Scorer.score(
            closedLoopCard(listOf("kohls")),
            PurchaseContext(amountCad = 50.0, category = "retail", merchantBrand = "petro-canada"),
            OwnerState.empty(), "2026-08-27")
        assertFalse(Warning.NETWORK_NOT_ACCEPTED in score.warnings)
    }

    /** Fail-closed: an open-loop card is untouched by any of this. */
    @Test
    fun `an open-loop card still guards on network`() {
        val card = TestFixtures.minimalCard(cardId = "some-visa")
            .copy(network = Network.VISA, acceptance = null)
        val score = Scorer.score(
            card,
            PurchaseContext(amountCad = 50.0, category = "retail",
                            acceptedNetworks = setOf(Network.MASTERCARD)),
            OwnerState.empty(), "2026-08-27")
        assertTrue(score.excluded)
        assertTrue(Warning.NETWORK_NOT_ACCEPTED in score.warnings)
    }
}
```

If `TestFixtures.minimalCard` or `OwnerState.empty()` are named differently in this module, read the existing tests under `android/core/engine/src/test/kotlin/com/cardcopilot/engine/` and use the established helpers — do not add new ones. Match the enum-constant convention Step 1 revealed rather than assuming `PRIVATE_LABEL`.

- [ ] **Step 3: Run it to verify it fails**

```bash
cd android && ./gradlew :core:engine:test --offline
```

Expected: compilation failure on the unresolved `Acceptance` reference.

- [ ] **Step 4: Add the model and the Scorer switch**

Mirror Task 6 exactly: the `privateLabel` network value, `AcceptanceScope`, `Acceptance`, a nullable `acceptance` on `CardProduct` defaulting to `null`, the `MERCHANT_NOT_ACCEPTED` warning, and the two-branch acceptance guard in `Scorer.score`.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd android && ./gradlew :core:engine:test --offline
```

Expected: **53** tests pass (48 + 5).

- [ ] **Step 6: Commit**

```bash
git log --oneline -1
git commit -m "feat(engine): Kotlin closed-loop acceptance, mirroring the Swift guard

Same wire format as the Swift twin: network privateLabel, an optional acceptance
object defaulting to null so a pre-2.5 catalogue decodes unchanged, and a
two-branch acceptance guard in Scorer.score. MERCHANT_NOT_ACCEPTED is its own
warning for the reason given in the Swift twin.

Kotlin 53/53." -- android/core/engine/src/main/kotlin/com/cardcopilot/engine/models/CatalogueModels.kt android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/Scorer.kt android/core/engine/src/test/kotlin/com/cardcopilot/engine/ClosedLoopAcceptanceTest.kt
```

---

## Phase 5 — Release and vendor

### Task 9: Cut card-contracts@2.5

**Files:**
- Modify: `contracts/card-catalogue.json` (`catalogueVersion` only), `contracts/programs.json` (`programsVersion` only), `contracts/CHANGELOG.md`, `contracts/RELEASE.json` (generated)
- Modify: both resource copies via the sync scripts

- [ ] **Step 1: Bump the versions**

Set `catalogueVersion` to `"2.5"` in `contracts/card-catalogue.json` and `programsVersion` to `"1.3"` in `contracts/programs.json`.

- [ ] **Step 2: Write the CHANGELOG entry**

Append to `contracts/CHANGELOG.md`, following the existing entry format. Cover: the `merchantCredit` model added alongside `ctMoney`; the `noRewards` schema variant that had been missing since 2.4; `privateLabel` and `acceptance`; and the explicit note that no card declares either yet, so no card's score changes.

- [ ] **Step 3: Cut the release and sync the resource copies**

```bash
./scripts/release-catalogue.sh
./scripts/sync-contracts-into-engine.sh
./scripts/sync-contracts-into-android.sh
```

- [ ] **Step 4: Run every suite**

```bash
cd Engine && swift test
cd ../android && ./gradlew :core:engine:test --offline
cd .. && ./scripts/check-id-permanence.sh
```

Expected: Swift 289, Kotlin 53, id-permanence PASS.

- [ ] **Step 5: Commit and push**

```bash
git log --oneline -1
git commit -m "chore(contracts): release card-contracts@2.5

merchantCredit alongside ctMoney, the noRewards schema variant missing since
2.4, privateLabel and the acceptance object. Additive throughout: no card
declares merchantCredit or closedLoop acceptance yet, so all 85 records keep
their bytes and every score is unchanged.

Swift 289, Kotlin 53." -- contracts/ Engine/Sources/CardCopilotEngine/Resources/ android/core/engine/src/main/resources/
git push
```

- [ ] **Step 6: Publish**

```bash
./scripts/publish-catalogue.sh
```

Verify the published release id resolves to exactly the byte-set just pushed. A published id must never describe two byte-sets.

### Task 10: Vendor 2.5 into MoneyTalks and mirror the twin

**Files:**
- Modify: `MoneyTalks/src/engine/cards-twin/models.ts`
- Modify: `MoneyTalks/src/engine/cards-twin/Scorer.ts`
- Create: `MoneyTalks/src/engine/cards-twin/merchantCredit.test.ts`
- Create: `MoneyTalks/src/engine/cards-twin/closedLoopAcceptance.test.ts`

**Interfaces:**
- Consumes: published `card-contracts@2.5`.
- Produces: TypeScript parity for both models.

**Background.** The precedent commit is `fb99471` — MoneyTalks vendors the contract AND mirrors the engine change in one commit, after PickMe publishes. `models.ts:232` holds the `ProgramValuation` union and `:263-270` a hand-written normalizer that infers `model` from field presence for legacy payloads.

- [ ] **Step 1: Sync the contracts**

```bash
cd /Users/zub/Documents/Github_Projects/MoneyTalks && ./scripts/sync-contracts.sh
```

- [ ] **Step 2: Write the failing tests**

Create `src/engine/cards-twin/merchantCredit.test.ts`:

```typescript
import { describe, expect, it } from 'vitest';
import { valueCad } from './Scorer';

describe('merchantCredit', () => {
  const base = {
    model: 'merchantCredit' as const,
    cadPerUnit: 1.0,
    optionalUsabilityFactor: 0.8,
    merchantScope: ['gap'],
    basis: 'test',
  };

  it('applies face value when the usability factor is not applied', () => {
    const valuations = { gapInc: { ...base, usabilityFactorApplied: false } };
    expect(valueCad(100, 'gapInc', valuations, {})).toBeCloseTo(100, 4);
  });

  it('discounts a merchant-locked dollar when the factor is applied', () => {
    const valuations = { gapInc: { ...base, usabilityFactorApplied: true } };
    expect(valueCad(100, 'gapInc', valuations, {})).toBeCloseTo(80, 4);
  });

  // The whole reason this is a separate model. ctMoney is a published name in a
  // digest-pinned release and must keep its own arm.
  it('leaves ctMoney valued on its own model', () => {
    const valuations = {
      ctMoney: {
        model: 'ctMoney' as const,
        cadPerUnit: 1.0,
        optionalUsabilityFactor: 0.95,
        usabilityFactorApplied: true,
      },
    };
    expect(valueCad(100, 'ctMoney', valuations, {})).toBeCloseTo(95, 4);
  });
});
```

Create `src/engine/cards-twin/closedLoopAcceptance.test.ts`:

```typescript
import { describe, expect, it } from 'vitest';
import { score } from './Scorer';

describe('closed-loop acceptance', () => {
  const closedLoopCard = (merchants: string[]) => ({
    ...minimalCard('kohls-charge'),
    network: 'privateLabel' as const,
    acceptance: { scope: 'closedLoop' as const, merchants },
  });

  it('excludes a closed-loop card at another merchant', () => {
    const s = score(closedLoopCard(['kohls']),
      { amountCad: 50, category: 'gasStation', merchantBrand: 'petro-canada' },
      emptyOwnerState(), '2026-08-27');
    expect(s.excluded).toBe(true);
    expect(s.warnings).toContain('merchantNotAccepted');
  });

  it('accepts a closed-loop card at its own merchant', () => {
    const s = score(closedLoopCard(['kohls']),
      { amountCad: 50, category: 'retail', merchantBrand: 'kohls' },
      emptyOwnerState(), '2026-08-27');
    expect(s.warnings).not.toContain('merchantNotAccepted');
  });

  // Silence beats recommending a card that gets declined.
  it('excludes a closed-loop card when the merchant is unknown', () => {
    const s = score(closedLoopCard(['kohls']),
      { amountCad: 50, category: 'retail', merchantBrand: undefined },
      emptyOwnerState(), '2026-08-27');
    expect(s.excluded).toBe(true);
    expect(s.warnings).toContain('merchantNotAccepted');
  });

  it('does not reuse the network warning for a merchant refusal', () => {
    const s = score(closedLoopCard(['kohls']),
      { amountCad: 50, category: 'retail', merchantBrand: 'petro-canada' },
      emptyOwnerState(), '2026-08-27');
    expect(s.warnings).not.toContain('networkNotAccepted');
  });

  it('still guards an open-loop card on network', () => {
    const card = { ...minimalCard('some-visa'), network: 'visa' as const, acceptance: undefined };
    const s = score(card,
      { amountCad: 50, category: 'retail', acceptedNetworks: ['mastercard'] },
      emptyOwnerState(), '2026-08-27');
    expect(s.excluded).toBe(true);
    expect(s.warnings).toContain('networkNotAccepted');
  });
});
```

`minimalCard` and `emptyOwnerState` are placeholders for this repo's existing test helpers — read `src/engine/cards-twin/fixtures.test.ts` and `draftExclusion.test.ts` and import whatever they already use. Do not add new fixture helpers, and match the real `score`/`valueCad` signatures rather than changing production code to fit these calls.

- [ ] **Step 3: Run them to verify they fail**

```bash
npx vitest run src/engine/cards-twin/merchantCredit.test.ts src/engine/cards-twin/closedLoopAcceptance.test.ts
```

- [ ] **Step 4: Extend the union and the normalizer**

In `models.ts`, add to the `ProgramValuation` union:

```typescript
  | ({ model: 'merchantCredit' } & MerchantCreditValuation)
```

with the interface:

```typescript
/// Merchant-locked store credit. Same arithmetic as CtMoneyValuation, deliberately a separate
/// model: `ctMoney` is a published name inside a digest-pinned release. See the Swift twin.
export interface MerchantCreditValuation {
  cadPerUnit: number;
  optionalUsabilityFactor: number;
  usabilityFactorApplied: boolean;
  /// Disclosure, not dispatch — Scorer never reads it.
  merchantScope: string[];
  basis?: string;
}
```

**Do not touch the `if ('cadPerUnit' in value)` normalizer branch at line 267.** It infers `ctMoney` from field presence for legacy payloads that carry no `model` key. `merchantCredit` payloads always carry an explicit `model`, so they never reach that branch — and widening it would silently reclassify legacy CT Money data.

- [ ] **Step 5: Add the Scorer arm and the acceptance guard**

Mirror Tasks 3 and 6 in `Scorer.ts`.

- [ ] **Step 6: Run every check**

```bash
npx vitest run
npx tsc --noEmit
```

Expected: **1095 + new tests** pass, and `tsc` clean.

- [ ] **Step 7: Commit**

```bash
git log --oneline -1
git commit -m "feat(contracts,engine): vendor card-contracts@2.5 and mirror merchantCredit and closed-loop acceptance

merchantCredit is a separate model from ctMoney for the reason spelled out in
PickMe's Swift twin — a published wire-format name is a fact, not an
implementation detail. The legacy field-presence normalizer is deliberately
untouched: it infers ctMoney for payloads carrying no model key, and
merchantCredit payloads always carry one, so widening it would silently
reclassify legacy CT Money data.

Closed-loop acceptance guards on merchantBrand where open-loop guards on
network. No card declares either yet, so publishedCards() is unchanged."
```

---

## Explicitly NOT in this plan

- **Landing actual cards on `merchantCredit` programIds.** Every brand needs a *published* face value read from the issuer's own site (D3), and `CatalogueIntegrityTests.testEveryProgramDefaultKeyIsARealCatalogueProgramId` refuses a valuation no card declares — so enum value, valuation and cards must land together, per brand, once the research exists. That is research-gated, not implementation-gated.
- **Landing actual closed-loop cards.** Same D3 gate.
- **Target Circle's 5% discount.** It earns no currency — it reduces the price at the till. No model covers that and none is invented here.
- **The 15 provenance-withdrawn cards.** Re-sourcing from issuer material first.
- **`programs.schema.json` and `merchant-pack.schema.json` missing from `RELEASE.json`'s digest list.** Real, found during planning, but a separate change.
