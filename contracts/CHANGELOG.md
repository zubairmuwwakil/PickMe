# Contracts changelog

One entry per catalogue/fixture change (spec §3). Newest first.

## 2026-08-20 — card-catalogue 1.4: three cards were silently fee-free on FX; fixtures 1.2

- **BUG FIX. `rbc-ion-plus-visa`, `bmo-ascend-world-elite` and `cibc-aventura-visa` shipped
  `"fxRules": []`** — the only three cards in either catalogue with no FX rule at all. `Scorer`
  reads "no active rule" as **zero** FX cost, so all three ranked as well as Wealthsimple on every
  foreign-currency purchase. Each now declares the standard 2.5%. `catalogueVersion` `1.3` → `1.4`.
- Tagged `sourceType: "inferred"`, not `issuerConfirmed`: 2.5% is each issuer's standard
  conversion markup and is corroborated by published card reviews (checked 2026-08-20), but the
  cardholder agreements themselves were not read. Each rule carries a `_note` saying so. Confirm
  and re-tag when the agreements are checked.
- **The gap was hidden behind another gap.** All three cards were unscorable until their programs
  gained valuations the same day, so no fixture had ever exercised their FX path. The schema
  cannot catch this — `"fxRules": []` is valid, and must stay valid, because *absent* and *zero*
  are different claims. New gate `CatalogueIntegrityTests.testEveryCardDeclaresAnFxRule` requires
  every card to state a rate. No allowlist: a genuinely fee-free card says `rate: 0.0` out loud,
  as `wealthsimple-vip`, `scotia-gold-amex` and `scotia-passport-visa-infinite-plus` already do.
- **`engine-fixtures.json` `1.1` → `1.2`. Four of the 27 expectations moved, on the `runnerUp`
  field ONLY — every `winner` and `winnerValueCad` is unchanged.** The fixtures run against
  `owner-state.json`, which owns all 27 cards, so the 14 previously-excluded cards were always in
  the candidate field; valuing their programs let them place. Each `notes` field carries the
  re-derived arithmetic.
  - `costco-mastercard-only-200`: mbna $2.00 → westjet $3.00
  - `rogers-cap-exhausted-postcap-400`: mbna $4.00 → westjet $6.00
  - `owner-condition-unresolved-rogers-300`: mbna $3.00 → westjet $4.50
  - `usd-online-165cad-crypto-inactive`: rogers $0.825 → scotia-gold-amex $1.65
- The first three are the **same fact**: WestJet's 1.5 points/$ at the posted 1.0¢ is 1.5%, the
  identical rate Rogers pays in cash. `rank()` breaks exact ties on `cardId` ascending, so Rogers
  keeps every win and WestJet takes second. **New case 28, `westjet-rogers-exact-tie-100`**, pins
  that tie explicitly — three cases had started depending on a tie-break nobody had asserted, and
  a future revaluation should fail one case that explains itself rather than three that look like
  unrelated regressions.
- The fourth is the FX bug: `cibc-aventura-visa` briefly took that slot with a wrong $1.65 before
  the fix. It is now `scotia-gold-amex`, which genuinely charges no FX and earns Scene+ 1x —
  the right answer for a USD purchase, and the case that caught the bug.
- **Known divergence: the Kotlin twin now fails these five cases.** `android`'s `Valuations` is
  still the six-property struct — Tasks 3–7 of the valuation phase are Swift-only so far — so its
  engine cannot value the ten new programs and still ranks them at $0.00. The fixture count
  constant in `FixtureHarnessTest.kt` is bumped to 28, but parity is Task 11 and is not done here.
  Android is not in CI (`.github/workflows/ci.yml` runs Swift only), so this does not gate merges.

## 2026-08-20 — programs.json: sourced valuations for the last ten programs; programsVersion 1.1

- **Every programId the catalogue declares is now valued.** `scenePlus`, `aeroplan`, `rbcAvion`,
  `tdRewards`, `bmoRewards`, `aventura`, `nbcRewards`, `pcOptimum`, `westJetPoints` and
  `amazonRewards` gain defaults, so `CatalogueIntegrityTests.knownUnvaluedPrograms` is EMPTY and
  its ratchet is set to `0`. A card on a new program now fails CI at authoring time instead of
  shipping as a silent exclusion.
- `programsVersion` `1.0` → `1.1` (MINOR, additive — ten programs added, none revalued).
- **One rule, applied uniformly**, recorded in the file's new `_method` key so the numbers mean
  the same thing on every card:
  - `centsPerPoint` = the best POSTED FIXED conversion the program publishes. A rate, never a
    forecast of what some redemption might turn out to be worth.
  - `floorCentsPerPoint` = the rate obtainable with nothing but the card — an unconditional
    statement credit, no qualifying purchase and no second account. OMITTED where the program has
    no cash redemption at all (`aeroplan`, `pcOptimum`, `westJetPoints`, `amazonRewards`), because
    `Scorer` falls back to `centsPerPoint` and a fabricated floor would pass an assumption off as
    a guarantee.
  - `aspirationalCentsPerPoint` = a published benchmark ONLY where it exceeds the ranked value.
    Only `aeroplan` (2.0¢) and `rbcAvion` (2.0¢) qualify; for the rest the benchmark sits at or
    below the posted rate, so there is no upside band to disclose.
- Ranked values, each with its source in `basis`: `scenePlus` 1.0¢ (floor 0.666667),
  `aeroplan` 1.0¢, `rbcAvion` 0.58¢ (floor 0.58), `tdRewards` 0.5¢ (floor 0.25),
  `bmoRewards` 0.666667¢ (floor 0.333333), `aventura` 1.0¢ (floor 0.625), `nbcRewards` 1.0¢
  (floor 0.4), `pcOptimum` 0.1¢, `westJetPoints` 1.0¢, `amazonRewards` 1.0¢.
- **`aeroplan` is ranked by transfer parity, not by benchmark.** It has no cash-out and posts no
  fixed conversion, so there is no issuer fact to anchor to. Amex Membership Rewards converts to
  Aeroplan 1:1 and is ranked here at 1.0¢; ranking Aeroplan above that would make one point worth
  more after a free transfer than before it. The published 2.0¢ benchmark (Prince of Travel Q2
  2026, as of 2026-05-01; Milesopedia 2026-01-01 agrees) is carried as the disclosure ceiling.
- **`rbcAvion` is one programId over two currencies — a known defect, disclosed in its `basis`.**
  `rbc-avion-visa-infinite` earns Avion Elite points (statement credit 0.58¢, flexible travel
  credit 1.0¢, Air Travel Redemption Schedule up to ~2.3¢); `rbc-ion-plus-visa` earns Avion
  Premium points, whose only fixed redemption is 0.58¢ and which cannot transfer to airlines.
  0.58¢ is ranked because it is the one posted rate true for both. The override is per programId,
  so an Elite owner cannot correct their card without over-valuing the ION+. Splitting the
  programId is the real fix and is not done here.
- **`westJetPoints` is WestJet POINTS, not the retired WestJet dollars.** The program converted on
  2025-04-30; WestJet posts 100 points = C$1 off base fare, surcharges, bags and seats, and RBC's
  product page states the earn as 1.5 and 2 points per dollar. That is what makes the catalogue's
  earn figures and a 1.0¢ unit value agree with the card's marketed 1.5% return.
- `pcOptimum` and `amazonRewards` are store-locked scrip valued at face. That is the same
  question `ctMoney` carries a 0.95 usability factor for, but the `points` model has no such
  factor; rather than invent a discount, each `basis` names the assumption and tells the owner to
  override downward if they do not shop there.
- Sources are named per entry and were checked 2026-08-20: issuer pages (Scotiabank, WestJet, PC
  Financial, MBNA, RBC, TD) for posted rates, and Prince of Travel, Milesopedia, Frugal Flyer,
  Money We Have and Ratehub for cash-out rates and benchmarks. Where two benchmarks disagree
  (Avion 2.0 vs 1.6, Aventura 1.0 vs 1.2) neither is used for ranking.

## 2026-08-20 — programs.json: catalogue-level default valuations; catalogueVersion 1.3

- **`programs.json` is read by the scoring path**, not just shipped: `RecommendationEngine.init`
  merges these defaults beneath whatever the owner has declared, so every scoring caller
  (PortfolioAnalyzer, RecurringAuditor, CategoryPickerAdvisor, Store's CheckoutService) picks them
  up — including owner states restored from a device, which never pass through `SeedLoader`. The
  owner's own declaration wins every key it sets; the catalogue only fills gaps. Against today's
  data the merge is a verified no-op, which is why the 27 fixtures still pass byte-unchanged.
- **New contract `programs.json`** (+ `schema/programs.schema.json`), copied into Engine and
  Android resources by both sync scripts and guarded by `ContractsSyncTests`. It holds the
  catalogue's DEFAULT valuation per `programId`; `OwnerState.valuationsCad` overrides any entry
  key-for-key. Loaded by `SeedLoader.loadPrograms()`.
- `catalogueVersion` `1.2` → `1.3` (MINOR). Additive: no card data changed, no rule changed, and
  all 27 golden fixtures in `engine-fixtures.json` pass byte-unchanged.
- **`program.programId` is no longer an engine dispatch key.** `Scorer.valueCad` used to switch on
  the programId string, so each of the six programs it named needed a hardcoded Swift property and
  a Kotlin twin — while the catalogue shipped sixteen programIds. The other ten fell to the
  switch's `default: return 0.0`, so 14 of 27 cards scored exactly $0.00 on every purchase while
  staying selectable in wallet setup. The Scorer now dispatches on the valuation's *model*, and a
  program becomes scoreable by gaining a data entry.
- The `programId` enum is hoisted to `card-catalogue.schema.json#/$defs/programId` so
  `programs.schema.json` references one list rather than keeping a second copy in step. Its
  description and the schema's top-level description are corrected accordingly.
- **Ten programs are deliberately left unvalued**: `scenePlus`, `aeroplan`, `rbcAvion`,
  `tdRewards`, `bmoRewards`, `aventura`, `nbcRewards`, `pcOptimum`, `westJetPoints`,
  `amazonRewards`. They need researched, sourced valuations. A guessed default is a number the
  owner cannot check silently deciding recommendations — the exact failure this contract exists to
  prevent. The gap is pinned in `CatalogueIntegrityTests.knownUnvaluedPrograms`, which now derives
  its "valued" set from this file and fails if an entry here is left listed as a known gap.
- Every default carries a `basis` disclosure naming its source and separating issuer facts from
  assumptions. `basis` was added to `CashBackValuation`, `CtMoneyValuation` and `CroValuation`
  (Swift and Kotlin); previously only `PointValuation` had one, so a disclosure written for CT
  Money's usability factor or CRO's held-risk factor would have been dropped on decode.
- `CroValuation.model` → `redemptionModel` (owner-state.json and both language twins). The
  `ProgramValuation` union's `model` discriminator shares one flat JSON object with its payload,
  so no payload may own that key.
- Owner states written before today are still read: `Valuations` decodes both the legacy
  named-field shape and `{"programs": {...}}`, and always writes the latter, so a wallet upgrades
  itself on first save. The legacy branch may be deleted one full release cycle after ship, with a
  dated entry here. Note the legacy key `cashBack` maps to programId `cashback`.

## 2026-08-20 — Standardized Cap Anchors in Candidate Catalogue

- Standardized `simplycash-preferred` cap anchor `"cardmembership anniversary"` → `"ownerState.amexAccountAnniversaryMonth"` in `candidate-catalogue.json`.
- Standardized `rbc-cashback-preferred` cap anchor `"account anniversary"` → `"ownerState.rbcAccountAnniversaryMonth"` in `candidate-catalogue.json`.
- Both anchors match the schema specification (`card-catalogue.schema.json:558`) requiring pointer path strings rather than informal text.
- Ran sync scripts to update Engine and Android resource copies.

## 2026-08-18 — Added Batch 3 of 7 Canadian Card Products & Insurance Certificates

- Added 7 researched Canadian credit cards to `card-catalogue.json`:
  1. `rbc-ion-plus-visa` (RBC ION+ Visa)
  2. `td-cash-back-visa-infinite` (TD Cash Back Visa Infinite Card)
  3. `bmo-ascend-world-elite` (BMO Ascend World Elite Mastercard)
  4. `westjet-rbc-world-elite` (WestJet RBC World Elite Mastercard)
  5. `amazon-ca-rewards-mastercard` (Amazon.ca Rewards Mastercard)
  6. `cibc-aventura-visa` (CIBC Aventura Visa Card)
  7. `amex-simplycash` (SimplyCash Card from American Express)
- Extended `program.programId` enum in `card-catalogue.schema.json` with `"westJetPoints"` and `"amazonRewards"`.
- Sourced and added verified Certificates of Insurance for all 7 cards at `issuerPage` verification status in `benefits-catalogue.json`.
- Accelerators set to `scoredInV1: false` fail closed safely pending dynamic points-program valuation, strict MCC predicate matching, and multi-cap engine support.
- Foreign purchases on `rbc-ion-plus-visa`, `bmo-ascend-world-elite`, and `cibc-aventura-visa` fail closed/suppressed due to unresolved card-specific FX rates.

## 2026-08-18 — catalogueVersion / benefitsCatalogueVersion bumped to 1.1 (MINOR)

- `catalogueVersion` in `card-catalogue.json` and `benefitsCatalogueVersion` in
  `benefits-catalogue.json` both bump `1.0` → `1.1`. No shape change; this is a
  catch-up bump. Both fields sat at `1.0` through the two batches below (10
  cards added, `program.programId` schema enum extended by 8 values) with no
  version bump either time, which is the reason MoneyTalks' vendored copy
  could drift silently for two syncs running: `catalogueVersion` was the one
  signal that could have told MoneyTalks its copy was stale, and it never
  moved. See `MoneyTalks/docs/superpowers/specs/2026-08-18-annual-fee-renewal-calendar-design.md`
  §12.1 for the full diagnosis and §12.2 for the fix (MoneyTalks' manifest now
  also records PickMe's git ref/commit directly, so this repeat cause and the
  version field are now two independent tripwires instead of one).
- The 10 cards this MINOR covers (both already-shipped batches, listed here
  once against the version they should have bumped):
  - `scotia-gold-amex`, `td-aeroplan-visa-infinite`, `rbc-avion-visa-infinite`,
    `cibc-dividend-visa-infinite`, `scotia-passport-visa-infinite-plus`
    (2026-08-17 batch 1)
  - `td-first-class-travel-visa-infinite`, `bmo-eclipse-visa-infinite`,
    `cibc-aventura-visa-infinite`, `national-bank-world-elite`,
    `pc-insiders-world-elite` (2026-08-17 batch 2)
- MAJOR stays reserved for a breaking shape change (spec §3); `SeedLoader.validate(catalogueVersion:)`
  gates on MAJOR only, so this MINOR bump requires no Engine code change —
  verified against `Engine/Sources/CardCopilotEngine/Loading/SeedLoader.swift`
  rather than assumed.
- Ran `scripts/sync-contracts-into-engine.sh` to carry both version bumps into
  the checked-in `Engine/Sources/CardCopilotEngine/Resources/` copies.

## 2026-08-17 — Added Batch 2 of 5 Canadian Card Products & Insurance Certificates

- Added 5 researched Canadian credit cards to `card-catalogue.json`:
  1. `td-first-class-travel-visa-infinite` (TD First Class Travel Visa Infinite Card)
  2. `bmo-eclipse-visa-infinite` (BMO eclipse Visa Infinite Card)
  3. `cibc-aventura-visa-infinite` (CIBC Aventura Visa Infinite Card)
  4. `national-bank-world-elite` (National Bank World Elite Mastercard)
  5. `pc-insiders-world-elite` (PC Insiders World Elite Mastercard)
- Extended `program.programId` enum in `card-catalogue.schema.json` with `"tdRewards"`, `"bmoRewards"`, `"aventura"`, `"nbcRewards"`, and `"pcOptimum"`.
- Sourced and added verified Certificates of Insurance for all 5 cards at `issuerPage` verification status in `benefits-catalogue.json`.
- Accelerators set to `scoredInV1: false` fail closed safely pending dynamic points-program valuation, strict MCC predicate matching, and statement-period/global cap engine support.

## 2026-08-17 — Added 5 Canadian Card Products & Insurance Certificates

- Added 5 researched Canadian credit cards to `card-catalogue.json`:
  1. `scotia-gold-amex` (Scotiabank Gold American Express Card)
  2. `td-aeroplan-visa-infinite` (TD Aeroplan Visa Infinite Card)
  3. `rbc-avion-visa-infinite` (RBC Avion Visa Infinite)
  4. `cibc-dividend-visa-infinite` (CIBC Dividend Visa Infinite Card)
  5. `scotia-passport-visa-infinite-plus` (Scotiabank Passport Visa Infinite + Card)
- Extended `program.programId` enum in `card-catalogue.schema.json` with `"scenePlus"`, `"aeroplan"`, and `"rbcAvion"`.
- Sourced and added verified Certificates of Insurance / Guides to Coverage for all 5 cards at `issuerPage` verification status in `benefits-catalogue.json`.
- Accelerators set to `scoredInV1: false` fail closed safely pending dynamic points-program valuation, strict MCC predicate matching, and multi-cap engine support.

## 2026-08-16 — Acquisition candidate catalogue

- Added `candidate-catalogue.json`, deliberately separate from the owned-card catalogue so an
  acquisition candidate cannot leak into checkout recommendations. The six-card initial Canadian
  shortlist uses only issuer-confirmed recurring earn, caps, fees and FX rules verified on
  2026-08-16. Welcome offers and first-year fee rebates are excluded from the encoded economics.
- Added an explicit `ownedCardIds` boundary to owner state. Acquisition analysis now compares each
  non-owned candidate against exactly those cards instead of treating catalogue membership as
  ownership.

## 2026-08-16 — Protection badge compares only what it shows

Fixes the `x-known-invariant-gap` recorded in the entry below; that key is gone from the schema,
replaced by `x-compared-vs-displayed`. No data change — engine, app, and schema documentation only.

- `maxAnnualCad` is now rendered by `BenefitsFormatting.factsLine` (`"$10,000/yr"`). It was voting in
  the dominance badge while invisible, so the badge's "equal or better on every line below" claim
  could turn on a row the user could not check. Concretely: Triangle's purchase protection displayed
  as `"90 days"`, character-identical to MBNA/Scotia/Tangerine/Rogers, while its unstated $10,000
  annual maximum strictly outranked all four.
- `maxOriginalWarrantyYears` is **removed from `BenefitsAdvisor.fieldSpecs`** and is now display-only
  (`"originals ≤ 5 yr"`). It is an eligibility ceiling, not a coverage magnitude: a certificate
  stating no ceiling plausibly means *no restriction* — the best case — but the code scored absence
  as worst, ranking the four cards carrying `5` above the five carrying `null` on a comparison that
  may have been exactly backwards. Absence is only rankable for magnitudes.
- The resulting invariant, now stated on `fieldSpecs` and `factsLine` and in the schema: **every
  compared field must be displayed; a displayed field need not be compared.** Pinned by
  `BenefitsComparisonTests.testOriginalWarrantyCeilingDoesNotDecideDominance` (ties instead of
  badging) and `testAnnualMaximumStillDecidesDominance` (the magnitude keeps its vote).

## 2026-08-16 — Fixture expansion (fixturesVersion 1.0 → 1.1)

- `engine-fixtures.json` grows 12 → 27 cases, completing spec §5: every rule family is now covered at
  least twice. New coverage: mccInclude at a nil MCC (the permissive-fallback path) and at a known
  non-matching MCC · mccExclude · merchantExclude by brand, isolated from the MCC gate · the
  effective-dating boundary from both sides of the flip day · the announced 2026-09-01 Crypto FX
  record ignored before its `effectiveFrom` · the FX free-allowance path · a second cap-proration
  straddle at a different split · a cap fully exhausted where the exhausted card still wins at its
  `postCapEarn` rate · switch-threshold `both` from the side the suite was missing (CAD floor met,
  pp floor missed) and the same purchase clearing both floors by 0.02pp · the valuation-upside
  disclosure gate from just inside and just outside the published benchmark · an `ownerCondition`
  left genuinely unresolved. MINOR, not MAJOR: shape is additive and every new expectation field is
  optional, so the 12 original cases are byte-unchanged and a 1.0 reader still loads the file.
- **Harness gained six fields, because three of §5's families were inexpressible in 1.0.** Per-case
  `asOf` (date boundaries cannot be exercised at one fixed date); `expected.warningsAbsent` (Crypto's
  two FX records are both rate 0, so the announced record applying early is dollar-identical and
  observable *only* as a warning — without a negative assertion that case would pass while broken);
  `expected.valuationSensitive` / `valuationDirection` / `alternateWinner` / `breakevenCentsPerPoint`
  (the disclosure gate had no assertable surface at all); and `ownerStateOverrides` `unsetFields`,
  since merging can only SET a field while nil is a distinct, load-bearing input. All optional and
  all mutation-tested — every one was verified to fail the suite when perturbed, because an optional
  field with a typo'd key is a silent no-op.
- Two behaviours the new cases pin that were previously undocumented, both current behaviour rather
  than endorsement: (1) **unknown data and unknown owner state fail in opposite directions** — a nil
  `purchase.mcc` skips `mccInclude` and the accelerated rule fires anyway (permissive), while a nil
  `ownerCondition` drops the rule (restrictive); (2) `appliedRuleId` names the rule that MATCHED, never
  the rate actually paid, so a fully-exhausted cap yields winner rule `rogers-base-2-with-service` at
  a 1.5% outcome — a UI rendering "2%" from `appliedRuleId` would overstate that checkout.
- Also pinned: `runnerUp` can exceed the winner's value when the switch threshold holds the default
  (it means "the card you passed up", not "second best"), and the FX free-allowance is
  declared-not-computed — a C$2,000 purchase against a C$1,400 monthly allowance is scored at $60.00
  when the defensible figure net of `postAllowanceRate` is $48.00.
- `schema/engine-fixtures.schema.json` updated to document all six fields.

## 2026-08-16 — Benefits contract parity

- Added `schema/benefits-catalogue.schema.json`. The extraction below moved `benefits-catalogue.json`
  into this directory but wrote schemas only for the other two files — the spec's own §1 listing
  omitted it — so benefits data was canonical here while every consumer had to re-derive its shape by
  reading `BenefitsModels.swift`. MoneyTalks had already hand-derived a zod schema that way; this is
  the single authoritative reading that replaces it. Spec §1 listing updated to match.
  The schema documents two things a reader cannot recover from the JSON alone: `family`/`kind` are
  **open** vocabularies (plain `String` in Swift; the enums are non-`Codable` namespaces, so unknown
  values decode, round-trip, and are ignored rather than rejected — load-bearing forward
  compatibility), while `verificationStatus` is a **closed** enum whose unknown values are a hard
  decode failure. Also records `x-known-invariant-gap`: `maxAnnualCad` and `maxOriginalWarrantyYears`
  feed the Pareto dominance badge but are never rendered by `BenefitsFormatting.factsLine`, so the
  badge's "equal or better on every line below" claim can turn on a row the user cannot see —
  currently masked by the data, not fixed.
- Normalised `benefitsCatalogueVersion` from `"0.2.0"` to `"1.0"`, matching the MAJOR.MINOR
  convention `catalogueVersion` and `fixturesVersion` already use (spec §3). **Not a breaking change:**
  the shape is byte-identical apart from that string; this declares the existing shape as 1.0 rather
  than changing it. The field stays decoded-but-unread — unlike `catalogueVersion`, `SeedLoader` does
  not gate on it, because benefits are disclose-only and never feed scoring, so a mismatch degrades
  displayed coverage facts instead of corrupting dollar recommendations. Revisit if a second engine
  ever loads this file.
- Consumers with a vendored copy (MoneyTalks) must re-sync: the version string changed, so the
  pinned sha256 for `benefits-catalogue.json` no longer matches.

## 2026-08-16 — Extraction

- Moved `card-catalogue.json`, `benefits-catalogue.json`, `engine-fixtures.json` here from
  `Engine/Sources/CardCopilotEngine/Resources/` and `Engine/Tests/CardCopilotEngineTests/Fixtures/`.
  This directory is now the single canonical home; the Engine package keeps drift-checked
  copies at the old paths because SPM cannot declare resources outside a package's own root
  (see `scripts/sync-contracts-into-engine.sh` and `ContractsSyncTests`).
- Replaced the ad hoc `2026-08-15.1` date-stamp versioning with `catalogueVersion: "1.0"`
  (MAJOR.MINOR) and made it load-bearing: `SeedLoader` now parses MAJOR and refuses to load a
  catalogue whose MAJOR it does not recognize. `engine-fixtures.json` gained the matching
  `fixturesVersion: "1.0"` for the same convention, ahead of any future non-Swift consumer.
- Added `schema/card-catalogue.schema.json` and `schema/engine-fixtures.schema.json`,
  documenting the current shape as decoded by `CardCopilotEngine` — including fields the
  engine decodes but never acts on, and fields present in the JSON that the Swift model
  doesn't declare at all and so are silently dropped by `JSONDecoder`.
