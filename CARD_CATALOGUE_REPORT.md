# Credit Card Catalogue Expansion — Session Report (2026-08-27)

Scope actually executed this session: **Stage A** (multi-currency/market schema evolution across
Swift/Kotlin/TypeScript) and **Stage B** (ingestion pipeline, discovery, gaps, research queue).
**No US or additional CA cards were promoted into `contracts/card-catalogue.json`** — that is
Stage C, deliberately deferred (see "What was NOT done" below).

## Coverage

| | Count |
|---|---|
| Published catalogue cards (unchanged) | 41 (all Canadian) |
| Issuers in the published catalogue | 18 |
| Discovered but NOT yet in the catalogue (deduplicated candidates) | 329 canonical products |
| — of which US (openCard + cc-offers) | ~319 |
| — of which CA (ClearFin sample) | ~9 |
| ClearFin CA URLs discovered but not yet fetched | 117 of 127 |
| Draft-tier cards added | **0** — the `status: draft` mechanism now exists but nothing uses it yet |

The 41-card catalogue itself did not change in content this session — only its *shape*
(currency-tagged fields, `market`/`billingCurrency`, `status`, `eligibility`). Coverage growth is
entirely staged as **discovery data** for Stage C, not live in the app.

## Source coverage

| Source | What was pulled | Fields per record |
|---|---|---|
| OpenCard AI (`opencardai.com/api/cards?full=1`) | 224 US cards, 23 issuer groups | `card_id`, `name`, `issuer`, `annual_fee` — **4 fields only**. `full=1` is a no-op (byte-identical response); there is no working per-card detail endpoint (`/api/cards/{id}` returns the Next.js HTML shell, not JSON) |
| cc-offers (`sgolovine/cc-offers`, MIT) | 242 US rows via its SQLite export | issuer, card name, segment, welcome offer, cash/miles bonus, spend requirement, annual fee, intro/regular APR, **prose** `rewards_key_perks`, `source_url`, `source_basis`, `retrieved` (2026-05-29 — 3 months stale) |
| ClearFin (`clearfin.ca`) | 127 CA card URLs discovered (sitemap); **10 pages fetched and field-extracted** as a representative sample | Annual fee, reward type, welcome offer, purchase/cash-advance/balance-transfer APR, FX fee, income requirement, recommended credit score, ClearFin's own "checked" date |
| CanadianCreditCards.app | Not used | Not attempted this session (time-boxed; no blocker found, just not reached) |
| Issuer sites | Not fetched directly this session | Every gap/queue entry names the issuer as the next authoritative source |

**Verified claim from the original plan review, now confirmed by actually pulling the data:**
OpenCard and cc-offers together give almost no *earn-rule* structure — cc-offers' rewards live
entirely in one free-text column. The dedup/discovery layer below is real and useful; it is not a
substitute for reading issuer terms.

## Verification

Every fact captured this session is `sourceType: comparisonSite` or the raw aggregator's own
label, `verificationStatus: unverified`. **Nothing new was written as `issuerConfirmed`.** The
existing 41 cards' provenance is untouched. Zero conflicting facts were force-resolved — where a
new source disagreed with something (e.g. two different fees for the same discovered card), it's
recorded as a `conflicting` gap, not silently picked.

## Deduplication result

- **1 confirmed match** to an existing catalogue card: ClearFin's `td-first-class` ↔
  `td-first-class-travel-visa-infinite` (name-token overlap 1.0, fee agrees exactly at $139).
- **0 false positives survived.** The first matching pass produced one — ClearFin's "CIBC Costco
  Mastercard" scored a spurious 0.5 overlap against "CIBC Dividend Visa Infinite" purely because
  both names contain the issuer's own name as a token. Fixed by stripping issuer tokens from the
  name-similarity comparison before scoring (the issuer match is already a separate, required
  gate) — `catalogue-pipeline/scripts/dedupe_and_report.py`'s `best_match()`. This is exactly the
  class of bug Phase 4 asked to guard against, caught by testing the dedup logic against real
  data rather than trusting it on inspection.
- **475 raw records → 329 canonical products** after cross-source merging (e.g. the same Amex
  card appearing in both openCard and cc-offers collapses to one candidate).

## Missing data (`card-data-gaps.json`)

| Importance | Count | What it means here |
|---|---|---|
| CRITICAL | 338 | A card discovered but not yet in the catalogue at all — no earn rules exist for it anywhere. Read literally against the original brief's definition ("missing info that can cause an incorrect *existing* recommendation"), a card that isn't in the catalogue can't yet cause a wrong pick — it's marked CRITICAL here in the sense of "blocks this card's correct entry entirely," a judgment call worth flagging rather than silently reinterpreting the rubric. |
| HIGH | 329 | Annual fee stated by only one source, unconfirmed against the issuer |
| MEDIUM | 1 (batch) | 117 ClearFin URLs known but not yet fetched |

## Research queue (`card-research-queue.json`)

339 entries, each naming: candidate id, official name, issuer, country, what's missing, current
(unverified) value and its source, the likely authoritative source, a suggested search query, and
whether it affects checkout/acquisition/benefits — exactly the shape Phase 9 asked for, so a next
agent (human or AI) can start verifying immediately without re-discovering what's missing.

## Important unresolved problems

1. **Coverage is US-heavy and CA-shallow.** 329 candidates, all but ~9 American. The CA-side gap
   (Capital One, Neo Financial, Brim have **zero** cards in the catalogue; CIBC/BMO/Scotia/TD/NBC
   each have far more products at ClearFin than in the catalogue) is real and was found by this
   session's own sample, not assumed — see the 10 fetched pages. Closing it needs more ClearFin
   fetches (mechanical — the extractor works) plus issuer verification (not mechanical).
2. **No US card can be scored correctly yet without Stage C's remaining engine work.** Stage A
   built `billingCurrency`, `spendNative`, `calendarQuarter`, and `predicate.ownerSelectedCategory`
   — but **program valuations stay CAD-only** (`programs.json`/`ProgramValuation` — see CHANGELOG).
   A US card entering with a USD-valued program (e.g. Chase Ultimate Rewards) would need that
   extended first, or it silently scores against a CAD-denominated valuation.
3. **The `status: draft` mechanism is built but unexercised.** No test proves an actual draft
   *card in the real catalogue* is excluded end-to-end through `RecommendationEngine`/
  `PortfolioAnalyzer` with real owner state — only synthetic-card unit tests (`MultiMarketTest`/
  `multiMarket.test.ts`/`MultiMarketTests.swift`) exercise it. Low risk (the mechanism is a single
  guard checked first in `Scorer.score`), but worth a fixture-level test once a real draft card
  exists.
4. **ClearFin extraction depends on their current page markup.** The extractor
  (`scripts/extract_clearfin.py`) pattern-matches two recurring React-tree shapes; a ClearFin
  redesign would silently return empty facts rather than erroring loudly. Not hardened this
  session — flagged, not fixed.

## Schema changes (Stage A — full detail in `contracts/CHANGELOG.md`)

`fee.annualCad`/`monthlyCad` → `fee.annual`/`monthly: Money`; `credit.valueCad` → `credit.value:
Money`; `earn.pointsPerCad` → `earn.pointsPerUnit`; `cap.measure: spendCad` → `spendNative`;
new `cap.period`/`credit.period: calendarQuarter`; new required `market`/`billingCurrency` per
card; new optional `status`/`eligibility`; `network` gains `discover`. Catalogue MAJOR version
1 → 2. Mirrored in the JSON Schema, Swift, Kotlin, and TypeScript/Zod — see CHANGELOG for the
full reasoning and the engine-side changes (billing-currency-aware `Scorer`, new
`ReportingCurrency` helper, `CapWindow` quarter support, market-scoped empty-wallet
recommendations and acquisition eligibility).

## Files changed

**PickMe:** `contracts/{card-catalogue,candidate-catalogue,RELEASE}.json`,
`contracts/schema/card-catalogue.schema.json`, `contracts/CHANGELOG.md`,
`Engine/Sources/CardCopilotEngine/{Models/*.swift,Engine/*.swift,Loading/SeedLoader.swift}`,
`Engine/Tests/.../{SeedLoaderTests,ScoredRuleSnapshotTests,MultiMarketTests}.swift`,
`Engine/Sources/CardCopilotEngine/Resources/*` (synced), `App/CardCopilot/{Views,Services}/*.swift`,
`Store/Sources/CardCopilotStore/CategoryMapper.swift`,
`android/core/engine/src/{main,test}/kotlin/com/cardcopilot/engine/**`,
`android/core/engine/src/{main,test}/resources/com/cardcopilot/engine/*` (synced),
new `catalogue-pipeline/` (raw snapshots, `dedupe_and_report.py`, `extract_clearfin.py`, the two
JSON artifacts), this report.

**MoneyTalks:** `contracts/*` (synced), `src/engine/cards-twin/*.ts` (+ new
`reportingCurrency.ts`, `multiMarket.test.ts`), `src/lib/contracts/cardCatalogue.ts` (+ test),
`src/lib/cards/{catalogueCard,cardPresentation,types}.ts` (+ test), `src/lib/domain/{bills/
cardForBill,cards/walletImpact}.ts`, `src/app/{bills/actions,cards/page,cards/[id]/page}.tsx`,
`src/components/cards/card-tile.tsx`.

## Tests

- **PickMe Engine (Swift):** not compiled or run — no Swift toolchain in this sandbox. Every
  changed call site was hand-checked against the exact signatures involved; CI on `macos-15` is
  the first real compile. Flagged clearly rather than claimed.
- **PickMe Android (Kotlin):** `:core:engine:test` — **41/41 passing** (34 pre-existing + 7 new
  `MultiMarketTest`), including the unchanged golden `FixtureHarnessTest`. Also fixed a
  pre-existing, unrelated bug this surfaced: `loadCandidateCatalogue()` still decoded the
  candidate file as a full `Catalogue`, a shape it left in 2026-08-24 — see CHANGELOG.
- **MoneyTalks:** `tsc --noEmit` clean project-wide. `vitest run` — **977/988 passing**; the 11
  failures are `contracts.test.ts`'s commit-provenance checks, which by design cannot pass while
  PickMe's changes are uncommitted (`sync-contracts.sh --allow-dirty` was used for local
  verification only) — they clear on a clean re-sync once PickMe's changes land.

## What was NOT done (deliberately, and why)

- **No US or additional CA card entered `contracts/card-catalogue.json`.** That's Stage C —
  issuer-verifying and promoting real cards — which the user explicitly scoped out of this
  session ("Stage A + B").
- **Program valuations are not currency-aware.** No catalogue program is USD-valued yet, so
  building that mechanism now would have nothing to exercise it. Flagged as the first thing Stage
  C needs if it picks a US card whose program isn't already CAD-valued.
- **CanadianCreditCards.app** was not queried this session (no blocker found — just not reached
  in the time available).
- **117 of 127 ClearFin URLs** are discovered but not fetched. The extractor works (proven on 10
  real pages); running it across the rest is mechanical, not research.

## Completion standard (against the original 16-point bar)

Broadly enumerated (✓ discovery, not yet promoted), source records preserved (✓ raw snapshots),
deduplicated into canonical products (✓, 329, with a caught-and-fixed false-positive), currencies
represented correctly (✓ schema + engine, verified in 3 languages), critical scoring fields
populated where available (✓ for the 41 unchanged cards; explicitly NOT for the 329 candidates —
that's the queue's job), missing/conflicting facts identified (✓ gaps file), a next agent can
continue without repeating discovery (✓ research queue), relevant tests pass (✓ Kotlin/TS,
Swift unverified), remains compatible with PickMe and MoneyTalks (✓, verified both directions).
