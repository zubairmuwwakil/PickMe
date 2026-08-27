# Ambient coverage instrument — and why place-level patronage (T6) is parked

**Date:** 2026-08-27
**Status:** instrument shipped; T6 deferred pending data
**Relates to:** [`2026-08-17-ambient-capture-design.md`](2026-08-17-ambient-capture-design.md) §13

## What was asked

Build place-level patronage and frequency-aware geofence slot ranking: a visit journal written
from Wallet captures, lazy POI corroboration, a targeted MapKit lookup to close the negative-cache
hole, a `FrequentedPlace` model, and tiered slot ranking in `rotateRegions`.

The work was gated on evidence: open the ambient explainer, and if `merchantConfidenceLow` no
longer dominates the seven-day suppression breakdown, re-scope or drop.

## Why the gate could not be passed

**1. The counter is empty.** `ambientDiagnostics.v1` does not exist in the app's `UserDefaults` on
the only simulator with the app installed. Not a low count — never written. `AmbientGate.evaluate`
has never run outside a unit test here.

**2. It was not going to be full.** [`testflight-beta-notes.md`](../compliance/testflight-beta-notes.md)
§C3 is entirely unchecked, including *"withhold external invites until the Phase-3 dogfood week
gate criteria (fired/suppressed/coverage) are met."* The field test that would populate the
counter is itself an open checklist item.

**3. `SuppressionLog` cannot measure slot pressure, empty or not.** This is the finding that
matters and it survives a perfect dogfood week. `diagnosticsStore.record` sits behind three
`return`s in `evaluateArrival` — a geofence must have fired, resolution must have succeeded, and
the engine must have advised. **A merchant that lost its slot produces no entry event at all.**
Slot pressure is a silence, and the log had no silence counter. The gate as posed was a
non-sequitur in both directions.

Two lesser problems with the same gate: the reasons are not a partition (`recommendedDefaultCard`
is inserted unconditionally *before* the confidence switch, so one arrival can increment both
counters), and `recommendedDefaultCard` is not a failure at all — it means the owner's default
card was right and silence was correct.

## What was built instead

The third gate criterion, which did not exist.

| Piece | Where |
|---|---|
| `AmbientRegionTier`, `RegionCandidate`, `RegionAllocation`, `allocateRegionBudget` | `Store/…/DiscoveryPolicy.swift` |
| `storedMerchantRegionTier`, `areaRegionTier` | `Store/…/DiscoveryPolicy.swift` |
| `AmbientCoverageLog` | `Store/…/AmbientCoverageLog.swift` |
| `DailyLogStore<Log>`, `AmbientCoverageStore` | `App/…/AmbientLocationService.swift` |
| Coverage card | `App/…/AmbientLocationExplainerView.swift` |

**Ranking is unchanged.** `allocateRegionBudget` still lets distance decide, because an instrument
that measures a policy the app does not run answers no question. Tiers are a tiebreak today; they
earn their keep in the eviction report.

Two incidental fixes rode along:

- **The sort was never stable.** `rotateRegions` said *"Stable sort: … confirmed merchants were
  appended first so they take the slot at equal distance."* `Array.sorted` is introsort. Two
  rotations over an unchanged world could disagree about the last slot and re-register a region
  that had not moved. The allocation now has a total order (distance → tier → id).
- **`maximumMonitoredRegions` was declared twice**, in the adapter and implicitly in the policy.
  Now once, in `DiscoveryPolicy`.

### The number T6 turns on

`AmbientCoverageLog.evictedWithStanding` — evictions that cost the app a merchant the owner has
confirmed or keeps paying at.

- **Zero across a dogfood week** → the cap only ever drops ground the owner has never shopped.
  Frequency-aware ranking changes nothing. Drop T6 §5.
- **Non-zero, with `rotationsAtCapacity` a large fraction of `rotations`** → the cap is binding on
  ground that matters, and T6 §5 has a measured case.

Areas inherit the standing of the merchants inside them (`areaRegionTier`). Without that the
metric would report "dropped a nearby shopping area" about the plaza holding the owner's weekly
grocery run, and a zero would have meant nothing.

## Design hole in T6, for whenever it is built

§2 offered two corroboration rules; neither closes the loop on its own.

`patronageKey` returns nil unless `MerchantRecognizer.recognise` hits one of the 127
`CanadianMerchantPreIndex` rows. `resolveDiscoveredMerchant` early-returns at
`guard let indexed = MerchantRecognizer.recognise(name) else` — **before** `frequentedKeys` is
consulted. So for §3's motivating case, the small standalone shop MapKit never surfaced:

| Corroboration | Corroborates? | Reaches the gate? |
|---|---|---|
| `MerchantRecognizer` identity | no — not indexed | n/a |
| `CaptureMatcher.merchantsAgree` | yes | no — key is not a pre-index id, early return hits first |

Closing it means consulting **place** identity ahead of the recognizer guard — a change to the
resolution ladder, not an addition beside it. Budget for that, not just for the journal.

## Privacy

`ambientCoverage.v1` holds integers only, partitioned by calendar day: rotations, capacity hits,
per-tier eviction counts, arrival-funnel counts. No coordinate, no merchant name, no identifier.
It is deliberately incapable of saying *where*. Inventory updated in
[`account-deletion.md`](../compliance/account-deletion.md); cleared by `forgetLocalHistory()`.

The four compliance docs covering brand-level patronage were uncommitted and in flight at the time
of this work and were **not** touched.

## Ratified decisions checked

- **D8** (a geofence entry writes nothing to the log) — holds. The coverage counters are integers
  about the app's own budget, not records of places.
- **D4** (geofence areas, resolve on arrival) — unchanged.
- **D3** (a new user has zero confirmed merchants) — unchanged; no tier is starved, because
  ranking is untouched.
