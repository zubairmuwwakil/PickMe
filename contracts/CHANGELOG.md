# Contracts changelog

One entry per catalogue/fixture change (spec §3). Newest first.

## 2026-08-27 — card-catalogue 2.2: first draft records, and the integrity gates that did not know about them

- **26 US cards added with `status: draft`** under the Option 1 ruling (issuer-flagship reward
  currencies only). Each carries identity and annual fee — the facts an aggregator gets right —
  and `earnRules: []`, `fxRules: []`, `caps: []`,
  `perTransactionRewardVisibility: "unknown"`. Nothing about their earn structure is claimed,
  because nothing about it has been verified. The 41 published CA cards are unchanged and keep
  their existing order in the file.
- **`lastVerifiedAt` on a draft is the SNAPSHOT date**, not a verification date. Promotion to
  `published` overwrites it with the date a human read the issuer's terms. Blurring the two would
  forge the provenance the catalogue exists to carry.
- **Five Swift gates and one Kotlin gate went red on this release, and all six were right to.**
  `testEveryCardCanEarnSomething`, `testEveryCardDeclaresAnFxRule`,
  `testEveryProgramIdIsValuedOrKnownUnvalued`, `testProductsWithoutBenefitsAreExactlyTheKnownGap`,
  `SeedLoaderTests.testCatalogueLoadsAllCards`, and Kotlin's
  `everyCatalogueProgramIdHasACatalogueDefault` were all written before `status` existed, when
  "in the catalogue" and "issuer-confirmed" were the same thing. Each is an assertion about a
  VERIFIED PRODUCT FACT, and a draft has none by design. They are now scoped to published cards
  (`isPublished`, which already existed on both models); the count gate asserts 41 *published*
  plus the presence of drafts, so it keeps asserting something as the corpus grows.
- **Not relaxed anywhere: `Scorer` still refuses a draft on the status guard**, ahead of the
  network, program and valuation guards. `testNoCatalogueCardIsExcludedForAnUnvaluedProgram`
  passed throughout without modification, which independently proves that ordering — the US
  programIds have no valuation, and the drafts on them never reach the valuation check.
- **The consumer side needed the same lesson.** MoneyTalks' `catalogueChoices` and five other
  surfaces read the raw corpus and offered drafts to users the day 2.2 landed; they now go through
  a `publishedCards()` chokepoint. `status` was introduced as a Scorer concept, and no other layer
  — presentation, integrity gates, or valuation ratchet — was taught about it. That is the whole
  shape of this entry.

## 2026-08-26 — card-catalogue 2.1: merchantInclude tokens normalized to lowercase kebab-case

- **25 of 26 `merchantInclude` rules used display-cased brand names** ("Loblaws", "Shoppers Drug Mart",
  "Air Canada") while `RuleMatcher.matches` does an exact, case-sensitive
  `include.contains(brand)` against `PurchaseContext.merchantBrand` — and every producer of that
  value (`CheckoutService.canonicalEngineBrand`, `SpendDistribution`, `CanadianMerchantPreIndex`)
  emits lowercase kebab-case ("costco", "canadian-tire"), the same convention the catalogue's own
  `merchantExclude` already used. No display-cased token could ever match. This was invisible
  because the affected rules were separately gated off live scoring by `scoredInV1: false` or
  `requires: ["predicate.merchantPartnerList"]` — the bug shipped inert and stayed that way.
- **Fixed by lowercasing and hyphenating every affected `merchantInclude` value**
  (`scotia-gold-featured-grocery-6x`, the two `td-aeroplan`/`amex-aeroplan-reserve`/
  `cibc-aeroplan` Air Canada rules, `cibc-dividend-expedia-2pct`,
  `scotia-passport-featured-grocery-3x`, the three `pc-insiders-*` rules, both
  `amazon-ca-rewards-mastercard` rules, and the twelve `pc-financial-*` grocery/shoppers/fuel/
  travel rules across `pc-financial-world-elite`, `pc-financial-mastercard`, and
  `pc-financial-world-mastercard`). `"Amazon.ca"` → `"amazon-ca"`, `"T&T"` → `"t-and-t"`; every
  other token is a straight lowercase-and-hyphenate. No rule's matching *behavior* changes today —
  every affected rule is still gated off live scoring — this only makes the token correct for the
  day the gate lifts.
- **New regression gate:** `CatalogueIntegrityTests.testMerchantBrandTokensAreLowercaseKebabCase`
  fails if any future `merchantInclude`/`merchantExclude` token is not lowercase kebab-case.
  `RuleMatcherTests` gained direct coverage of the `merchantInclude` predicate path
  (`testMerchantIncludeMatchesListedBrand`, `testMerchantIncludeRejectsBrandNotOnTheList`,
  `testMerchantIncludeIsCaseSensitive`, `testMerchantIncludeRejectsMissingMerchantBrand`) — it had
  none before, which is why this went unnoticed.
- **No schema change.** `merchantInclude`/`merchantExclude` were always untyped strings; the
  convention is enforced by the new test, not the schema.

## 2026-08-26 — card-catalogue 2.0: multi-market shape (Money, market/billingCurrency, spendNative, calendarQuarter, draft status)

**Why:** preparing to import US cards surfaced that the catalogue baked CAD into its shape —
`fee.annualCad`, `credit.valueCad`, `earn.pointsPerCad`, `cap.measure: spendCad` — rather than
representing currency explicitly. A US card's fee is stated in USD; converting it to CAD at
authoring time (as the old field names would force) is exactly the "invented number" this
catalogue's D3 sourcing bar exists to prevent. This bump makes every monetary field
currency-tagged and gives every card an explicit market before any non-Canadian product enters.

**Breaking shape changes (MAJOR 1 → 2):**
- `fee.annualCad`/`monthlyCad: number` → `fee.annual`/`monthly: {amount, currency}`.
- `credit.valueCad: number` → `credit.value: {amount, currency}`.
- `earn.pointsPerCad` → `earn.pointsPerUnit` — per unit of the card's OWN `billingCurrency`, not
  CAD unconditionally.
- `cap.measure: "spendCad"` → `"spendNative"` — measured in the card's own `billingCurrency`.
  `spendUsdEquivalent` unchanged.
- Every card now requires `market` (`"CA"|"US"`) and `billingCurrency` (`"CAD"|"USD"`). All 41
  existing cards migrated to `market: "CA"`, `billingCurrency: "CAD"` — behaviourally identical
  to today, verified by the unchanged 28 golden fixtures.

**Additive:**
- `cap.period`/`credit.period` gain `"calendarQuarter"` (`EngineCapability.capCalendarQuarter`,
  supported from day one) — US rotating-category cards (5x groceries up to $1,500/quarter) were a
  shape this catalogue could not express at all before this.
- `predicate.ownerSelectedCategory` generalizes the Tangerine-only `ownerSelectedTangerineCategory`
  mechanism (`CardState.selectedCategories` was never Tangerine-specific, only the string naming
  it was) for US selectable-category cards. Both strings accepted; no existing rule rewritten.
- `network` gains `"discover"`.
- `status: "published"|"draft"` (absent = published). A `draft` record is a research-grade entry
  that has not cleared the issuer-confirmed sourcing bar; `Scorer`/`RecommendationEngine` and
  `PortfolioAnalyzer` refuse to score one even if it ends up in `ownedCardIds`.
  `AcquisitionAnalyzer` may still surface one, clearly excluded from `recommended`. This is the
  two-tier corpus mechanism a bulk US import will use — no draft cards are added by this commit.
  `card-catalogue.schema.json` still validates every card as before; nothing here relaxes it.
- `eligibility.residency` (optional; absent means "assume `[market]`") plus documentation-only
  `incomeRequirementCad`/`creditScoreTier`/`provinceStateRestriction`/`businessOnly` capture
  points for a later pass.
- `OwnerState.market` (optional, raw `Market` string) — the owner's own residency. Gates the
  empty-wallet checkout fallback (`RecommendationEngine`) and `AcquisitionAnalyzer.recommended`
  to the owner's market by default; never gates `ownedCardIds` itself (a Canadian resident
  legitimately holding a US card is not locked out) or which candidates get scored (marginal-value
  math stays meaningful cross-market — only the *default-surfaced* recommendation is scoped).

**Engine changes, mirrored in all three implementations (Swift/Kotlin/TypeScript):**
- `Scorer` computes earn and the FX gate against the purchase amount converted into the CARD's
  OWN billing currency (reusing the existing `usdEquivalent`/pinned-fallback mechanism
  `spendUsdEquivalent` caps already relied on), not `amountCad` unconditionally. For every
  CAD-billing card (all 41 today) this is the identity — verified unchanged by the golden
  fixtures — and is exercised for a USD-billing card by new `MultiMarketTest`/`multiMarket.test.ts`
  suites (7 cases each: USD-equivalent earn, pinned-rate fallback, FX-gate-by-billing-currency in
  both directions, quarterly cap straddle, draft exclusion).
- New `ReportingCurrency` (Swift/Kotlin) / `reportingCurrency.ts` (TS): converts a `Money` value
  to the engine's fixed CAD reporting currency at the point of use (`PortfolioAnalyzer`,
  `AcquisitionAnalyzer`, `catalogueCard.ts`) — a catalogue `Money` value itself is never rewritten.
  Reuses the existing pinned `fallbackCadToUsd` rather than a second constant that could drift.
- `CapWindow` (Swift/Kotlin) resolves `calendarQuarter` windows; the TS twin has no window
  resolver (unchanged — MoneyTalks doesn't do cap-window projection).
- **Not done, deliberately:** program *valuations* (`programs.json`, `ProgramValuation`) stay
  CAD-only in this bump — no catalogue program is USD-valued yet, so adding currency-awareness to
  the valuation model is deferred until Stage C actually sources one, rather than building a
  mechanism with nothing to exercise it.

**A pre-existing, unrelated bug found and fixed while re-running the Kotlin suite against the
migrated catalogue:** `SeedLoader.loadCandidateCatalogue()` (Kotlin only) still decoded
`candidate-catalogue.json` as a full `Catalogue`, a shape that file left behind on 2026-08-24 when
candidates became id references. Nothing had run the Kotlin suite against a real candidate file
since; two Kotlin-only tests (`ProgramValuationTest`, `CapabilityGatingTest`) still unioned
`loadCandidateCatalogue().cards` into their "every card" scans, the exact "wallet + candidates"
duplication the one-corpus decision retired in Swift. Kotlin now has its own `CandidateSet`
mirroring Swift's, and both tests read `loadCatalogue().cards` alone.

**Verified:** PickMe `Engine` — no Swift toolchain in this environment; changes reviewed by hand
against the exact signatures involved but NOT compiler-checked, and CI on `macos-15` is the first
real check. Android `:core:engine:test` — 41/41 passing (34 pre-existing + 7 new
`MultiMarketTest`), including the golden `FixtureHarnessTest` unchanged. MoneyTalks — `tsc --noEmit`
clean project-wide; `vitest run` 977/988 passing; the 11 failures are `contracts.test.ts`'s
commit-provenance checks, which by design cannot pass while PickMe's contract changes are
uncommitted (`scripts/sync-contracts.sh --allow-dirty` was used for local verification) — they
clear on a clean re-sync once this lands.

## 2026-08-20 — card-catalogue: 51 `scoredInV1: false` rules migrated to `requires`/`outOfScope`

- **`scoredInV1: false` had no machine meaning.** 51 of the 96 earn rules carried it, and nothing
  checked *why* — enabling a capability meant grepping the catalogue for flags to flip. Each rule
  now declares either `requires: [<EngineCapability>]` ("not yet — turns on automatically when
  this ships") or `outOfScope: {reason}` ("never — permanently inert"). Every existing `_note` is
  kept.
- **43 rules → `requires`.** Blockers were read off each rule's `_note` (or, for four rules with
  no note of their own, the owning card's `_note`) against the mapping in
  `docs/superpowers/plans/2026-08-20-p1-valuation-capability.md` Task 9: statement-period/annual
  window → `cap.statementYear`; first-of-two/global/monthly-billing tiering →
  `cap.globalGroup`; strict issuer-MCC matching → `predicate.mccStrict`; merchant
  normalization/partner list/provider list → `predicate.merchantPartnerList`; needs
  litres → `earn.perLitre`; card-marginal vs member earn → `earn.marginal`. A few rules (e.g.
  `td-aeroplan-gas-grocery-ev-1_5x`, `bmo-eclipse-grocery-5x` and its three siblings) declare two
  capabilities where the note states two distinct blockers — both must ship before the rule goes
  live.
- **5 rules → `outOfScope`**, all online booking channels (Expedia For TD, Amex Travel, CIBC
  Rewards Centre, NBC à la carte travel), per spec §9.3: `cobalt-amex-travel-bonus`,
  `cibc-dividend-expedia-2pct`, `td-fct-expedia-8x`, `cibc-aventura-rewards-centre-2x`,
  `nbc-we-a-la-carte-travel-2x`. PickMe is an at-the-register copilot; these permanently do not
  belong to it. `predicate.channelIdentity` is deliberately not an `EngineCapability` case, so a
  future reader cannot build toward it by mistake.
- **3 rules stay on `scoredInV1: false`, each with a `_note` explaining why it isn't `requires` or
  `outOfScope` yet:**
  - `scotia-gold-gas-transit-3x` — blocker unconfirmed. Its predicate and cap are both already
    supported (plain category predicate on a `calendarYear` cap), so it looks disabled as a group
    with its cap-sharing siblings rather than for a reason of its own. Needs a human check against
    Scotia's terms before it gets a real marker.
  - `amazon-ca-prime-2_5x`, `amazon-ca-nonprime-1_5x` — blocked on `CardState.flags`
    (owner-linked Prime status), which is the *next* plan's scope, not an engine capability gap
    this one can express.
- **New regression gate:** `CapabilityGatingTests.testNoRuleIsDisabledWithoutAMachineReadableReason`
  fails if any rule outside that allowlist of three carries `scoredInV1: false` with neither
  `requires` nor `outOfScope` — so a future disabled rule can't ship without saying why.
- **Schema:** `contracts/schema/card-catalogue.schema.json` documents `requires` and `outOfScope`,
  marks `scoredInV1` `"x-status": "deprecated"`, and opens `earnRule.ownerConditions.items` from a
  closed `enum` to a documented open string — matching how `benefits-catalogue.schema.json`
  already treats `family`/`kind`. The closed enum previously let `amazonEligiblePrimeLinked` ship
  with no `RuleMatcher` handler and no schema complaint; opening it doesn't add a handler, but it
  stops the schema from claiming one exists.
- **All 27 `engine-fixtures.json` cases pass byte-unchanged.** `requires` naming an unsupported
  capability produces exactly the skip `scoredInV1: false` used to — no scoring outcome moved.
  `catalogueVersion` stays `1.4`; this change is a marker migration, not new data.
- **Fixed a pre-existing test in passing:**
  `SpendDistributionTests.testPlaceholderProfileCoversEveryCategoryTheWalletAccelerates` filtered
  live rules with a raw `rule.scoredInV1 != false` check, which read a rule's now-`nil`
  `scoredInV1` (with `requires` doing the gating instead) as live. Switched it to
  `RuleMatcher.isLive`, the same check the engine itself uses.

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
