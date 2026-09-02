# Arrival resolution, adjustable alert policy, and the field log

**Date:** 2026-09-02
**Status:** design, awaiting implementation
**Scope:** PickMe only. `Engine` (+ Kotlin twin), `Store`, `App`. No new data sources,
no new permissions, no cross-repo work.
**Baseline commit:** `2986ce2`

## Why this exists

An owner walked into Shoppers Drug Mart, tapped a card, and got no arrival alert.
Minutes later the post-purchase path told them a different card would have earned
$0.51 more. Investigation showed nothing was broken in delivery — the system made
six deliberate decisions not to speak, and five of them were made for a bad reason.

The on-device diagnostics for that week:

```
6 arrivals · 6 evaluated · 0 fired · 6 suppressed
  5 · merchantConfidenceLow
  1 · advantageBelowUnverifiedThreshold
  1 · recommendedDefaultCard
15 regions registered · 0 of 64 rotations used all 20 places
```

Permissions were all green and the region budget was never binding. Every failure
is in resolution and policy, not in plumbing.

## What the investigation established

Each of these is a verified reading of the code at `2986ce2`, not an inference.

### 1. Apple's place type never reaches the confidence model

`predict` (`Store/Sources/CardCopilotStore/CategoryMapper.swift:65`) carries a
`.mapKitCategory` tier that maps `pharmacy → drugStore`, `restaurant → dining`,
`gasstation → gasStation`, `foodmarket → grocery`, `hotel → lodging` and more.

`resolveDiscoveredMerchant`
(`Store/Sources/CardCopilotStore/DiscoveredMerchantResolution.swift:100`) then lifts
only `.brandPrior` out of that result:

```swift
confidence: fromPoi.confidenceSource == .brandPrior ? .brandMatched : .unknown
```

So a POI Apple confidently classifies as a pharmacy resolves to `.unknown`, which
`AmbientGate` suppresses to `.presence` unconditionally — a Live Activity naming no
card. No multiplier can reach it. **This is the 5 of 6.**

The same file already treats `.mapKitCategory` as sufficient to auto-assign a
category to a real logged purchase (`resolveWalletMerchant`, same file, guards only
`confidenceSource != .fallback`). The wallet path trusts this evidence; the arrival
path calls it unknown. One file, two verdicts, same evidence.

### 2. The arrival never asks where the owner is

`didEnterRegion` (`App/CardCopilot/Services/AmbientLocationService.swift:487`) calls
`evaluateArrival` with no coordinate, and `resolve`
(`AmbientLocationService.swift:759`) takes none. The class comment claims the shop
"gets resolved on arrival, from a fresh fix." No fix is ever requested.

Consequences:

- Rung 1 (owner-confirmed merchant) measures `verifiedMerchantRadiusMeters = 60`
  from the **area centroid** (`AmbientLocationService.swift:284`), not from the
  owner. Areas run to `maximumAreaRadiusMeters = 400`, so a confirmed store near the
  edge of a plaza can never claim its own visit — confirming a terminal by hand does
  not reliably promote it.
- Rung 2 picks `resolved.first(where: { $0.1.confidence != .unknown })`
  (`AmbientLocationService.swift:798`) over `area.members`, whose order comes from
  `clusterIntoAreas` sorting by `(latitude, longitude, id)`
  (`Store/Sources/CardCopilotStore/DiscoveryPolicy.swift:170`). That sort exists to
  keep region registration stable across rotations, and it silently became the
  resolution answer. **PickMe names the southernmost recognised store in the plaza.**

Expected accuracy in a plaza with *k* recognised stores is therefore about 1/*k*,
biased south. Measuring that number tells us nothing worth knowing, which is why
the resolution fixes belong in the instrumented build rather than after it.

### 3. The unverified multiplier is applied to an invented amount

On arrival there is no purchase, so `ambientPurchaseContext`
(`Store/Sources/CardCopilotStore/CheckoutService.swift:37`) substitutes a category
estimate — `drugStore` is $25, the fallback is $50.

`AmbientGate.scaled` doubles **both** floors for `.brandMatched`
(`Engine/Sources/CardCopilotEngine/Engine/AmbientGate.swift`), and the default
threshold is `0.5pp AND $0.25` with `semantics: "both"` (`contracts/owner-state.json`).
Doubling gives `1.0pp AND $0.50`. Dividing the CAD floor by a guessed basket makes
the effective bar category-dependent:

| category | estimate | effective bar |
|---|---|---|
| wholesaleClub | $150 | 1.0pp |
| ctFamily | $80 | 1.0pp |
| grocery | $60 | 1.0pp |
| gasStation | $55 | 1.0pp |
| *(fallback)* | $50 | 1.0pp |
| dining | $35 | 1.43pp |
| **drugStore** | **$25** | **2.0pp** |
| streaming | $15 | 3.33pp |

The observed Shoppers gap was $0.51 on $33.90 = 1.50pp — over the intended 1.0pp
bar, under the accidental 2.0pp one. Nobody chose 2pp for drugstores; it fell out of
`minAdvantageCad × multiplier ÷ estimate`. **This is the 1 of 6.**

### 4. The arrival path and the post-purchase path cannot agree

|  | arrival gate | post-purchase verdict |
|---|---|---|
| amount | category estimate | real |
| baseline | `ownerState.defaultCardId` | the card actually tapped |
| threshold | ×2 scaled | unscaled |

`AmbientLocationService.swift:683` vs
`Store/Sources/CardCopilotCapture/WalletCaptureVerdict.swift`. Three independent
differences guarantee a band where the app stays silent on arrival and then reports
a loss afterwards. That band is where the reported incident landed.

### 5. A plaza gets one wake for the whole trip

Stores covered by an area deliberately get no region of their own
(`AmbientLocationService.swift:594`). `didEnterRegion` fires once on crossing in, and
discovery only refreshes on a significant location change (~500 m), which a walk
across a car park is not. Dollarama → Tim Hortons → Shoppers is **one wake, one
answer, delivered before the first store, never revised.**

This is architectural, not a defect, and this spec does not fix it. It is the
question the field log exists to inform.

## Decisions taken

**D1. Apple's place type becomes its own confidence tier, not a reuse of
`.brandMatched`.** `.brandMatched` means *we recognise this brand*; place-type
evidence means *we know the category, not the merchant*. Those are different claims
and the whole defect is that they were conflated. Cost is one Kotlin twin change plus
fixtures, covered by the existing gate command.

**D2. Resolution fixes ship in the instrumented build, not after it.** Measuring an
arbitrary baseline characterises a coin flip. The goal is the *ceiling* of the
approach, which requires a best-effort resolver.

**D3. Alert policy becomes debug-adjustable rather than re-guessed.** The right
threshold is what the engagement data says, not a new constant chosen the same way
the old one was.

**D4. The field log is dev-only.** Compiled into Debug and TestFlight builds, never
an App Store release. No consent UI, no privacy-label impact. It records
coordinates and merchant names, which the shipping counters deliberately do not.

**D5. The log is designed for offline replay.** Full candidate sets and raw gate
inputs, so alternative policies are evaluated from the export instead of shipped to
find out.

## Non-goals

- Multi-stop plaza trips (finding 5). Informed by the log, designed later.
- Changing what the post-purchase path does. Finding 4 is recorded, not fixed —
  reconciling the two baselines is a policy decision the data should inform.
- Any new location permission, continuous tracking, or background mode. The
  Arrival alerts screen promises "no continuous route tracking" and that stands.
- Shipping the log to App Store builds, or any server-side collection.

## Work, in order

Each group must leave the gate command green before the next begins:

```bash
(cd Engine && swift test) && (cd android && ./gradlew :core:engine:test)
```

Plus an App target compile — see `docs`/memory for the `xcodebuild` invocation; never
pass `-sdk iphonesimulator`.

### Group A — resolution (Store + App)

**A1. Request a fix on arrival.** `didEnterRegion` requests a one-shot location and
holds the arrival until it lands or a ~5 s timeout expires. `didUpdateLocations`
currently means "significant change → refresh discovery", so arrival fixes need a
distinct path; do not let an arrival fix trigger a discovery refresh or vice versa.
Background region wakes are short — the timeout must be enforced and its expiry
recorded, and an arrival with no fix must still resolve exactly as it does today.

**A2. Rank candidates by distance from the owner.** Replace the `resolved.first`
selection at `AmbientLocationService.swift:798` with nearest-first ordering against
the arrival fix. `clusterIntoAreas`'s `(latitude, longitude, id)` sort must **not**
change — it is load-bearing for region stability. Order at the point of resolution,
not at the point of clustering. With no fix, fall back to today's behaviour.

**A3. Promote confirmed merchants from the owner's position.** Rung 1 measures
`verifiedMerchantRadiusMeters` from the arrival fix rather than the area centroid.
With no fix, retain the centroid measurement.

**A4. New confidence tier for place-type evidence.** Add a case to
`AmbientMerchantConfidence` meaning "category known, merchant not" — Swift and the
Kotlin twin, plus `AmbientGateTests` / `AmbientGateTest` coverage on both sides.
`resolveDiscoveredMerchant` returns it when `predict` yields `.mapKitCategory`.
Its multiplier starts at `unverifiedAdvantageMultiplier`'s current value so A4 alone
changes no firing decision; Group B is what makes it tunable.

### Group B — adjustable alert policy (Engine + App)

**B1. Multipliers become gate inputs.** `unverifiedAdvantageMultiplier`,
`frequentedAdvantageMultiplier`, and the new tier's multiplier move from static
constants onto `AmbientGateInput` with defaults equal to today's values. Swift and
Kotlin, with tests pinning the defaults so an omitted argument cannot silently change
policy.

**B2. Debug controls.** A debug-only section on the Arrival alerts screen exposing:
the switch threshold (already a gate input, so free), the three multipliers, and the
category-estimate behaviour. Values persist in `UserDefaults` and are recorded on
every field-log record so the export is self-describing.

**B3. Surface the estimate.** The estimated amount and the effective bar it produces
must be visible in the debug screen. The table in finding 3 should be derivable at
runtime, not from a spec.

### Group C — field log (Store pure + App capture)

**C1. Record model and metrics live in `Store`, pure and unit-tested.** Capture,
persistence, and export live in `App`. Follows the existing split: policy is pure,
CoreLocation is not.

**C2. One record per arrival**, written at `evaluateArrival`: timestamp, region id,
area centroid and radius; the fix with `horizontalAccuracy` or an explicit timeout
marker; **every candidate** with name, `poiCategoryRaw`, coordinates, distance from
the fix, pack recognition, resolved category and confidence; which candidate was
chosen and which rung answered; engine inputs and outputs including the estimate
used; the gate's tier, every suppression reason, and the active debug settings.

**C3. Discriminability margin**, computed per arrival: the distance gap between the
nearest and runner-up candidates relative to the fix's own accuracy. This is the
ceiling metric and needs no receipt, so it accrues on every arrival including ones
with no purchase. Margin below accuracy means no algorithm can resolve that arrival
and the design must handle ambiguity instead.

**C4. Receipt join.** When a Wallet capture lands within ~90 minutes of an arrival,
append merchant descriptor, real amount and timestamp. Pure join function, tested
against fixtures. Yields:
- **card-equivalence accuracy** — of arrivals where the store was guessed wrong, how
  often was the *card* still right. **This is the number that decides the rework.**
- top-1 store accuracy, and candidate containment (was the true store in the set at
  all — the ceiling).
- gate replay at the real amount and with the CAD floor unscaled: how many alerts the
  estimate ate.

**C5. Engagement.** The existing notification actions (`usedRecommended`,
`usedOtherCard`, `mute`) and Live Activity dismissals are recorded against the
arrival that produced them. This is the only signal for whether an alert was *useful*
rather than merely correct, and it only accrues once alerts fire — which is what
Group B is for.

**C6. Export.** Debug-only row on the Arrival alerts screen, share sheet, JSON.
Capped ring buffer; wiped by the existing `forgetLocalHistory`.

## Testing

- `Engine` and the Kotlin twin: gate behaviour for the new tier and for
  multipliers-as-inputs, including a test that pins the defaults.
- `Store`: resolution returning the new tier for each `.mapKitCategory` mapping;
  nearest-first ordering with and without a fix; discriminability margin; the receipt
  join and every derived metric, against fixtures.
- `App`: the arrival-fix path — fix arrives, fix times out, fix arrives after the
  timeout — must not change resolution outcomes in the no-fix case.
- No test may depend on real coordinates or on the owner's device data.

## Conventions

- Work directly on `main`. No branches, no PRs (`AGENTS.md`).
- Stage explicit paths, never `git add -A`; this repo routinely carries another
  session's in-flight work, including `contracts/*.json` and the Android mirror.
- Leave `App/CardCopilot/Localizable.xcstrings` alone. It is dirty from another
  session's IDE extraction, and the debug UI should use plain literals rather than
  the string catalogue.
- If a group feels too large, make it smaller rather than asking.

## What the data decides later

If card-equivalence accuracy is high, the rework is "answer when it doesn't matter" —
score every plausible candidate and speak when they agree — and per-store resolution
never needs to be solved. If it is low, per-store resolution has to be designed
properly, and the discriminability margins say whether that is even possible on this
hardware. Either outcome gets its own spec.

The deeper question that follows: the gate reads only merchant-identity confidence,
while the card depends on category. Feeding category confidence into the gate
directly, and reserving identity for the things that actually need it — muting a
merchant, naming a storefront — is the real restructure. It should not be attempted
before the numbers exist.
