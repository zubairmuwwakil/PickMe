# Catalogue scalability — program design

**Status:** Design ratified 2026-08-20; five of six open decisions resolved (§9).
P1 Phase 0–1 planned at [`../superpowers/plans/2026-08-20-p1-valuation-capability.md`](../superpowers/plans/2026-08-20-p1-valuation-capability.md).
**Parent decisions:** `../../CLAUDE.md` · `../../ECOSYSTEM.md` · `2026-08-16-card-contract-spec.md`
**Horizon:** North America (CA + US), thousands of cards.
**Goal:** make adding a card, rewards program, merchant, owner condition or cap anchor a *data* edit,
and make it impossible for catalogue data to outrun engine support silently.

---

## 1. The problem, with evidence

The card catalogue was correctly designed as data. Seven satellite registries were left as code, so
the catalogue can only ever be as useful as the slowest satellite.

| Registry | Location | Population | Open? |
|---|---|---|---|
| Card products | `contracts/card-catalogue.json` | 27 | data ✅ |
| Program valuations | `OwnerState.swift` `Valuations` + `Scorer.valueCad` switch | 6 of 16 programIds | code ❌ |
| Owner conditions | `RuleMatcher.conditionsResolveTrue` | 3 of 4 declared ids | code ❌ |
| Cap anchors | `CapWindow.anchorMonth` path switch | 2 paths | code ❌ |
| Merchant identity | `CanadianMerchantPreIndex.swift` | 127 Swift literals | code ❌ |
| Card artwork | `CardVisualTheme.swift` | ~7 themed | code ❌ |
| Short names | `AmbientLocationService.swift:636` | switch | code ❌ |
| Category spend estimates | `CheckoutService.swift:29` | dict literal | code ❌ |

Every one is the same defect: **an open set modelled as a closed one**, with no machine check that
data and code agree.

### 1.1 Measured consequences (verified 2026-08-20)

- **14 of 27 cards score exactly $0.00 CAD on every purchase.** Their `programId` falls to
  `default: return 0.0` in `Scorer.valueCad`. All 14 remain selectable in `WalletSetupView`
  (`ForEach(catalogue.cards)`, unfiltered), so an owner can add a card that structurally cannot win.
- **51 of 96 earn rules (53%) carry `scoredInV1: false`.** Blocker themes, derived from their
  `_note` fields: caps/period windows 21 · MCC strictness 13 · merchant identity 8 · unlabelled 8 ·
  channel identity 4 · unit/marginal-earn 3 · owner condition 3. Themes overlap — a rule can carry
  more than one — so these sum above 51. The "unlabelled" bucket undercounts: **ten** rules name no
  blocker at all — seven carry no `_note`, three carry one that describes the rule without saying
  what blocks it. §9.1 assigns nine of the ten by inference.
- **Valuation is *not* among those blockers.** The "valuation and scorer support required" notes sit
  on the `program` object (catalogue lines 1202, 1359, 1470, 1764, 2293), never on an earn rule.
  These are two independent failure modes: `scoredInV1: false` prevents a rule from *matching*;
  the valuation gap values a *matched* rule's output at zero. Fixing valuation makes 14 cards
  scoreable at base rate; it does not make their accelerators fire.
- **`amazonEligiblePrimeLinked`** is declared in `card-catalogue.json:2911` and
  `card-catalogue.schema.json:373`, and is absent from `conditionsResolveTrue`. It fails closed,
  silently, with no warning surface.
- **`lastVerifiedAt` and `sourceType` are declared, decoded, and never read** in either Swift or
  Kotlin. Provenance discipline is enforced by code review alone. 155 dated facts today; at horizon
  that is ~8,000.
- **`purchase.mcc` is `nil` on every real checkout.** `CheckoutService.swift:103`, `:131` and
  `ambientPurchaseContext` (`:41`) all construct `PurchaseContext` without `mcc`. Only the share
  extension supplies one (`ShareAdvisorView.swift:182`), sourced from the hand-written pre-index.
  The permissive `return true` fallback in `RuleMatcher.matches` therefore runs 100% of the time.

### 1.2 The distribution surface

Any contract change fans out to five places: `contracts/` (canonical) · the Engine SPM resource copy
(drift-checked by `ContractsSyncTests`) · the Android resource copy · MoneyTalks' vendored copy with
a pinned sha256 · the server's card-alias table that resolves `cardRaw → resolvedCardId`. Per
`CLAUDE.md`, fixture changes are API changes.

---

## 2. The program

Four independently shippable projects. They are ordered by dependency, not preference — each earlier
project materially shrinks the later ones.

```
P1  Uncloseing + capability system   ── hard prerequisite for P2 and P4
     │
     ├─► P2  Cap expressiveness       ── 21 dead rules
     │
     ├─► P4  Snapshot delivery        ── needs P1's capability skew handling
     │
     └─► P3  Merchant identity        ── ~21 dead rules; longest; runs alongside
```

**Why P1 must lead.** Remote delivery of a catalogue the engine cannot absorb is a reliable pipe for
data that scores zero. Cap work done before capability declaration means hand-flipping
`scoredInV1` flags with no way to know you found them all. And `CapWindow.anchorMonth`'s hardcoded
path switch is both a P1 registry *and* the mechanism statement-period caps need — building cap work
first means building a second anchor lookup beside the first.

---

## 3. P1 — Uncloseing + capability system

### 3.1 Program valuations

`ProgramValuation` becomes a sum type on a `model` discriminator — the pattern `Earn` already uses
on `type` (`CatalogueModels.swift:8`):

```swift
public enum ProgramValuation: Equatable, Sendable {
    case points(PointValuation)
    case cashback(CashBackValuation)
    case ctMoney(CtMoneyValuation)
    case cro(CroValuation)
}

public struct Valuations: Codable, Equatable, Sendable {
    public var programs: [String: ProgramValuation]
}
```

Each existing valuation type survives intact. CRO keeps its `faceValueFactorIfAutoSold` /
`defaultHeldRiskFactor` branch on `croHandling`; CT Money keeps its usability factor. **No flattening
into anonymous factors, and no condition-expression strings** — a string like
`"croHandling == autoSell"` would require a parser, and the parser is code, which moves the closed
set rather than opening it.

**Catalogue ships default valuations; owner state overrides.** New `contracts/programs.json` carries
a default `ProgramValuation` per `programId` plus its `basis` text. Resolution order is
`ownerOverride ?? catalogueDefault ?? unsupported`. Without this, adding a program stays a two-place
change (catalogue *and* every owner-state file). Defaults must remain inspectable and overridable:
per standing policy, point values are disclosed assumptions, not facts.

`Scorer.valueCad` returns an outcome rather than a `Double`, so a missing program can never silently
become zero.

### 3.2 Owner conditions

`CardState` gains `flags: [String: Bool]?`. `rogersEligibleServiceLinked` and
`cryptoLevelUpProActive` migrate into it. Genuinely structural fields stay named, because specific
engine logic reads them rather than generic condition resolution: Tangerine's selection machinery
(`selectedCategories`, `treatAsAllSelected`, `thirdCategoryUnlocked`, `nextChangeEffectiveDate`) and
`croHandling`.

```swift
static func conditionsResolveTrue(_ conditions: [String]?, state: CardState) -> Bool {
    guard let conditions else { return true }
    return conditions.allSatisfy { condition in
        switch condition {
        case "tangerineCategorySelected": return state.selectedCategories != nil
        default: return state.flags?[condition] ?? false   // fail closed
        }
    }
}
```

The schema's `ownerConditions` enum becomes an **open** documented vocabulary, matching how benefits
`family`/`kind` are already handled.

**Conditions must declare how to ask.** `WalletSetupView.swift:118,130,171` currently hardcodes
`setup.ownedCardIds.contains("rogers-red-we")`. Each condition carries a prompt so the setup UI is
data-driven end to end:

```json
"ownerConditions": [
  { "conditionId": "amazonEligiblePrimeLinked",
    "prompt": "Is an active Amazon Prime membership linked to this card?" }
]
```

### 3.3 Cap anchors

`CardState.anchors: [String: Int]` replaces `scotiaAccountYearAnchorMonth` and
`rogersAccountAnniversaryMonth`. `CapWindow.anchorMonth`'s path switch becomes a dictionary lookup.
An unresolvable anchor keeps today's fail-closed behaviour but gains a warning.

The dictionary also carries P2's statement day-of-month at no extra cost — it is simply another key.
Owner setup collects the statement period alongside the anniversary date (§9.2).

### 3.4 Merchant index and presentation registries

- `CanadianMerchantPreIndex.swift`'s 127 literals → `contracts/merchant-index.json`, same provenance
  treatment as the rest of `contracts/`.
- `CardVisualTheme` → `contracts/presentation.json`, **with a default theme derived from `network` +
  `issuer`** so an unthemed card renders sanely instead of falling off a `switch`.
- `shortName` becomes an optional `CardProduct` field, falling back to a truncation of
  `officialName`.
- `categoryAmountEstimates` moves into the per-market block — those are CAD figures and become wrong
  the moment a US card exists.

### 3.5 The capability system

Rules declare what they need; the engine declares what it has; mismatch is loud, visible and
fails closed.

```json
{ "ruleId": "td-fct-grocery-6x", "requires": ["cap.statementYear"] }
```

```swift
public enum EngineCapability: String, CaseIterable, Sendable {
    case capCalendarMonth    = "cap.calendarMonth"
    case capCalendarYear     = "cap.calendarYear"
    case capAccountYear      = "cap.accountYear"
    case capStatementYear    = "cap.statementYear"             // not yet supported
    case capGlobalGroup      = "cap.globalGroup"               // not yet supported
    case merchantPartnerList = "predicate.merchantPartnerList" // not yet supported
}
static let supported: Set<EngineCapability> = [ … ]
```

A rule whose `requires` is not a subset of `supported` is skipped with a recorded reason. A card
whose program resolves to no valuation is excluded with a recorded reason, reusing the existing
`RuleResolution.cardExcluded(reason:)` concept.

**Two markers, not one — "not yet" and "never" are different states** (§9.3). A rule blocked on
unbuilt work declares `requires: [...]` and turns on automatically when that capability ships. A rule
that is permanently inert declares `outOfScope: { reason: "..." }`, and its capability is never to be
built. Collapsing these into one marker is how a future reader ends up building channel identity
because a rule appeared to ask for it.

**This replaces `scoredInV1`,** which is a hand-maintained boolean with no machine meaning. Migrating
the existing 51 disabled rules is mechanical: each rule's `requires` is derivable from its `_note`
text. Ten rules carry no blocker in their note; nine are assigned by inference in §9.1 and one
(`scotia-gold-gas-transit-3x`) needs a human answer.

**The property that matters is what happens when a capability is later added.** Today, shipping
statement-period caps means hunting the catalogue for every `scoredInV1: false` blocked on that and
flipping each by hand, with no way to know the set is complete. With declared capabilities, adding
`capStatementYear` to `supported` turns on every rule that declared it, with no catalogue edit. The
maintenance burden inverts from O(rules) to O(capabilities).

### 3.6 Warnings, and a reachable crash

**Corrected 2026-08-20 during implementation planning.** This section originally proposed a new
`EngineWarning` type with associated values. That was wrong: `Scorer.swift:3` already defines a
`Warning` enum, `CandidateScore` already carries `warnings: [Warning]`, and `exclusionReason: String?`
already exists for human-readable detail. Extending those is smaller and follows the established
pattern.

```swift
public enum Warning: String, Codable, Equatable, Sendable {
    case drawerCard, unresolvedOwnerState, networkNotAccepted,
         capNearlyExhausted, negativeNetValue, fxAllowanceAssumed, hypotheticalSelection,
         unsupportedProgram,      // no valuation for this card's program
         unsupportedCapability    // rule needs an engine feature this build lacks
}
```

The specifics — which program, which capability — travel in `exclusionReason`.

`RecommendationEngine.swift:54` holds
`precondition(!scores.isEmpty, "no scorable card — catalogue misconfigured")`. Once unsupported
programs *exclude* cards rather than scoring them zero, a wallet of entirely unsupported cards
reaches that precondition — a data-triggered crash. `recommend` therefore returns an outcome:

```swift
public enum RecommendationOutcome: Sendable {
    case advised(Recommendation)
    case cannotAdvise(reasons: [String])
}
```

**This is the one genuinely breaking engine-API change in the program.** It is the right one: "I
cannot advise you, and here is why" is information the UI needs and currently cannot express.

**Staleness becomes machine-read.** The engine computes `lastVerifiedAt` age against `asOf` and emits
`staleData` past a per-market threshold. Nearly free once warnings exist, and it is the only thing
that makes ~8,000 facts survivable. The threshold is deliberately unset at first — warn only, no CI
gate, for one release cycle, then set it from observed issuer change frequency (§9.5).

### 3.7 Migration safety

The hazard, precisely: `OwnerState` is JSON-encoded into `UserDefaults` under
`ca.pickme.owner-state-profiles.v1` as a **dictionary of all profiles**, decoded via
`(try? JSONDecoder().decode([String: OwnerState].self, from: data)) ?? [:]`
(`AccountOwnerStateStore.swift:65`, and identically at `:103` in `OwnerStateUploadQueue`). `Valuations` fields
are non-optional. A naive shape change fails every profile at once, silently, returning zero
profiles — total wallet loss with no error surfaced.

| # | Change | Notes |
|---|---|---|
| a | **Tolerant per-profile decode** | Decode outer dictionary to raw values, attempt each profile independently, drop and log the bad one. **Ship first, alone, with tests** — protects every future migration, not just this one. |
| b | **Dual-shape decode for `Valuations`** | Custom `init(from:)` accepting legacy named fields *or* the `programs` dictionary; always encodes the new shape. Keep one full release cycle, then delete with a dated changelog entry. |
| c | **Server coordination** | `OwnerStateUploadQueue` pushes the complete wallet to MoneyTalks and `MoneyTalksSync` reads back server-resolved `resolvedCardId`. Both sides see the shape change; the server must accept both during transition. **Needs a decision-log entry, not just this repo's changelog.** |
| d | **`ownerStateVersion` made load-bearing** | Currently decoded and never read, exactly as `catalogueVersion` was before the contract work. Gate on MAJOR the same way. |
| e | **Kotlin twin** | `OwnerState.kt:96` is the identical fixed struct; `Scorer.kt:161` the identical `else -> 0.0`. Same dual-shape decode. Android's Room DB holds predictions/purchases/observations/merchants, not owner state, so the local hazard is smaller — but the data class must read a synced payload in either shape. |
| f | **Sequence the MoneyTalks re-pin** | Catalogue files change → sha256 changes → drift check fails until re-synced. Land catalogue change, re-pin, then land the consumer change. |

### 3.8 File layout and split-readiness

- **Add `market: "CA"` per card.** The catalogue-level `currency: "CAD"` is the single field most
  directly blocking a US card.
- **Move market-specific singletons into a per-market block:** currency, `categoryAmountEstimates`,
  staleness threshold, default program valuations.
- **Keep one file.** The future split is `cards.filter { $0.market == "CA" }` as a build step — safe
  precisely because nothing cross-references across markets.
- **Add `contracts/manifest.json`:** catalogue version, per-file sha256, generation timestamp. This is
  what P4's snapshot sync verifies, and it immediately replaces MoneyTalks' hand-pinned hashes.

New files, each with a schema: `merchant-index.json`, `presentation.json`, `programs.json`,
`manifest.json`. Both sync scripts and `ContractsSyncTests` extend to cover them.

### 3.9 Testing

1. **The existing 27 fixture cases must pass byte-unchanged.** If the valuation refactor is
   behaviour-preserving for the six known programs, every case produces identical output. Any diff is
   a bug, not an expectation update. This is the primary safety net.
2. **New fixture families:** unsupported program → excluded with warning, never $0-ranked · rule
   declaring an unsupported capability → skipped, card still scored on its other rules · owner
   condition supplied via `flags` → rule fires (pins `amazonEligiblePrimeLinked`) · condition absent
   → fail closed with warning · unresolvable cap anchor → warning · *every* card unsupported →
   `cannotAdvise`, no crash · stale `lastVerifiedAt` → warning at a pinned `asOf`.
3. **Mutation-test every new optional field** — same bar the contracts changelog already sets: "an
   optional field with a typo'd key is a silent no-op."
4. **Migration tests:** legacy `OwnerState` decodes; one corrupt profile does not take out its
   neighbours; round-trip writes the new shape.
5. **Kotlin parity**; `fixturesVersion` MINOR bump.
6. **New CI gate:** assert every `programId` in the catalogue resolves to a valuation, every
   `requires` value is a known capability, every `ownerConditions` id is answerable, and every
   `cap.anchor` is resolvable.

---

## 4. P2 — Cap expressiveness

Three model changes covering 21 dead rules:

- **`Cap.scope: "rule" | "card"`** — a card-scoped cap counts all spend regardless of which rule
  fired. Covers CIBC Dividend's $50k all-purchases counter.
- **`rule.capIds: [String]?`** (additive; `capId` retained, so MINOR not MAJOR) with
  **first-exhausted** resolution. Covers CIBC's *"$50k all-card purchases OR $20k accelerated
  purchases, whichever first."*
- **`CapPeriod.statementYear` / `.statementMonth`** with a statement-date anchor, inheriting P1's
  anchor dictionary. Covers TD FCT's January statement window and CIBC's December reset.

National Bank's 5x→2x tiering falls out for free: a card-scoped monthly $2,500 cap whose
`postCapEarn` is 2x. No new reward type is needed.

**Resolved 2026-08-20 (§9.2): day-precise window boundary, month-precise projection output.** The
statement period is collected from the owner alongside the anniversary date, so the input exists.
`CapWindow.Window` gains day granularity — a type change that ripples into `CapProjector`, making
this project larger than first sized. `CapProjector`'s reported crossing stays at month granularity,
because its inputs are declared billing estimates.

---

## 5. P3 — Merchant identity

The one project that is not an engine project. Covers ~21 dead rules (13 MCC strictness, 8 merchant
identity) and gates any US launch, since the entire merchant index is Canadian.

- **5a. Index at scale** — 127 entries → thousands, CA and US. Unlike the card catalogue, this is
  where external POI datasets genuinely help.
- **5b. Brand/family resolution** — "Loblaw family" spans Loblaws, No Frills, RCSS, Zehrs,
  Independent, Shoppers. The model already has the shape (`merchantInclude: ["loblaws"]` in
  predicates, `merchantBrand: "loblaws"` in the index); it needs scale plus a family/partner-list
  concept.
- **5c. Channel identity — resolved 2026-08-20: permanently out of scope** (§9.3). These are online
  booking channels; PickMe is an at-the-register copilot. The affected rules take an `outOfScope`
  marker rather than `requires`, and `predicate.channelIdentity` is removed from `EngineCapability`
  entirely.
- **5d. MCC supply** — issuers do not publish per-merchant MCC, so no external dataset solves this.
  But `sourceType: ownerObserved` already exists in the contract, and `StoredObservation` already
  records `observedCategory` and `missClassRaw` from owner confirmations. **MCC can be learned from
  owner feedback** — merchant → presumed MCC, confidence rising with confirmations, provenance
  honestly marked `ownerObserved`. This is a better fit than sourcing data that does not exist.

**Note:** `mccRequired` strictness is deliberately *not* proposed. Because `purchase.mcc` is `nil` on
every real checkout, `mccRequired: true` would be `scoredInV1: false` in disguise. Revisit only once
5d supplies MCCs.

---

## 6. P4 — Snapshot delivery

Chosen model: **bundled floor snapshot plus signed, opportunistically-synced updates.** The
recommendation path reads a file on the device and never touches the network. The only change is how
that file arrives.

- **Signing** — Ed25519 detached signature over `manifest.json`; public key in the binary. The
  manifest carries per-file sha256, so one signature covers the whole snapshot. This replaces the
  integrity guarantee currently provided free by iOS code-signing the app bundle.
- **Sync client** — background fetch, ETag/`If-None-Match`, atomic swap; never mutates the snapshot
  mid-recommendation.
- **Version skew** — an engine lacking a capability a new snapshot requires skips those rules with
  warnings. **This is P1's capability system doing the work,** and is why P4 cannot precede it.
- **Fallback ladder** — cached snapshot → bundled floor snapshot. Never a partial state.
- **Partitioning** — by `market` (added in P1). **Whole-market fetches only, never per-card**, so
  request patterns cannot leak which cards an owner holds.
- **Offline hole** — an owner adding a card while offline whose rules are not in the local snapshot.
  Either constrain the picker to the cached snapshot or fail closed with a clear message. Must be
  deliberate.
- **CI runs the fixture harness against the published snapshot** before devices can reach it. This
  replaces the engine/data version-locking that bundling currently provides for free.

**Privacy position.** The live commitment is `testflight-beta-notes.md`: *"The core app functions
completely on-device without an account."* Verified: `prepareAccount` opens with
`guard let userID else { return }`, so the signed-out path reaches no backend. Snapshot delivery
preserves this exactly; live query would destroy it. Effective-dating (`status: "announced"` with
`effectiveFrom`) means a device holds rules weeks before they activate, so infrequent syncing stays
correct.

---

## 7. Sequencing

1. **P1** — hard gate; shrinks all three others.
2. **P2 and P4** — independent of each other, either order. P2 delivers more visible value sooner;
   P4 becomes urgent as P3 grows the data volume.
3. **P3** — starts any time after P1 fixes the data location; runs longest, in parallel.

**Two items to ship immediately, before P1,** because they are small and protect everything after:

- **The catalogue/capability CI gate** (~20 lines). It would have failed the day `scotia-gold-amex`
  was added with `programId: "scenePlus"`, again for each of the nine programs after it, and again
  when `amazonEligiblePrimeLinked` landed with no handler — four batches of silent breakage caught at
  authoring time.
- **Tolerant per-profile decode** in `AccountOwnerStateStore` (§3.7a).

---

## 8. Out of scope

- **Milestone/threshold rewards** (Scotia Passport's $40k Scene+ bonus, WestJet's companion voucher,
  MBNA's birthday bonus). These do not depend on what the purchase was, so they never enter the
  checkout pick — the same reasoning `CardCredit` already documents. They belong to
  `PortfolioAnalyzer` and keep/cancel display, modelled as a `milestones` array separate from
  `earnRules`.
- **Loyalty baseline / marginal earn** (PC Optimum member earn vs. card-marginal earn). Real, and
  already noted in the catalogue's `_note` fields, but a scoring redesign. Later.
- **External dataset import.** Verified 2026-08-20: `sgolovine/cc-offers` is MIT with 242 offers from
  28 issuers, but its README describes *offers* data — welcome/intro bonuses, APR, fees, perks — with
  no structured reward rules, MCC codes or effective dates. Welcome offers are content this catalogue
  deliberately excludes. OpenCard's own site states 224 US cards, US only, with no license stated for
  code or data. **Neither can be a source of truth here regardless of licence**, because every fact
  would land at `sourceType: inferred`, which the D3 sourcing bar forbids shipping. Import buys
  discovery, not verification, and verification is the expensive half. What *is* worth taking is
  cc-offers' MIT agent-refresh workflow — see §9.
- **Open-sourcing the catalogue.** Strategy decision, not engineering. Easier after the schema
  settles.
- **Extracting the catalogue into a standalone data product.** Deferred by design, not rejected:
  §3.8's layout and §6's manifest make later extraction mechanical rather than a rewrite.

---

## 9. Decisions — resolved 2026-08-20

| # | Decision | Resolution |
|---|---|---|
| 1 | Blockers for the unlabelled `scoredInV1: false` rules | **Resolved except one** — see §9.1 |
| 2 | Statement-period caps: month or day precision? | **Day precision.** Statement period is collected from the owner alongside the anniversary date. See §9.2 |
| 3 | Channel identity in scope? | **No — permanently out of scope.** See §9.3 |
| 4 | Adopt cc-offers' MIT agent-refresh architecture? | **Yes, the pattern — not the code.** See §9.4 |
| 5 | Staleness threshold and CI behaviour | **Measure before setting.** See §9.5 |
| 6 | Server acceptance window for both `Valuations` shapes | Open — see §9.6 |

### 9.1 Blockers for unlabelled disabled rules

Seven rules carry no `_note`; three more carry a note that describes the rule without naming a
blocker. Assignments below are inferred from predicate shape and sibling rules on the same card.

| Rule | Assigned blocker |
|---|---|
| `scotia-gold-gas-transit-3x` | **Needs a human answer.** Plain category predicate, `capId` on a `calendarYear` cap the engine already supports. Appears to have been disabled as a group with its cap-sharing siblings. May be enableable as soon as `scenePlus` has a valuation — verify before assuming. |
| `td-fct-dining-6x`, `td-fct-transit-6x`, `td-fct-recurring-digital-4x` | P2 — `cap.statementYear` + shared `capIds`. Sibling `td-fct-grocery-6x` cites TD's $25k January statement-period cap; these carry no `capId` because a shared statement-period cap was inexpressible. |
| `nbc-we-recurring-2x` | P2 — card-scoped monthly cap with `postCapEarn`. This is the post-cap tier of the 5x→2x structure, not an independent rule. |
| `nbc-we-a-la-carte-travel-2x` | **Out of scope** (§9.3) — `channels: ["aLaCarteTravel"]`. |
| `pc-insiders-joe-fresh-40ppd` | P3 — merchant identity. Joe Fresh is a Loblaw brand; sibling cites Loblaw-family normalization. |
| `westjet-rbc-direct-2x` | P3 — merchant identity ("eligible WestJet flights or Vacations packages"). |
| `amazon-ca-prime-2_5x`, `amazon-ca-nonprime-1_5x` | **P1** — owner condition (`amazonEligiblePrimeLinked`). Fixed outright by §3.2. |

### 9.2 Statement-period precision

**Window boundary is day-precise; projection output stays month-precise.** These are separable, and
`CapWindow`'s existing note — *"pretending to a day would be precision the data does not carry"* —
governs the second, not the first. The counter therefore resets on the correct calendar date, while
`CapProjector` continues reporting a crossing to the month, because its inputs are declared billing
estimates.

Consequences for P2, which make it larger than first sized:

- `CapWindow.Window` is `(startMonth, endMonth)` strings today. Day precision changes that type, and
  `CapProjector` consumes it.
- The input is free: a statement day-of-month is simply another key in P1's
  `CardState.anchors: [String: Int]` dictionary (§3.3). Owner setup collects it alongside the
  anniversary month.

### 9.3 Channel identity — out of scope, permanently

"Expedia For TD", "Amex Travel", "CIBC Rewards Centre", NBC's `aLaCarteTravel` are online booking
channels. PickMe is an at-the-register copilot; these do not belong to it.

**This requires a distinction the capability system did not originally carry: "not yet supported"
versus "never; out of scope."** Without it, a future reader sees
`requires: ["predicate.channelIdentity"]` and builds the capability because a rule asked for it.

- `requires: [...]` means *not yet* — the rule turns on automatically when the capability ships.
- `outOfScope: { reason: "..." }` means *never* — the rule is permanently inert and its capability is
  never to be built.

Rules taking `outOfScope`: `nbc-we-a-la-carte-travel-2x`, `td-fct-expedia-8x`,
`cibc-aventura-rewards-centre-2x`, `cobalt-amex-travel-bonus`, `cibc-dividend-expedia-2pct`.
`predicate.channelIdentity` is removed from the `EngineCapability` enum entirely.

### 9.4 Authoring pipeline

Adopt cc-offers' **pattern**, not its code — its workflow targets an offers-shaped schema (§8). The
loop worth copying: institution-target research → issuer-page research → write an entry carrying
source URL, retrieval timestamp and raw evidence.

**Add the gate cc-offers does not have:** an agent-authored entry lands at `sourceType: inferred` and
cannot ship until a human promotes it to `issuerConfirmed`. This is the D3 sourcing bar, and it is
what prevents agent throughput from becoming agent-authored financial advice.

### 9.5 Staleness threshold

**Do not pick a number now.** Emit the `staleData` warning with no CI gate for one release cycle,
observe how often issuer facts actually change, then set the threshold from that evidence. A number
chosen today would be invented.

The signal has a user-facing home already: `submission-readiness.md` B13 wants
*"Rules verified `<date>`"* on the recommendation screen.

### 9.6 Server acceptance window — still open

When the wallet data shape changes, owners on older app builds keep sending the **old** shape to
MoneyTalks until they update. The server must therefore understand both shapes for some period.

The open question is how long that period is before the old-shape handling is deleted — which is
really a question about **how long old app versions are supported**. Cross-repo; needs a decision-log
entry in MoneyTalks, not just this repo's changelog.

---

## 10. Compliance-doc drift, recorded here so it is not lost

Not a defect — the compliance documents are pre-launch drafts written ahead of the code, and revising
them toward reality is expected. Recorded so the revision actually happens.

`submission-readiness.md:451` (B10) asks for an automated guard that the app makes no network call
except MapKit, stating the entire privacy posture rests on it, and noting it is "guaranteed only by
nobody having added a dependency yet."

The **posture holds**: sign-in is optional and `prepareAccount` guards on `userID`, so the signed-out
path reaches no backend. But ClerkKit is now linked in and `Clerk.configure(publishableKey:)` runs
unconditionally in `CardCopilotApp.init()` on every launch, including signed-out. Whether it performs
a client or environment bootstrap at configure time is SDK internals, not determinable from this
source, and can change in a point release.

**Corrected action item:** restate B10 as *the signed-out launch path issues no request to any host
but MapKit's*, and assert it in a test. Unlike the unconditional form, that will not fail by design
the moment someone signs in.

**The discipline that still binds:** softening is free while these documents are unpublished. The
docs' own rule — *"Publishing `privacy-policy.md` before they ship turns a draft into a false
statement"* — is about publication, not authorship. An accuracy pass across
`submission-readiness.md`, `privacy-policy.md`, `app-privacy-labels.md` and `testflight-beta-notes.md`
is a gate before anything goes public, and is its own task, independent of this program.
