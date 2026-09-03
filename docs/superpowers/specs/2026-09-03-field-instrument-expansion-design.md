# Field instrument expansion — Radar coverage, correction, delivery truth, wake cost

**Date:** 2026-09-03
**Status:** design, awaiting implementation
**Scope:** PickMe only. `App` and `Store`. No `Engine` change, no Kotlin twin change, no new
permissions, no new data sources.
**Baseline commit:** `531d594`
**Predecessor:** [`2026-09-02-arrival-resolution-and-field-log-design.md`](2026-09-02-arrival-resolution-and-field-log-design.md)
(Groups A–C, landed `054193a`…`508fbf3`)

## Why this exists

The field log from Groups A–C instruments the **ambient** path only —
`ArrivalFieldLogStore` is referenced solely inside `AmbientLocationService`. The owner's
actual reported failure lives in the **foreground** path:

> "I walked into Shoppers Drug Mart yesterday and it wouldn't even show under nearby
> locations even though I was standing in Shoppers."

That is `CopilotSession.loadNearby` → `LiveMerchantProvider.nearby` → `rankNearbyMerchants`,
none of which writes a field record. A fortnight of carrying the current build therefore
produces no evidence about the one thing the owner has observed twice.

Two candidate mechanisms are live and this work must distinguish them:

- **Result set** — `MKLocalPointsOfInterestRequest` sweeps a 200 m radius with no category
  filter and returns a bounded set. A plaza dense with micro-businesses (and, per the owner's
  hypothesis, defunct ones still registered) can crowd out the anchor tenant.
- **Pin geometry** — a large store's MapKit pin sits at the building or parcel centroid. From
  the till against one wall, a 20 m-away office is genuinely closer *to its own pin* than the
  owner is to the anchor's. The store is returned, but ranks below its neighbours.

The first needs a second, targeted query. The second needs different ranking. They are not the
same work, and guessing between them is what this expansion exists to stop.

**This also tests A2.** "Rank candidates by distance from the owner" shipped in `054193a`. If
pin geometry is the mechanism, nearest-by-pin is the wrong ranking precisely where the anchor
tenant is large — which is where the owner actually spends.

## Owner's instruction on breadth

The owner asked for maximum instrumentation during the debug window, explicitly overriding a
recommendation to avoid adding further aggregate counters. That recommendation was: three
counter systems already exist (`SuppressionLog`, `AmbientCoverageLog`, arrival explanations)
and a fourth answers nothing the record-level log cannot. The owner reaffirmed. Build the
counters. This note exists so the reasoning is not re-litigated later.

## Decisions taken

**D1. Everything is gated behind `FIELD_DIAGNOSTICS` except Group E.** The correction loop is a
product feature and ships ungated (see D2). Everything else is a throwaway instrument and must
not reach an App Store binary — the privacy policy does not disclose it.

**D2. The correction loop reuses the existing confirmation write.** Correcting a store must go
through the same path that sets `StoredMerchant.confirmedCategory`, not a new one. That column
is what promotes a merchant to `.verified` and its unscaled threshold, and a second way to
write it is a second way for the two to disagree.

**D3. Extend `NearbyLookupMetricsStore`, do not add a parallel store.** It already counts
`prefetchAttempt`, `movementCacheHit`, `tap`, `locationTimeout`, `merchantTimeout`,
`emptyResult` and `failure`, and its header states it holds no coordinates, identity, query
text or precise timestamps. New Radar counters belong there. Its privacy property must hold.

**D4. Record-level detail and counters stay separate.** Counters answer "how often"; the field
log answers "what happened that time". Do not derive one from the other.

## Non-goals

- Fixing the ranking or adding a targeted chain query. This expansion measures which mechanism
  is at fault; the fix is designed once that is known.
- Any change to `Engine` or the Kotlin twin.
- Disclosing any of this in the privacy policy. It is `FIELD_DIAGNOSTICS`-gated and removed
  before submission (`531d594` is reverted at that point).

## Work

Each group must leave green:

```bash
(cd Engine && swift test) && (cd android && ./gradlew :core:engine:test)
```

plus `Store` tests and an App target build in **both** Debug and Release — Release now compiles
the `FIELD_DIAGNOSTICS` paths and is what reaches the phone via TestFlight. Never pass
`-sdk iphonesimulator`; use `-scheme CardCopilot`, never `-target`.

### Group D — instrument the Radar path (highest value, do first)

**D-1.** Emit an `ArrivalFieldRecord` from `CopilotSession.loadNearby` with a new
`source: .radar`, carrying the same payload the ambient path records: the fix and its
`horizontalAccuracy`, **every** candidate returned with name, `poiCategoryRaw`, coordinates,
distance, pack recognition, resolved category and confidence, plus which was ranked first.

**D-2.** Record the **raw MapKit response size** before `rankNearbyMerchants` dedupes, and the
count after. A cap that truncates upstream is invisible once the list is deduped.

**D-3.** Record **chain containment**: whether any candidate resolved to a
`CanadianMerchantPreIndex` row, and that row's id. This is what turns "Shoppers wasn't there"
from recollection into a counted fact, and it is the single field that separates the two
candidate mechanisms.

**D-4.** Record the **discriminability margin** for Radar scans exactly as the ambient path
does, so foreground and background are comparable.

Radar is tapped far more often than geofences are crossed, so this is also the densest source
of samples available and can be triggered deliberately by walking into a store and tapping.

### Group E — "not this store" correction (ships ungated)

**E-1.** A control on the Home answer card that rejects the current subject and offers the
other candidates. `retarget(_:provenance:)` already re-points the card; this adds the explicit
*negative* signal, which nothing currently captures.

**E-2.** Choosing the right store writes a confirmed merchant through the existing confirmation
path (D2). Do not invent a second writer for `confirmedCategory`.

**E-3.** Under `FIELD_DIAGNOSTICS`, append the correction to the field record that produced the
subject: what was offered, what was rejected, what was chosen, and that candidate's rank.

This is the only ground truth that does not require a purchase. Receipt joins label perhaps a
fifth of visits; this labels any visit the owner chooses to correct.

### Group F — notification delivery truth

**F-1.** After scheduling an arrival notification, record whether
`UNUserNotificationCenter.getDeliveredNotifications()` still lists it — sampled shortly after
scheduling and again on next foreground.

**F-2.** Distinguish four outcomes on the record and in counters: never requested, request
threw, accepted then absent from Notification Center, accepted and present.

Today only "iOS accepted the request" is recorded, which cannot separate "we never asked",
"iOS dropped it", and "it appeared and was missed" — the exact ambiguity that opened this
investigation.

### Group G — background wake accounting

**G-1.** Count background wakes per day by cause (region entry, region exit, significant change,
`requestState` synthesis) and record each wake's wall-clock duration.

**G-2.** Count wakes where the arrival fix timed out, separately from wakes with no fix
requested.

This is the only item that speaks to whether ambient monitoring is affordable at all. A battery
cost discovered in week one is a design input; discovered after launch it is a review.

### Group H — counters, per the owner's instruction

Extend `NearbyLookupMetricsStore` (D3) and `AmbientCoverageLog`:

- Radar: scans, raw vs deduped result counts bucketed, scans containing a recognised chain,
  scans where the top-ranked candidate was **not** a recognised chain while one was present
  (the pin-geometry signature).
- Delivery: the four Group F outcomes.
- Wakes: the Group G counts.

All counters keep `NearbyLookupMetricsStore`'s stated privacy property — no coordinates, no
identity, no query text, no timestamps precise enough to reconstruct a visit. Identity-bearing
detail belongs in the `FIELD_DIAGNOSTICS` record log, never in a counter.

Surface them in the existing debug section rather than a new screen.

**Migration:** every counter model persisted per-day in `UserDefaults` needs a tolerant
`init(from:)` when a field is added. Synthesized `Codable` throws on a missing key even where
the property has a default, and `DailyLogStore` reads a throw as empty history — silently
deleting the pre-change baseline that makes a new counter interpretable. `AmbientCoverageLog`
and `AmbientVisit` both already do this; follow them.

## Testing

- `Store`: the Radar record shape, chain containment, margin parity between Radar and ambient,
  and every new counter's merge and tolerant decode, against fixtures.
- `App`: the correction loop writes exactly one confirmed merchant through the existing path;
  delivery-truth classification across all four outcomes.
- No test may depend on real coordinates or on the owner's device data.

## Conventions

- Work directly on `main`. No branches, no PRs (`AGENTS.md`).
- Stage explicit paths, never `git add -A`. This tree routinely carries other sessions' work.
- Leave `App/CardCopilot/Localizable.xcstrings` to the IDE; debug-only UI uses plain literals.
- If a group feels too large, make it smaller rather than asking.
