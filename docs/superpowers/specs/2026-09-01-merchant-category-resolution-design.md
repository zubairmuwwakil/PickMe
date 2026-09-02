# Merchant category resolution — one ladder, one source

**Date:** 2026-09-01
**Status:** design, awaiting review
**Scope:** PickMe only. No cross-repo work, no new data sources.

## The problem

Every card decision starts by answering one question: *what kind of spending is
this?* The answer picks the multiplier, and therefore the card.

Three code paths answer it today, and two of them answer it wrongly.

### 1. A search tap discards the category it was handed

`PreIndexedMerchant.category` is already a canonical taxonomy id — `grocery`,
`dining`, `transit`. Two call sites put it into `NearbyMerchant.poiCategoryRaw`,
a field that means "Apple's place-type vocabulary," and drop `mcc` entirely:

- `HomeView.swift:767` — the offline autocomplete dropdown
- `MerchantProvider.swift:52` — `LiveMerchantProvider.fallbackSearch`

`predict` then runs the value through `canonicalPoiCategory` and switches on
`foodmarket` / `restaurant` / `pharmacy`. `"grocery"` matches none of them, so it
falls to `default`: category `other`, confidence `.fallback`.

Two vocabularies share one `String?` field, so the mismatch compiles cleanly and
surfaces only as a wrong recommendation.

Of the 127 indexed brands, only two groups survive the round trip: the 9
`gasStation` rows, purely because `"gasStation".lowercased()` happens to equal the
`"gasstation"` case label, and the handful of names caught by `brandPriors` in
`CategoryMapper`. Everything else — 26 dining rows, 19 grocery, all transit,
streaming, drugStore, travel — scores as `other`.

### 2. Wallet capture matches storefront names, not payment descriptors

`contracts/merchant-pack.json` carries 254 `matchKeys`, of which **127 are
descriptor-shaped needles that are not the merchant's display name**: `amzn mktp
ca`, `apple com bill`, `seven eleven`, `a w`. Its overrides file states the reason
plainly:

> The pre-index answers 'what is this PLACE' (MapKit gave PickMe a tidy name). A
> payment descriptor is a different string entirely: 'TIM HORTONS #4021 TORONTO
> ON', 'SQ \*CAFE METRO', 'UBER \*EATS PENDING'.

`MerchantRecognizer` reads none of them. It builds its alias index from
`PreIndexedMerchant.name` and derives variants with a regex
(`MerchantRecognizer.swift:35`). `AMZN MKTP CA` cannot tokenize into
`["amazon", "ca"]`, so Apple Pay captures of Amazon, Apple, and 125 other brands
fall through to `predict(poiCategoryRaw: nil, ...)` — where the entire MapKit
switch is unreachable and only the 9 `brandPriors` can fire.

`AutoCaptureLog.record` then stores `nil` rather than a fabricated `other`
(`AutoCaptureLog.swift:107`), which is the honest choice and is why these rows
appear in Activity with no category at all.

### 3. Location enrichment is built, correct, and gated shut

`enrichUnknownWalletMerchants` (`CheckoutFlowView.swift:468`) already does the
right thing: takes the capture's coordinates, runs a MapKit lookup around them,
and matches the payment descriptor against real nearby places. Coordinates do not
supply a category — they supply *identity*, which is the part Apple Pay withholds.

`resolveWalletMerchant` then requires `prediction.candidates.count == 1`
(`DiscoveredMerchantResolution.swift:53`). But `CategoryMapper` deliberately forks
the two most common place types:

- `gasstation` → `["gasStation", "other"]` (`CategoryMapper.swift:74`)
- `store` → `["other", "grocery"]` (`CategoryMapper.swift:102`)

So a gas-station capture can never be enriched, no matter how good the fix or the
name match. The fork that exists to keep the app honest is read by this gate as
"not confident enough."

## Why this is a wiring problem, not a data problem

`purchase-categories.json` defines 25 categories. Card rules reference 23, and the
distribution is top-heavy — grocery (38 rule references), gasStation (30), dining
(29), transit (21), travel (19), evCharging (16), foodDelivery (14), lodging (13),
streaming (13), then a long flat tail where `ctFamily`, `eGames`,
`retailShopping`, and `wholesaleClub` appear once each.

About thirteen categories change which card wins. The rest score base earn, where
every card ties — so a merchant landing in `other` instead of `retailShopping`
costs the owner nothing.

The task is therefore **bucketing into ~13 outcomes**, not identifying every
business in Canada. All the data needed for that already exists in the repository
and is not plugged in.

### Explicit non-goal: importing an open places dataset

An earlier draft proposed growing the pack from 127 rows to thousands via
Foursquare / Overture / Wikidata. That is rejected, for four reasons in order of
weight:

1. **It targets the axis that already works.** A places dataset resolves identity
   *by location*, which MapKit already handles well — `restaurant`/`cafe`/`bakery`
   → dining, `pharmacy` → drugStore, `hotel` → lodging, each single-candidate. The
   broken axis is identity *by descriptor string*, and an independent café's
   descriptor (`SQ *BLUE DOOR`) matches no brand table at any size.
2. **It scales guesses, not facts.** The pack's own provenance says so:
   *"Categories and MCCs are editorial research, not observed network data."*
   Multiplying unverified priors 50x sits badly against D3, which blocks a card
   from `published` without issuer-confirmed sourcing.
3. **The coverage it buys is mostly non-differentiating.** Independents cluster in
   dining (MapKit already resolves it) and retail (does not change the answer).
4. **It costs the most and is gated on the slowest thing** — a RAW_SOURCE_POLICY
   licence review, plus app-bundle weight.

MCC is assigned by the acquirer to a merchant terminal and travels on the payment
network. No public Apple API exposes it, and bank aggregation is on ECOSYSTEM.md's
"Never on this path" list. Identity → category is therefore always a prior, never
a lookup of ground truth — which is exactly what `ConfidenceSource` already models.

## Design

### Part 1 — The pack becomes the source of truth

`contracts/merchant-pack.json` already exists with a JSON schema, a `packVersion`
MAJOR-refusal rule, and a `--check` staleness gate in `.claude/settings.json`. It
is a **complete superset** of the Swift model — every field `PreIndexedMerchant`
carries (`category`, `mcc`, `merchantBrand`, `notes`, `acceptedNetworks`) is
present, plus `matchKeys` and `emailDomains` that the Swift type lacks.

Today the arrow points the wrong way: `scripts/generate-merchant-pack.mjs`
generates the JSON *from* `CanadianMerchantPreIndex.swift`, and no Swift code reads
the result. The pack is an export for In Unity with no consumer in this repo.

Invert it:

1. Add `merchant-pack.json` to `scripts/sync-contracts-into-engine.sh`, copying
   into `Engine/Sources/CardCopilotEngine/Resources/` like every other contract.
   `ContractsSyncTests` then guards byte-level drift for free.
2. Add `SeedLoader.loadMerchantPack()` plus a decoded-once
   `SeedLoader.merchantPack` static, following the exact shape of
   `purchaseCategories` and `ownerConditions` — including `preconditionFailure` on
   an unreadable pack. A resource compiled into the bundle and gated by tests
   cannot be unreadable at runtime without the build being broken, and an empty
   fallback would silently uncategorize every merchant.
3. Refuse an unrecognized `packVersion` MAJOR, matching
   `supportedCatalogueMajorVersion`.
4. Rewrite `CanadianMerchantPreIndex` as a thin view over the loaded pack, keeping
   its public API (`all`, `search(_:limit:)`) and `PreIndexedMerchant`'s shape
   unchanged so its five call sites need no edit — plus a new `matchKeys` field,
   which is the whole point of loading the pack.

   **`PreIndexedMerchant.id` must not adopt the pack's slug.** It is persisted:
   `MerchantPatronageStore` keys visit history on it and resolves display names
   back through it (`MerchantPatronageStore.swift:143`), and
   `resolveDiscoveredMerchant` tests `frequentedKeys.contains(indexed.id)`. The
   pack's `amazon-ca` is a different string from the historical `amazon.ca`, so
   adopting it would silently orphan every owner's patronage record. The id stays
   derived from the display name; adopting stable ids is a migration, not an edit.
5. Delete the 127 hand-written rows from the Swift file.
6. Delete `generate-merchant-pack.mjs` and `merchant-pack-overrides.json`. The
   generator's only question was "does this JSON match the Swift array?", which
   stops existing the moment the array does. Its curation guidance moves into the
   pack's own `_provenance` so it travels with the data, and its CI slot is taken
   by `scripts/validate-catalogue-schema.py` — which now covers the pack and
   catches the failure the generator never could: a hand-edited `matchKey` that
   is not normalized, and so can never match anything.

**Android is untouched.** There is no Kotlin pre-index or `MerchantRecognizer`;
merchant recognition is not engine semantics, so the cross-language gate does not
cover it and `sync-contracts-into-android.sh` needs no change.

### Part 2 — One resolver, and it reads the match keys

`MerchantRecognizer.aliasIndex` stops deriving aliases from `displayName` with a
regex and reads `matchKeys` from the pack instead. The curated keys are already
normalized the way the overrides readme documents — lowercased, diacritics folded,
runs of non-alphanumerics collapsed to one space — which is the same normalization
`MerchantRecognizer.tokens` performs.

The matching machinery does not change. The schema already specifies the contract
`MerchantRecognizer` implements — *"matched as whole words against a normalized
merchant string. Ordered longest-first so the most specific needle wins"* — which
is exactly `contains` plus the longest-match tiebreak in `recognise`. Only the
*source* of the needles is wrong.

So `tokens`, `contains`, and the tiebreak stay. What is deleted is the alias
*derivation*: `aliases(for:)`, the `/`-splitting, the country-word drop, the
lone-acronym parenthetical, and the `Alias.isDerived` asymmetry that exists only
because the code guesses at forms. A curator states them directly instead, under
the discipline the overrides file already documents:

> Add a key here ONLY when it is unambiguous on its own. 'metro' is a grocery chain
> AND half of 'CAFE METRO'; it earns its place because the generator matches whole
> words and the longest match wins, but a two-letter or generic needle […] is how a
> pack starts producing confident nonsense.

Curation discipline plus longest-match replaces the `isDerived` guard. Note that a
short single-token key like `amzn` is deliberate and must keep matching inside a
longer descriptor — `AMZN MKTP CA` resolves through it — so no minimum-token rule
may be added.

The two search call sites stop lying about `poiCategoryRaw`:

```swift
NearbyMerchant(id: "preindex:\(match.id)",
               name: match.name,
               poiCategoryRaw: nil,          // we have no POI signal here
               merchantCategoryCode: match.mcc,
               latitude: 0, longitude: 0, distanceMeters: nil)
```

`predict` checks `observedMCCCategory` first, so this alone resolves 5411 →
grocery, 5814 → dining, 4121 → transit. But the MCC table is deliberately sparse —
`ctFamily`, `streaming`, `foodDelivery`, `householdUtilities` have no entry — so
both sites route through `resolveDiscoveredMerchant` instead, which already
consults the pack, takes the row's category as a `.brandPrior`, carries its MCC,
and preserves the Walmart fork (`DiscoveredMerchantResolution.swift:105`).

That is the single ladder every caller uses:

```
reconciledStatement          owner reconciled against a statement
repeatedTerminal             confirmed ≥2 times at this terminal
ownerConfirmedTerminal       confirmed once
observedMcc                  an MCC we actually saw
brandPrior                   the pack recognized the brand
mapKitCategory               Apple told us the place type
fallback                     nothing — store nil, never "other"
```

### Part 3 — Ungate location enrichment

Replace the `candidates.count == 1` gate in `resolveWalletMerchant` with a check
the engine can actually act on.

`CheckoutService.recommend` already scores *every* candidate branch and collapses
to `.single` when the branches agree on a winner
(`CheckoutService.swift:206-218`). Ambiguity is free when the cards agree. A
two-element candidate set is a perfectly good answer, and the current gate throws
away exactly the shape the engine was built to resolve.

New rule: accept a resolution whose `confidenceSource != .fallback` and whose
candidate set is non-empty, and store the **candidate set**, not just the winner.
`enrichAutomaticPurchase` gains the same treatment, dropping its mirrored
`candidates.count == 1` and `category != "other"` guards
(`CheckoutService.swift:401-403`).

A capture enriched to `["gasStation", "other"]` is scored across both branches. If
one card wins both, the owner is told which card; if not, the purchase is marked
as needing one tap to settle — the state `PurchaseAttentionStatus` already exists
to express.

The distance ceiling (150 m), the 60% name-overlap floor, and the
once-per-session `attemptedWalletEnrichmentIDs` guard all stay. Those bound
*identity*, which must stay strict. Only the *category confidence* gate relaxes.

### Part 4 — Measure the ladder

Nobody currently knows what fraction of captures resolve, or at which rung. Adding
data before measuring is how the places-dataset detour happened.

`NearbyLookupMetricsStore` (`App/CardCopilot/Services/`) is the existing on-device,
no-telemetry pattern. Add a sibling `CategoryResolutionMetricsStore` recording, per
resolution: which rung answered, whether the candidate set was forked, and whether
enrichment was attempted / succeeded / was skipped and why.

Surfaced in the existing diagnostics screen. Nothing leaves the device — this
satisfies the ambient spec's "no user financial telemetry is exported" clause and
keeps the decision about a bigger pack an evidence-based one.

## Testing

The cross-language gate is unaffected (no engine semantics change), but it still
runs:

```bash
(cd Engine && swift test) && (cd android && ./gradlew :core:engine:test)
```

New coverage, written test-first:

| Test | Asserts |
|---|---|
| `MerchantPackLoadingTests` | pack loads from bundle; unknown `packVersion` MAJOR is refused; all 127 rows survive the round trip with `mcc`, `merchantBrand`, `notes` intact |
| `MerchantRecognizerTests` (extend) | `AMZN MKTP CA` → Amazon.ca; `APPLE COM BILL` → Apple Services; `TIM HORTONS #4021 TORONTO ON` → Tim Hortons; whole-word matching holds (`shell` does not match `SHELLFISH CO`); longest match wins where two rows share a needle |
| `PreIndexTapResolutionTests` (new) | tapping the pre-index row for Loblaws yields `grocery`, not `other`; Tim Hortons yields `dining`; Walmart keeps its fork |
| `DiscoveredMerchantResolutionTests` (extend) | a gas-station wallet capture with a good fix now enriches to `["gasStation", "other"]` rather than being rejected |
| `CheckoutServiceTests` (extend) | an enriched two-candidate purchase scores both branches and collapses when the winners agree |
| `ContractsSyncTests` | `merchant-pack.json` matches its `Engine/Resources` copy byte for byte |

`python3 scripts/validate-catalogue-schema.py` replaces the generator's CI step and
must stay green.

## Follow-on, deliberately out of scope

**Stable merchant identity.** `LiveMerchantProvider.syntheticId(name:coordinate:)`
produces `"Metro@43.65,-79.38"`. If MapKit nudges a coordinate, it becomes a
different merchant and the owner's learned confirmations orphan. iOS 18 is the
deployment target and `MKMapItem.identifier` should be available there — to be
verified against the SDK before relying on it. This is a precondition for any
future shared learning, but it is not required by the three fixes above and would
widen the change.

**E-receipt evidence.** MoneyTalks owns email ingestion, and the pack already
carries `emailDomains` for 45 merchants. A receipt names the merchant
unambiguously and beats both a places dataset and a descriptor guess. That is a
MoneyTalks decision record, not a PickMe task.

**Owner confirmations as the growth engine.** Already at the top of the ladder and
already wired through `PurchaseDetailSheetView`. Once Part 4 reports real numbers,
the question of whether the pack needs to grow at all can be answered with
evidence.

## Unrelated finding, recorded here so it is not lost

`2026-08-31-ambient-intelligence-value-proposition-design.md` plans around
FinanceKit at lines 86 and 121 — "automatic category cap exhaustion tracking,"
"dynamic spend cap exhaustion via FinanceKit." The research file
`docs/research/canadian-card-copilot-research-2026-08-15.md:298` rules the
opposite, checked through WWDC 2026: *"FinanceKit is still not a general
transaction-access rail for Canadian bank and card accounts,"* with the explicit
instruction *"Do not plan v1 or v1.5 Canadian reconciliation around FinanceKit."*
Two specs disagree and the newer one plans on a rail unavailable in this market.
Reconcile separately from this work.
