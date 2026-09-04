# Contracts changelog

One entry per catalogue/fixture change (spec §3). Newest first.

## 2026-09-04 — merchant-pack 1.1: a narrowing needs a source

**Additive schema field; one editorial correction.** `acceptedNetworks` treated both directions as
the same claim, and they are not. The open `[amex, visa, mastercard]` default is a non-claim: if it
is wrong the owner taps a second card at the till and sees it happen. Removing a network is an
affirmative negative claim the app renders as text ("does not accept American Express") and which
silently withholds a card the owner may never discover they should have used — nothing they can
observe contradicts it. All 151 rows carried the same evidentiary bar for both, which was none.

- New optional `acceptanceProvenance` (`sourceType`, `sources`, `lastVerifiedAt`) — the same
  vocabulary `card-catalogue.schema.json` already uses per rule, and documentation-only in the same
  way: no Swift or Kotlin decoder reads it. It gates the curator, not the engine.
- `merchant-pack.schema.json` now **requires** it on any row narrower than the open default, via an
  `if/then/else` on "contains all three networks". `inferred` is deliberately not a legal
  `sourceType` here: the point of the gate is that a narrowing rests on something a reviewer can
  open. All 17 existing narrowed rows are backfilled from each merchant's own published
  payment-methods page, verified 2026-09-04.
- `matchKeys` correction on narrowed rows. A needle that is an ordinary English word or a common
  surname resolves unrelated businesses into a grocery banner and produces exactly the false
  negative claim above: `superstore` (→ "Superstore Liquidation"), `fortino` and `zehr` (surnames)
  are removed. Each row keeps a specific key. `dominion` and `no frills` survive only because a row
  must also be reachable from its own `displayName`; narrowing those needs the displayName narrowed,
  and `PreIndexedMerchant.id` derives from it and is persisted — a migration, not an edit.
- `scripts/check-acceptance-freshness.py` makes the gate standing rather than one-time: a narrowed
  row whose `lastVerifiedAt` passes 365 days fails `document-freshness.yml` (advisory, weekly cron),
  not `ci.yml`. A merchant that *starts* taking a network is the failure nothing else here can see —
  the row decodes, the pack validates, and the app keeps withholding a card that would now work.
- **MINOR 1.0 → 1.1.** Purely additive; `SeedLoader.validate(packVersion:)` gates on MAJOR only, and
  the field is absent from every decoder, so consumers on 1.0 are unaffected.

## 2026-08-31 — card-catalogue 2.16 & purchase-categories 1.1: hierarchy and merchant dimensions

**Additive taxonomy metadata; no scoring change.** Category definitions may now name a broader
`parentID` for reporting and a separate `merchantGroupID` for merchant-specific legacy tokens.
Neither field implicitly broadens a card predicate: issuer-sourced rule matching remains exact.

- Travel, retail, entertainment, dining, and membership leaves now expose their broader parent.
- `ctFamily` and `marriottDirect` remain valid wire ids for compatibility, while explicitly
  declaring `canadianTireFamily` and `marriottDirect` as merchant-group dimensions. New storage
  can retain both the purchase category and merchant group instead of conflating them.
- `card-catalogue.json` moves only its version string, **MINOR 2.15 → 2.16**. No earn rule,
  fixture expectation, or released card fact changes.

## 2026-08-31 — card-catalogue 2.15 & purchase-categories 1.0: one persisted vocabulary

**Additive sidecar contract; persistence correction.** Purchase-category ids and aliases had
three handwritten implementations in Swift, Kotlin, and MoneyTalks. They already disagreed on
legacy input and on which catalogue predicates could be stored as merchant classifications.

- New `purchase-categories.json` declares 25 real purchase categories, their canonical English
  source labels, and durable aliases. Swift and Kotlin now decode this registry instead of
  maintaining alias switches.
- Four rule-side predicate tokens (`recurring`, `foreignCurrency`, `ownerSelectedCategory`, and
  legacy `ownerSelectedTangerineCategory`) are declared separately. Engines may match them, but
  database write boundaries must reject them as merchant or purchase classifications.
- Unknown engine input remains forward-compatible and can fall through to base earn. Persisted
  values are intentionally stricter: only a declared purchase id may be written.
- The new registry and schema join the content-addressed release set. `card-catalogue.json` moves
  only its `catalogueVersion` string, **MINOR 2.14 → 2.15**, because consumers of 2.14 continue to
  decode every existing catalogue record.

## 2026-08-30 — card-catalogue 2.14 & fixtures 1.7: plural cap references become executable

**Additive contract shape, corrective twin coverage.** The 2.13 catalogue introduced `capIds`
for rules that race multiple meters, but the 32-case shared fixture set never read the field.
Swift implemented it while Kotlin still read only legacy `capId`, so both native suites could be
green while disagreeing on the released bytes.

- Two shared cases inspect the named CIBC Dividend Visa Infinite candidate through a new optional
  `expected.cardScores` assertion. Its live base rule deliberately has `capId: null` and only
  `capIds`; one case leaves $50 of global-cap room and the other leaves none. The dollar value is
  unchanged because the base earn and post-cap earn are both 1%, so `capNearlyExhausted` is the
  decisive signal: a consumer that ignores `capIds` omits it and fails.
- `cardScores` is a general fixture capability over `Recommendation.allCandidates`, not a
  CIBC-specific escape hatch. It lets the executable contract pin card-local behavior without
  falsifying network acceptance or forcing a lower-value card to become the wallet winner.
- Synthetic Swift and Kotlin scorer tests pin the true two-meter behavior: the cap with the least
  remaining room constrains the accelerated portion; the first declared cap supplies
  `postCapEarn`; and multiple nearly exhausted meters emit one warning. Kotlin now ports Swift's
  `effectiveCapIds`/`splitMulti` semantics.
- This release deliberately does **not** activate `cap.globalGroup` or `cap.statementYear`.
  Twenty-nine rules across eleven cards still declare one of those capabilities, so enabling
  either would be a separate catalogue-wide card-semantics decision, not fixture maintenance.

## 2026-08-30 — benefits-catalogue 1.3: Part 2 Canadian insurance dossier ingestion

Ingested verified first-party insurance certificates, benefits terms, and document indices for 16 Canadian credit cards:
- `cibc-costco-mastercard` (Belair; Purchase Security $60k aggregate, Extended Warranty +1 yr, Mobile Device $1,000)
- `royal-bank-of-canada-rbc-british-airways-visa` (RBC / Aviva; Emergency Medical unlimited 31d/7d, Flight Delay $500, Baggage Delay $2,500, Rental CDW 48d $65k MSRP, Purchase Security $50k/yr, Extended Warranty +1 yr)
- `amex-aeroplan-reserve` (Belair / Chubb; Emergency Medical $5M 15d, Trip Cancellation $3k, Trip Interruption $6k, Flight & Baggage Delay $1k shared, Baggage Loss $1k, Rental CDW 48d $85k MSRP, Purchase Protection $1k, Extended Warranty +1 yr)
- `bmo-cashback-world-elite` (CUMIS / Allianz; Emergency Medical $5M 8d, Flight Delay $500, Baggage Delay $1k, Baggage Loss $1k, Rental CDW 48d $65k MSRP, Purchase Security + Extended Warranty $60k combined lifetime, Extended Warranty +1 yr)
- `simplii-cashback-visa` (Belair; Purchase Security $60k aggregate, Extended Warranty +1 yr)
- `pc-financial-world-mastercard` (American Bankers; Purchase Assurance $1k / $50k lifetime, Extended Warranty +1 yr)
- `pc-financial-world-elite` (American Bankers; Emergency Medical 10d under 65, Rental CDW, Purchase Assurance $1k / $50k lifetime, Extended Warranty +1 yr)
- `desjardins-odyssey-world-elite` (Desjardins / American Bankers; Emergency Medical $5M 60d/31d/15d, Trip Cancellation $2.5k, Trip Interruption, Baggage Delay $500, Baggage Loss $1k, Rental CDW 48d $85k MSRP, Purchase Protection $10k / $50k lifetime, Extended Warranty +2 yrs, Mobile Device $1,500)
- `rbc-cashback-preferred-we` (Aviva / RBC; Rental CDW 48d $65k MSRP, Purchase Security $50k/yr, Extended Warranty +2 yrs / 3x multiplier)
- `amex-gold-rewards` (Belair; Emergency Medical $5M 15d, Trip Cancellation $3k, Trip Interruption $6k, Flight & Baggage Delay $500 shared, Baggage Loss $500, Rental CDW 48d $85k MSRP, Purchase Protection $1k, Extended Warranty +1 yr)
- `amex-simplycash-preferred` (Belair; Emergency Medical $5M 15d, Flight & Baggage Delay $500 shared, Baggage Loss $500, Rental CDW 48d $85k MSRP, Purchase Protection $1k, Extended Warranty +1 yr, Mobile Device $1k)
- `cibc-aeroplan-visa-infinite-privilege` (Belair; Emergency Medical $5M 31d/10d, Trip Cancellation $10k, Trip Interruption $25k, Flight Delay $1k, Baggage Delay $1k, Baggage Loss $2.5k, Rental CDW 48d $100k MSRP, Purchase Security $60k aggregate, Extended Warranty +2 yrs / 3x, Mobile Device $1.5k)
- `td-aeroplan-visa-infinite-privilege` (TD Life / TD Home & Auto / American Bankers; Emergency Medical $5M 31d/4d, Trip Cancellation $5k, Trip Interruption $25k, Flight Delay $1k, Baggage Delay $1k, Baggage Loss $2.5k, Rental CDW 48d $85k MSRP, Purchase Security $60k lifetime, Extended Warranty +2 yrs / 2x, Mobile Device $1.5k)
- `home-trust-preferred-visa` (Chubb; Purchase Security $5k per occurrence)
- `mbna-smart-cash-world` (TD Home & Auto; Rental CDW 31d $65k market value, Purchase Assurance $60k lifetime, Extended Warranty +1 yr)
- `pc-financial-mastercard` (American Bankers; Purchase Assurance $1k / $50k lifetime, Extended Warranty +1 yr)
- Benefits catalogue card count advances from 30 to 46 cards. All 16 cards retired from `BenefitsLoaderTests.knownGap`.

## 2026-08-30 — card-catalogue 2.12 & owner-conditions 1.1: Part 1 Canadian card publication

Ingested first-party publication research dossier for 5 Canadian credit cards:
- **`cibc-costco-mastercard`**: Promoted to published. 3% dining, 3% Costco gas in Canada (sharing $5,000/yr gas+EV cap with 2% non-Costco gas and 2% EV charging MCC 5552, 1% post-cap), 2% Costco.ca ($8,000/yr cap, 1% post-cap), 1% base cashback under `costcoCashRewardsCa` (0.95 usability factor). 2.5% FX markup.
- **`royal-bank-of-canada-rbc-british-airways-visa`**: Promoted to published. $165 annual fee, 3 Avios / $1 CAD on direct British Airways bookings (Visa MCC 3005), 2 Avios / $1 CAD on dining & food delivery (MCC 5812, 5813, 5814), 1 Avios / $1 CAD base earn under `avios` (1.0¢ ranked parity). 2.5% FX markup.
- **`neo-financial-neo-world-mastercard`**: Promoted to published with 3 selectable cashback configurations supported via `owner-conditions.json` flags (`neoProfileGasAndGrocery`, `neoProfileShopAndDine`, `neoProfileEverywhere`):
  - *Gas & Grocery*: 2% grocery ($1k/mo cap), 2% gas/EV ($1k/mo cap), 2% recurring ($500/mo cap), 0.5% post-cap.
  - *Shop & Dine*: 2% food & drink ($500/mo cap), 2% retail shopping ($500/mo cap, excluding Amazon/Costco/wholesale), 0.5% post-cap.
  - *Everywhere*: 1% flat unlimited.
  - Base fallback: 0.5% unlimited. 3.0% FX markup.
- **`mbna-true-line-mastercard`**: Promoted to published. $0 annual fee, `noRewards` program valued at $0.00.
- **`capital-one-canada-capital-one-guaranteed`**: Promoted to published. $0 annual fee, secured card under `noRewards` program valued at $0.00.
- Published card count advances from 53 to 58.

## 2026-08-29 — card-catalogue 2.11 & fixtures 1.6: release benefits document index

The additive benefits-catalogue 1.2 document index landed after the 2.10 release stamp. This
release carries those bytes in a new immutable digest and moves the paired catalogue/fixture
versions as required by the contract versioning rule. No card rules or fixture expectations
change; existing 1.1 benefits readers continue to work because `documents` is optional.

## 2026-08-29 — benefits-catalogue 1.2: add per-card document index

Added a `documents` array to all 27 current benefits-catalogue cards. It supports multiple
issuer/underwriter sources such as certificates of insurance, cardholder agreements, welcome
guides, fee schedules, lounge terms, and claims instructions. Existing 1.1 readers remain valid;
the document `kind` is open-ended and each document carries its own verification status and
effective date. The research manifest is retained in `benefits-documents-research.json` so future
refreshes can distinguish public issuer evidence from the owner's own cardholder documents.

## 2026-08-28 — card-catalogue 2.10 & fixtures 1.5: Amazon's Prime ladder becomes payable

**Intentional behaviour activation.** `amazonEligiblePrimeLinked` became answerable in 2.8, but
both Amazon.ca merchant rules retained `scoredInV1: false`; 2.9 correctly pinned that two-gate
state rather than pretending the advertised earn had gone live. This release removes the second
gate now that both engines resolve the owner condition from `CardState.flags`. The Amazon card's
published rule bytes therefore change deliberately: eligible Amazon.ca and Whole Foods purchases
score at 2.5x with linked Prime and 1.5x otherwise. **MINOR, 2.9 → 2.10.**

- Fixtures move 1.4 → 1.5 and 31 → 32 cases. The 2.9 transitional
  `amazon-prime-flag-answered-but-rule-unscored-100` case is superseded by the pair it said it was
  written to become once the gate lifted:
  - `amazon-prime-linked-fires-2_5x`: 250 points × the posted 1.0¢ = $2.50, beating the
    Wealthsimple default's $2.00 by $0.50 / 0.50pp and clearing both switch floors exactly.
  - `amazon-prime-unanswered-fails-closed`: no flag skips 2.5x; the Amazon card earns 150 points ×
    1.0¢ = $1.50 on its non-Prime rule, while the realistic all-network wallet remains on
    Wealthsimple at $2.00 with Cobalt second at $1.80. If 2.5x guessed true, the winner flips.
- The first 28 fixture expectations remain byte-for-byte unchanged. The two 2.9 Rogers flag cases
  are also unchanged.
- Swift and Kotlin add a card-level `RuleMatcher.resolve` assertion for the fact the whole-wallet
  fixture cannot expose in `winnerRule`: unanswered Prime resolves the Amazon card itself to
  `amazon-ca-nonprime-1_5x`, not its 1x base.
- The fixture purchases retain Amazon.ca's real all-network acceptance. They do not manufacture a
  Mastercard-only checkout merely to force the 1.5x card into the winner slot.

## 2026-08-28 — card-catalogue 2.9 & fixtures 1.4: the flags representation gets tested

**Additive throughout.** No card record's bytes change, no existing fixture expectation changes,
and the schema only gains an optional property. `card-catalogue.json` moves only its
`catalogueVersion` string — required, because `RELEASE.json` digests the whole file set and a
published release id must never describe two different sets of bytes. **MINOR, 2.8 → 2.9.**

- **Three new fixture cases, 28 → 31, the first to exercise `CardState.flags` at all.** 2.8 shipped
  `flags`, wired both fixture harnesses to accept a `flags` override, and then added no case that
  used one. All four CI jobs were green on a representation nothing executed.
  - `flags-beat-stale-legacy-mirror-300` pins the **precedence rule**, which until now lived only
    in a doc comment: the base owner state resolves `rogersEligibleServiceLinked` to `false`, the
    override sets only `flags`, and `resolvedFlags` must let the newer dictionary overwrite the
    stale mirror. Reverse the merge order and the case lands on $4.50 instead of $6.00. Every
    migration off the legacy properties depends on that direction holding.
  - `flags-explicit-false-fails-closed-300` pins that `false` and absent are **one state at the
    engine boundary** — `flags[condition] ?? false`. Its expectations are byte-identical to
    `owner-condition-unresolved-rogers-300` from a different input, which is the assertion: an
    implementation testing key presence rather than value passes every other case in the file and
    pays the owner 2% for answering "no".
  - `amazon-prime-flag-answered-but-rule-unscored-100` — see the correction below.
- **CORRECTION to the 2.8 entry.** It claimed owners with a linked Prime membership "will begin
  earning 2.5x at Amazon.ca and Whole Foods instead of 1.5x — a behaviour change, and an intended
  one". **That did not happen and cannot.** `amazon-ca-prime-2_5x` and `amazon-ca-nonprime-1_5x`
  both still carry `scoredInV1: false`, and `RuleMatcher.isScheduleLive` drops a rule on that flag
  *before* `conditionsResolveTrue` is ever consulted. 2.8 made the condition **answerable**; it did
  not make it **payable**, and there are two gates in series. The new fixture pins the real
  behaviour and is written to flip — decisively, to a $2.50 win over the default's $2.00 — the day
  `scoredInV1` is lifted. Lifting it is a behaviour change owed a decision, not a tidy-up.
- **`engine-fixtures.schema.json` is now actually run.** It shipped inside the release digest and
  nothing ever validated against it, so its `cardStateOverride: additionalProperties: false` — the
  one thing standing between a typo'd override key and a fixture that silently asserts against the
  *unmodified* base owner state — had never fired. Added to `validate-catalogue-schema.py`'s pairs
  and verified to reject an unknown key. The schema gains an optional `flags` object; its keys are
  deliberately unconstrained, because the closed list lives in `owner-conditions.json` and
  duplicating it would make declaring a condition a two-file edit again.
- **`programs.schema.json` is still unrun**, for the same reason and one more: it `$ref`s
  `card-catalogue.schema.json#/$defs/programId`, and resolving a cross-file `$ref` needs a
  `referencing` registry the script does not build. Recorded here rather than fixed.
- Fixture harness case-count ratchets moved 28 → 31 in both languages.
- **MoneyTalks is NOT re-vendored by this release and must not be until its TS twin learns
  `flags`.** `src/engine/cards-twin/RuleMatcher.ts` still switches on hardcoded condition names and
  has no `resolvedFlags`; its fixture harness field-copies specific override keys and would ignore
  a `flags` override entirely, scoring the three new cases against the unmodified base state. The
  hub stays on `card-contracts@2.8`, where it is correct, until that lands.

## 2026-08-28 — card-catalogue 2.8, owner-conditions 1.0 & fixtures 1.3: owner conditions become data

**Additive throughout.** No card record's bytes change; `card-catalogue.json` moves only its
`catalogueVersion` string, and `engine-fixtures.json` only its `fixturesVersion`. All 28 existing
fixture expectations are untouched.

- **New `owner-conditions.json` + schema, both in the release digest.** Declares every
  `ownerConditions` id: how it is answered (`boolean` → `CardState.flags`, `categorySelection` →
  Tangerine's structural selection machinery), and the English source prompt to ask it with.
- **Deliberately a sidecar registry, not spec §3.2's inline `[{conditionId, prompt}]` shape.**
  `EarnRule.ownerConditions` is a published array of strings inside a content-addressed release
  with four vendored copies across two repos; changing its element type is a MAJOR bump for no
  behavioural gain. `programs.json` solved the identical open-set-modelled-as-closed problem for
  valuations one section earlier in the same spec, and this follows that precedent. The rule's
  `[String]` array is unchanged.
- **`amazonEligiblePrimeLinked` is answerable for the first time.** It shipped in the catalogue
  with no `RuleMatcher` case, so `amazon-ca-prime-2_5x` fell to `default: return false` and could
  not fire in any build that ever existed. `CatalogueIntegrityTests.knownUnhandledConditions` is
  now **empty** and its ratchet is set to zero. Owners of that card who confirm a linked Prime
  membership will begin earning 2.5x at Amazon.ca and Whole Foods instead of 1.5x — a behaviour
  change, and an intended one.
- **`CardState.flags: [String: Bool]?`** carries answers by condition id in both engines. An absent
  key is unresolved and still fails closed; `false` is a real "no". The named
  `rogersEligibleServiceLinked` / `cryptoLevelUpProActive` properties are **retained and mirrored**
  for one release: MoneyTalks stores owner state and has not been audited for which keys it reads.
  Legacy states decode unchanged, `flags` wins on conflict, and every read goes through
  `resolvedFlags`. Removing the named properties is a follow-up gated on that audit.
- **`FILES` in `release-catalogue.sh` gained two entries** (`owner-conditions.json`,
  `schema/owner-conditions.schema.json`). **MoneyTalks' `FILES` list in `scripts/sync-contracts.sh`
  must be updated to match**, or its `contracts.test.ts` digest check fails against
  `card-contracts@2.8`. That is a cross-repo change this release cannot make for itself.
- Prompts are English **source** strings, not display strings. Consumers resolve
  `ownerCondition.<id>.prompt` from their own catalogue and fall back to the registry, so a new
  condition ships askable immediately and picks up translations without a contract release.

## 2026-08-27 — card-catalogue 2.7 & programs 1.5: merchantCredit, closed-loop acceptance, and a schema in the digest

Two new mechanisms and one long-standing schema gap. **Additive throughout — no card
declares either mechanism yet, so every one of the 133 card records keeps its bytes and no
card's score changes.** The only edit to `card-catalogue.json` in this release is its
`catalogueVersion` string; `programs.json` likewise moves only its `programsVersion`.

- **`merchantCredit` — a valuation model for merchant-locked store credit.** Added to
  `programs.schema.json` *alongside* `ctMoney`, deliberately not folded into it: `ctMoney` is a
  published wire-format name inside a digest-pinned release, and a published name is a fact
  rather than an implementation detail. The arithmetic is the same today
  (`cadPerUnit` × optional usability factor); the models are separate because their *identities*
  are. `merchantCredit` additionally carries `merchantScope`, which is disclosure only —
  `Scorer` never dispatches on it. No programme declares `merchantCredit` yet: a brand needs a
  published face value read from the issuer's own site (D3) before it can, and
  `CatalogueIntegrityTests.testEveryProgramDefaultKeyIsARealCatalogueProgramId` refuses a
  valuation no card declares. Enum value, valuation and cards land together, per brand, once
  that research exists.
- **`noRewards` — the schema variant that had been missing since 2.4.** `programs.json` has
  carried a `noRewards` valuation since 2.4 while its own schema had no variant for it, so the
  file did not validate against the schema shipped beside it. Nothing checked, which is why the
  drift shipped and survived two releases. Closed here, along with the gate that would have
  caught it: `ProgramsSchemaTests` now validates `programs.json` against
  `programs.schema.json` on every run.
- **`privateLabel` and the `acceptance` object — a card accepted by a merchant, not by a
  network.** `card-catalogue.schema.json` gains the `privateLabel` network value and an optional
  `acceptance` object (`{ scope: "openLoop" | "closedLoop", merchants: [...] }`), plus an
  `if/then` invariant tying `privateLabel` to `closedLoop`. A closed-loop card is guarded on
  `merchantBrand` where an open-loop card is guarded on `network`, and a merchant refusal raises
  the new `merchantNotAccepted` warning rather than reusing `networkNotAccepted` — a store card
  declined at a gas station was never a network problem. An unknown merchant excludes the card:
  silence beats recommending a card that gets declined at the till. 0 of 133 cards declare
  `privateLabel` or an `acceptance` object today.
- **`schema/programs.schema.json` joins the release digest.** It had never been in
  `RELEASE.json`'s file list, so a change to it moved no digest and no consumer could detect it
  — a real hole in a release whose entire content *is* a schema change. `merchant-pack.schema.json`
  stays out on purpose: the pack carries its own `packVersion` and changes on a different cadence.
  Consumers must vendor `schema/programs.schema.json` from 2.7 onward.

**On the version number.** `card-contracts@2.5` and `@2.6` were stamped locally but never
published; the last release on GitHub is `@2.4`. Rather than reuse either id for different
bytes — a published id must never describe two byte-sets — this work takes the next free
number. **2.7 is therefore the first published release since 2.4 and carries 2.5's and 2.6's
content as well**: the co-brand reward currencies, the resolved annual fees, the eight promoted
US cards and the minted drafts described in the two entries below.

Verified at 2.7: Swift 296 tests green, Kotlin 58 green, `check-id-permanence.sh` green.

## 2026-08-27 — card-catalogue 2.6 & programs 1.4: high-ROI US catalogue and scoring expansion

- **Prompt 2 Architectural Rulings**:
  - `costcoCashRewardsCa` and `costcoCashRewardsUs` added to `$defs/programId/enum` and valued under the `ctMoney` store-scrip model (`optionalUsabilityFactor: 0.95`, `usabilityFactorApplied: true`), acknowledging that annual warehouse reward certificates have no cross-border reciprocity and cannot be cashed out unconditionally as statement credits.
  - `amazonRewardsUs` added to `$defs/programId/enum` and valued with a guaranteed `floorCentsPerPoint: 1.0` (unconditional cash-out / statement credit via Chase).
- **Prompt 1 Co-Brand Valuations Completed in `programs.json`**:
  - Added defaults for `hiltonHonors` (0.5¢ / 0.5¢ floor via Amazon checkout / 0.6¢ aspirational), `emiratesSkywards` (1.0¢ / dynamic), `frontierMiles` (1.0¢ / dynamic), `choicePrivileges` (0.6¢ / 0.8¢ aspirational), `costcoCashRewardsCa` (1.0 / 0.95 factor), `costcoCashRewardsUs` (1.0 / 0.95 factor), and `amazonRewardsUs` (1.0¢ / 1.0¢ floor).
- **8 Flagship US Cards Promoted to `published`**:
  - Full issuer-confirmed `earnRules`, `caps`, `fxRules`, and `credits` authored for:
    1. `chase-sapphire-preferred-card` (3x dining, 3x streaming, 3x online grocery, 2x travel, 0% FX, $50 hotel credit)
    2. `chase-sapphire-reserve` (3x dining, 3x travel, 0% FX, $300 travel credit)
    3. `chase-freedom-unlimited` (1.5x base, 3x dining, 3x drugstore)
    4. `chase-freedom-flex` (1x base, 3x dining, 3x drugstore)
    5. `american-express-gold-card` (4x dining up to $50k/yr, 4x US grocery up to $25k/yr, 3x flights, $120 dining credit)
    6. `american-express-the-platinum-card` (5x flights up to $500k/yr, $200 airline fee credit, 0% FX)
    7. `american-express-blue-business-plus` (2x everyday up to $50k/yr)
    8. `citi-double-cash-card` (2x base)
- **17 New US Draft Cards Minted**:
  - Refined `infer_networks.py` with product and tier heuristics (190 networks mapped, 0 conflicts).
  - Resolved all remaining annual fee conflicts across the queue (`citi-strata-elite-card`, `chase-ink-business-cash-credit-card`, `chase-marriott-bonvoy-bold-credit-card`, `american-express-marriott-bonvoy-bevy`).
  - Successfully imported 17 new draft cards including Apple Card, Bilt Blue/Obsidian/Palladium, Citi Costco Anywhere, Wells Fargo Autograph Journey, FNBO Evergreen, Chase Slate Edge, etc.

## 2026-08-27 — card-catalogue 2.5: four co-brand currencies unblocked, eight annual fees resolved

- **Four new `programId` enum values added** — `hiltonHonors`, `emiratesSkywards`, `frontierMiles`, `choicePrivileges`.
- **Eight disputed annual fees resolved from official issuer terms** (Prompt 3 from `RESEARCH-PROMPTS.md`):
  - `american-express-hilton-honors`: resolved to **$550** ongoing for the Aspire tier (`Hilton Honors American Express Aspire Card`), disentangling the $0 / $150 / $195 / $550 range across the Amex Hilton family.
  - `american-express-delta-skymiles-gold-business`: resolved to **$150** ongoing ($0 intro yr 1), disentangling the Gold ($150), Platinum ($350), and Reserve ($650) business tiers.
  - `american-express-delta-skymiles-platinum`: resolved to **$350** ongoing, disentangling from Reserve ($650).
  - `bank-of-america-alaska-airlines-atmos-ascent`: resolved to **$95** ongoing, disentangling from Summit ($395).
  - `bank-of-america-atmos-rewards-visa-signature`: resolved to **$95** ongoing ($70 base company fee + $25 per card).
  - `barclays-emirates-skywards-premium-world`: resolved to **$499** ongoing for the Premium tier, disentangling from Rewards ($99).
  - `barclays-frontier-airlines-world-mastercard`: resolved to **$99** ongoing, clearing stale historical $89 aggregator records.
  - `wells-fargo-choice-privileges-mastercard`: resolved to **$0** ongoing, disentangling from Select ($95).
- **Minted 24 schema-valid draft cards into `contracts/card-catalogue.json`** via `promote_drafts.py`.
- Verified: Swift test suites green; `check-raw-source-policy.sh` green; `release-catalogue.sh` stamped `card-contracts@2.5`.

## 2026-08-27 — programs 1.3: default valuations for six co-brand currencies

- **Default valuations added for six co-brand currencies** — `aaAdvantage`, `atmosRewards`,
  `avios`, `cathayAsiaMiles`, `deltaSkyMiles`, `disneyRewards`. Closes the Prompt 1 research gap left
  open by catalogue 2.4.
- **Strict adherence to the valuation standard**:
  - `floorCentsPerPoint` is **omitted** across all five airline points currencies (`aaAdvantage`,
    `atmosRewards`, `avios`, `cathayAsiaMiles`, `deltaSkyMiles`), because none offers an unconditional
    statement credit or cash-out with nothing but the card. Scorer falls back to `centsPerPoint` rather
    than assuming a floor.
  - `centsPerPoint` is anchored at **1.0¢ by transfer parity** across dynamic airline currencies: major
    bank currencies (Amex MR, Chase UR, Citi ThankYou, Capital One, RBC Avion) transfer 1:1, so
    ranking a co-brand currency above 1.0¢ would make one point worth more after a free transfer than
    before it.
  - `deltaSkyMiles` independently carries a posted fixed conversion: **1.0¢** via Delta's "Pay with Miles"
    (5,000 miles = $50 on `delta.com`), available to all Delta Amex cardholders in this catalogue.
  - `disneyRewards` is valued under the **`ctMoney`** store-scrip model (`cadPerUnit: 1.0`,
    `optionalUsabilityFactor: 0.95`, `usabilityFactorApplied: true`) rather than `points`, recognizing
    that Disney Rewards Dollars are store-locked merchant scrip rather than an abstract point currency.
  - `spiritFreeSpirit` is **deliberately omitted** (`refused`): Spirit Airlines ceased independent
    operations, Free Spirit is defunct, and Bank of America discontinued the cards (converting
    cardholders to Customized Cash Rewards).
- **Cards remain drafts**: Adding valuations does not promote any card from `draft` to `published`
  ahead of issuer-confirmed earn rules (D3).

## 2026-08-27 — card-catalogue 2.4: seven co-brand reward currencies, none of them valued

- **Seven new `programId` values** — `aaAdvantage`, `atmosRewards`, `avios`, `cathayAsiaMiles`,
  `deltaSkyMiles`, `disneyRewards`, `spiritFreeSpirit` — landing **15 new `draft` cards**.
  Catalogue is now 41 CA published, 40 US draft, 4 CA draft. This is the Option 2 follow-up the
  2026-08-27 Option 1 ruling explicitly did not drop: roughly two in three US candidates earn a
  currency this catalogue could not name, and mapping them onto a near-enough enum value was
  rejected outright, because a Delta card recorded as `amexMembershipRewardsUs` is not
  approximately right — it values the card in a currency it does not earn.

- **NOTHING was added to programs.json, and that is the point.** `centsPerPoint` is a DISCLOSED
  ASSUMPTION requiring a sourced basis, and there is no honest source for these yet. Every card on
  them is a `draft`, and `Scorer` refuses a draft on the status guard, so an unvalued co-brand
  programme excludes nothing that was not already excluded. This is the same shape as the six
  `*Us` placeholders added in 2.2, which have carried no valuation since. **The `knownUnvaluedPrograms`
  allowlist is deliberately NOT used**: it has been scoped to published cards since 2026-08-27
  (99cace9), so a draft-only programme never reaches it, and its ratchet is pinned at zero.
  Valuing these is tracked as separate research; until then the honest record is silence.

- **No engine code changed in any of the three languages, and none was needed.** `programId` is a
  `String` in Swift, Kotlin and TypeScript alike — the closed enum exists only in
  `schema/card-catalogue.schema.json`, and `Scorer.valueCad` dispatches on the *valuation's* model,
  not on the programId. `noRewards` needed a mirror in 2.3 because it added a new valuation MODEL;
  these are points programmes and add none. What each language gained instead is a regression test
  (`CoBrandProgramTests`, `CoBrandProgramTest`, `coBrandProgram.test.ts`) whose set of new
  programmes is DERIVED as "declared by a card, absent from programs.json" rather than hardcoded,
  so it maintains itself as the remaining currencies land.

- **The safety property is an ordering, and it turned out to be three-deep.** Writing the test
  revealed that a draft on an unvalued programme is stopped three separate times: `isPublished`,
  then an empty `earnRules` set that `RuleMatcher.resolve` cannot satisfy, and only then the
  valuation check. That means **no draft can exercise the valuation guard at all** — the first
  attempt at the test flipped a draft to `published` and it was still excluded for having no rule.
  The risk this creates is that `status` could stop mattering while the empty rule set keeps the
  suite green, so the tests now pin each layer to the reason it exists rather than asserting the
  outcome and accepting any cause.

- **Three of the nineteen proposed currencies were wrong, and were not shipped as proposed.**
  `alaskaMileagePlan` names a programme that no longer exists and `hawaiianMiles` names a currency
  that no longer exists: Alaska and Hawaiian merged both into **Atmos Rewards** (launched
  2025-08-20, HawaiianMiles absorbed 1:1 on 2025-10-01, existing Hawaiian World Elite cardholders
  earning Atmos points from that date). They are ONE currency, shipped as `atmosRewards` with four
  cards, and the Barclays Hawaiian card is mapped to it on that sourced fact rather than to a
  retired currency. `cathayAsiaMiles` is kept: Cathay folded Asia Miles and Marco Polo Club into a
  single `Cathay` membership in 2022, but Asia Miles remains the spendable currency.

- **`costcoCashRewards` was refused.** The CIBC card pays a CAD certificate redeemable only at
  Canadian Costco warehouses; Citi Costco Anywhere pays a USD certificate redeemable only at US
  ones. They are not fungible, so one shared programId would value a card in a currency it does not
  earn — and the only *landable* card of the two was the Canadian one, which would have defined a
  generically-named entry entirely from a CAD certificate. A shared programId is correct only where
  the currency is genuinely the same, which is why `marriottBonvoy` and `aeroplan` are cross-market
  and this is not. `avios` IS such a case and is deliberately cross-market: Aer Lingus, British
  Airways and Iberia (US) plus RBC British Airways (CA) all earn into the same IAG currency.

- **Twelve of the nineteen proposed values were held back because they land no card today.**
  Six (`jetBlueTrueBlue`, `unitedMileagePlus`, `southwestRapidRewards`, `wyndhamRewards`,
  `worldOfHyatt`, `ihgOneRewards`) are blocked on `network`, which the aggregator snapshots do not
  carry and which is catastrophic to guess. Four more (`hiltonHonors`, `emiratesSkywards`,
  `frontierMiles`, `choicePrivileges`) reached the *fee* gate and were refused there: giving them a
  programId revealed a second, independent gap the currency gap had been masking, with sources
  disagreeing at `[0, 150, 195, 550]` for the Hilton entry — the whole Hilton Amex family described
  under one name. Shipping an enum value that names nothing puts a permanent, published entry in a
  contract for a card that does not exist in it; 2.2 did that with six placeholders and the schema
  now needs a paragraph explaining them. These come back for free once their gap is closed.

- **Two of the deferred currencies are not points programmes** and will need the `ctMoney` model
  rather than `points` when they are eventually valued: Disney Rewards Dollars and both Costco
  certificates are store-locked, dollar-denominated annual rewards, which is exactly the shape
  CT Money carries a usability factor for. Recorded here so the valuation pass does not default
  them to `points` and quietly claim a dollar locked to one merchant is a dollar.

- **The `programId` description in the schema was corrected.** It claimed `Scorer.valueCad` "still
  returns 0.0 rather than excluding the card" and that the gap "is pinned in
  `knownUnvaluedPrograms`". Both have been false since 2026-08-20: an unvalued programme answers
  nil and the card is excluded with `unsupportedProgram`, and the allowlist is empty. That sentence
  misdescribed the exact safety property this release depends on.

- Verified: Swift 282/282, Kotlin 50/50, TypeScript 1109/1109.

## 2026-08-27 — card-catalogue 2.3 / programs 1.2: `noRewards`, for a card that earns nothing

- **New `programId` value `noRewards`, and a matching valuation model.** MBNA True Line and
  Capital One Guaranteed Secured have no rewards programme at all, and `program` is a REQUIRED
  field with a closed enum, so until now there was no way to say so. Every workaround was a lie:
  mapping them to `cashback` claims a programme they do not have, and omitting the field is not
  permitted.
- **The whole point is the distinction `Scorer.valueCad` already drew and could not express.** A
  MISSING valuation returns nil/null and `Scorer.score` excludes the card with
  `unsupportedProgram`, because "we do not know what this is worth" must never rank as "worth
  nothing" — that rule dates from the 11-of-16 unvalued-programs bug. `noRewards` returns **0.0**
  and the card is scored, ranking last on merit rather than vanishing from a comparison it belongs
  in. Same principle as `fxRules`, where a fee-free card declares `rate: 0.0` rather than saying
  nothing: the fact is STATED, never inferred from an absence.
- **It carries a `basis` like every other default**, because `testEveryProgramDefaultDisclosesItsBasis`
  requires one and it is right to — "this is a fact, not an estimate" is exactly what a reader of
  the valuation disclosure needs told. Named `noRewards` and not `none`: a bare `none` case on a
  non-Optional Swift enum is a standing ambiguity trap.
- **Three cards land with it (catalogue 2.3, all `draft`):** MBNA True Line and Capital One
  Guaranteed Secured on `noRewards`, and Neo World Mastercard on the existing `cashback` — the
  first Canadian candidates to enter since the corpus collapse. Catalogue is now 41 CA published,
  26 US draft, 3 CA draft.
- **The ratchet forced the ordering, correctly.** `testEveryProgramDefaultKeyIsARealCatalogueProgramId`
  refuses a programs.json valuation that no card declares, so the enum value, the default and the
  cards had to land in one change rather than three. That gate was written to catch typos and it
  caught a real sequencing error instead.
- Mirrored in Swift (`NoRewardsValuation`, `ProgramValuation.noRewards`), Kotlin
  (`NoRewardsValuation`) and TypeScript, each with its own regression test. Swift 276/276,
  Kotlin 46/46, TypeScript 1095/1095.

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
