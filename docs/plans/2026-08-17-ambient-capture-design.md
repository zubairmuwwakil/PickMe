# Ambient Capture — design

**Status:** approved in conversation 2026-08-17; not yet implemented.
**Supersedes:** the ambient-notification behaviour specced in Phase 3 (`2026-08-16-phase3-ambient-spec.md`)
and the reconcile ritual in the MVP design doc §6.
**Scope boundary:** this is a **Path A** (local-only) design. Nothing here requires an account, a
network call to PickMe, or the Apple Wallet Shortcut. Path B remains an optional accelerator, and
§11 records the seam that lets it converge later.

---

## 1. The problem

Path A currently captures *what actually happened* worse than Path B does, and worse than it needs
to. Three specific failures:

1. **The card is never observed.** It is recalled weeks later from a statement, chosen from a
   `Picker`. Path B reads it off the Wallet transaction in real time.
2. **The amount is a pre-purchase guess.** `AmountCaptureView` runs *before* payment and offers
   `$10 / $25 / $50 / $100 / $200` presets. The real charge is $47.83. There is no field anywhere
   that records the actual amount, and `valueRecovered()` multiplies through the guess.
3. **The one-tap "Match" button fabricates evidence.** `quickConfirm` copies
   `predictedRewardUnits` into `observedRewardUnits`, so `arithmeticVerdict` compares a number to
   itself and returns `.matches`. The arithmetic bar — whose stated threshold is 100% — passes
   without a statement ever being read.

Underlying all three: the data model has two moments (advice, statement) where the world has
three. The missing one is **the till** — the instant after payment, when the card tapped is
certain and the amount is on the terminal screen, and when neither is knowable from a statement
that does not yet exist.

## 2. Decisions

Settled in conversation; recorded so they are not relitigated.

| # | Decision | Rationale |
|---|---|---|
| D1 | Arrival fires a **local notification**, not a Live Activity | `Activity.request()` throws `ActivityAuthorizationError.visibility` from the background. A geofence only ever wakes the app in the background. Push-to-start needs APNs, which needs a server, which Path A refuses. |
| D2 | **Live Activity cut entirely** | Its only unique job was persisting an amount-entry handle across the visit. D6 does that better and better-timed. It would have cost a widget extension target, a new bundle ID, an App Group, and migrating the SwiftData store into a shared container. |
| D3 | Arrival covers **discovered** merchants, not only confirmed ones | A new user has zero confirmed merchants, so zero geofences, so the feature is dead until they have manually checked out somewhere. The product's base job is to answer on day one. |
| D4 | Geofence **areas**, resolve **stores** on arrival | iOS caps monitored regions at 20 app-wide. At the current 150 m radius, 20 storefronts fit inside one suburban plaza — the whole budget spent on one location, firing a dozen simultaneous entries with nothing to arbitrate them. Areas make the budget cover ~20 *plazas*, and resolution happens with a fresh fix at the moment of arrival rather than pre-baked minutes earlier. |
| D5 | Merchant confidence becomes **three tiers**, and the gate loosens for the middle one | Today `AmbientGate` requires `.high`, which only comes from owner-reconciled terminals. Every discovered merchant is `.low`, so D3 would produce exactly zero notifications. |
| D6 | **Exit + dwell** is the amount-capture moment | The arrival notification fires before payment, when the amount is unknowable. Asking for it there means the user must later excavate a buried notification. Region exit is when the receipt is in hand. |
| D7 | Dwell time **disambiguates and de-phantoms** | Walking past gives enter→exit in seconds; shopping gives twenty minutes. This filters walk-bys without asking the user, and identifies which of several overlapping areas was actually visited. |
| D8 | A geofence entry **writes nothing** to the log | Records are created only on user action. The log stays a record of purchases, not of places walked past, and the metrics denominator stays clean. |
| D9 | Discovery is governed by a **spatial cache with negative caching**, not a rate budget | See §6. The quota is a non-issue; battery, iOS's background execution budget, and the passive query trail are the real costs. |

## 3. The three-record model

```
StoredPrediction  ──1:1──▶  StoredPurchase  ──1:1──▶  StoredObservation
   (immutable)                (fills in)                 (immutable)
 "what the app said"      "what I tapped, what      "what posted, and how"
                            it cost"
```

Each record answers exactly one question, and none can impersonate another. That is the property
the whole experiment rests on, and the `quickConfirm` bug is what happens when it is violated.

### 3.1 `StoredPurchase` (new)

```swift
@Model
public final class StoredPurchase {
    public private(set) var id: UUID
    public private(set) var createdAt: Date

    /// nil until stated. Never inferred from the recommendation.
    public var cardUsedId: String?
    /// Provenance of `cardUsedId`. A card named at the till and a card recalled a week later
    /// are different evidence and must not be averaged into one confidence.
    public var cardSourceRaw: String?

    /// The amount actually charged — NOT the pre-purchase estimate.
    public var amountCad: Double?
    public var amountSourceRaw: String?

    /// Set once both card and amount are known. Drives the "finish these" queue.
    public var completedAt: Date?

    public var prediction: StoredPrediction?

    @Relationship(deleteRule: .cascade, inverse: \StoredObservation.purchase)
    public var observation: StoredObservation?
}

public enum CaptureSource: String, Codable, Sendable {
    case atTill        // stated within the visit — fresh, high trust
    case recalledLater // stated during reconcile — recalled, lower trust
    case walletCapture // Path B, read off the Wallet transaction
}
```

**Why per-field provenance rather than one on the record.** The card and the amount can arrive at
different moments and by different routes — "Used this card" tapped at the till, amount typed in
during reconcile a week later. A single record-level source would have to lie about one of them.
`valueRecovered()` is only as honest as the amount it multiplies, so it needs to know.

### 3.2 Changes to existing models

**`StoredObservation`** loses `cardUsed` — that fact belongs to the till, not the statement — and
re-parents from `StoredPrediction` to `StoredPurchase`. What remains is purely statement-derived:
`observedCategory`, `observedRewardUnits`, `missClassRaw`, `note`, `confirmedAt`. This is a
simplification, not just a move: the type now means one thing.

**`StoredPrediction.amountCad` is renamed `scoredAmountCad`.** Semantics are unchanged (nil when
the owner skipped amount entry; it is the figure the engine scored against). The rename exists
because `prediction.amountCad` and `purchase.amountCad` would otherwise sit in the same codebase
meaning "guess before paying" and "what it actually cost" — the exact ambiguity that let
`valueRecovered()` silently use the wrong one.

`StoredPrediction` keeps its `private(set)` discipline and gains no mutable fields.

### 3.3 Migration

A SwiftData `VersionedSchema` + custom `MigrationStage`. For each existing `StoredPrediction`:

1. Create a `StoredPurchase`, linked to it.
2. If the prediction has an observation, move `observation.cardUsed` → `purchase.cardUsedId` with
   `cardSourceRaw = .recalledLater` (true of every historical row — all were entered at reconcile).
3. Copy `prediction.amountCad` → `purchase.amountCad` with `amountSourceRaw = .recalledLater`, and
   set `completedAt` where both are present.
4. Re-parent the observation to the purchase.

The historical amounts are pre-purchase estimates being recorded as actuals, which is a small lie.
It is the least-bad option: dropping them would zero an existing scoreboard, and there is no way to
recover a real figure retroactively. `.recalledLater` provenance at least marks them as untrusted.

> **Verify before implementing:** whether the app has ever been installed with data worth
> preserving. If the store is disposable, a destructive schema reset is far cheaper than a custom
> migration stage and should be preferred.

## 4. Metrics corrections

Three, all enabled by the new model.

**`quickConfirm` stops fabricating.** It passes `observedRewardUnits: nil`. Quick-confirmed rows
then count toward category accuracy — which is what the user actually asserted by tapping "Match"
— and fall out of the arithmetic denominator via the existing `.notEligible` path. The units
comparison and its tolerances need no change at all: that rule was always correct, it was being
fed a lie.

**`valueRecovered()` gains the check it never had.** It currently credits the full
`winnerValueCad - defaultCardValueCad` advantage for every confirmed prediction with an amount —
**including ones where the owner ignored the advice and tapped their default card anyway.** The new
guard requires `purchase.cardUsedId == prediction.winnerCardId`. It also switches from
`scoredAmountCad` to `purchase.amountCad`, so the scoreboard is built on real charges.

**Value recovered is reported as two figures.** *Confirmed* (statement-reconciled) and *pending*
(purchase complete, not yet reconciled). Requiring reconciliation for the headline number is the
honest reading, but it would hold the scoreboard at $0 for weeks. Showing both keeps the strong
claim strong and the weak claim labelled — consistent with `ExperimentMetrics` returning `nil`
rather than `0%` when there is no evidence.

**Arithmetic eligibility** now reads the amount from the purchase: a reward comparison against a
guessed basket was never meaningful, and now there is a real number to use instead.

## 5. Confidence tiers and the gate

```swift
public enum AmbientMerchantConfidence: String, Codable, Equatable, Sendable {
    case verified      // owner-reconciled THIS terminal (was `.high`)
    case brandMatched  // canonicalEngineBrand() resolved the POI name to a known brand
    case unknown       // a bare POI pin (was `.low`)
}
```

Firing policy:

| Tier | Fires when |
|---|---|
| `verified` | advantage clears the owner's `SwitchThreshold` (unchanged behaviour) |
| `brandMatched` | advantage clears `SwitchThreshold` **scaled by `unverifiedAdvantageMultiplier` (2.0)** on whichever axes `semantics` requires |
| `unknown` | never |

New suppression reason `.advantageBelowUnverifiedThreshold`, distinct from
`.advantageBelowSwitchThreshold` so the field-test counters can tell "loosening the gate is
producing noise" from "the threshold is simply high." Adding a case to the persisted
`AmbientSuppressionReason` is decode-safe — old `SuppressionLog` blobs simply lack the key.

`AmbientGate` remains a pure function with no location, notification, or persistence dependency.
The strict-conjunction structure and the all-failed-reasons return value are unchanged.

**What this decision costs.** The existing doc comment is explicit that a brand or MapKit guess is
deliberately not enough to interrupt the owner. Loosening it spends down an interruption budget
someone chose carefully. The 2.0 multiplier is a starting guess, not a derived value — the
suppression counters exist precisely so it can be tuned against evidence rather than argued about.

## 6. Discovery and the spatial cache

### 6.1 What the constraint actually is

Native MapKit (`MKLocalSearch`, `MKLocalPointsOfInterestRequest`) is free and unmetered — no API
key, no billing. The metered Apple products are MapKit JS and the Apple Maps Server API, neither of
which is in play. Mapbox would be per-request billed *and* would ship coordinates to a third party
who is not the OS vendor, which is strictly worse here.

Throttling is real: `MKError.loadingThrottled`, at a community-measured ~50 requests per 60 seconds
per app. Apple does not document the figure and says it is subject to change. Against a realistic
worst case of ~20 queries *per day*, this is three orders of magnitude of headroom.

**So the quota is not the constraint.** The real costs are battery (each query is a background
radio wake), iOS's background execution budget (an app that wakes constantly gets deprioritized),
and the passive movement trail handed to Apple. The design therefore minimises queries because they
are wasteful, and treats throttling purely as a backstop error case.

### 6.2 Mechanism

People are extremely repetitive geographically. The cache exploits that.

```swift
@Model final class ExploredCell {
    var cellKey: String      // ~1 km grid: "\(round(lat*100))_\(round(lon*100))"
    var exploredAt: Date
    var areaCount: Int       // 0 is a valid, meaningful result
}

@Model final class ShoppingArea {
    var id: UUID
    var centroidLatitude: Double
    var centroidLongitude: Double
    var radiusMeters: Double
    var discoveredAt: Date

    @Relationship(deleteRule: .cascade, inverse: \AreaMember.area)
    var members: [AreaMember]
}

/// A POI found inside an area. Its own @Model rather than a Codable blob so members can be
/// queried and pruned independently, and so a member can later be promoted to a confirmed
/// StoredMerchant without a decode round-trip.
@Model final class AreaMember {
    var name: String
    var identifier: String?     // Apple Maps place id, where one exists
    var poiCategoryRaw: String?
    var latitude: Double
    var longitude: Double
    var area: ShoppingArea?
}
```

Query gating, in order — all of it pure and testable:

1. **Speed gate.** `CLLocation.speed` above ~8 m/s (~30 km/h) means driving, not shopping. Highway
   travel is the single largest generator of significant-location-change events and produces zero
   purchases. Skip.
2. **Cache hit.** If this cell is explored and within TTL (30 days), use the stored areas. No
   network.
3. **Negative caching.** A cell with `areaCount == 0` is still a hit. Without this, the residential
   street the owner lives on is re-queried forever.
4. **Local rate ceiling.** A small cap per rolling hour as a backstop, so a bug can never become a
   throttle.
5. **Throttle handling.** On `MKError.loadingThrottled`, back off and do not retry inside the same
   background wake.

Steady state after a couple of weeks of ordinary life: **one to three queries per day**, spiking
only on travel to genuinely new places. Week one is the expensive week and is still trivially cheap.

### 6.3 Region allocation

All monitored regions are `ShoppingArea`s, uniformly. A confirmed `StoredMerchant` that falls
inside no discovered area becomes a single-member area of its own. This gives one code path for
arrival instead of two, and one budget instead of two competing ones.

Ranking for the 20 slots: nearest first, with areas containing a confirmed merchant sorted ahead of
purely discovered ones at equal distance.

### 6.4 Component boundary

All policy lives in the `Store` package as pure functions with no MapKit or CoreLocation import, so
it is exhaustively testable on macOS without a device:

- `cellKey(latitude:longitude:) -> String`
- `clusterIntoAreas(_ pois: [NearbyMerchant]) -> [ShoppingArea]`
- `shouldQueryDiscovery(cell:cache:speedMetersPerSecond:recentQueries:now:) -> DiscoveryDecision`
- `rankAreasForMonitoring(_ areas:, origin:, limit:) -> [ShoppingArea]`
- `dwellDecision(enteredAt:exitedAt:didEngage:) -> DwellOutcome`

`AmbientLocationService` in the App target remains a thin adapter: CoreLocation and MapKit in,
decisions out, notifications scheduled. It gains no policy.

## 7. The arrival → exit flow

**On area entry** (background wake, ~10 s of runtime):

1. Take a fresh precise fix.
2. Resolve the merchant, cheapest first:
   - nearest confirmed `StoredMerchant` within ~60 m → `verified`
   - else nearest cached area member whose name resolves via `canonicalEngineBrand()` → `brandMatched`
   - else one fresh MapKit POI query at the fix, if the cache is stale or does not disambiguate → `brandMatched` or `unknown`. This query is subject to the same rate ceiling and throttle backoff as discovery (§6.2 steps 4–5), but **not** to the speed gate — arriving at an area is by definition the moment the owner has stopped moving.
3. Predict category, run `RecommendationEngine`, run `AmbientGate`.
4. Record the entry timestamp for dwell. This is ephemeral bookkeeping in `UserDefaults`, not a log
   write — D8 stands: no `StoredPrediction` or `StoredPurchase` exists until the owner acts.
5. If the gate fires, schedule the notification.

**Arrival notification.**
Title: `"Walmart — use MBNA World Elite (4% cash back)"` (existing format).
Actions: `Used this card` · `Used a different card…` · `Mute this merchant`.

`Used this card` writes a `StoredPrediction` + `StoredPurchase` pair with `cardUsedId` set and
`cardSourceRaw = .atTill`. This is the first moment anything is written — per D8, the geofence
entry itself logged nothing. Notification action handlers get background runtime sufficient for a
SwiftData write.

**On area exit:**

1. `dwell = exitedAt - enteredAt`.
2. Under ~4 minutes → discard. Walk-by, no record, no prompt.
3. Over threshold **and the owner engaged with the arrival notification** → fire the amount prompt.

That second condition matters. The exit prompt is a **follow-up to an engagement, never a cold
ask.** If the gate suppressed the arrival notification (the default card was already best), the
owner never saw anything, and asking "what did you spend at Starbucks?" out of nowhere is exactly
the interruption the silence-first policy exists to prevent.

**Exit notification.** `"What did you spend at Walmart?"` with a `UNTextInputNotificationAction`.
The typed figure lands on the pending purchase as `amountCad` with `amountSourceRaw = .atTill`.

### 7.1 Dwell bookkeeping

Entry timestamps must survive app termination between enter and exit. A small
`[areaId: Date]` map in `UserDefaults`, matching the existing `AmbientDiagnosticsStore` /
`AmbientMerchantMuteStore` pattern. Entries older than ~6 hours are pruned on write — an exit event
that never arrives must not strand a timestamp that later produces an absurd dwell.

This map is location data. `forgetLocalHistory()` must clear it (§10).

## 8. The reconcile split

One queue becomes two, because "unfinished" now means two different things:

- **Finish** — `PredictionLog.awaitingCompletion()`: purchases missing a card or an amount. One
  field, fast, no statement needed.
- **Reconcile** — `PredictionLog.awaitingConfirmation()`: complete purchases with no statement
  observation. The existing weekly ritual, now simpler because the card is already known.

`ReconcileEntryView` loses its card `Picker` (the card lives on the purchase) and gains an
editable actual-amount field, since a purchase may reach reconcile with the amount still missing.
The merchant and card remain editable throughout — a `brandMatched` arrival is a guess, and D5
means guesses now reach the user.

## 9. Performance

`refreshHome()` currently makes four separate passes: `valueRecovered()`, `knownMerchants()`,
`awaitingConfirmation()`, and `metrics()` — three of which call `allPredictions()`, an unfiltered
fetch followed by in-memory filtering. Fine at the 30-row target; the whole point of ambient capture
is to raise the row count, and a third record type with relationships to walk makes each pass
heavier.

The fix is one pass, not cleverer predicates: fetch predictions once with their purchases and
observations, and compute all four outputs from that single result. `knownMerchants()` stays its
own fetch.

> **Verify during implementation:** whether `#Predicate` can express `$0.observation == nil` across
> a relationship on the deployment target. If it cannot, a maintained `isComplete` boolean on
> `StoredPurchase` is the fallback — denormalized but reliable. Do not block on this; the
> single-pass change delivers the win regardless.

## 10. Privacy deltas

Three, all requiring the compliance docs to change. Those docs are already stale — they describe an
app with no accounts and no server, which stopped being true when Clerk and the MoneyTalks sync
landed. This work adds to that debt rather than creating it, but the location claims are ones this
design is directly responsible for.

1. **`ExploredCell` is a coarse record of everywhere the owner has been** — not merely where they
   shopped, but every ~1 km cell passed through and checked. This is a broader location footprint
   than anything stored today, and it exists purely as an optimization. It therefore needs
   **age-based pruning independent of freshness** (drop cells not revisited in ~90 days) so it never
   accretes into a lifetime movement history.
2. **MapKit is queried as the owner moves, not only when they ask.** Privacy policy §6 currently
   says Maps requests happen when the owner looks for a merchant. That becomes false. Apple — not
   PickMe — receives a sparse passive movement signal. Section 6.2's gating keeps it sparse, and
   §6 of the policy must say so plainly rather than being quietly left as-is.
3. **`LocalDataEraser` must cover the new surfaces.** Today it erases observations, predictions,
   and merchants. It must also erase `StoredPurchase`, `ExploredCell`, `ShoppingArea`, and the
   dwell-timestamp map — and `AmbientLocationService.forgetLocalHistory()` must stop monitoring the
   discovered areas, not just the merchant regions. A wipe that leaves the movement cache behind
   would leave the most sensitive new data in place, which is the exact failure the eraser's own
   doc comment says the merchant rows were included to avoid.

## 11. Out of scope

Deliberately excluded, with the seam noted where one exists.

- **Live Activity, widget extension, App Group, shared-container migration** (D2). Additive later;
  nothing here blocks it.
- **Push-to-start Live Activities.** Requires APNs and therefore a server. Incompatible with Path A
  by definition; available to Path B users as a future option.
- **The Path B bridge.** A `WalletEvent` *is* a `StoredPurchase` with
  `cardSourceRaw = .walletCapture` — that is why the record is shaped this way. Mapping
  `WalletFeedback` onto pending purchases needs `resolvedCardId` on the wire (today it carries only
  the display string `cardRaw`), so it is specified as future work, not built here.
- **`OwnerState` persistence.** Card settings and valuations are read from the bundled seed on every
  launch and never written back; synced cap progress is lost on relaunch. A real gap, unrelated to
  this design, tracked separately.
- **Compliance doc rewrite.** §10 states what becomes false. Rewriting `privacy-policy.md` and
  `app-privacy-labels.md` — which also need the Clerk/server changes folded in — is its own task.

## 12. Testing

Almost all of this is testable without a device, which is why the model and policy land first.

**`Store` package (unit, no device):** the three-record model and its invariants; the migration,
against a fixture store built on the old schema; `cellKey` quantization at Canadian latitudes;
clustering, including the degenerate single-POI and fully-overlapping cases; `shouldQueryDiscovery`
across every gate (speed, cache hit, negative cache hit, TTL expiry, rate ceiling); `dwellDecision`
around the threshold and for the never-engaged case; the corrected `valueRecovered()`, specifically
that ignoring the advice credits zero; `quickConfirm` producing `.notEligible`; the single-pass
`refreshHome()` returning values identical to the four-pass version.

**`Engine` package (unit):** `AmbientGate` across all three tiers × both `SwitchThreshold`
semantics, and that `unknown` never fires regardless of advantage.

**Device-only (manual, documented as a field-test checklist):** geofence entry and exit in a real
plaza; dwell measurement against real exit-event lag; notification actions writing from a background
wake; behaviour on a cold start with an empty store.

## 13. Open risks

- **Exit-event lag.** iOS coalesces and delays region exits. Dwell will be noisy. The signal we
  need is "20 minutes vs. 40 seconds," far above the noise floor — but the 4-minute threshold is a
  guess and should be validated in the field before it is treated as tuned.
- **`brandMatched` false positives.** `canonicalEngineBrand()` matches on substring. A "Walmart
  Pharmacy" inside a Walmart resolves to the same brand but is a different category. The category
  fork already handles ambiguity at checkout; whether it handles it acceptably in a notification's
  one line of text is unproven.
- **20 regions is still 20.** In a dense downtown, even areas will exceed the budget. The ranking
  degrades gracefully (nearest wins), but coverage in dense urban cores will be worse than in
  suburbs, and that is not fixable within CoreLocation's cap.
- **The 2.0 multiplier is unvalidated.** See §5.
